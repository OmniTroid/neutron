import AppKit
import NeutronKit
import SwiftUI

@main
struct NeutronApp: App {
    @State private var model = AppModel()

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
                ContentUnavailableView("Select a Game", systemImage: "gamecontroller",
                                       description: Text("Your Windows games from Steam appear in the sidebar."))
                    .background(Theme.background)
            }
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh library")
            }
        }
        .task {
            await model.load()
            #if DEBUG
            await debugSnapshot()
            #endif
        }
        .sheet(item: $model.prompt) { LoginSheet(prompt: $0) }
        .sheet(isPresented: Binding(get: { model.accountRequestFor != nil },
                                    set: { if !$0 { model.accountRequestFor = nil } })) {
            AccountSheet()
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
