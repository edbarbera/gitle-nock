import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: Settings?
    private var state: AppState?
    private var notch: NotchWindowController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let settings = Settings()
            let state = AppState(settings: settings)
            let notch = NotchWindowController(state: state)
            let settingsWindow = SettingsWindowController(state: state)

            state.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }

            self.settings = settings
            self.state = state
            self.notch = notch
            self.settingsWindow = settingsWindow

            notch.start()

            // With no projects there is nothing the notch can usefully do, so open
            // settings on a first run rather than leaving the user hunting.
            if state.repos.isEmpty { settingsWindow.show() }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
