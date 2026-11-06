import AppKit
import NeutronKit
import Observation

@MainActor @Observable
final class AppModel {
    var startingSteam = false
    var startingGame = false
    var errorMessage: String?
    var status = WindowsSteam.Status(running: false, signedIn: false)
    /// The name Steam knows the running game by, looked up once per app ID.
    var runningGameName: String?
    private var namedAppID: UInt32?
    /// Owned Windows games and their install state, read from the client's caches.
    var games: [SteamGame] = []
    var states: [UInt32: AppState] = [:]
    var loadingLibrary = true
    var search = ""
    /// Games asked to start or install, until Steam reports back.
    var pending: Set<UInt32> = []
    private var libraryAccount: String?
    var recentGames = RecentPrograms().load()
    private var reported: Set<String> = []
    private var steam: Task<WindowsSteam, Error>?

    private func log(fallbacks: [String]) {
        let stamp = Date.now.ISO8601Format()
        let lines = fallbacks.map { "\(stamp) \($0)\n" }.joined()
        try? FileManager.default.createDirectory(at: Paths.fallbackLog.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let file = try? FileHandle(forWritingTo: Paths.fallbackLog) {
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data(lines.utf8))
            try? file.close()
        } else {
            try? Data(lines.utf8).write(to: Paths.fallbackLog)
        }
    }

    /// Logs anything not rendering with DXMT while the window is open.
    func monitor() async {
        while !Task.isCancelled {
            guard let steam = try? await client() else { return }
            let status = await Task.detached(priority: .utility) { try? steam.status() }.value
            if let status, status != self.status {
                self.status = status
                await name(runningApp: status.runningAppID)
            }
            await refreshLibrary()
            let new = (status?.fallbacks ?? []).map(\.description).filter { !reported.contains($0) }
            if !new.isEmpty {
                reported.formUnion(new)
                log(fallbacks: new)
            }
            try? await Task.sleep(for: .seconds(6))
        }
    }

    private func name(runningApp appID: UInt32?) async {
        guard appID != namedAppID else { return }
        namedAppID = appID
        guard let appID else { runningGameName = nil; return }
        runningGameName = await Task.detached(priority: .utility) {
            (try? AppInfo.read(appID: appID))?["common"]?["name"]?.text
                ?? CompatDB.shared?.entry(appID: appID)?.title
        }.value
    }

    /// Reads the owned games once per signed-in account, and install states on every pass.
    func refreshLibrary() async {
        let account = status.signedIn ? status.account ?? "" : nil
        let reloadGames = games.isEmpty || account != libraryAccount
        let (games, states) = await Task.detached(priority: .utility) {
            (reloadGames ? try? SteamLibrary.games() : nil, SteamApps.states())
        }.value
        if let games, !games.isEmpty || account != nil {
            self.games = games
            libraryAccount = account
        }
        if states != self.states { self.states = states }
        loadingLibrary = false
        if let running = status.runningAppID { pending.remove(running) }
        pending.subtract(states.filter { $0.value.updating }.keys)
    }

    var installedGames: [SteamGame] { filtered.filter { states[$0.appID]?.installed == true || states[$0.appID]?.updating == true } }
    var otherGames: [SteamGame] { filtered.filter { states[$0.appID] == nil } }

    private var filtered: [SteamGame] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? games : games.filter { $0.name.localizedStandardContains(query) }
    }

    /// Starts an installed game, starting Steam first when it isn't running.
    func play(_ game: SteamGame) {
        steamAction(game, verb: "start") { try $0.launch(appID: game.appID) }
    }

    /// Opens Steam's install dialog, where the user picks the drive and confirms.
    func install(_ game: SteamGame) {
        if let entry = CompatDB.shared?.entry(appID: game.appID), entry.blocked {
            errorMessage = "\(game.name) is listed as not working on Neutron\(entry.summary.map { ": \($0)" } ?? ".") Install it from Steam's window to try anyway."
            return
        }
        steamAction(game, verb: "install") { try $0.install(appID: game.appID) }
    }

    func uninstall(_ game: SteamGame) {
        steamAction(game, verb: "uninstall", track: false) { try $0.uninstall(appID: game.appID) }
    }

    func showInSteam(_ game: SteamGame) {
        steamAction(game, verb: "show", track: false) { try $0.open("steam://nav/games/details/\(game.appID)") }
    }

    func revealInstall(_ game: SteamGame) {
        guard let dir = states[game.appID]?.directory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    private func steamAction(_ game: SteamGame, verb: String, track: Bool = true,
                             _ action: @escaping @Sendable (WindowsSteam) throws -> Void) {
        if track { pending.insert(game.appID) }
        Task {
            do {
                let steam = try await client()
                if !status.running {
                    startingSteam = true
                    defer { startingSteam = false }
                    try await steam.start()
                }
                try await Task.detached(priority: .userInitiated) { try action(steam) }.value
                // Steam's dialogs only show while Wine is the active app
                if !track || verb == "install", let pid = await Task.detached(operation: { steam.windowProcessID() }).value {
                    NSRunningApplication(processIdentifier: pid)?.activate()
                }
            } catch {
                errorMessage = "Couldn't \(verb) \(game.name): \(error)"
            }
            if track {
                // a launch that never shows up in Steam's state shouldn't spin forever
                try? await Task.sleep(for: .seconds(45))
                pending.remove(game.appID)
            }
        }
    }

    private func client() async throws -> WindowsSteam {
        // the first call assembles the runtime, which copies files: everything that asks at startup shares it
        if let steam { return try await steam.value }
        let steam = Task.detached(priority: .userInitiated) { try WindowsSteam() }
        self.steam = steam
        do {
            return try await steam.value
        } catch {
            self.steam = nil
            throw error
        }
    }

    func launchSteam() {
        startingSteam = true
        Task {
            defer { startingSteam = false }
            do {
                let steam = try await client()
                try await steam.start()
                // macOS doesn't bring an app launched in the background forward, and Wine shows windows only when active
                if let pid = await Task.detached(operation: { steam.windowProcessID() }).value {
                    NSRunningApplication(processIdentifier: pid)?.activate()
                }
            } catch {
                errorMessage = "Couldn't start Steam: \(error)"
            }
        }
    }

    func load(game: URL) {
        startingGame = true
        Task {
            defer { startingGame = false }
            let access = game.startAccessingSecurityScopedResource()
            defer { if access { game.stopAccessingSecurityScopedResource() } }
            do {
                let steam = try await client()
                try await Task.detached(priority: .userInitiated) { try steam.launch(program: game) }.value
                recentGames = RecentPrograms().load()
            } catch {
                errorMessage = "Couldn't start \(game.lastPathComponent): \(error)"
            }
        }
    }

    func forget(game: URL) {
        RecentPrograms().remove(game)
        recentGames = RecentPrograms().load()
    }
}
