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
                            note: "They often hold passwords or keys. Saving them puts those in your project's history — and sending online shares them.",
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
                Text("On a project with other people, it's safer to put changes on their own line first so they can be looked over.")
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

// MARK: - First-time setup

/// The notch version of `gitle start`, which bails out entirely without a terminal.
struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var focusedField: Field?

    private enum Field { case name, email }

    private var canFinish: Bool {
        !state.setupName.trimmingCharacters(in: .whitespaces).isEmpty
            && !state.setupEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BackHeader(
                title: "Set up this folder",
                subtitle: "Your name and email get stamped on everything you save"
            )

            HStack(spacing: 10) {
                SetupField(placeholder: "Your name", text: $state.setupName, field: .name, focused: $focusedField)
                SetupField(placeholder: "you@example.com", text: $state.setupEmail, field: .email, focused: $focusedField)
            }

            SetupToggle(
                isOn: $state.setupWantsGitignore,
                icon: "eye.slash.fill",
                tint: Theme.good,
                title: "Keep junk and secrets out",
                subtitle: "Adds a .gitignore matched to this project"
            )

            SetupToggle(
                isOn: $state.setupWantsFirstSave,
                icon: "clock.arrow.circlepath",
                tint: Theme.accent,
                title: "Make a first save",
                subtitle: "Snapshots everything here as “first version”"
            )

            Spacer(minLength: 0)

            ActionButton(title: "Set it up", icon: "sparkles", tint: Theme.good, fills: true) {
                state.runSetup()
            }
            .disabled(!canFinish)
        }
    }

    private struct SetupField: View {
        let placeholder: String
        @Binding var text: String
        let field: Field
        var focused: FocusState<Field?>.Binding

        var body: some View {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Theme.isDark ? .black.opacity(0.22) : .white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(
                            focused.wrappedValue == field ? Theme.accent.opacity(0.8) : Theme.stroke,
                            lineWidth: focused.wrappedValue == field ? 1.5 : 0.8
                        )
                )
                .focused(focused, equals: field)
                .animation(Theme.hover, value: focused.wrappedValue)
        }
    }
}

/// A switch with room to explain itself. The stock `Toggle` label can't carry
/// two lines and an icon without fighting its own alignment.
struct SetupToggle: View {
    @Binding var isOn: Bool
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 11) {
            IconChip(icon: icon, tint: tint, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.display(12.5, .medium))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(Theme.body(10.5))
                    .foregroundStyle(Theme.textFaint)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .plainSurface(cornerRadius: Theme.controlRadius)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - Undo

struct UndoView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BackHeader(title: "Go back", subtitle: "Two ways to rewind, both explained before they run")

            if let last = state.lastSaveMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR LAST SAVE")
                        .font(Theme.display(9, .bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textFaint)
                    Text("“\(last)”")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .plainSurface(cornerRadius: Theme.controlRadius)

                RewindCard(
                    icon: "arrow.uturn.backward.circle.fill",
                    tint: Theme.accent,
                    title: "Undo that save",
                    detail: "Removes the saved point. Every file change it held stays exactly as it is."
                ) { state.undoLastSave() }
            } else {
                Text("You haven't saved anything yet, so there's nothing to undo.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textDim)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .plainSurface(cornerRadius: Theme.controlRadius)
            }

            if !state.status.isClean {
                RewindCard(
                    icon: "trash.fill",
                    tint: Theme.bad,
                    title: "Throw away unsaved changes",
                    detail: "\(state.status.changes.count) file\(state.status.changes.count == 1 ? "" : "s") would go back to how they were at your last save."
                ) { state.screen = .confirmDiscard }
            }

            Spacer(minLength: 0)
        }
    }
}

