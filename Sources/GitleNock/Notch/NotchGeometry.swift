import AppKit

/// Where the notch is, or where we should pretend it is.
struct NotchGeometry {
    /// Size of the collapsed pill in screen points.
    let collapsedSize: CGSize
    /// Screen-space rect of the collapsed pill.
    let collapsedRect: CGRect
    /// Whether this screen has a real hardware notch.
    let isRealNotch: Bool
    let screen: NSScreen
    /// Whether a pill should stand in for a missing hardware notch.
    let showsFallbackPill: Bool

    /// Fallback pill dimensions for screens with no notch, tuned to look like one.
    static let fallbackSize = CGSize(width: 200, height: 32)

    /// Nothing to show: no hardware notch, and the user turned the pill off.
    var isHidden: Bool { !isRealNotch && !showsFallbackPill }

    static func current(showFallbackPill: Bool = true) -> NotchGeometry? {
        // A notch is a property of one specific screen. Pick that screen whenever
        // one is connected — mouse position or "main" (the screen with the key
        // window) can land on a different display in any multi-monitor setup,
        // which drew the fallback pill on a MacBook that has a real notch.
        let notched = NSScreen.screens.first(where: Self.hasNotch)

        guard let screen = notched
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        else { return nil }
        return NotchGeometry(screen: screen, showsFallbackPill: showFallbackPill)
    }

    private static func hasNotch(_ screen: NSScreen) -> Bool {
        guard #available(macOS 12.0, *) else { return false }
        return screen.auxiliaryTopLeftArea != nil
            && screen.auxiliaryTopRightArea != nil
            && screen.safeAreaInsets.top > 0
    }

    init(screen: NSScreen, showsFallbackPill: Bool = true) {
        self.screen = screen
        self.showsFallbackPill = showsFallbackPill
        let frame = screen.frame

        // On notched Macs the menu bar is split into two auxiliary areas with the
        // notch sitting in the gap between them.
        if #available(macOS 12.0, *), Self.hasNotch(screen) {
            // hasNotch already proved these are non-nil; re-read rather than thread
            // the values through as extra parameters.
            let left = screen.auxiliaryTopLeftArea!
            let right = screen.auxiliaryTopRightArea!
            let width = frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            collapsedSize = CGSize(width: width, height: height)
            isRealNotch = true
        } else {
            collapsedSize = Self.fallbackSize
            isRealNotch = false
        }

        collapsedRect = CGRect(
            x: frame.midX - collapsedSize.width / 2,
            y: frame.maxY - collapsedSize.height,
            width: collapsedSize.width,
            height: collapsedSize.height
        )
    }

    /// The expanded panel hangs below the notch, keeping the same top edge and centre.
    func expandedRect(size: CGSize) -> CGRect {
        let width = max(size.width, collapsedSize.width)
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - size.height,
            width: width,
            height: size.height
        )
    }

    /// Hover target: slightly taller and wider than the pill so the cursor
    /// doesn't have to land pixel-perfectly on the notch itself.
    var hoverRect: CGRect {
        collapsedRect.insetBy(dx: -12, dy: -4)
    }
}
