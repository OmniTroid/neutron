import AppKit
import NeutronKit
import SwiftUI

@main
struct NeutronApp: App {
    @State private var model = AppModel()
    @StateObject private var updater = Updater()

    init() {
        // lets `swift run NeutronApp` come to the front without an app bundle
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Neutron", id: "library") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1240, height: 800)
        .commands {
            CheckForUpdatesCommand(updater: updater)
            CommandGroup(after: .toolbar) {
                Button("Refresh Library") { Task { await model.load() } }
                    .keyboardShortcut("r")
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 380)
        } detail: {
            if let game = model.selectedGame {
                GameDetailView(game: game)
                    .id(game.appID)
            } else {
                ContentUnavailableView {
                    Label(model.games.isEmpty ? "Sign in to Steam" : "Select a Game", systemImage: "gamecontroller")
                } description: {
                    Text(model.games.isEmpty ? "Your library appears here once Steam has signed in." : "Your Windows games appear in the sidebar.")
                } actions: {
                    if !model.status.signedIn {
                        Button(model.status.running ? "Show Steam" : "Start Steam") { model.showSteam() }
                            .disabled(model.startingSteam)
                    }
                }
                    .background(Theme.background)
            }
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.showSteam() } label: { Image(systemName: "macwindow") }
                    .help(model.status.running ? "Show Steam" : "Start Steam")
                    .disabled(model.startingSteam)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh library")
            }
        }
        .task { await model.monitor() }
        .task {
            await model.load()
            #if DEBUG
            await debugSnapshot()
            #endif
        }
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
    /// NEUTRON_SNAPSHOT=<png> [NEUTRON_SNAPSHOT_APPID=<id>]: render the window to a PNG and quit, for design review.
    func debugSnapshot() async {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["NEUTRON_SNAPSHOT"] else { return }
        if let appID = env["NEUTRON_SNAPSHOT_APPID"].flatMap(UInt32.init) { model.selection = appID }
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: \.isVisible), let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        NSApp.terminate(nil)
    }
}
#endif
