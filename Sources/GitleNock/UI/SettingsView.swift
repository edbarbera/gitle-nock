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
                FootNote("Automatic follows your macOS light/dark setting. The hardware notch itself always stays black — a lit rectangle up there reads as a bug, not a feature.")
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
                FootNote("Drives both the frosted layer and the tint over it. At 0% the panel is clear — just the glass buttons, the rim and the text — which looks its best over a calm wallpaper and gets hard to read over a busy one. The preview above is accurate at every setting.")
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

private struct AccentGrid: View {
    @Binding var selection: AccentChoice
    let isDark: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AccentChoice.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    ZStack {
                        Circle()
                            .fill(choice.color(isDark: isDark).gradient)
                            .frame(width: 22, height: 22)
                        if choice == .system {
                            // The one swatch whose colour isn't its own choice —
                            // mark it so it doesn't look like a duplicate blue.
                            Image(systemName: "applelogo")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                            .frame(width: 22, height: 22)
                    }
                    .padding(3)
                    .overlay(
                        Circle().strokeBorder(
                            selection == choice ? Color.accentColor : .clear,
                            lineWidth: 2
                        )
                    )
                }
                .buttonStyle(.plain)
                .help(choice.label)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Appearance mode picker. The stock segmented control can't carry an icon per
/// segment, and the icons are what make the three modes readable at a glance.
private struct SegmentedPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    let symbol: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: symbol(option))
                            .font(.system(size: 15))
                        Text(label(option))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 340)
    }
}

// MARK: - Projects

private struct ProjectsPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle("Projects", subtitle: "Folders gitle nock keeps an eye on. The one that's ticked is the one the notch shows.")

            if state.repos.isEmpty {
                EmptyState(
                    icon: "folder.badge.plus",
                    title: "No projects yet",
                    detail: "Pick the folder your work lives in and gitle nock takes it from there."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(state.repos) { repo in
                        SettingsRepoRow(repo: repo, isActive: repo.id == state.activeRepo?.id)
                        if repo.id != state.repos.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )
            }

            Button {
                state.addRepo()
            } label: {
                Label("Add a project…", systemImage: "plus")
            }
            .controlSize(.large)
        }
    }
}

private struct SettingsRepoRow: View {
    @EnvironmentObject private var state: AppState
    let repo: Repo
    let isActive: Bool

    @State private var hovering = false

    private var isMissing: Bool { !FileManager.default.fileExists(atPath: repo.path) }

    var body: some View {
        HStack(spacing: 11) {
            Button {
                state.select(repo)
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .rounded))
                    if isMissing {
                        Text("folder missing")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                    }
                }
                Text(repo.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 0)

            Button {
                state.remove(repo)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.35)
            .help("Remove from the list. Your files are not touched.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Behaviour

private struct BehaviourPane: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneTitle("Behaviour", subtitle: "When the panel appears and what it checks with you first.")

            SettingsGroup("Checking for changes") {
                Picker("Look for changes every", selection: $settings.refreshInterval) {
                    ForEach(Settings.refreshChoices, id: \.self) { seconds in
                        Text("\(Int(seconds)) seconds").tag(seconds)
                    }
                }
                .frame(maxWidth: 320)
            }

            SettingsGroup("Where it shows") {
                Toggle("Show a pill on screens without a notch", isOn: $settings.showPillWithoutNotch)
                FootNote("External monitors and older Macs have no notch to hide in, so the panel needs somewhere to live.")
            }

            SettingsGroup("Safety") {
                Toggle("Ask me before sending work online", isOn: $settings.confirmBeforeSending)
                FootNote("Warnings about private files, oversized files and sending straight to a shared branch always appear — this only adds a plain confirmation on top.")
            }

            SettingsGroup("Startup") {
                Toggle("Open gitle nock when I log in", isOn: $settings.launchAtLogin)
                if let error = settings.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Under the hood

private struct SetupPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle("Under the hood", subtitle: "The tools gitle nock is driving, and who your saves are signed as.")

            VStack(spacing: 0) {
                StatusLine(
                    ok: state.gitleInstalled,
                    label: "gitle",
                    detail: GitleRunner.gitlePath ?? "Not found — install it to grab the latest."
                )
                Divider()
                StatusLine(ok: true, label: "git", detail: GitReader.gitPath)

                if let identity = state.gitIdentity {
                    Divider()
                    StatusLine(
                        ok: !identity.name.isEmpty && !identity.email.isEmpty,
                        label: "Signed as",
                        detail: identity.email.isEmpty ? identity.name : "\(identity.name) <\(identity.email)>"
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )

            FootNote("Signing in with GitHub is coming later. For now gitle nock uses the git account already set up on this Mac.")
        }
    }
}

private struct StatusLine: View {
    let ok: Bool
    let label: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(label)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .frame(width: 74, alignment: .leading)
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - About

private struct AboutPane: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneTitle("About", subtitle: nil)

            HStack(spacing: 16) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(settings.resolvedAccent.gradient)
                    )
                    .shadow(color: settings.resolvedAccent.opacity(0.4), radius: 12, y: 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text("gitle nock")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Version \(Bundle.main.shortVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Version control that lives in your notch and speaks plain English.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Divider()

            HStack {
                Text("Hover the notch at the top of your screen to open the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit gitle nock") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

// MARK: - Pieces

private struct PaneTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct FootNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
