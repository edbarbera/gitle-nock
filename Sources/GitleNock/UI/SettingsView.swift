import SwiftUI

/// The settings window. Uses stock system styling rather than the notch's dark
/// theme, because it is an ordinary window and should look like one.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: Settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                projects
                Divider()
                behaviour
                Divider()
                setup
                Divider()
                about
            }
            .padding(22)
        }
        .frame(minWidth: 460)
    }

    // MARK: - Projects

    private var projects: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Your projects", subtitle: "Folders gitle nock keeps an eye on.")

            if state.repos.isEmpty {
                Text("No projects yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(state.repos) { repo in
                        SettingsRepoRow(repo: repo, isActive: repo.id == state.activeRepo?.id)
                        if repo.id != state.repos.last?.id { Divider() }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            }

            Button("Add a project…") { state.addRepo() }
                .padding(.top, 2)
        }
    }

    // MARK: - Behaviour

    private var behaviour: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Behaviour")

            Picker("Check for changes every", selection: $settings.refreshInterval) {
                ForEach(Settings.refreshChoices, id: \.self) { seconds in
                    Text("\(Int(seconds)) seconds").tag(seconds)
                }
            }
            .frame(maxWidth: 320)

            Toggle("Show a pill on screens without a notch", isOn: $settings.showPillWithoutNotch)
            Text("External monitors and older Macs have no notch to hide in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Ask me before sending work online", isOn: $settings.confirmBeforeSending)

            Toggle("Light appearance for the notch menu", isOn: $settings.useLightAppearance)
            Text("The hardware notch itself stays black either way — this only changes the menu that drops down from it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Open gitle nock when I log in", isOn: $settings.launchAtLogin)
            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Setup")

            StatusLine(
                ok: state.gitleInstalled,
                label: "gitle",
                detail: GitleRunner.gitlePath ?? "Not found — install it to save, send and grab."
            )
            StatusLine(
                ok: true,
                label: "git",
                detail: GitReader.gitPath
            )

            if let identity = state.gitIdentity {
                StatusLine(
                    ok: !identity.name.isEmpty && !identity.email.isEmpty,
                    label: "Signed as",
                    detail: identity.email.isEmpty ? identity.name : "\(identity.name) <\(identity.email)>"
                )
            }

            Text("Signing in with GitHub is coming later. For now gitle nock uses the git account already set up on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - About

    private var about: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("gitle nock")
                    .font(.headline)
                Text("Version \(Bundle.main.shortVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit gitle nock") { NSApplication.shared.terminate(nil) }
        }
    }
}

// MARK: - Pieces

private struct SectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusLine: View {
    let ok: Bool
    let label: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(label).frame(width: 74, alignment: .leading)
            Text(detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsRepoRow: View {
    @EnvironmentObject private var state: AppState
    let repo: Repo
    let isActive: Bool

    private var isMissing: Bool { !FileManager.default.fileExists(atPath: repo.path) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .onTapGesture { state.select(repo) }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(repo.name).fontWeight(isActive ? .semibold : .regular)
                    if isMissing {
                        Text("folder missing")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.22)))
                    }
                }
                Text(repo.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 0)

            Button {
                state.remove(repo)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove from the list. Your files are not touched.")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
