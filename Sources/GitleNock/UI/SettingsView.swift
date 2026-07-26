import AppKit
import SwiftUI

/// The settings window. An ordinary macOS window — sidebar on the left, one
/// pane at a time on the right — rather than a second copy of the notch's
/// styling, which would be pretending to be something it isn't.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: Settings

    @State private var section: SettingsSection = .appearance

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)
                .background(SidebarMaterial())

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch section {
                    case .appearance: AppearancePane()
                    case .projects: ProjectsPane()
                    case .behaviour: BehaviourPane()
                    case .setup: SetupPane()
                    case .about: AboutPane()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, 34)
                .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settings.resolvedAccent.gradient)
                    )
                VStack(alignment: .leading, spacing: 0) {
                    Text("gitle nock")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Version \(Bundle.main.shortVersion)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            // Clears the traffic lights, which sit over the content because the
            // window uses a full-size content view for the sidebar's blur.
            .padding(.horizontal, 12)
            .padding(.top, 42)
            .padding(.bottom, 14)

            ForEach(SettingsSection.allCases) { item in
                SidebarRow(item: item, isSelected: section == item) {
                    section = item
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }
}

// MARK: - Sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case projects
    case behaviour
    case setup
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .projects: return "Projects"
        case .behaviour: return "Behaviour"
        case .setup: return "Under the hood"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .projects: return "folder.fill"
        case .behaviour: return "slider.horizontal.3"
        case .setup: return "wrench.and.screwdriver.fill"
        case .about: return "info.circle.fill"
        }
    }
}

private struct SidebarRow: View {
    let item: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (hovering ? Color.primary.opacity(0.07) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Sidebar blur, so the window matches System Settings and Finder rather than
/// sitting on a flat grey.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Appearance

private struct AppearancePane: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneTitle("Appearance", subtitle: "How the panel that drops out of the notch looks.")

            PanelPreview()

            SettingsGroup("Theme") {
                SegmentedPicker(
                    options: AppearanceMode.allCases,
                    selection: $settings.appearance,
                    label: \.label,
                    symbol: \.symbol
                )
                FootNote(
                    "Automatic follows your macOS light/dark setting. The hardware notch itself always stays "
                        + "black — a lit rectangle up there reads as a bug, not a feature."
                )
            }

            SettingsGroup("Accent colour") {
                AccentGrid(selection: $settings.accent, isDark: settings.resolvedIsDark)
            }

            SettingsGroup("Opacity") {
                HStack(spacing: 14) {
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $settings.panelOpacity,
                        in: Settings.opacityRange
                    )
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.secondary)
                    Text("\(Int(settings.panelOpacity * 100))%")
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                FootNote(
                    "Drives both the frosted layer and the tint over it. At 0% the panel is clear — just the "
                        + "glass buttons, the rim and the text — which looks its best over a calm wallpaper and "
                        + "gets hard to read over a busy one. The preview above is accurate at every setting."
                )
            }

            SettingsGroup("Motion") {
                Toggle("Tone down animation", isOn: $settings.reduceMotion)
                FootNote("Keeps the panel's transitions but drops the springy overshoot and the pulsing status dot.")
            }
        }
    }
}

/// A live miniature of the notch panel, so appearance choices can be judged
/// without hunting for the cursor target at the top of the screen.
private struct PanelPreview: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        // The preview draws with the same `Theme` tokens the real panel uses, so
        // it has to publish the current settings into them before reading any.
        // The `let` is load-bearing: inside a `@ViewBuilder` body, a bare
        // `_ = expr` is swallowed into `buildExpression` and fails to conform
        // to `View`, whereas `let _ = expr` is a declaration ViewBuilder skips.
        // swiftlint:disable:next redundant_discardable_let
        let _ = Theme.apply(settings)

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("my-project")
                    .font(Theme.display(9.5, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                Text("main")
                    .font(Theme.display(9, .medium))
                    .foregroundStyle(Theme.textDim)
                Circle()
                    .fill(Theme.warn)
                    .frame(width: 5, height: 5)
            }
            .padding(.horizontal, 12)
            .frame(height: 22)
            .legibleOnPanel()

            Rectangle().fill(Theme.stroke).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("2 unsaved changes")
                        .font(Theme.display(13, .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Save them whenever you like")
                        .font(Theme.body(8.5))
                        .foregroundStyle(Theme.textDim)
                }
                .legibleOnPanel()

                HStack(spacing: 7) {
                    PreviewTile(icon: "tray.and.arrow.down.fill", tint: Theme.warn, title: "Save")
                    PreviewTile(icon: "arrow.up.circle.fill", tint: Theme.accent, title: "Send")
                    PreviewTile(icon: "arrow.down.circle.fill", tint: Theme.good, title: "Grab")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 12)
        }
        .frame(width: 340, height: 132)
        .background(
            ZStack {
                // Stand-in wallpaper. The real panel's blur samples the desktop
                // behind the *window*, which here would be this settings window
                // rather than anything the preview draws — so the preview can't
                // use `PanelMaterial` and has to reproduce it: the same artwork,
                // blurred, at the same strength the slider gives the real one.
                PreviewWallpaper()

                PreviewWallpaper()
                    .blur(radius: 18)
                    .opacity(Theme.materialStrength)

                NotchShape(radius: 18).fill(Theme.panelScrim)
                NotchShape(radius: 18).fill(
                    LinearGradient(colors: [Theme.accentWash, .clear],
                                   startPoint: .top, endPoint: .center)
                )
            }
        )
        .clipShape(NotchShape(radius: 18))
        .overlay(NotchShape(radius: 18).stroke(Theme.specular, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: settings.appearanceToken)
    }
}

/// Stand-in desktop for the preview. Deliberately has hard edges and bright
/// blobs in it — a smooth gradient looks identical blurred and unblurred, which
/// would hide exactly the thing the opacity slider is changing.
private struct PreviewWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.14, blue: 0.38),
                         Color(red: 0.55, green: 0.22, blue: 0.45),
                         Color(red: 0.95, green: 0.55, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.9))
                .frame(width: 46, height: 46)
                .offset(x: -104, y: -22)

            Circle()
                .fill(Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.75))
                .frame(width: 30, height: 30)
                .offset(x: 118, y: 34)

            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.5))
                .frame(width: 90, height: 8)
                .offset(x: 20, y: -44)

            RoundedRectangle(cornerRadius: 4)
                .fill(.black.opacity(0.45))
                .frame(width: 130, height: 8)
                .offset(x: -30, y: 50)
        }
        .frame(width: 340, height: 132)
        .clipped()
    }
}

private struct PreviewTile: View {
    let icon: String
    let tint: Color
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            IconChip(icon: icon, tint: tint, size: 18)
            Text(title)
                .font(Theme.display(9, .semibold))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(Theme.isDark ? 0.16 : 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.3), lineWidth: 0.8)
        )
    }
}
