import ArgumentParser
import Foundation
import NeutronKit

@main
struct Neutron: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run Windows Steam games on macOS through Wine, bridged to the native Steam client.",
        subcommands: [Install.self, Run.self, Wine.self, WindowsSteamCommand.self]
    )
}

extension Backend: ExpressibleByArgument {}

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Download a game's Windows build.")

    @Argument var appID: UInt32
    @Option(help: "Steam account; prompts for login once, remembered afterwards.") var user: String?

    func run() async throws {
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
    @Option var backend: Backend = .dxmt
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
        abstract: "Proof of concept: drive a hidden Windows Steam client (for VAC games).",
        subcommands: [Start.self, Login.self, Launch.self, Stop.self]
    )

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install if needed and start Windows Steam with no windows.")

        func run() async throws {
            let steam = try WindowsSteam()
            print("starting Windows Steam (the first start downloads its update)…")
            try await steam.start()
            print(await steam.isLoginScreenShown ? "running, not signed in: run `neutron windows-steam login`"
                                                  : "running, signed in as \(await steam.signedInAccount() ?? "?")")
        }
    }

    struct Login: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Sign in by scanning a QR code with the Steam Mobile app.")

        func run() async throws {
            setvbuf(stdout, nil, _IOLBF, 0)
            let steam = try WindowsSteam()
            guard await steam.isRunning else { throw NeutronError("Windows Steam isn't running; run `neutron windows-steam start`") }
            var shown: [[Bool]]?
            while await steam.isLoginScreenShown {
                if let code = try? await steam.loginQRCode(), code != shown {
                    shown = code
                    print("\u{1B}[2J\u{1B}[H" + renderQR(code))
                    print("Scan with the Steam Mobile app (Steam Guard > Scan QR code). Waiting…")
                }
                try await Task.sleep(for: .seconds(2))
            }
            try await Task.sleep(for: .seconds(3))
            print("signed in as \(await steam.signedInAccount() ?? "?")")
        }
    }

    struct Launch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Launch an installed game through Windows Steam.")
        @Argument var appID: UInt32

        func run() async throws {
            let steam = try WindowsSteam()
            try await steam.launch(appID: appID)
            print("launch requested for \(appID)")
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Shut Windows Steam down.")

        func run() async throws {
            try await WindowsSteam().stop()
            print("stopped")
        }
    }
}

/// Renders QR modules with half blocks (two module rows per line) and a quiet zone, light on dark terminals.
func renderQR(_ modules: [[Bool]]) -> String {
    let quiet = 2
    let size = modules.count + quiet * 2
    func dark(_ x: Int, _ y: Int) -> Bool {
        let mx = x - quiet, my = y - quiet
        return mx >= 0 && my >= 0 && my < modules.count && mx < modules.count && modules[my][mx]
    }
    var lines: [String] = []
    for y in stride(from: 0, to: size, by: 2) {
        var line = ""
        for x in 0..<size {
            switch (dark(x, y), dark(x, y + 1)) {
            case (false, false): line += "\u{2588}"
            case (true, false): line += "\u{2584}"
            case (false, true): line += "\u{2580}"
            case (true, true): line += " "
            }
        }
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}
