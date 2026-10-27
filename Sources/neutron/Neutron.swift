import ArgumentParser
import Foundation
import NeutronKit

@main
struct Neutron: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run Windows Steam games on macOS through Wine, bridged to the native Steam client.",
        subcommands: [Install.self, Run.self, Wine.self, Compat.self, WindowsSteamCommand.self]
    )
}

extension Backend: ExpressibleByArgument {}

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Download a game's Windows build.")

    @Argument var appID: UInt32
    @Option(help: "Steam account; prompts for login once, remembered afterwards.") var user: String?
    @Flag(help: "Install even if the compatibility database lists the game as blocked.") var force = false

    func run() async throws {
        if let entry = CompatDB.shared?.entry(appID: appID), entry.blocked {
            let reason = "\(entry.title) is listed as not working on macOS: \(entry.summary ?? entry.status)"
            guard force else { throw NeutronError("\(reason) Pass --force to install anyway.") }
            print("neutron: \(reason)")
        }
        var config = Config.load()
        guard let user = user ?? config.user else { throw NeutronError("pass --user <steam-user> the first time") }
        guard let appInfo = try AppInfo.read(appID: appID) else {
            throw NeutronError("Steam has no info for \(appID) yet, open it in your Steam library first")
        }
        guard let game = InstalledGame(appID: appID, appInfo: appInfo) else {
            throw NeutronError("no Windows launch option found for \(appID)")
        }
        try await DepotDownloader.install(game, user: user)
        config.user = user
        try config.save()
        print("installed \(game.name) to \(Library.directory(appID: appID).path)")
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch an installed game, or an exe, through the Steam bridge.")

    @Option(name: .customLong("appid"), help: "Steam AppID (enables Steamworks).") var appID: UInt32?
    @Option(help: "Default: the game's setting, else the compatibility database's, else dxmt.") var backend: Backend?
    @Option var prefix: String?
    @Argument var exe: String?
    @Argument(parsing: .postTerminator, help: "Extra game arguments, after --.") var args: [String] = []

    func run() throws {
        let launch: (exe: URL, workingDirectory: URL, arguments: [String])
        if let exe {
            let url = URL(filePath: exe).standardizedFileURL
            launch = (url, url.deletingLastPathComponent(), [])
        } else if let appID {
            launch = Library.launch(try Library.game(appID: appID))
        } else {
            throw NeutronError("pass an exe or --appid")
        }

        let backend = backend ?? appID.map(Config.load().backend(for:)) ?? .dxmt
        let prefix = try prefix.map { try Prefix(url: URL(filePath: $0).standardizedFileURL, backend: backend) }
            ?? Prefix.forApp(appID, backend: backend)
        try prefix.prepare()
        if let appID {
            for note in try prefix.linkCloudSaves(appID: appID) { print("neutron: \(note)") }
        }
        try exec(prefix.gameCommand(appID: appID, exe: launch.exe, workingDirectory: launch.workingDirectory,
                                    arguments: launch.arguments + args))
    }
}

struct Wine: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a raw wine command in a prefix.")

    @Option var backend: Backend = .dxmt
    @Option var prefix: String?
    @Argument(parsing: .captureForPassthrough) var args: [String] = []

    func run() throws {
        let prefix = try prefix.map { try Prefix(url: URL(filePath: $0).standardizedFileURL, backend: backend) }
            ?? Prefix.forApp(nil, backend: backend)
        try prefix.prepare()
        try exec(prefix.wineCommand(args))
    }
}

struct Compat: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show what the compatibility database (highball-db) knows about a game.")

    @Argument var appID: UInt32

    func run() throws {
        guard let db = CompatDB.shared else { throw NeutronError("compat.json not found") }
        guard let entry = db.entry(appID: appID) else { return print("no entry for \(appID)") }
        print(entry.title)
        if entry.tested { print("status: \(entry.status)\(entry.lastVerified.map { ", verified \($0)" } ?? "")") }
        if let renderer = entry.renderer {
            print("renderer: \(renderer)\(entry.backend == nil ? " (not in Neutron, which uses dxmt)" : "")")
        }
        if let args = entry.launchArgs { print("launch args: \(args.joined(separator: " "))") }
        if let anticheat = entry.anticheat, let names = anticheat.names {
            print("anti-cheat: \(names.joined(separator: ", "))\(anticheat.macVerdict.map { " (\($0))" } ?? "")")
        }
        if entry.nativeMac == true { print("native macOS version available") }
        if let summary = entry.summary { print(summary) }
        print("source: \(db.source)")
    }
}

func exec(_ command: Command) throws -> Never {
    if let dir = command.workingDirectory {
        FileManager.default.changeCurrentDirectoryPath(dir.path)
    }
    let argv = ([command.executable.path] + command.arguments).map { strdup($0) } + [nil]
    let envp = command.environment.map { strdup("\($0)=\($1)") } + [nil]
    execve(command.executable.path, argv, envp)
    throw NeutronError("exec \(command.executable.path) failed: \(String(cString: strerror(errno)))")
}

struct WindowsSteamCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "windows-steam",
        abstract: "Valve's Windows Steam client in its own prefix, for games that need it (VAC).",
        discussion: "Neutron runs the unmodified client with its window shown and uses only Steam's own command-line options and steam:// URLs. Sign in and confirm installs in Steam's window.",
        subcommands: [Start.self, Status.self, InstallGame.self, Launch.self, Stop.self]
    )

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install if needed and start the client, or show its window.")
        @Flag(help: "Start in the tray without opening the window.") var silent = false

        func run() async throws {
            print("starting Windows Steam (the first start downloads and installs its update)…")
            try await WindowsSteam().start(silent: silent)
            print("running; sign in through Steam's window if you haven't")
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show whether the client runs, who is signed in and which game runs.")

        func run() throws {
            let status = try WindowsSteam().status()
            guard status.running else { return print("not running") }
            print(status.signedIn ? "signed in as \(status.account ?? "?")" : "running, not signed in")
            if let appID = status.runningAppID { print("running app \(appID)") }
        }
    }

    struct InstallGame: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "install", abstract: "Open Steam's install dialog for a game.")
        @Argument var appID: UInt32

        func run() throws {
            try WindowsSteam().install(appID: appID)
            print("confirm the install in Steam's window")
        }
    }

    struct Launch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Launch a game through the client.")
        @Argument var appID: UInt32

        func run() async throws {
            let steam = try WindowsSteam()
            try await steam.start(silent: true)
            try steam.launch(appID: appID)
            print("launch requested for \(appID)")
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Shut the client down.")

        func run() async throws {
            try await WindowsSteam().stop()
            print("stopped")
        }
    }
}
