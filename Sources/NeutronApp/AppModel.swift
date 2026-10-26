import AppKit
import NeutronKit
import Observation

@MainActor @Observable
final class Download {
    var progress: Double?
    var status = "Starting…"
    var session: InstallSession?
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case installed = "Installed"
    case windowsOnly = "Windows only"

    var id: Self { self }
}

struct PendingPrompt: Identifiable {
    let appID: UInt32
    let prompt: InstallPrompt
    var id: String { "\(appID)-\(prompt)" }
}

@MainActor @Observable
final class AppModel {
    var games: [SteamGame] = []
    var installed: Set<UInt32> = []
    var downloads: [UInt32: Download] = [:]
    var running: [UInt32: GameSession] = [:]
    var launching: Set<UInt32> = []
    var selection: UInt32?
    var search = ""
    var filter: LibraryFilter = .all
    var config = Config.load()
    var prompt: PendingPrompt?
    var accountRequestFor: UInt32?
    var errorMessage: String?
    var loading = true

    var selectedGame: SteamGame? { games.first { $0.appID == selection } }

    var visibleGames: [SteamGame] {
        games.filter { game in
            switch filter {
            case .all: true
            case .installed: installed.contains(game.appID) || downloads[game.appID] != nil
            case .windowsOnly: !game.hasMacVersion
            }
        }
        .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var steamIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.valvesoftware.steam").isEmpty
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let (games, installed) = try await Task.detached(priority: .userInitiated) {
                let games = try SteamLibrary.games()
                return (games, Set(games.map(\.appID).filter { SteamLibrary.isInstalled($0) }))
            }.value
            self.games = games
            self.installed = installed
            if selection == nil { selection = games.first { installed.contains($0.appID) }?.appID ?? games.first?.appID }
        } catch {
            errorMessage = "Couldn't read your Steam library: \(error)"
        }
    }

    func backend(for game: SteamGame) -> Backend { config.backend(for: game.appID) }

    func setBackend(_ backend: Backend, for game: SteamGame) {
        config.backends = (config.backends ?? [:]).merging([String(game.appID): backend.rawValue]) { $1 }
        try? config.save()
    }

    // MARK: Install

    func install(_ game: SteamGame) {
        guard let user = config.user else {
            accountRequestFor = game.appID
            return
        }
        guard let info = try? AppInfo.read(appID: game.appID),
              let installedGame = InstalledGame(appID: game.appID, appInfo: info) else {
            errorMessage = "Steam has no Windows launch option for \(game.name)."
            return
        }

        let download = Download()
        downloads[game.appID] = download
        let appID = game.appID
        Task {
            do {
                download.session = try await InstallSession(game: installedGame, user: user) { event in
                    Task { @MainActor in self.handle(event, for: appID) }
                }
            } catch {
                downloads[appID] = nil
                errorMessage = "\(error)"
            }
        }
    }

    func setAccount(_ user: String) {
        config.user = user
        try? config.save()
        if let appID = accountRequestFor, let game = games.first(where: { $0.appID == appID }) {
            accountRequestFor = nil
            install(game)
        }
    }

    func cancelDownload(_ game: SteamGame) {
        downloads[game.appID]?.session?.cancel()
    }

    func answer(_ prompt: PendingPrompt, with text: String?) {
        self.prompt = nil
        guard let session = downloads[prompt.appID]?.session else { return }
        if let text { session.respond(text) } else { session.cancel() }
    }

    private func handle(_ event: InstallEvent, for appID: UInt32) {
        guard let download = downloads[appID] else { return }
        switch event {
        case .status(let status):
            download.status = status
        case .progress(let progress):
            download.progress = progress
        case .prompt(.mobileConfirmation):
            download.status = "Approve the sign-in in the Steam Mobile app…"
        case .prompt(let prompt):
            self.prompt = PendingPrompt(appID: appID, prompt: prompt)
        case .finished(.success):
            downloads[appID] = nil
            installed.insert(appID)
        case .finished(.failure(let error)):
            downloads[appID] = nil
            if prompt?.appID == appID { prompt = nil }
            if error.description != "Download cancelled" { errorMessage = error.description }
        }
    }

    // MARK: Play

    func play(_ game: SteamGame) {
        let appID = game.appID
        let backend = backend(for: game)
        launching.insert(appID)
        Task {
            defer { launching.remove(appID) }
            do {
                running[appID] = try await Task.detached(priority: .userInitiated) {
                    let launch = Library.launch(try Library.game(appID: appID))
                    let prefix = try Prefix.forApp(appID, backend: backend)
                    try prefix.prepare()
                    let command = prefix.gameCommand(appID: appID, exe: launch.exe,
                                                     workingDirectory: launch.workingDirectory, arguments: launch.arguments)
                    return try GameSession(prefix: prefix, command: command) { _ in
                        Task { @MainActor in self.running[appID] = nil }
                    }
                }.value
            } catch {
                errorMessage = "Couldn't launch \(game.name): \(error)"
            }
        }
    }

    func stop(_ game: SteamGame) {
        guard let session = running[game.appID] else { return }
        Task.detached { session.stop() }
    }

    // MARK: Files

    func uninstall(_ game: SteamGame) {
        do {
            try FileManager.default.removeItem(at: Library.directory(appID: game.appID))
            installed.remove(game.appID)
        } catch {
            errorMessage = "Couldn't uninstall \(game.name): \(error)"
        }
    }

    func revealInstall(_ game: SteamGame) {
        NSWorkspace.shared.activateFileViewerSelecting([Library.directory(appID: game.appID)])
    }

    func openLog(_ game: SteamGame) {
        let log = Paths.prefixes.appending(path: "\(game.appID)/neutron.log")
        if FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.open(log)
        } else {
            errorMessage = "\(game.name) hasn't been launched yet."
        }
    }

    func openInSteam(_ game: SteamGame) {
        NSWorkspace.shared.open(URL(string: "steam://nav/games/details/\(game.appID)")!)
    }

    func openStorePage(_ game: SteamGame) {
        NSWorkspace.shared.open(URL(string: "steam://store/\(game.appID)")!)
    }

    func launchSteam() {
        NSWorkspace.shared.open(URL(string: "steam://open/main")!)
    }
}
