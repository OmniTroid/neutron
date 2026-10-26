import Sparkle
import SwiftUI

/// Sparkle's standard updater; it reads the feed URL and public key from Info.plist.
@MainActor
final class Updater: ObservableObject {
    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published var canCheckForUpdates = false

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesCommand: Commands {
    @ObservedObject var updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
