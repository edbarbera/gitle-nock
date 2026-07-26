import SwiftUI

/// Everything below the notch bar once the menu is open.
struct MenuContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)

            GlassEffectContainer(spacing: 12) {
                Group {
                    if !state.gitleInstalled {
                        MissingGitleView()
                    } else if state.activeRepo == nil {
                        NoRepoView()
                    } else if state.isBusy {
                        BusyView(label: state.busyLabel)
                    } else {
                        screenBody
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // Screens slide rather than cross-fade, so a flow reads as steps
            // forward through one panel instead of unrelated cards swapping.
            .animation(Theme.spring, value: state.screen)
        }
    }

    @ViewBuilder
    private var screenBody: some View {
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

// MARK: - Main menu

struct MainMenuView: View {
    @EnvironmentObject private var state: AppState

    private var status: RepoStatus { state.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeader()

            if status.accessDenied {
                NoticeBlock(
                    text: "macOS is blocking access to this folder. Pick it again to give permission "
                        + "— it only takes a second.",
                    actionTitle: "Give access",
                    icon: "lock.open.fill",
                    tint: Theme.warn
                ) { state.addRepo() }
            } else if !status.isRepo {
                NoticeBlock(
                    text: "This folder isn't being tracked yet. Setting it up takes a few seconds "
                        + "and means you can always get back to how things were.",
                    actionTitle: "Set it up",
                    icon: "sparkles",
                    tint: Theme.good
                ) { state.beginSetup() }
            } else if status.hasConflicts {
                // Nothing else can move until these are settled, so this replaces
                // the usual tiles rather than sitting alongside them.
                NoticeBlock(
                    text: "\(status.conflictedFiles.count) file\(status.conflictedFiles.count == 1 ? "" : "s") changed "
                        + "in two places at once. Pick which version to keep and everything carries on as normal.",
                    actionTitle: "Sort it out",
                    icon: "arrow.triangle.pull",
                    tint: Theme.warn
                ) { state.beginConflicts() }
            } else {
                // Three tiles across: the panel is wide, so the primary actions sit
                // side by side instead of stacking into a tall column.
                HStack(alignment: .top, spacing: 12) {
                    ActionTile(
                        icon: "tray.and.arrow.down.fill",
                        tint: Theme.warn,
                        title: "Save your work",
                        subtitle: status.isClean
                            ? "Nothing new to save"
                            : "\(status.changes.count) file\(status.changes.count == 1 ? "" : "s") changed",
                        badge: status.isClean ? nil : "\(status.changes.count)",
                        enabled: !status.isClean
                    ) { state.beginSave() }

                    ActionTile(
                        icon: "arrow.up.circle.fill",
                        tint: Theme.accent,
                        title: "Send it online",
                        subtitle: sendSubtitle,
                        badge: status.ahead > 0 ? "\(status.ahead)" : nil,
                        enabled: true
                    ) { state.send() }

                    ActionTile(
                        icon: "arrow.down.circle.fill",
                        tint: Theme.good,
                        title: "Grab the latest",
                        subtitle: status.behind > 0
                            ? "\(status.behind) update\(status.behind == 1 ? "" : "s") waiting"
                            : "You're up to date",
                        badge: status.behind > 0 ? "\(status.behind)" : nil,
                        enabled: true
                    ) { state.grab() }
                }
                .frame(height: 104)

                if !status.isClean {
                    ChangedFilesStrip(changes: status.changes) { state.screen = .files }
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

/// The one line that says how things stand, sized so it's readable from across
/// a desk. Everything else on the main menu is subordinate to it.
struct SummaryHeader: View {
    @EnvironmentObject private var state: AppState

    private var status: RepoStatus { state.status }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(status.headline)
                    .font(Theme.display(21, .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.text, Theme.text.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(subline)
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // The branch is already named in the top strip, so it isn't repeated
            // here — these pills only carry what that strip has no room for.
            HStack(spacing: 6) {
                if status.behind > 0 {
                    StatusPill(text: "\(status.behind) in", icon: "arrow.down", tint: Theme.good)
                }
                if status.ahead > 0 {
                    StatusPill(text: "\(status.ahead) out", icon: "arrow.up", tint: Theme.accent)
                }
            }
        }
        .legibleOnPanel()
    }

    /// Second line: the reassuring detail under the headline, never a repeat of it.
    private var subline: String {
        if status.accessDenied { return "Give gitle nock permission and it'll pick up where it left off" }
        if !status.isRepo { return "Nothing is being tracked in this folder yet" }
        if status.hasConflicts { return "Nothing is lost — pick a version for each and carry on" }
        if !status.hasRemote { return "This project has no online copy yet" }
        if !status.isClean { return "Save them whenever you like — nothing goes online until you send it" }
        if status.ahead > 0 { return "Your saves are safe on this Mac, just not shared yet" }
        return "Everything here matches the copy online"
    }
}

/// A primary action, sized to sit in a row of three.
struct ActionTile: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var badge: String?
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    private var isLit: Bool { hovering && enabled }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 6) {
                    IconChip(icon: icon, tint: tint, size: 30)
                    Spacer(minLength: 0)
                    if let badge {
                        Text(badge)
                            .font(Theme.display(10.5, .bold))
                            .foregroundStyle(Theme.isDark ? .black.opacity(0.8) : .white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.display(13.5, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(13)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .glassPane(tint: enabled ? tint : nil, interactive: enabled)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(isLit ? tint.opacity(0.12) : .clear)
                .allowsHitTesting(false)
        )
        .opacity(enabled ? 1 : 0.42)
        .scaleEffect(pressed ? 0.98 : (isLit ? 1.025 : 1))
        .shadow(color: tint.opacity(isLit ? 0.32 : 0), radius: 16, y: 6)
        .animation(Theme.hover, value: hovering)
        .animation(Theme.snap, value: pressed)
        .onHover { hovering = $0 }
        .onLongPressGesture(minimumDuration: 0.6, pressing: { pressed = $0 && enabled }, perform: {})
    }
}
