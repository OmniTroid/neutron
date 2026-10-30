import AppKit
import ArgumentParser
import Foundation
import NeutronKit

@main
struct Neutron: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run Valve's Windows Steam client on macOS through Wine and DXMT.",
        discussion: "Neutron runs the unmodified client with its window shown and uses only Steam's own command-line options and steam:// URLs. Sign in, confirm installs and accept prompts in Steam's window.",
        subcommands: [Start.self, Status.self, Stop.self, List.self, Install.self, Uninstall.self, Launch.self,
                      Compat.self, Wine.self]
    )
}

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Install Steam if needed and start it, or show its window.")
    @Flag(help: "Start in the tray without opening the window.") var silent = false

    func run() async throws {
        print("starting Steam (the first start downloads and installs its update)…")
        let steam = try WindowsSteam()
        try await steam.start(silent: silent)
        // macOS doesn't bring an app launched in the background forward, and Wine shows windows only when active
        if !silent, let pid = steam.windowProcessID() {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        print("running; sign in through Steam's window if you haven't")
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show whether Steam runs, who is signed in and which game runs.")

    func run() throws {
        let status = try WindowsSteam().status()
        if !status.running {
            print("not running")
        } else {
            print(status.signedIn ? "signed in as \(status.account ?? "?")" : "running, not signed in")
            if let appID = status.runningAppID { print("running app \(appID)") }
        }
        warn(status.fallbacks)
        if !status.fallbacks.isEmpty { throw ExitCode(2) }
    }
}

func warn(_ fallbacks: [GraphicsCheck.Fallback]) {
    for fallback in fallbacks {
        FileHandle.standardError.write(Data("NOT DXMT: \(fallback)\n".utf8))
    }
}

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Quit Steam and everything running in its prefix.")

    func run() async throws {
        try await WindowsSteam().stop()
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List owned Windows games and their install state.")
    @Flag(help: "Only installed games.") var installed = false

    func run() throws {
        let states = SteamApps.states()
        for game in try SteamLibrary.games() {
            let state = states[game.appID]
            guard !installed || state?.installed == true else { continue }
            let label = state.map { $0.updating ? "updating" : $0.installed ? "installed" : "partial" } ?? ""
            print("\(game.appID)\t\(game.name)\t\(label)")
        }
    }
}

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open Steam's install dialog for a game.")
    @Argument var appID: UInt32
    @Flag(help: "Install even if the compatibility database lists the game as blocked.") var force = false

    func run() throws {
        if let entry = CompatDB.shared?.entry(appID: appID), entry.blocked {
            let reason = "\(entry.title) is listed as not working on macOS: \(entry.summary ?? entry.status)"
            guard force else { throw NeutronError("\(reason) Pass --force to install anyway.") }
            print("neutron: \(reason)")
        }
        try WindowsSteam().install(appID: appID)
        print("confirm the install in Steam's window")
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open Steam's uninstall confirmation for a game.")
    @Argument var appID: UInt32

    func run() throws {
        try WindowsSteam().uninstall(appID: appID)
    }
}

struct Launch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch a game through Steam.")
    @Argument var appID: UInt32

    func run() async throws {
        let steam = try WindowsSteam()
        try await steam.start(silent: true)
        let before = Set(steam.fallbacks())
        try steam.launch(appID: appID)
        // a game picks its renderer while it starts
        var reported = before
        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(1))
            let new = steam.fallbacks().filter { !reported.contains($0) }
            warn(new)
            reported.formUnion(new)
        }
        if reported.count > before.count { throw ExitCode(2) }
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
        if let renderer = entry.renderer { print("tested with: \(renderer)") }
        if let args = entry.launchArgs { print("launch options: \(args.joined(separator: " "))") }
        if let anticheat = entry.anticheat, let names = anticheat.names {
            print("anti-cheat: \(names.joined(separator: ", "))\(anticheat.macVerdict.map { " (\($0))" } ?? "")")
        }
        if entry.nativeMac == true { print("native macOS version available") }
        if let summary = entry.summary { print(summary) }
        print("source: \(db.source)")
    }
}

struct Wine: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a raw wine command in Steam's prefix.")
    @Argument(parsing: .captureForPassthrough) var args: [String] = []

    func run() throws {
        let steam = try WindowsSteam()
        let argv = ([steam.wine.path] + args).map { strdup($0) } + [nil]
        let envp = steam.environment.map { strdup("\($0)=\($1)") } + [nil]
        execve(steam.wine.path, argv, envp)
        throw NeutronError("exec \(steam.wine.path) failed: \(String(cString: strerror(errno)))")
    }
}
