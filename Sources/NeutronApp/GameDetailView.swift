import NeutronKit
import SwiftUI

struct GameDetailView: View {
    @Environment(AppModel.self) private var model
    let game: SteamGame
    @State private var sizeOnDisk: Int64?
    @State private var confirmingUninstall = false

    private var installed: Bool { model.installed.contains(game.appID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                actionBar
                VStack(spacing: 16) {
                    if !model.steamIsRunning {
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
        .task(id: "\(game.appID)-\(installed)") {
            sizeOnDisk = nil
            guard installed else { return }
            let appID = game.appID
            sizeOnDisk = await Task.detached(priority: .utility) { SteamLibrary.sizeOnDisk(appID) }.value
        }
        .confirmationDialog("Uninstall \(game.name)?", isPresented: $confirmingUninstall) {
            Button("Uninstall", role: .destructive) { model.uninstall(game) }
        } message: {
            Text("This deletes the downloaded Windows build. Your Wine prefix and saves are kept.")
        }
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

            if installed {
                stat("Size on disk", sizeOnDisk.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
            } else if let size = game.installSize {
                stat("Download size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            stat("Graphics", model.backend(for: game) == .dxmt ? "DXMT · Metal" : "wined3d · OpenGL")
            if game.hasMacVersion {
                stat("Platform", "Also on macOS")
            }

            Spacer()

            HStack(spacing: 8) {
                Button { model.openInSteam(game) } label: { Image(systemName: "arrow.up.forward.app") }
                    .help("Show in Steam")
                Button { model.openStorePage(game) } label: { Image(systemName: "bag") }
                    .help("Store page")
                Menu {
                    if installed {
                        Button("Show in Finder", systemImage: "folder") { model.revealInstall(game) }
                        Button("Open Log", systemImage: "doc.text") { model.openLog(game) }
                        Divider()
                        Button("Verify Files", systemImage: "checkmark.shield") { model.install(game) }
                        Button("Uninstall…", systemImage: "trash", role: .destructive) { confirmingUninstall = true }
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
        if let download = model.downloads[game.appID] {
            DownloadProgress(download: download) { model.cancelDownload(game) }
        } else if model.running[game.appID] != nil {
            Button { model.stop(game) } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(ActionButtonStyle(colors: Theme.stop))
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

    private var steamBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Steam isn't running").font(.system(size: 13, weight: .semibold))
                Text("Games use the Mac Steam client for sign-in, achievements and friends.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button("Open Steam") { model.launchSteam() }
                .controlSize(.large)
        }
        .padding(14)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.yellow.opacity(0.25)))
    }

    private var compatibilityCard: some View {
        Card(title: "Compatibility") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Graphics backend", selection: Binding(
                    get: { model.backend(for: game) },
                    set: { model.setBackend($0, for: game) }
                )) {
                    Text("DXMT (Direct3D 10/11 on Metal)").tag(Backend.dxmt)
                    Text("wined3d (OpenGL)").tag(Backend.wined3d)
                }
                .pickerStyle(.radioGroup)
                .disabled(model.running[game.appID] != nil)

                Text("Direct3D 9 games use wined3d with either option.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var aboutCard: some View {
        Card(title: "Details") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                detailRow("App ID", String(game.appID))
                detailRow("Status", installed ? "Installed" : "Not installed")
                detailRow("Prefix", "~/Library/Application Support/Neutron/prefixes/\(game.appID)")
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
    let download: Download
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(download.progress.map { "Downloading · \(Int($0 * 100))%" } ?? "Preparing")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                ProgressView(value: download.progress ?? 0)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                Text(download.status)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 260)

            Button(action: cancel) { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle())
                .help("Cancel download")
        }
    }
}
