import ArgumentParser
import Foundation
import NeutronKit

@main
struct Neutron: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run Windows Steam games on macOS through Wine, bridged to the native Steam client.",
        subcommands: [Install.self, Run.self, Wine.self]
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
