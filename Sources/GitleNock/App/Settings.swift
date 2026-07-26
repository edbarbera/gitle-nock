import AppKit
import ServiceManagement
import SwiftUI

/// How the notch panel picks between its light and dark palettes.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

/// The colour that leads every primary action and highlight in the panel.
///
/// Deliberately a short, named list rather than a free colour well: the point is
/// a palette that always reads well against glass, not a paint program.
enum AccentChoice: String, CaseIterable, Identifiable {
    case system
    case blue
    case indigo
    case violet
    case pink
    case orange
    case mint
    case graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match macOS"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .violet: return "Violet"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .mint: return "Mint"
        case .graphite: return "Graphite"
        }
    }

    /// Resolved for a given palette. Colours are hand-picked rather than taken
    /// from the system set so they hold their identity on top of glass, where
    /// stock `.blue` and friends wash out badly.
    func color(isDark: Bool) -> Color {
        switch self {
        case .system:
            return Color(nsColor: .controlAccentColor)
        case .blue:
            return isDark ? Color(red: 0.36, green: 0.63, blue: 1.00) : Color(red: 0.05, green: 0.45, blue: 0.94)
        case .indigo:
            return isDark ? Color(red: 0.51, green: 0.55, blue: 1.00) : Color(red: 0.29, green: 0.32, blue: 0.87)
        case .violet:
            return isDark ? Color(red: 0.72, green: 0.52, blue: 1.00) : Color(red: 0.51, green: 0.27, blue: 0.87)
        case .pink:
            return isDark ? Color(red: 1.00, green: 0.45, blue: 0.68) : Color(red: 0.88, green: 0.19, blue: 0.47)
        case .orange:
            return isDark ? Color(red: 1.00, green: 0.60, blue: 0.29) : Color(red: 0.87, green: 0.40, blue: 0.05)
        case .mint:
            return isDark ? Color(red: 0.32, green: 0.85, blue: 0.70) : Color(red: 0.03, green: 0.60, blue: 0.49)
        case .graphite:
            return isDark ? Color(red: 0.72, green: 0.74, blue: 0.79) : Color(red: 0.35, green: 0.37, blue: 0.41)
        }
    }
}

/// User-adjustable preferences, backed by UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    static let refreshChoices: [Double] = [3, 6, 15, 30]

    /// Below this the text on glass stops being readable over a busy desktop.
    static let opacityRange: ClosedRange<Double> = 0.45...1.0

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

    /// Appearance of the notch menu itself. `.system` follows macOS; the other
    /// two pin it, because a panel that hangs over every app is something people
    /// want to fix independently of the rest of the desktop.
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: "settings.appearance") }
    }

    @Published var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: "settings.accent") }
    }

    /// How solid the panel's material is. 1 is near-opaque; lower lets more of
    /// the desktop through the glass.
    @Published var panelOpacity: Double {
        didSet {
            let clamped = min(max(panelOpacity, Settings.opacityRange.lowerBound), Settings.opacityRange.upperBound)
            if clamped != panelOpacity {
                panelOpacity = clamped
                return
            }
            defaults.set(panelOpacity, forKey: "settings.panelOpacity")
        }
    }

    /// Motion can be turned down without turning the design off — the panel
    /// still animates, just shorter and without the springy overshoot.
    @Published var reduceMotion: Bool {
        didSet { defaults.set(reduceMotion, forKey: "settings.reduceMotion") }
    }

    /// Tracks the system light/dark setting so `.system` appearance can resolve.
    /// `NSApp.effectiveAppearance` is not observable from SwiftUI on its own.
    @Published private(set) var systemIsDark: Bool = Settings.readSystemIsDark()

    @Published private(set) var launchAtLoginError: String?

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != isRegisteredForLogin else { return }
            applyLaunchAtLogin()
        }
    }

    private var appearanceObserver: NSKeyValueObservation?

    init() {
        let stored = defaults.double(forKey: "settings.refreshInterval")
        refreshInterval = stored > 0 ? stored : 6

        showPillWithoutNotch = defaults.object(forKey: "settings.showPillWithoutNotch") as? Bool ?? true
        confirmBeforeSending = defaults.object(forKey: "settings.confirmBeforeSending") as? Bool ?? false
        reduceMotion = defaults.object(forKey: "settings.reduceMotion") as? Bool ?? false

        // Carry over the old boolean switch so an existing install doesn't get
        // silently flipped back to dark on first launch after the redesign.
        if let raw = defaults.string(forKey: "settings.appearance"),
           let mode = AppearanceMode(rawValue: raw) {
            appearance = mode
        } else if let legacy = defaults.object(forKey: "settings.useLightAppearance") as? Bool {
            appearance = legacy ? .light : .dark
        } else {
            appearance = .system
        }

        accent = AccentChoice(rawValue: defaults.string(forKey: "settings.accent") ?? "") ?? .blue

        let storedOpacity = defaults.double(forKey: "settings.panelOpacity")
        panelOpacity = storedOpacity > 0 ? storedOpacity : 0.82

        launchAtLogin = false
        launchAtLogin = isRegisteredForLogin

        observeSystemAppearance()
    }

    /// True when the panel should draw its dark palette right now.
    var resolvedIsDark: Bool {
        switch appearance {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }

    var resolvedAccent: Color { accent.color(isDark: resolvedIsDark) }

    /// Everything that changes what the panel looks like, in one value. Views
    /// hang `.id()` off this so a preference change forces a full repaint —
    /// `Theme`'s palette is static state that SwiftUI cannot observe on its own.
    var appearanceToken: String {
        "\(appearance.rawValue)-\(accent.rawValue)-\(resolvedIsDark)-\(Int(panelOpacity * 100))-\(reduceMotion)"
    }

    private static func readSystemIsDark() -> Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func observeSystemAppearance() {
        guard let app = NSApp else { return }
        appearanceObserver = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.systemIsDark = Settings.readSystemIsDark()
            }
        }
    }

    private var isRegisteredForLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
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
