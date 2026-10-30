import NeutronKit
import SwiftUI

struct GameDetailView: View {
    @Environment(AppModel.self) private var model
    let game: SteamGame

    private var state: AppState? { model.states[game.appID] }
    private var installed: Bool { state?.installed == true }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                actionBar
                VStack(spacing: 16) {
                    if !model.status.fallbacks.isEmpty {
                        fallbackBanner
                    }
                    if !model.status.signedIn {
                        steamBanner
                    }
                    HStack(alignment: .top, spacing: 16) {
                        compatibilityCard
                        aboutCard
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .background {
            ZStack(alignment: .top) {
                Theme.background
                // Steam's blurred hero backdrop behind the page body
                Color.clear
                    .frame(height: 760)
                    .overlay {
                        SteamImage(url: Artwork.heroBlur.url(for: game)) { Color.clear }
                            .opacity(0.35)
                    }
                    .clipped()
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // overlay so the art's natural width can't widen the layout
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .overlay {
                    SteamImage(url: Artwork.hero.url(for: game) ?? Artwork.header.url(for: game)) {
                        LinearGradient(colors: [Theme.raised, Theme.background], startPoint: .top, endPoint: .bottom)
                    }
                }
                .clipped()

            LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                           .init(color: Theme.background.opacity(0.5), location: 0.8),
                                   .init(color: Theme.background.opacity(0.75), location: 1)],
                           startPoint: .top, endPoint: .bottom)

            SteamImage(url: Artwork.logo.url(for: game), contentMode: .fit) {
                Text(game.name)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
            }
            .frame(maxWidth: 380, maxHeight: 130, alignment: .bottomLeading)
            .shadow(color: .black.opacity(0.5), radius: 18, y: 4)
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(height: 380)
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 28) {
            primaryAction

            if let state, state.sizeOnDisk > 0 {
                stat("Size on disk", ByteCountFormatter.string(fromByteCount: state.sizeOnDisk, countStyle: .file))
            } else if let size = game.installSize {
                stat("Download size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            stat("Graphics", "DXMT · Metal")

            Spacer()

            HStack(spacing: 8) {
                Button { model.showInSteam(game) } label: { Image(systemName: "arrow.up.forward.app") }
                    .help("Show in Steam")
                Button { model.openStorePage(game) } label: { Image(systemName: "bag") }
                    .help("Store page")
                Menu {
                    if state != nil {
                        Button("Show in Finder", systemImage: "folder") { model.revealInstall(game) }
                        Divider()
                        Button("Verify Files", systemImage: "checkmark.shield") { model.verify(game) }
                        Button("Uninstall…", systemImage: "trash", role: .destructive) { model.uninstall(game) }
                    } else {
                        Button("Install", systemImage: "arrow.down.circle") { model.install(game) }
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuIndicator(.hidden)
                .menuStyle(.button)
                .help("Manage")
            }
            .buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .background(Theme.panel.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.4)).frame(height: 1) }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let state, state.updating || state.paused || !state.installed {
            DownloadProgress(state: state) { model.showDownloads() }
        } else if model.isRunning(game) {
            Button {} label: { Label("Running", systemImage: "gamecontroller.fill") }
                .buttonStyle(ActionButtonStyle(colors: Theme.stop))
                .disabled(true)
        } else if model.launching.contains(game.appID) {
            Button {} label: {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Launching")
                }
            }
            .buttonStyle(ActionButtonStyle(colors: Theme.play))
            .disabled(true)
        } else if installed {
            Button { model.play(game) } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(ActionButtonStyle(colors: Theme.play))
                .keyboardShortcut(.return, modifiers: .command)
        } else {
            Button { model.install(game) } label: { Label("Install", systemImage: "arrow.down.to.line") }
                .buttonStyle(ActionButtonStyle(colors: Theme.install))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: Cards

    private var fallbackBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Not rendering with DXMT").font(.system(size: 13, weight: .semibold))
                ForEach(model.status.fallbacks, id: \.self) { fallback in
                    Text(fallback.description)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.red.opacity(0.4)))
    }

    private var steamBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.running ? "Sign in to Steam" : "Steam isn't running").font(.system(size: 13, weight: .semibold))
                Text("Steam installs, updates and launches your games. Sign in and confirm prompts in its window.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button(model.status.running ? "Show Steam" : "Start Steam") { model.showSteam() }
                .controlSize(.large)
                .disabled(model.startingSteam)
        }
        .padding(14)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.yellow.opacity(0.25)))
    }

    private var compatibilityCard: some View {
        Card(title: "Compatibility") {
            VStack(alignment: .leading, spacing: 10) {
                if let entry = CompatDB.shared?.entry(appID: game.appID) {
                    compatReport(entry)
                    Divider()
                }
                Text("Direct3D 10 and 11 render through DXMT on Metal; other graphics APIs use Wine's own.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func compatReport(_ entry: CompatDB.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if entry.tested {
                    badge(entry.blocked ? "Doesn't work" : entry.status == "community" ? "Community report" : "Verified",
                          color: entry.blocked ? .red : .green)
                }
                if let anticheat = entry.anticheat?.names, !anticheat.isEmpty {
                    badge(anticheat.joined(separator: ", "), color: entry.blocked ? .red : .orange)
                }
                if let renderer = entry.renderer {
                    badge("Tested with \(renderer)", color: .blue)
                }
            }
            if let summary = entry.summary {
                Text(summary).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
            if entry.usesVAC {
                Text("Uses VAC. Whether VAC accepts Wine on macOS hasn't been verified.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            if let args = entry.launchArgs {
                Text("Suggested launch options: \(args.joined(separator: " "))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
            }
            Text("From highball-db\(entry.lastVerified.map { ", verified \($0)" } ?? "")")
                .font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var aboutCard: some View {
        Card(title: "Details") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                detailRow("App ID", String(game.appID))
                detailRow("Status", installed ? "Installed" : state != nil ? "Downloading" : "Not installed")
                if let dir = state?.directory {
                    detailRow("Folder", dir.path.replacingOccurrences(of: Paths.home.path, with: "~"))
                }
            }
            .font(.system(size: 12))
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(Theme.secondaryText)
            Text(value)
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct DownloadProgress: View {
    let state: AppState
    let showDownloads: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                ProgressView(value: state.progress ?? 0)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                if state.bytesToDownload > 0 {
                    Text("\(bytes(state.bytesDownloaded)) of \(bytes(state.bytesToDownload))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 260)

            Button(action: showDownloads) { Image(systemName: "arrow.down.circle") }
                .buttonStyle(IconButtonStyle())
                .help("Show Steam's downloads")
        }
    }

    private var title: String {
        let percent = state.progress.map { " · \(Int($0 * 100))%" } ?? ""
        return state.paused ? "Paused\(percent)" : state.updating ? "Downloading\(percent)" : "Queued in Steam"
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
