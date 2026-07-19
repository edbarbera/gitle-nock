import AppKit

/// A borderless panel that can still take keyboard focus.
///
/// Borderless windows refuse key status by default, which would leave the
/// "what did you change?" text field untypeable.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
