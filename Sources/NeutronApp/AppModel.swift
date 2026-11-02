import AppKit
import NeutronKit
import Observation

@MainActor @Observable
final class AppModel {
    var startingSteam = false
    var startingGame = false
    var errorMessage: String?
    private var reported: Set<String> = []
    private var steam: Task<WindowsSteam, Error>?

    /// Warns about anything not rendering with DXMT while the window is open.
    func monitor() async {
        while !Task.isCancelled {
            guard let steam = try? await client() else { return }
            let status = await Task.detached(priority: .utility) { try? steam.status() }.value
            let new = (status?.fallbacks ?? []).map(\.description).filter { !reported.contains($0) }
            if !new.isEmpty {
                reported.formUnion(new)
                errorMessage = "Not rendering with DXMT:\n" + new.joined(separator: "\n")
            }
            try? await Task.sleep(for: .seconds(6))
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
            } catch {
                errorMessage = "Couldn't start \(game.lastPathComponent): \(error)"
            }
        }
    }
}
