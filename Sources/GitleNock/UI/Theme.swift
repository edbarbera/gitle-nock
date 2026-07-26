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

    /// The scrim over the panel's blur. Mapped straight off the slider with no
    /// multiplier: 1 is a solid panel, 0 leaves nothing but the glass surfaces
    /// and the rim. Anything in between is a real reading of the number shown
    /// in Settings, which is the point of showing it.
    static var panelScrim: Color {
        let base = isDark ? Color(white: 0.07) : Color(white: 0.97)
        return base.opacity(opacity)
    }

    /// How much of the behind-window blur to draw. This tracks the slider too —
    /// leaving it at full strength was what kept the panel frosted no matter how
    /// far the scrim came down, and made the low end of the range pointless.
    static var materialStrength: Double { opacity }

    /// The accent wash across the top of the panel. Fades out with everything
    /// else, or a panel set to clear keeps a coloured stain on it.
    static var accentWash: Color {
        accent.opacity((isDark ? 0.13 : 0.09) * opacity)
    }

    /// Halo for text sitting straight on the panel with no surface under it.
    ///
    /// Once the panel is mostly clear there is no known colour behind that text —
    /// it's whatever wallpaper happens to be there — so a light theme over a dark
    /// desktop goes unreadable. Fading in a halo the opposite side of the text is
    /// the same trick macOS uses for desktop icon labels. Invisible above ~55%,
    /// where the scrim is doing the job on its own.
    static var legibilityHalo: Color {
        let needed = max(0, 0.55 - opacity) / 0.55
        return (isDark ? Color.black : Color.white).opacity(needed * 0.9)
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

    static var good: Color {
        isDark ? Color(red: 0.30, green: 0.86, blue: 0.56) : Color(red: 0.05, green: 0.60, blue: 0.35)
    }
    static var warn: Color {
        isDark ? Color(red: 1.00, green: 0.74, blue: 0.29) : Color(red: 0.80, green: 0.50, blue: 0.02)
    }
    static var bad: Color {
        isDark ? Color(red: 1.00, green: 0.44, blue: 0.44) : Color(red: 0.83, green: 0.16, blue: 0.16)
    }

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
        let cornerRadius = min(radius, min(rect.width, rect.height) / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius),
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
    /// 0…1. Set through `alphaValue` rather than SwiftUI's `.opacity`, which an
    /// `NSVisualEffectView` does not reliably honour.
    var strength: Double = 1

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
        view.alphaValue = strength
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

    /// For text and icons drawn straight onto the panel, with no card of their
    /// own to sit on. Does nothing until the panel is turned down far enough to
    /// need it. Two passes because one soft shadow isn't enough contrast against
    /// a bright wallpaper.
    func legibleOnPanel() -> some View {
        shadow(color: Theme.legibilityHalo, radius: 3)
            .shadow(color: Theme.legibilityHalo, radius: 7)
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
