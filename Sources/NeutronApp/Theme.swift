import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.078, blue: 0.106)
    static let panel = Color(red: 0.106, green: 0.157, blue: 0.220)
    static let raised = Color(red: 0.145, green: 0.200, blue: 0.267)
    static let accent = Color(red: 0.400, green: 0.753, blue: 0.957)
    static let secondaryText = Color(red: 0.561, green: 0.596, blue: 0.627)
    static let play = [Color(red: 0.459, green: 0.690, blue: 0.133), Color(red: 0.345, green: 0.541, blue: 0.106)]
    static let install = [Color(red: 0.278, green: 0.749, blue: 1.0), Color(red: 0.102, green: 0.267, blue: 0.761)]
    static let stop = [Color(red: 0.208, green: 0.502, blue: 0.769), Color(red: 0.145, green: 0.353, blue: 0.584)]
}

/// Steam's big uppercase action button, with a gradient fill that brightens on hover.
struct ActionButtonStyle: ButtonStyle {
    var colors: [Color]
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .frame(minWidth: 168, minHeight: 46)
            .padding(.horizontal, 22)
            .background(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .brightness(hovering ? 0.08 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: colors[0].opacity(hovering ? 0.45 : 0.25), radius: hovering ? 14 : 8, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Small square icon button used in the action bar.
struct IconButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(hovering ? .white : Theme.secondaryText)
            .frame(width: 38, height: 38)
            .background(Theme.raised.opacity(hovering ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .onHover { hovering = $0 }
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}
