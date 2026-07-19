import SwiftUI

// MARK: - Picking files

/// The checklist that used to be gitle's terminal `ui.Pick`. Everything starts
/// ticked, so "save it all" stays a single extra tap.
struct PickFilesView: View {
    @EnvironmentObject private var state: AppState

    private var picked: Int { state.pickedPaths.count }
    private var total: Int { state.status.changes.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                BackHeader(title: "What should be saved?")
                Spacer(minLength: 0)
                SmallButton(title: "All") { state.pickAll() }
                SmallButton(title: "None") { state.pickNone() }
            }

            Text("Everything's ticked. Untick anything you'd rather keep for later.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
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
            .frame(maxHeight: 190)

            Spacer(minLength: 0)

            HoverCard(action: { state.reviewPicked() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(picked == 0 ? Theme.textFaint : Theme.warn)
                    Text(picked == 0
                         ? "Pick at least one file"
                         : "Continue with \(picked) of \(total) file\(total == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .disabled(picked == 0)
            .opacity(picked == 0 ? 0.45 : 1)
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
            HStack(spacing: 8) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isPicked ? Theme.good : Theme.textFaint)

                Image(systemName: change.kind.symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textDim)

                VStack(alignment: .leading, spacing: 0) {
                    Text(change.filename)
                        .font(.system(size: 12))
                        .foregroundStyle(isPicked ? Theme.text : Theme.textDim)
                    Text(change.path)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)

                Text(change.kind.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Theme.cardHover : Theme.card)
            )
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(Theme.bad)
                Text("Worth a second look")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if !report.secrets.isEmpty {
                        RiskGroup(
                            tint: Theme.bad,
                            title: "These look like private files",
                            note: "They often hold passwords or keys. Saving them puts those in your project's history — and sending online shares them.",
                            rows: report.secrets
                        )
                    }
                    if !report.large.isEmpty {
                        RiskGroup(
                            tint: Theme.warn,
                            title: "These are large",
                            note: "Big files make the project slow to grab and send for everyone.",
                            rows: report.large.map { "\($0.path)  ·  \(SafetyRails.humanSize($0.size))" }
                        )
                    }
                }
            }
            .frame(maxHeight: 150)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                HoverCard(action: { state.dropFlagged(report) }) {
                    HStack(spacing: 7) {
                        Image(systemName: "minus.circle.fill").foregroundStyle(Theme.good)
                        Text("Leave those out")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
                HoverCard(action: { state.acceptRisks() }) {
                    Text("Save them anyway")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }
}

private struct RiskGroup: View {
    let tint: Color
    let title: String
    let note: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            ForEach(rows, id: \.self) { row in
                Text("•  \(row)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Sending to a shared branch

/// gitle's push-to-main nudge. Headless it defaulted to "no", which made every
/// send from the notch fail on a default-branch project.
struct ConfirmProtectedSendView: View {
    @EnvironmentObject private var state: AppState
    let branch: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warn)
                Text("Sending straight to \(branch)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            Text("‘\(branch)’ is the shared line of work everyone builds on. On a project with other people, it's safer to put changes on their own line first so they can be looked over.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Text("Working on your own? Sending straight to \(branch) is perfectly fine.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                HoverCard(action: { state.confirmProtectedSend() }) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(Theme.accent)
                        Text("Send to \(branch)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
                HoverCard(action: { state.screen = .main }) {
                    Text("Not now")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                }
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
        VStack(alignment: .leading, spacing: 9) {
            BackHeader(title: "This project isn't online yet")

            Text("Make an empty repository at github.com/new, then paste its link here. Your work goes up straight after.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://github.com/you/your-project.git", text: $state.remoteURL)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.text)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(focused ? Theme.accent.opacity(0.7) : Theme.hairline, lineWidth: 1)
                )
                .focused($focused)
                .onSubmit { state.connectAndSend() }

            Spacer(minLength: 0)

            HoverCard(action: { state.connectAndSend() }) {
                HStack(spacing: 7) {
                    Image(systemName: "link").foregroundStyle(Theme.accent)
                    Text("Connect and send")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .disabled(isEmpty)
            .opacity(isEmpty ? 0.45 : 1)
        }
        .onAppear { focused = true }
    }
}

// MARK: - First-time setup

/// The notch version of `gitle start`, which bails out entirely without a terminal.
struct SetupView: View {
    @EnvironmentObject private var state: AppState

    private var canFinish: Bool {
        !state.setupName.trimmingCharacters(in: .whitespaces).isEmpty
            && !state.setupEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            BackHeader(title: "Set up this folder")

            Text("Your name and email get stamped on everything you save, so people can see who did what.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SetupField(placeholder: "Your name", text: $state.setupName)
                SetupField(placeholder: "you@example.com", text: $state.setupEmail)
            }

            Toggle(isOn: $state.setupWantsGitignore) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep junk and secrets out")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                    Text("Adds a .gitignore matched to this project.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)

            Toggle(isOn: $state.setupWantsFirstSave) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Make a first save")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                    Text("Snapshots everything here as “first version”.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)

            Spacer(minLength: 0)

            HoverCard(action: { state.runSetup() }) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.good)
                    Text("Set it up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .disabled(!canFinish)
            .opacity(canFinish ? 1 : 0.45)
        }
    }
}

private struct SetupField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Undo

struct UndoView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            BackHeader(title: "Go back")

            if let last = state.lastSaveMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your last save")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                    Text("“\(last)”")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))

                HoverCard(action: { state.undoLastSave() }) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text("Undo that save")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        Text("Removes the saved point. Every file change it held stays exactly as it is.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("You haven't saved anything yet, so there's nothing to undo.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
            }

            if !state.status.isClean {
                HoverCard(action: { state.screen = .confirmDiscard }) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Image(systemName: "trash.fill").foregroundStyle(Theme.bad)
                            Text("Throw away unsaved changes")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        Text("\(state.status.changes.count) file\(state.status.changes.count == 1 ? "" : "s") would go back to how they were at your last save.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

/// The one screen in the app that destroys work, so it names every file and
/// makes the safe option the easy one.
struct ConfirmDiscardView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(Theme.bad)
                Text("This cannot be undone")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            Text("These \(state.status.changes.count) file\(state.status.changes.count == 1 ? "" : "s") will go back to how they were at your last save. Anything you've typed since is gone for good — there's no way to get it back.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.status.changes) { change in
                        HStack(spacing: 7) {
                            Image(systemName: change.kind.symbol)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.bad)
                            Text(change.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(maxHeight: 120)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                HoverCard(action: { state.screen = .main }) {
                    HStack(spacing: 7) {
                        Image(systemName: "shield.fill").foregroundStyle(Theme.good)
                        Text("Keep my changes")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
                HoverCard(action: { state.discardAllChanges() }) {
                    Text("Throw them away")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.bad)
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(Theme.warn)
                Text("Two versions of the same thing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            Text("Someone else changed the same lines you did. Pick which version to keep for each file — nothing is lost until you choose.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.conflicts) { file in
                        ConflictRow(file: file, labels: labels)
                    }
                }
            }
            .frame(maxHeight: 165)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                HoverCard(action: { state.finishConflicts() }) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(state.allConflictsResolved ? Theme.good : Theme.textFaint)
                        Text(state.allConflictsResolved
                             ? "All done — finish up"
                             : "\(state.conflicts.filter(\.isResolved).count) of \(state.conflicts.count) sorted")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
                .disabled(!state.allConflictsResolved)
                .opacity(state.allConflictsResolved ? 1 : 0.5)

                HoverCard(action: { state.abortConflicts() }) {
                    Text("Undo the whole \(state.status.mergeOp.verb)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }
}

private struct ConflictRow: View {
    @EnvironmentObject private var state: AppState
    let file: ConflictFile
    let labels: (ours: String, theirs: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: file.isResolved ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 12))
                    .foregroundStyle(file.isResolved ? Theme.good : Theme.warn)
                Text(file.filename)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(file.path)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }

            if !file.isResolved {
                HStack(spacing: 6) {
                    SmallButton(title: "Keep \(labels.ours)") {
                        state.resolve(file.path, as: .keepOurs)
                    }
                    SmallButton(title: "Keep \(labels.theirs)") {
                        state.resolve(file.path, as: .keepTheirs)
                    }
                    SmallButton(title: "Open it") {
                        state.openInEditor(relativePath: file.path)
                    }
                    SmallButton(title: "Done by hand") {
                        state.resolve(file.path, as: .editedByHand)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card)
        )
    }
}

// MARK: - Shared bits

struct SmallButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hovering ? Theme.text : Theme.textDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(hovering ? Theme.cardHover : Theme.card)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
