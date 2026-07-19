import SwiftUI

enum Theme {
    enum Mode { case dark, light }

    /// Kept in sync with `Settings.useLightAppearance` by `NotchRootView`, which
    /// also forces a full redraw when it flips — plain `static let` colors below
    /// can't be observed by SwiftUI on their own, so the view has to force it.
    static var mode: Mode = .dark

    static var shell: Color { mode == .dark ? .black : .white }
    static var text: Color { mode == .dark ? .white : .black }
    static var textDim: Color { mode == .dark ? .white.opacity(0.55) : .black.opacity(0.55) }
    static var textFaint: Color { mode == .dark ? .white.opacity(0.35) : .black.opacity(0.38) }
    static var card: Color { mode == .dark ? .white.opacity(0.07) : .black.opacity(0.05) }
    static var cardHover: Color { mode == .dark ? .white.opacity(0.13) : .black.opacity(0.09) }
    static var hairline: Color { mode == .dark ? .white.opacity(0.10) : .black.opacity(0.12) }

    static let good = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let warn = Color(red: 1.00, green: 0.72, blue: 0.23)
    static let bad = Color(red: 1.00, green: 0.35, blue: 0.35)
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.00)

    /// Radius of the notch's lower corners.
    static let notchRadius: CGFloat = 14

    // Tinted-card recipe: every coloured surface derives from its accent the same
    // way, so tiles and buttons stay consistent no matter which tint they carry.
    static func wash(_ tint: Color) -> Color { tint.opacity(0.12) }
    static func washHover(_ tint: Color) -> Color { tint.opacity(0.19) }
    static func edge(_ tint: Color) -> Color { tint.opacity(0.28) }
    static func edgeHover(_ tint: Color) -> Color { tint.opacity(0.55) }
}

/// The panel silhouette: square across the top edge of the screen, rounded below,
/// so it reads as an extension of the hardware notch.
struct NotchShape: Shape {
    var radius: CGFloat = Theme.notchRadius

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
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// An icon sitting in a soft coloured circle, like the tiles' send/grab badges.
/// Used everywhere an icon leads a card or header, so colour reads consistently.
struct IconChip: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.22)))
    }
}

/// A row that lights up under the cursor. Used for every tappable thing in the menu.
/// Pass a tint to give it a coloured wash and border; leave nil for the neutral grey.
struct HoverCard<Content: View>: View {
    var tint: Color? = nil
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var hovering = false

    private var fill: Color {
        if let tint { return hovering ? Theme.washHover(tint) : Theme.wash(tint) }
        return hovering ? Theme.cardHover : Theme.card
    }

    private var border: Color {
        if let tint { return hovering ? Theme.edgeHover(tint) : Theme.edge(tint) }
        return hovering ? Theme.hairline : .clear
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}
