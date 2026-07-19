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
                .frame(height: 100)

                if !status.isClean {
                    HoverCard(action: { state.screen = .files }) {
                        HStack(spacing: 8) {
                            IconChip(icon: "doc.on.doc.fill", tint: Theme.warn, size: 20)
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

    private var isLit: Bool { hovering && enabled }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                IconChip(icon: icon, tint: tint, size: 26)
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
                    .fill(isLit ? Theme.washHover(tint) : Theme.wash(tint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isLit ? Theme.edgeHover(tint) : Theme.edge(tint), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .scaleEffect(isLit ? 1.02 : 1)
        .shadow(color: tint.opacity(isLit ? 0.25 : 0), radius: 10, y: 4)
        .animation(.easeOut(duration: 0.15), value: hovering)
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
                HoverCard(tint: tint, action: action) {
                    HStack(spacing: 8) {
                        IconChip(icon: icon, tint: tint, size: 20)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .semibold))
                Text(state.status.branch.isEmpty ? "—" : state.status.branch)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.accent.opacity(0.15)))

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
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? Theme.cardHover : .clear))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: hovering)
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
                IconChip(
                    icon: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: result.succeeded ? Theme.good : Theme.bad
                )
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

            HoverCard(tint: Theme.accent, action: { state.addRepo() }) {
                HStack(spacing: 8) {
                    IconChip(icon: "plus.circle.fill", tint: Theme.accent, size: 20)
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
                HoverCard(tint: Theme.accent, action: { state.confirmSend() }) {
                    HStack(spacing: 8) {
                        IconChip(icon: "arrow.up.circle.fill", tint: Theme.accent, size: 20)
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
