import AppKit
import SwiftUI

/// Owns the one real window this app has. Kept alive for the whole session so
/// closing it and reopening it doesn't lose scroll position or rebuild state.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }

        // An accessory app has no Dock icon to click, so it must activate itself
        // or the window opens behind whatever the user was already using.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Deliberately not re-centred: the window is centred once when created, and
        // yanking it back would undo wherever the user dragged it.
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "gitle nock Settings"
        // The sidebar's blur runs the full height of the window, so the titlebar
        // has to be see-through or it cuts a grey band across the top of it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(state)
                .environmentObject(state.settings)
        )
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
