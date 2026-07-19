import Foundation
import ServiceManagement

/// User-adjustable preferences, backed by UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    static let refreshChoices: [Double] = [3, 6, 15, 30]

    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: "settings.refreshInterval") }
    }

    /// Show the pill on screens with no hardware notch. Off means the app is
    /// invisible on external displays rather than floating a bar over them.
    @Published var showPillWithoutNotch: Bool {
        didSet { defaults.set(showPillWithoutNotch, forKey: "settings.showPillWithoutNotch") }
    }

    @Published var confirmBeforeSending: Bool {
        didSet { defaults.set(confirmBeforeSending, forKey: "settings.confirmBeforeSending") }
    }

    /// Appearance of the notch menu itself, independent of the system's own
    /// light/dark setting — the panel has always been a fixed dark theme, so
    /// this needs its own switch rather than reading `NSApp.effectiveAppearance`.
    @Published var useLightAppearance: Bool {
        didSet { defaults.set(useLightAppearance, forKey: "settings.useLightAppearance") }
    }

    @Published private(set) var launchAtLoginError: String?

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != isRegisteredForLogin else { return }
            applyLaunchAtLogin()
        }
    }

    init() {
        let stored = defaults.double(forKey: "settings.refreshInterval")
        refreshInterval = stored > 0 ? stored : 6

        showPillWithoutNotch = defaults.object(forKey: "settings.showPillWithoutNotch") as? Bool ?? true
        confirmBeforeSending = defaults.object(forKey: "settings.confirmBeforeSending") as? Bool ?? false
        useLightAppearance = defaults.object(forKey: "settings.useLightAppearance") as? Bool ?? false
        launchAtLogin = false
        launchAtLogin = isRegisteredForLogin
    }

    private var isRegisteredForLogin: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            // Unsigned and ad-hoc-signed builds are routinely refused here, so
            // report it rather than leaving a toggle that silently lies.
            launchAtLoginError = error.localizedDescription
            launchAtLogin = isRegisteredForLogin
        }
    }
}
