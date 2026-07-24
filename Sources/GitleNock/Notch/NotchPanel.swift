import AppKit
import SwiftUI

/// A borderless panel that can still take keyboard focus.
///
/// Borderless windows refuse key status by default, which would leave the
/// "what did you change?" text field untypeable.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that lays out into the notch instead of around it.
///
/// On a notched Mac AppKit hands a window overlapping the cutout a top safe-area
/// inset the height of the notch, and SwiftUI dutifully starts its layout below
/// it — which drew the collapsed slab hanging under the notch rather than hidden
/// behind it. This panel *is* the notch, so it wants the whole rect.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        if #available(macOS 13.3, *) { safeAreaRegions = [] }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
