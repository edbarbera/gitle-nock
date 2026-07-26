import AppKit
import SwiftUI

// MARK: - Tokens

/// The panel's design system: palette, type, radii, motion.
///
/// Held as static state rather than an `EnvironmentValue` so every view can read
/// a token without threading it through. The trade-off is that SwiftUI can't
/// observe it, so `NotchRootView` writes the values from `Settings` and hangs an
/// `.id(settings.appearanceToken)` off the tree to force a repaint on change.
enum Theme {
    static var isDark: Bool = true
    static var accent: Color = AccentChoice.blue.color(isDark: true)
    /// 0…1, how solid the panel material is. Driven by the opacity slider.
    static var opacity: Double = 0.82
    static var reduceMotion: Bool = false

    // MARK: Text

    static var text: Color { isDark ? .white : Color(white: 0.06) }
    static var textDim: Color { isDark ? .white.opacity(0.62) : Color(white: 0.06).opacity(0.62) }
    static var textFaint: Color { isDark ? .white.opacity(0.36) : Color(white: 0.06).opacity(0.40) }

    // MARK: Surfaces
    //
    // These sit *on top of* the panel material, so they are always translucent
    // washes rather than solid fills — a solid card would punch a matte hole in
    // the glass and kill the depth the whole design rests on.

    static var surface: Color { isDark ? .white.opacity(0.07) : .black.opacity(0.045) }
    static var surfaceHover: Color { isDark ? .white.opacity(0.13) : .black.opacity(0.075) }
    static var stroke: Color { isDark ? .white.opacity(0.10) : .black.opacity(0.09) }
    static var strokeStrong: Color { isDark ? .white.opacity(0.20) : .black.opacity(0.16) }

    /// The scrim behind the panel's blur. Opacity 1 makes it near-solid; the
    /// slider walks it back towards pure blur.
    static var panelScrim: Color {
        let base = isDark ? Color(white: 0.07) : Color(white: 0.97)
        return base.opacity(opacity * (isDark ? 0.86 : 0.80))
    }

    /// Rim light along the top edge of a glass surface — the single cue that
    /// sells a pane as glass rather than a translucent rectangle.
    static var specular: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [.white.opacity(0.42), .white.opacity(0.07), .white.opacity(0.02)]
                : [.white.opacity(0.95), .white.opacity(0.35), .white.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Semantics

    static var good: Color { isDark ? Color(red: 0.30, green: 0.86, blue: 0.56) : Color(red: 0.05, green: 0.60, blue: 0.35) }
    static var warn: Color { isDark ? Color(red: 1.00, green: 0.74, blue: 0.29) : Color(red: 0.80, green: 0.50, blue: 0.02) }
    static var bad: Color { isDark ? Color(red: 1.00, green: 0.44, blue: 0.44) : Color(red: 0.83, green: 0.16, blue: 0.16) }

    // MARK: Shape

    /// Radius of the panel's lower corners. Generous, so the slab reads as one
    /// continuous piece of hardware with the cutout above it.
    static let panelRadius: CGFloat = 26
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 13

    // MARK: Type
    //
    // Rounded for anything a person reads as a label or a headline; the default
    // face for prose and the monospaced face for paths. Rounded across the board
    // gets cutesy, and default across the board reads like a developer tool —
    // which is exactly the audience this app is *not* for.

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }

    // MARK: Motion

    static var spring: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.78)
    }

    static var snap: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.86)
    }

    static var hover: Animation {
        reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.16)
    }

    /// Applied to the whole tree from `Settings` before any token is read.
    @MainActor
    static func apply(_ settings: Settings) {
        isDark = settings.resolvedIsDark
        accent = settings.resolvedAccent
        opacity = settings.panelOpacity
        reduceMotion = settings.reduceMotion
    }
}

// MARK: - Panel silhouette

/// The panel outline: square across the top edge of the screen, rounded below,
/// so it reads as an extension of the hardware notch.
struct NotchShape: Shape {
    var radius: CGFloat = Theme.panelRadius

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Behind-window blur. The panel floats over other apps, so its base layer has
/// to sample the desktop rather than tint a colour — that sampling is what the
/// opacity slider is actually adjusting.
struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: Theme.isDark ? .vibrantDark : .vibrantLight)
    }
}

// MARK: - Glass

extension View {
    /// A raised, interactive pane. Liquid Glass does the refraction; the stroke
    /// on top adds the rim light, which the effect alone doesn't draw strongly
    /// enough at these small sizes.
    func glassPane(
        cornerRadius: CGFloat = Theme.cardRadius,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        var glass = Glass.regular.interactive(interactive)
        // Restrained on purpose: past roughly a fifth the tint stops refracting
        // what's behind it and the pane reads as a flat coloured card.
        if let tint { glass = glass.tint(tint.opacity(Theme.isDark ? 0.17 : 0.14)) }

        return self
            .glassEffect(glass, in: shape)
            .overlay(
                shape.strokeBorder(Theme.specular, lineWidth: 0.8)
                    .blendMode(Theme.isDark ? .plusLighter : .normal)
                    .opacity(0.7)
                    .allowsHitTesting(false)
            )
    }

    /// A flat wash for things that group content but aren't pressable. Cheaper
    /// than glass and, more importantly, stays visually behind it.
    func plainSurface(cornerRadius: CGFloat = Theme.cardRadius, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(tint.map { $0.opacity(Theme.isDark ? 0.14 : 0.10) } ?? Theme.surface))
            .overlay(shape.strokeBorder(tint.map { $0.opacity(0.28) } ?? Theme.stroke, lineWidth: 0.8))
    }
}

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
    var tint: Color? = nil
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
    var icon: String? = nil
    var tint: Color? = nil
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
    var icon: String? = nil
    var tint: Color? = nil
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
    var icon: String? = nil
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
    var subtitle: String? = nil
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
    }
}

/// Heading for a screen that can't be backed out of by chevron — warnings and
/// dead ends, where the icon carries the severity.
struct AlertHeader: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil

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
    }
}

/// Scroll list without the stock macOS chrome, which looks wrong on glass.
///
/// `maxHeight` nil means "take whatever the screen has left", which is what
/// every list screen wants — a fixed cap clipped short lists that would
/// otherwise have fitted.
struct PanelScroll<Content: View>: View {
    var maxHeight: CGFloat? = nil
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
