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
    var badge: String? = nil
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

/// The row under the tiles: what's actually changed, named, one click from the
/// full list. Reassurance that the app is looking at the right folder.
struct ChangedFilesStrip: View {
    let changes: [FileChange]
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.warn)

                Text("See what changed")
                    .font(Theme.display(12, .medium))
                    .foregroundStyle(Theme.text)

                Text(changes.prefix(4).map(\.filename).joined(separator: "  ·  "))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Theme.textDim : Theme.textFaint)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .legibleOnPanel()
        }
        .buttonStyle(.plain)
        .plainSurface(cornerRadius: Theme.controlRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : .clear)
                .allowsHitTesting(false)
        )
        .animation(Theme.hover, value: hovering)
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
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle {
                    ActionButton(title: actionTitle, icon: icon, tint: tint, action: action)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plainSurface(tint: tint)
    }
}

// MARK: - Footer

/// The always-there toolbar. Sits in its own glass capsule so it reads as
/// chrome rather than as one more thing to decide about.
struct FooterBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Two capsules, not one bar: quitting sits apart from the things
            // people press all day, and one stretched-out tray with a lone
            // button at the far end reads as an unfinished toolbar.
            HStack(spacing: 2) {
                FooterButton(
                    icon: state.editorIsAvailable ? "chevron.left.forwardslash.chevron.right" : "folder",
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
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .glassPane(cornerRadius: 17, interactive: false)

            Spacer(minLength: 12)

            FooterButton(icon: "power", help: "Quit gitle nock", tint: Theme.bad) {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .glassPane(cornerRadius: 17, interactive: false)
        }
    }
}

struct FooterButton: View {
    let icon: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? (tint ?? Theme.text) : Theme.textFaint)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(hovering ? (tint ?? Color.primary).opacity(Theme.isDark ? 0.16 : 0.10) : .clear)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(Theme.hover, value: hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - States

struct BusyView: View {
    let label: String

    @State private var sweep = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Theme.stroke, lineWidth: 3)
                    .frame(width: 34, height: 34)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(
                        LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.2)],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(sweep ? 360 : 0))
                    .animation(
                        Theme.reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false),
                        value: sweep
                    )
            }

            Text(label)
                .font(Theme.display(13, .medium))
                .foregroundStyle(Theme.textDim)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { sweep = true }
    }
}

struct ResultView: View {
    @EnvironmentObject private var state: AppState
    let result: ActionResult

    private var subtitle: String? {
        if !result.succeeded { return "Here's exactly what git said, in case it helps" }
        if result.files.isEmpty { return nil }
        return "\(result.files.count) file\(result.files.count == 1 ? "" : "s") changed on your machine"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AlertHeader(
                icon: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tint: result.succeeded ? Theme.good : Theme.bad,
                title: result.title,
                subtitle: subtitle
            )

            if let detail = result.detail {
                PanelScroll(maxHeight: 168) {
                    Text(detail)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .plainSurface(cornerRadius: Theme.controlRadius)
            }

            // What a grab actually brought down. The whole point of the notch
            // reporting "Got 3 updates" is being able to hover and see which.
            if !result.files.isEmpty {
                PanelScroll {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.files) { file in
                            FileRow(change: file)
                        }
                    }
                }
            }

            if result.files.isEmpty && result.detail == nil {
                Spacer(minLength: 0)
            }

            ActionButton(title: "Back", icon: "chevron.left") { state.screen = .main }
        }
    }
}

struct MissingGitleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AlertHeader(
                icon: "shippingbox.fill",
                tint: Theme.warn,
                title: "gitle isn't installed",
                subtitle: "Grabbing the latest runs the gitle command behind the scenes"
            )

            Text("Paste this into Terminal, then reopen gitle nock.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textDim)

            Text("curl -fsSL https://raw.githubusercontent.com/edbarbera/gitle/main/install.sh | sh")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .plainSurface(cornerRadius: Theme.controlRadius)

            Spacer(minLength: 0)
        }
    }
}

struct NoRepoView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add your first project")
                    .font(Theme.display(21, .semibold))
                    .foregroundStyle(Theme.text)
                Text("Pick the folder your work lives in. gitle nock watches it from up here and takes care of the rest.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ActionButton(title: "Choose a folder", icon: "folder.badge.plus", tint: Theme.accent) {
                state.addRepo()
            }

            Spacer(minLength: 0)
            FooterBar()
        }
    }
}

/// Shown before sending, when the user has asked to be asked.
struct ConfirmSendView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackHeader(title: "Send your work online?")

            Text(state.status.ahead > 0
                 ? "\(state.status.ahead) save\(state.status.ahead == 1 ? "" : "s") will be uploaded to the shared copy online."
                 : "This uploads your saved work to the shared copy online.")
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                ActionButton(title: "Send it", icon: "arrow.up.circle.fill", tint: Theme.accent) {
                    state.confirmSend()
                }
                ActionButton(title: "Not now") { state.screen = .main }
            }
        }
    }
}