/// A destructive-ish option that has to say what it does before it's tapped.
private struct RewindCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        GlassButton(tint: tint, action: action) {
            HStack(spacing: 11) {
                IconChip(icon: icon, tint: tint, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.display(12.5, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(Theme.body(10.5))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The one screen in the app that destroys work, so it names every file and
/// makes the safe option the easy one.
struct ConfirmDiscardView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            AlertHeader(
                icon: "exclamationmark.octagon.fill",
                tint: Theme.bad,
                title: "This cannot be undone",
                subtitle: "Anything typed since your last save is gone for good"
            )

            Text("These \(state.status.changes.count) file\(state.status.changes.count == 1 ? "" : "s") will go back to how they were at your last save.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            PanelScroll {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(state.status.changes) { change in
                        HStack(spacing: 8) {
                            Image(systemName: change.kind.symbol)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.bad)
                            Text(change.path)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .plainSurface(cornerRadius: Theme.controlRadius, tint: Theme.bad)

            HStack(spacing: 10) {
                ActionButton(title: "Keep my changes", icon: "shield.fill", tint: Theme.good) {
                    state.screen = .main
                }
                ActionButton(title: "Throw them away") { state.discardAllChanges() }
            }
        }
    }
}

// MARK: - Conflicts

/// The notch version of `gitle fix-conflicts`, which refuses to run without a
/// terminal. One decision per file, in the vocabulary of what the user just did.
struct ConflictsView: View {
    @EnvironmentObject private var state: AppState

    private var labels: (ours: String, theirs: String) { state.status.mergeOp.sideLabels }
    private var resolved: Int { state.conflicts.filter(\.isResolved).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AlertHeader(
                    icon: "arrow.triangle.pull",
                    tint: Theme.warn,
                    title: "Two versions of the same thing",
                    subtitle: "Someone else changed the same lines you did — nothing is lost until you choose"
                )
                ProgressPill(done: resolved, total: state.conflicts.count)
            }

            PanelScroll {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.conflicts) { file in
                        ConflictRow(file: file, labels: labels)
                    }
                }
            }

            HStack(spacing: 10) {
                ActionButton(
                    title: state.allConflictsResolved ? "All done — finish up" : "\(resolved) of \(state.conflicts.count) sorted",
                    icon: "checkmark.circle.fill",
                    tint: state.allConflictsResolved ? Theme.good : nil
                ) { state.finishConflicts() }
                    .disabled(!state.allConflictsResolved)

                ActionButton(title: "Undo the whole \(state.status.mergeOp.verb)") {
                    state.abortConflicts()
                }
            }
        }
    }
}

/// How far through the conflicts the user is, as a ring rather than a number —
/// the one place in the app where progress is worth showing graphically.
private struct ProgressPill: View {
    let done: Int
    let total: Int

    private var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.stroke, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    fraction >= 1 ? Theme.good : Theme.warn,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)")
                .font(Theme.display(8.5, .bold))
                .foregroundStyle(Theme.textDim)
        }
        .frame(width: 32, height: 32)
        .animation(Theme.spring, value: fraction)
    }
}

private struct ConflictRow: View {
    @EnvironmentObject private var state: AppState
    let file: ConflictFile
    let labels: (ours: String, theirs: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: file.isResolved ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 13))
                    .foregroundStyle(file.isResolved ? Theme.good : Theme.warn)

                VStack(alignment: .leading, spacing: 0) {
                    Text(file.filename)
                        .font(Theme.body(12.5, .medium))
                        .foregroundStyle(Theme.text)
                    Text(file.path)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)

                if file.isResolved {
                    StatusPill(text: "Sorted", icon: "checkmark", tint: Theme.good)
                }
            }

            if !file.isResolved {
                HStack(spacing: 6) {
                    ChipButton(title: "Keep \(labels.ours)", tint: Theme.accent) {
                        state.resolve(file.path, as: .keepOurs)
                    }
                    ChipButton(title: "Keep \(labels.theirs)", tint: Theme.accent) {
                        state.resolve(file.path, as: .keepTheirs)
                    }
                    ChipButton(title: "Open it", icon: "arrow.up.forward.app") {
                        state.openInEditor(relativePath: file.path)
                    }
                    ChipButton(title: "Done by hand", tint: Theme.good) {
                        state.resolve(file.path, as: .editedByHand)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .plainSurface(cornerRadius: 12, tint: file.isResolved ? Theme.good : nil)
    }
}
