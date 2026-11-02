import AppKit
import NeutronKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct NeutronApp: App {
    @State private var model = AppModel()
    @StateObject private var updater = Updater()

    init() {
        // lets `swift run NeutronApp` come to the front without an app bundle
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Neutron", id: "main") {
            ContentView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .commands {
            CheckForUpdatesCommand(updater: updater)
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var choosingGame = false

    var body: some View {
        VStack(spacing: 12) {
            Button { model.launchSteam() } label: {
                Label(model.startingSteam ? "Starting Steam…" : "Launch Steam", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.startingSteam)

            Button { choosingGame = true } label: {
                Label(model.startingGame ? "Starting…" : "Load Other Game…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.startingGame)
        }
        .controlSize(.extraLarge)
        .padding(32)
        .frame(width: 360)
        .fileImporter(isPresented: $choosingGame, allowedContentTypes: [UTType(filenameExtension: "exe") ?? .data]) { result in
            switch result {
            case .success(let game): model.load(game: game)
            case .failure(let error): model.errorMessage = "Couldn't open the file: \(error.localizedDescription)"
            }
        }
        .task { await model.monitor() }
        #if DEBUG
        .task { await debugSnapshot() }
        #endif
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil },
                                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#if DEBUG
extension ContentView {
    /// NEUTRON_SNAPSHOT=<png>: render the window to a PNG and quit, for design review.
    func debugSnapshot() async {
        guard let path = ProcessInfo.processInfo.environment["NEUTRON_SNAPSHOT"] else { return }
        try? await Task.sleep(for: .seconds(1))
        guard let window = NSApp.windows.first(where: \.isVisible), let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        NSApp.terminate(nil)
    }
}
#endif
