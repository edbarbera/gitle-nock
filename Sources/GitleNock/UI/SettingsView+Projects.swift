import SwiftUI

struct AccentGrid: View {
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
struct SegmentedPicker<Option: Hashable & Identifiable>: View {
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

struct ProjectsPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(
                "Projects",
                subtitle: "Folders gitle nock keeps an eye on. The one that's ticked is the one the notch shows."
            )

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

struct BehaviourPane: View {
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
                FootNote(
                    "External monitors and older Macs have no notch to hide in, so the panel needs somewhere to live."
                )
            }

            SettingsGroup("Safety") {
                Toggle("Ask me before sending work online", isOn: $settings.confirmBeforeSending)
                FootNote(
                    "Warnings about private files, oversized files and sending straight to a shared branch "
                        + "always appear — this only adds a plain confirmation on top."
                )
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

struct SetupPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle("Under the hood", subtitle: "The tools gitle nock is driving, and who your saves are signed as.")

            VStack(spacing: 0) {
                StatusLine(
                    isHealthy: state.gitleInstalled,
                    label: "gitle",
                    detail: GitleRunner.gitlePath ?? "Not found — install it to grab the latest."
                )
                Divider()
                StatusLine(isHealthy: true, label: "git", detail: GitReader.gitPath)

                if let identity = state.gitIdentity {
                    Divider()
                    StatusLine(
                        isHealthy: !identity.name.isEmpty && !identity.email.isEmpty,
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

            FootNote(
                "Signing in with GitHub is coming later. For now gitle nock uses the git account already "
                    + "set up on this Mac."
            )
        }
    }
}

private struct StatusLine: View {
    let isHealthy: Bool
    let label: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isHealthy ? Color.green : Color.orange)
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
