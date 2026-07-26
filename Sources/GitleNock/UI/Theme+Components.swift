import SwiftUI

// MARK: - Primitives

/// An icon in a soft tinted squircle. Leads every card, tile and header, so the
/// tint is the fastest way to read what kind of thing a row is.
struct IconChip: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [tint, tint.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(tint.opacity(Theme.isDark ? 0.20 : 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 0.8)
            )
    }
}

/// The button everything in the panel is built from: a glass pill that lifts
/// under the cursor. `tint` nil gives the neutral variant used for anything
/// that isn't the recommended action on screen.
struct GlassButton<Content: View>: View {
    var tint: Color?
    var cornerRadius: CGFloat = Theme.controlRadius
    var fills: Bool = true
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassPane(cornerRadius: cornerRadius, tint: hovering && isEnabled ? tint : tint?.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(hovering && isEnabled ? Theme.surfaceHover : .clear)
                .allowsHitTesting(false)
        )
        .shadow(
            color: (tint ?? .black).opacity(hovering && isEnabled ? 0.28 : 0),
            radius: 12,
            y: 5
        )
        .scaleEffect(pressed ? 0.975 : (hovering && isEnabled ? 1.02 : 1))
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Theme.hover, value: hovering)
        .animation(Theme.snap, value: pressed)
        .onHover { hovering = $0 }
        .onLongPressGesture(minimumDuration: 0.6, pressing: { pressed = $0 && isEnabled }, perform: {})
    }
}

/// A labelled action, sized to sit in a row. The workhorse of every flow screen.
struct ActionButton: View {
    let title: String
    var icon: String?
    var tint: Color?
    var fills: Bool = false
    let action: () -> Void

    var body: some View {
        GlassButton(tint: tint, fills: fills, action: action) {
            HStack(spacing: 9) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint ?? Theme.textDim)
                }
                Text(title)
                    .font(Theme.display(12.5, tint == nil ? .medium : .semibold))
                    .foregroundStyle(tint == nil ? Theme.textDim : Theme.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: fills ? .infinity : nil, alignment: fills ? .center : .leading)
        }
    }
}

/// A compact capsule used for inline choices, where a full button would shout.
struct ChipButton: View {
    let title: String
    var icon: String?
    var tint: Color?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(Theme.display(10.5, .medium))
            }
            .foregroundStyle(hovering ? (tint ?? Theme.text) : Theme.textDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(hovering ? Theme.surfaceHover : Theme.surface)
            )
            .overlay(
                Capsule().strokeBorder(
                    hovering ? (tint ?? Theme.strokeStrong).opacity(0.5) : Theme.stroke,
                    lineWidth: 0.8
                )
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.hover, value: hovering)
        .onHover { hovering = $0 }
    }
}

/// A small key/value badge — branch name, file count, anything glanceable.
struct StatusPill: View {
    let text: String
    var icon: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(Theme.display(10.5, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(tint.opacity(Theme.isDark ? 0.16 : 0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.26), lineWidth: 0.8))
    }
}

/// The heading on every screen that isn't the main menu.
struct BackHeader: View {
    @EnvironmentObject private var state: AppState
    let title: String
    var subtitle: String?
    /// Where the chevron goes. Defaults to the main menu; multi-step flows pass
    /// their own previous step.
    var back: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let back { back() } else { state.screen = .main }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(hovering ? Theme.text : Theme.textDim)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(hovering ? Theme.surfaceHover : Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .animation(Theme.hover, value: hovering)
            .onHover { hovering = $0 }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.display(15, .semibold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .legibleOnPanel()
    }
}

/// Heading for a screen that can't be backed out of by chevron — warnings and
/// dead ends, where the icon carries the severity.
struct AlertHeader: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            IconChip(icon: icon, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.display(15, .semibold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .legibleOnPanel()
    }
}

/// Scroll list without the stock macOS chrome, which looks wrong on glass.
///
/// `maxHeight` nil means "take whatever the screen has left", which is what
/// every list screen wants — a fixed cap clipped short lists that would
/// otherwise have fitted.
struct PanelScroll<Content: View>: View {
    var maxHeight: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: maxHeight ?? .infinity)
        // Fade the top and bottom rather than hard-cutting rows, so a long list
        // reads as continuing past the edge instead of being clipped short.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
