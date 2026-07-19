import SwiftUI

/// Everything below the notch bar once the menu is open.
struct MenuContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.hairline)

            Group {
                if !state.gitleInstalled {
                    MissingGitleView()
                } else if state.activeRepo == nil {
                    NoRepoView()
                } else if state.isBusy {
                    BusyView(label: state.busyLabel)
                } else {
                    switch state.screen {
                    case .main: MainMenuView()
                    case .pickFiles: PickFilesView()
                    case .risks(let report): RiskView(report: report)
                    case .save: SaveView()
                    case .files: FilesView()
                    case .repos: ReposView()
                    case .confirmSend: ConfirmSendView()
                    case .confirmProtectedSend(let branch): ConfirmProtectedSendView(branch: branch)
                    case .connect: ConnectView()
                    case .setup: SetupView()
                    case .undo: UndoView()
                    case .confirmDiscard: ConfirmDiscardView()
                    case .conflicts: ConflictsView()
                    case .result(let result): ResultView(result: result)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Main menu

struct MainMenuView: View {
    @EnvironmentObject private var state: AppState

    private var status: RepoStatus { state.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeader()

            if status.accessDenied {
                NoticeBlock(
                    text: "macOS is blocking access to this folder. Pick it again to give permission — it only takes a second.",
                    actionTitle: "Give access",
                    icon: "lock.open.fill",
                    tint: Theme.warn
                ) { state.addRepo() }
            } else if !status.isRepo {
                NoticeBlock(
                    text: "This folder isn't being tracked yet. Setting it up takes a few seconds and means you can always get back to how things were.",
                    actionTitle: "Set it up",
                    icon: "sparkles",
                    tint: Theme.good
                ) { state.beginSetup() }
            } else if status.hasConflicts {
                // Nothing else can move until these are settled, so this replaces
                // the usual tiles rather than sitting alongside them.
                NoticeBlock(
                    text: "\(status.conflictedFiles.count) file\(status.conflictedFiles.count == 1 ? "" : "s") changed in two places at once. Pick which version to keep and everything carries on as normal.",
                    actionTitle: "Sort it out",
                    icon: "arrow.triangle.pull",
                    tint: Theme.warn
                ) { state.beginConflicts() }
            } else {
                // Three tiles across: the panel is wide, so the primary actions sit
                // side by side instead of stacking into a tall column.
                HStack(alignment: .top, spacing: 10) {
                    ActionTile(
                        icon: "tray.and.arrow.down.fill",
                        tint: Theme.warn,
                        title: "Save your work",
                        subtitle: status.isClean
                            ? "Nothing new to save"
                            : "\(status.changes.count) file\(status.changes.count == 1 ? "" : "s") changed",
                        enabled: !status.isClean
                    ) { state.beginSave() }

                    ActionTile(
                        icon: "arrow.up.circle.fill",
                        tint: Theme.accent,
                        title: "Send it online",
                        subtitle: sendSubtitle,
                        enabled: true
                    ) { state.send() }

                    ActionTile(
                        icon: "arrow.down.circle.fill",
                        tint: Theme.good,
                        title: "Grab the latest",
                        subtitle: status.behind > 0
                            ? "\(status.behind) update\(status.behind == 1 ? "" : "s") waiting"
                            : "You're up to date",
                        enabled: true
                    ) { state.grab() }
                }
                .frame(height: 94)

                if !status.isClean {
                    HoverCard(action: { state.screen = .files }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textDim)
                            Text("See what changed")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.text)
                            Text(status.changes.prefix(3).map(\.filename).joined(separator: ", "))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textFaint)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            FooterBar()
        }
    }

    private var sendSubtitle: String {
        if !status.hasRemote { return "Not online yet — connect it first" }
        if status.ahead > 0 { return "\(status.ahead) save\(status.ahead == 1 ? "" : "s") ready to go" }
        return "Nothing waiting to send"
    }
}

/// A primary action, sized to sit in a row of three.
struct ActionTile: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering && enabled ? Theme.cardHover : Theme.card)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }
}

/// An explanatory message with an optional single action.
struct NoticeBlock: View {
    let text: String
    let actionTitle: String?
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle {
                HoverCard(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: icon).foregroundStyle(tint)
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
                .frame(maxWidth: 220)
            }
        }
    }
}

struct SummaryHeader: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                Text(state.status.branch.isEmpty ? "—" : state.status.branch)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.textDim)

            Text(state.status.headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }
}

struct ActionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct FooterBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 14) {
            FooterButton(
                icon: "chevron.left.forwardslash.chevron.right",
                help: state.editorIsAvailable ? "Open in VS Code" : "Show in Finder"
            ) {
                state.openActiveRepoInEditor()
            }
            FooterButton(icon: "square.grid.2x2", help: "Switch project") {
                state.screen = .repos
            }
            FooterButton(icon: "arrow.uturn.backward", help: "Go back / undo") {
                state.beginUndo()
            }
            FooterButton(icon: "arrow.clockwise", help: "Refresh") {
                state.forceRefresh()
            }
            FooterButton(icon: "gearshape", help: "Settings") {
                state.openSettings()
            }
            Spacer()
            FooterButton(icon: "power", help: "Quit gitle nock") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.top, 4)

    }
}

struct FooterButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(hovering ? Theme.text : Theme.textFaint)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - States

struct BusyView: View {
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.small)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ResultView: View {
    @EnvironmentObject private var state: AppState
    let result: ActionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.succeeded ? Theme.good : Theme.bad)
                Text(result.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }

            if let detail = result.detail {
                ScrollView {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
            }

            Spacer(minLength: 0)
            HoverCard(action: { state.screen = .main }) {
                Text("Back")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
        }
    }
}

struct MissingGitleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("gitle isn't installed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("This menu runs the gitle command behind the scenes. Install it, then reopen this app.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Text("curl -fsSL https://raw.githubusercontent.com/edbarbera/gitle/main/install.sh | sh")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .textSelection(.enabled)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            Spacer()
        }
    }
}

struct NoRepoView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add your first project")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Pick the folder your work lives in. gitle takes care of the rest.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HoverCard(action: { state.addRepo() }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    Text("Choose a folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .frame(maxWidth: 260)

            Spacer()
            FooterBar()
        }
    }
}

/// Shown before sending, when the user has asked to be asked.
struct ConfirmSendView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BackHeader(title: "Send your work online?")

            Text(state.status.ahead > 0
                 ? "\(state.status.ahead) save\(state.status.ahead == 1 ? "" : "s") will be uploaded to the shared copy online."
                 : "This uploads your saved work to the shared copy online.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                HoverCard(action: { state.confirmSend() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(Theme.accent)
                        Text("Send it")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
                HoverCard(action: { state.screen = .main }) {
                    Text("Not now")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .frame(maxWidth: 380)

            Spacer(minLength: 0)
        }
    }
}
