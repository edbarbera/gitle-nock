import SwiftUI

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
    var tint: Color?
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
                Text(
                    "Pick the folder your work lives in. gitle nock watches it from up here and takes care of the rest."
                )
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

            Text(
                state.status.ahead > 0
                    ? "\(state.status.ahead) save\(state.status.ahead == 1 ? "" : "s") "
                        + "will be uploaded to the shared copy online."
                    : "This uploads your saved work to the shared copy online."
            )
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
