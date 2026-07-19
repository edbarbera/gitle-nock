import SwiftUI

enum Theme {
    static let shell = Color.black
    static let text = Color.white
    static let textDim = Color.white.opacity(0.55)
    static let textFaint = Color.white.opacity(0.35)
    static let card = Color.white.opacity(0.07)
    static let cardHover = Color.white.opacity(0.13)
    static let hairline = Color.white.opacity(0.10)

    static let good = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let warn = Color(red: 1.00, green: 0.72, blue: 0.23)
    static let bad = Color(red: 1.00, green: 0.35, blue: 0.35)
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.00)

    /// Radius of the notch's lower corners.
    static let notchRadius: CGFloat = 14
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

/// A row that lights up under the cursor. Used for every tappable thing in the menu.
struct HoverCard<Content: View>: View {
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hovering ? Theme.cardHover : Theme.card)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
