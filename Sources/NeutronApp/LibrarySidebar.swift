import NeutronKit
import SwiftUI

struct LibrarySidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Filter", selection: $model.filter) {
                ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List(selection: $model.selection) {
                Section {
                    ForEach(model.visibleGames) { game in
                        GameRow(game: game).tag(game.appID)
                    }
                } header: {
                    Text("\(model.filter == .installed ? "Installed" : "Games") (\(model.visibleGames.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.loading {
                    ProgressView().controlSize(.small)
                } else if model.visibleGames.isEmpty {
                    ContentUnavailableView(model.search.isEmpty ? "No Games" : "No Results",
                                           systemImage: model.search.isEmpty ? "gamecontroller" : "magnifyingglass")
                }
            }
        }
        .background(Theme.panel.opacity(0.45))
        .searchable(text: $model.search, placement: .sidebar, prompt: "Search games")
    }
}

struct GameRow: View {
    @Environment(AppModel.self) private var model
    let game: SteamGame

    var body: some View {
        let state = model.states[game.appID]
        let installed = state?.installed == true
        HStack(spacing: 10) {
            SteamImage(url: Artwork.icon.url(for: game)) {
                RoundedRectangle(cornerRadius: 5).fill(Theme.raised)
                    .overlay(Image(systemName: "gamecontroller.fill").font(.system(size: 10)).foregroundStyle(Theme.secondaryText))
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .saturation(installed ? 1 : 0.2)
            .opacity(installed ? 1 : 0.7)

            Text(game.name)
                .lineLimit(1)
                .foregroundStyle(installed ? .primary : .secondary)

            Spacer(minLength: 4)

            if let state, state.updating {
                ProgressView(value: state.progress ?? 0)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .tint(Theme.accent)
            } else if model.isRunning(game) {
                Text("Running")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.play[0])
            }
        }
        .padding(.vertical, 2)
    }
}
