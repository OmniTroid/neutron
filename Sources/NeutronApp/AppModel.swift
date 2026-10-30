import AppKit
import NeutronKit
import Observation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case installed = "Installed"

    var id: Self { self }
}

@MainActor @Observable
final class AppModel {
    var games: [SteamGame] = []
    var states: [UInt32: AppState] = [:]
    var status = WindowsSteam.Status(running: false, signedIn: false)
    var startingSteam = false
    var launching: Set<UInt32> = []
    var selection: UInt32?
    var search = ""
    var filter: LibraryFilter = .all
    var errorMessage: String?
    var loading = true
    private var steam: WindowsSteam?

    var selectedGame: SteamGame? { games.first { $0.appID == selection } }

    var visibleGames: [SteamGame] {
        games.filter { filter == .all || states[$0.appID] != nil }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    func isRunning(_ game: SteamGame) -> Bool { status.runningAppID == game.appID }

    func load() async {
        loading = true
        defer { loading = false }
        // empty until Steam has signed in once and cached the account's licenses
        let games = await Task.detached(priority: .userInitiated) { (try? SteamLibrary.games()) ?? [] }.value
        self.games = games
        states = await Task.detached(priority: .userInitiated) { SteamApps.states() }.value
        if selection == nil { selection = games.first { states[$0.appID]?.installed == true }?.appID ?? games.first?.appID }
    }

    /// Follows the client's own files and registry while the window is open.
    func monitor() async {
        var tick = 0
        while !Task.isCancelled {
            states = await Task.detached(priority: .utility) { SteamApps.states() }.value
            if tick % 3 == 0, let steam = try? await client() {
                let status = await Task.detached(priority: .utility) {
                    (try? steam.status()) ?? WindowsSteam.Status(running: false, signedIn: false)
                }.value
                if status.signedIn && !self.status.signedIn { await load() }
                let new = status.fallbacks.filter { !self.status.fallbacks.contains($0) }
                if !new.isEmpty {
                    errorMessage = "Not rendering with DXMT:\n" + new.map(\.description).joined(separator: "\n")
                }
                self.status = status
            }
            tick += 1
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func client() async throws -> WindowsSteam {
        if let steam { return steam }
        // the first call assembles the runtime, which copies files
        let steam = try await Task.detached(priority: .userInitiated) { try WindowsSteam() }.value
        self.steam = steam
        return steam
    }

    // MARK: Steam

    func showSteam() {
        startingSteam = true
        Task {
            defer { startingSteam = false }
            do {
                try await client().start()
            } catch {
                errorMessage = "Couldn't start Steam: \(error)"
            }
        }
    }

    /// Starts Steam in the tray if needed, then hands it a request.
    private func request(_ what: String, _ action: @escaping @Sendable (WindowsSteam) throws -> Void) {
        Task {
            do {
                let steam = try await client()
                if !status.running { startingSteam = true }
                defer { startingSteam = false }
                try await steam.start(silent: true)
                try await Task.detached { try action(steam) }.value
            } catch {
                errorMessage = "Couldn't \(what): \(error)"
            }
        }
    }

    // MARK: Games

    func install(_ game: SteamGame) {
        let appID = game.appID
        request("install \(game.name)") { try $0.install(appID: appID) }
    }

    func uninstall(_ game: SteamGame) {
        let appID = game.appID
        request("uninstall \(game.name)") { try $0.uninstall(appID: appID) }
    }

    func verify(_ game: SteamGame) {
        let appID = game.appID
        request("verify \(game.name)") { try $0.open("steam://validate/\(appID)") }
    }

    func play(_ game: SteamGame) {
        let appID = game.appID
        launching.insert(appID)
        request("launch \(game.name)") { try $0.launch(appID: appID) }
        Task {
            try? await Task.sleep(for: .seconds(20))
            launching.remove(appID)
        }
    }

    func showInSteam(_ game: SteamGame) {
        let appID = game.appID
        request("open \(game.name) in Steam") { try $0.open("steam://nav/games/details/\(appID)") }
    }

    func showDownloads() {
        request("open Steam's downloads") { try $0.open("steam://open/downloads") }
    }

    func openStorePage(_ game: SteamGame) {
        NSWorkspace.shared.open(URL(string: "https://store.steampowered.com/app/\(game.appID)")!)
    }

    func revealInstall(_ game: SteamGame) {
        guard let dir = states[game.appID]?.directory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
