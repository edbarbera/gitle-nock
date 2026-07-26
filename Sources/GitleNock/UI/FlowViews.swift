import SwiftUI

// MARK: - Picking files

/// The checklist that used to be gitle's terminal `ui.Pick`. Everything starts
/// ticked, so "save it all" stays a single extra tap.
struct PickFilesView: View {
    @EnvironmentObject private var state: AppState

    private var picked: Int { state.pickedPaths.count }
    private var total: Int { state.status.changes.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BackHeader(
                    title: "What should be saved?",
                    subtitle: "Everything's ticked — untick anything you'd rather keep for later"
                )
                ChipButton(title: "All", icon: "checkmark", tint: Theme.good) { state.pickAll() }
                ChipButton(title: "None", icon: "minus") { state.pickNone() }
            }

            PanelScroll {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.status.changes) { change in
                        PickRow(
                            change: change,
                            isPicked: state.pickedPaths.contains(change.path)
                        ) {
                            state.togglePick(change.path)
                        }
                    }
                }
            }

            ActionButton(
                title: picked == 0
                    ? "Pick at least one file"
                    : "Continue with \(picked) of \(total) file\(total == 1 ? "" : "s")",
                icon: "arrow.right",
                tint: picked == 0 ? nil : Theme.warn,
                fills: true
            ) { state.reviewPicked() }
                .disabled(picked == 0)
        }
    }
}

private struct PickRow: View {
    let change: FileChange
    let isPicked: Bool
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isPicked ? Theme.good : .clear)
                        .frame(width: 16, height: 16)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isPicked ? Theme.good : Theme.strokeStrong, lineWidth: 1.2)
                        .frame(width: 16, height: 16)
                    if isPicked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.isDark ? .black.opacity(0.85) : .white)
                    }
                }
                .animation(Theme.snap, value: isPicked)

                Image(systemName: change.kind.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(FileRow.tint(for: change.kind).opacity(isPicked ? 1 : 0.5))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(change.filename)
                        .font(Theme.body(12.5, .medium))
                        .foregroundStyle(isPicked ? Theme.text : Theme.textDim)
                    Text(change.path)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)

                Text(change.kind.rawValue)
                    .font(Theme.display(10, .medium))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plainSurface(cornerRadius: 11)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : .clear)
                .allowsHitTesting(false)
        )
        .opacity(isPicked ? 1 : 0.62)
        .animation(Theme.hover, value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Risky files

/// gitle's "Save these anyway?" warning, which never reached anyone running the
/// notch because it needs a terminal to answer.
struct RiskView: View {
    @EnvironmentObject private var state: AppState
    let report: RiskReport

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            AlertHeader(
                icon: "exclamationmark.shield.fill",
                tint: Theme.bad,
                title: "Worth a second look",
                subtitle: "Nothing has been saved yet — your call"
            )

            PanelScroll {
                VStack(alignment: .leading, spacing: 9) {
                    if !report.secrets.isEmpty {
                        RiskGroup(
                            tint: Theme.bad,
                            icon: "key.fill",
                            title: "These look like private files",
                            note: "They often hold passwords or keys. Saving them puts those in your project's "
                                + "history — and sending online shares them.",
                            rows: report.secrets
                        )
                    }
                    if !report.large.isEmpty {
                        RiskGroup(
                            tint: Theme.warn,
                            icon: "shippingbox.fill",
                            title: "These are large",
                            note: "Big files make the project slow to grab and send for everyone.",
                            rows: report.large.map { "\($0.path)  ·  \(SafetyRails.humanSize($0.size))" }
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                ActionButton(title: "Leave those out", icon: "minus.circle.fill", tint: Theme.good) {
                    state.dropFlagged(report)
                }
                ActionButton(title: "Save them anyway") { state.acceptRisks() }
            }
        }
    }
}

private struct RiskGroup: View {
    let tint: Color
    let icon: String
    let title: String
    let note: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                IconChip(icon: icon, tint: tint, size: 20)
                Text(title)
                    .font(Theme.display(12.5, .semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }

            ForEach(rows, id: \.self) { row in
                Text(row)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(note)
                .font(Theme.body(10.5))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plainSurface(cornerRadius: Theme.controlRadius, tint: tint)
    }
}

// MARK: - Sending to a shared branch

/// gitle's push-to-main nudge. Headless it defaulted to "no", which made every
/// send from the notch fail on a default-branch project.
struct ConfirmProtectedSendView: View {
    @EnvironmentObject private var state: AppState
    let branch: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            AlertHeader(
                icon: "exclamationmark.triangle.fill",
                tint: Theme.warn,
                title: "Sending straight to \(branch)",
                subtitle: "This is the line of work everyone builds on"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "On a project with other people, it's safer to put changes on their own line "
                        + "first so they can be looked over."
                )
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Working on your own? Sending straight to \(branch) is perfectly fine.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plainSurface(cornerRadius: Theme.controlRadius)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                ActionButton(title: "Send to \(branch)", icon: "arrow.up.circle.fill", tint: Theme.accent) {
                    state.confirmProtectedSend()
                }
                ActionButton(title: "Not now") { state.screen = .main }
            }
        }
    }
}

// MARK: - Connecting an online home

struct ConnectView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var focused: Bool

    private var isEmpty: Bool {
        state.remoteURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BackHeader(
                title: "This project isn't online yet",
                subtitle: "One link and every save from now on is backed up"
            )

            HStack(spacing: 10) {
                StepBadge(number: 1, text: "Make an empty repository at github.com/new")
                StepBadge(number: 2, text: "Paste its link below")
            }

            PanelTextField(
                placeholder: "https://github.com/you/your-project.git",
                text: $state.remoteURL,
                focused: $focused,
                monospaced: true,
                onSubmit: { state.connectAndSend() }
            )

            Spacer(minLength: 0)

            ActionButton(title: "Connect and send", icon: "link", tint: Theme.accent, fills: true) {
                state.connectAndSend()
            }
            .disabled(isEmpty)
        }
        .onAppear { focused = true }
    }
}

/// A numbered instruction. Two of these beat one paragraph for anyone who has
/// never made a repository before.
private struct StepBadge: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(Theme.display(10.5, .bold))
                .foregroundStyle(Theme.isDark ? .black.opacity(0.8) : .white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Theme.accent))

            Text(text)
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .plainSurface(cornerRadius: 11)
    }
}
