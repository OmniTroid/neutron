import AppKit
import NeutronKit
import SwiftUI

/// Owned games as cover art: installed first, then the rest of the library, then programs started from outside Steam.
struct LibraryView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 168), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if model.games.isEmpty {
                    emptyState
                } else if model.installedGames.isEmpty && model.otherGames.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                        .padding(.top, 40)
                } else {
                    section("Installed", model.installedGames)
                    section("Library", model.otherGames)
                }
                if !model.recentGames.isEmpty && model.search.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Other Games", count: model.recentGames.count)
                        RecentGamesView()
                            .frame(maxWidth: 420)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ games: [SteamGame]) -> some View {
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: title, count: games.count)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(games) { GameTile(game: $0) }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Group {
            if model.loadingLibrary {
                ProgressView().controlSize(.small)
            } else if !model.status.signedIn {
                ContentUnavailableView {
                    Label("No Games Yet", systemImage: "gamecontroller")
                } description: {
                    Text("Sign in to Steam and your Windows games show up here.")
                } actions: {
                    Button(model.status.running ? "Show Steam" : "Launch Steam") { model.launchSteam() }
                        .disabled(model.startingSteam)
                }
            } else {
                ContentUnavailableView("No Windows Games", systemImage: "gamecontroller",
                                       description: Text("Games you own with a Windows version show up here."))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct SectionTitle: View {
    let text: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.headline)
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }
}

/// A game's portrait capsule with its name and what it's doing. Click plays an installed game or installs it.
struct GameTile: View {
    @Environment(AppModel.self) private var model
    let game: SteamGame
    @State private var hovering = false

    private var state: AppState? { model.states[game.appID] }
    private var installed: Bool { state?.installed == true && state?.updating != true }
    private var running: Bool { model.status.runningAppID == game.appID }
    private var pending: Bool { model.pending.contains(game.appID) }

    var body: some View {
        Button(action: primary) {
            VStack(alignment: .leading, spacing: 8) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name)
                        .font(.callout)
                        .lineLimit(1)
                    detail
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(game.name)
        .contextMenu { menu }
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                SteamImage(game: game, artwork: .capsule) {
                    ZStack {
                        Rectangle().fill(.quinary)
                        Text(game.name)
                            .font(.callout.weight(.medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.primary.opacity(hovering ? 0.25 : 0.08))
            }
            .overlay { badge }
            .saturation(installed || running || state?.updating == true ? 1 : 0.35)
            .opacity(installed || running || state?.updating == true ? 1 : 0.8)
            .animation(.easeOut(duration: 0.15), value: hovering)
    }

    /// The action a click takes, shown on hover; progress while Steam works on it.
    @ViewBuilder
    private var badge: some View {
        if let state, state.updating {
            ProgressRing(value: state.progress ?? 0)
        } else if pending {
            ProgressView().controlSize(.small)
                .padding(10)
                .background(.thinMaterial, in: Circle())
        } else if hovering && !running {
            Image(systemName: installed ? "play.fill" : "arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.thinMaterial, in: Circle())
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if running {
            HStack(spacing: 5) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Playing")
            }
        } else if let state, state.updating {
            Text(state.paused ? "Paused" : progressText(state))
        } else if pending {
            Text(installed ? "Starting…" : "Opening Steam…")
        } else if installed, let state, state.sizeOnDisk > 0 {
            Text(bytes(state.sizeOnDisk))
        } else if !installed, let size = game.installSize {
            Text(bytes(size))
        } else {
            Text(installed ? "Installed" : "Not installed")
        }
    }

    @ViewBuilder
    private var menu: some View {
        if installed {
            Button("Play") { model.play(game) }.disabled(running)
        } else if state == nil {
            Button("Install…") { model.install(game) }
        }
        Button("Show in Steam") { model.showInSteam(game) }
        if state != nil {
            Button("Show in Finder") { model.revealInstall(game) }
            Divider()
            Button("Uninstall…") { model.uninstall(game) }
        }
    }

    private func primary() {
        guard !pending, !running, state?.updating != true else { return }
        installed ? model.play(game) : model.install(game)
    }

    private func progressText(_ state: AppState) -> String {
        guard let progress = state.progress else { return "Preparing…" }
        if state.bytesDownloaded == 0 { return "Queued · \(bytes(state.bytesToDownload))" }
        return "\(Int(progress * 100)) % of \(bytes(state.bytesToDownload))"
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, value))
                .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: value)
        }
        .frame(width: 26, height: 26)
        .padding(8)
        .background(.thinMaterial, in: Circle())
    }
}

@MainActor
private let imageCache = NSCache<NSString, NSImage>()

/// Finds and loads a game's art from Steam's library cache off the main thread, with a placeholder until it arrives.
struct SteamImage<Placeholder: View>: View {
    let game: SteamGame
    let artwork: Artwork
    @ViewBuilder var placeholder: Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .task(id: game.appID) {
            let key = "\(game.appID)/\(artwork)" as NSString
            if let cached = imageCache.object(forKey: key) {
                image = cached
                return
            }
            let (game, artwork) = (game, artwork)
            let loaded = await Task.detached(priority: .userInitiated) {
                artwork.url(for: game).flatMap { NSImage(contentsOf: $0) }
            }.value
            if let loaded { imageCache.setObject(loaded, forKey: key) }
            image = loaded
        }
    }
}
