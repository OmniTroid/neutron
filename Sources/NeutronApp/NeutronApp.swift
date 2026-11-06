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
        .defaultSize(width: 940, height: 680)
        .commands {
            CheckForUpdatesCommand(updater: updater)
        }
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Wine prefix") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Paths.steamPrefix.path)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open in Finder") {
                        try? FileManager.default.createDirectory(at: Paths.steamPrefix, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(Paths.steamPrefix)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var choosingGame = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HeaderView()
                    .layoutPriority(1)
                Spacer(minLength: 0)
                SearchField(text: $model.search)
                    .frame(minWidth: 120, maxWidth: 220)
                Button { choosingGame = true } label: {
                    Label(model.startingGame ? "Starting…" : "Open Other Game…", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("o")
                .disabled(model.startingGame)
                .help("Run a Windows program that isn't in Steam")
                .fixedSize()

                Button { model.launchSteam() } label: {
                    Label(steamButtonTitle, systemImage: model.status.running ? "macwindow" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.startingSteam)
                .fixedSize()
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            LibraryView()
        }
        .frame(minWidth: 760, minHeight: 480)
        .fileImporter(isPresented: $choosingGame, allowedContentTypes: [UTType(filenameExtension: "exe") ?? .data]) { result in
            switch result {
            case .success(let game): model.load(game: game)
            case .failure(let error): model.errorMessage = "Couldn't open the file: \(error.localizedDescription)"
            }
        }
        .onOpenURL { model.load(game: $0) }
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

    private var steamButtonTitle: String {
        if model.startingSteam { return "Starting Steam…" }
        return model.status.running ? "Show Steam" : "Launch Steam"
    }
}

struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        .background {
            Button("") { focused = true }.keyboardShortcut("f").hidden()
        }
        // macOS focuses the first text field in a new window; the library is what's wanted first
        .task { focused = false }
    }
}

/// The app's name and one line on what Steam is doing.
struct HeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Neutron")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize()
                }
                .animation(.default, value: statusText)
            }
        }
    }

    private var statusText: String {
        let status = model.status
        if model.startingSteam && !status.running { return "Starting Steam…" }
        guard status.running else { return "Steam isn't running" }
        if status.runningAppID != nil { return "Playing \(model.runningGameName ?? "a game")" }
        guard status.signedIn else { return "Steam is running · not signed in" }
        return status.account.map { "Signed in as \($0)" } ?? "Signed in"
    }

    /// Green while something runs, grey otherwise: colour only for state.
    private var dotColor: Color {
        let status = model.status
        if status.runningAppID != nil || status.signedIn { return .green }
        if status.running || model.startingSteam { return .orange }
        return Color.secondary.opacity(0.5)
    }
}

struct RecentGamesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.recentGames, id: \.path) { game in
                RecentGameRow(game: game)
                if game != model.recentGames.last {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct RecentGameRow: View {
    @Environment(AppModel.self) private var model
    let game: URL
    @State private var hovering = false

    var body: some View {
        Button { model.load(game: game) } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: game.path))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.deletingLastPathComponent().lastPathComponent)
                        .font(.body)
                    Text(game.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.05) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(model.startingGame)
        .help(game.path)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game]) }
            Button("Remove from List") { model.forget(game: game) }
        }
    }
}

#if DEBUG
extension ContentView {
    /// NEUTRON_SNAPSHOT=<png>: render the window to a PNG and quit, for design review.
    func debugSnapshot() async {
        if ProcessInfo.processInfo.environment["NEUTRON_SHOW_SETTINGS"] != nil {
            openSettings()
        }
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
