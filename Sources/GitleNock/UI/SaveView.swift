import SwiftUI

/// Asks the one question a save needs: what did you change?
struct SaveView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var focused: Bool

    private var pickedSummary: String {
        let picked = state.pickedPaths.count
        let total = state.status.changes.count
        if picked == total {
            return "\(picked) file\(picked == 1 ? "" : "s") will be saved."
        }
        return "\(picked) of \(total) files will be saved — the rest stay as they are."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Back lands on the checklist, not the menu: the picking step is what
            // came before, and stepping over it would lose the selection.
            BackHeader(title: "Save your work", back: { state.screen = .pickFiles })

            Text("Describe what you changed, in your own words.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim)

            TextField("fixed the login page", text: $state.saveMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1...3)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(focused ? Theme.accent.opacity(0.7) : Theme.hairline, lineWidth: 1)
                )
                .focused($focused)
                .onSubmit { state.save() }

            // Reflects the checklist, not the whole repo — the two differ as soon
            // as anything was unticked, and quietly saying "all 12" would be a lie.
            Text(pickedSummary)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)

            HoverCard(action: { state.save() }) {
                HStack {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(Theme.warn)
                    Text("Save it")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .disabled(state.saveMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(state.saveMessage.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)

            Spacer(minLength: 0)
        }
        .onAppear { focused = true }
    }
}

struct FilesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BackHeader(title: "What changed")

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.status.changes) { change in
                        HStack(spacing: 8) {
                            Image(systemName: change.kind.symbol)
                                .font(.system(size: 11))
                                .foregroundStyle(tint(for: change.kind))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(change.filename)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.text)
                                Text(change.kind.rawValue)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Spacer(minLength: 0)
            HoverCard(action: { state.beginSave() }) {
                Text("Save these")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private func tint(for kind: FileChange.Kind) -> Color {
        switch kind {
        case .new: return Theme.good
        case .changed: return Theme.warn
        case .deleted: return Theme.bad
        case .renamed: return Theme.accent
        }
    }
}

struct ReposView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BackHeader(title: "Your projects")

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(state.repos) { repo in
                        RepoRow(repo: repo, isActive: repo.id == state.activeRepo?.id)
                    }
                }
            }

            Spacer(minLength: 0)
            HoverCard(action: { state.addRepo() }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("Add a project")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }
}

struct RepoRow: View {
    @EnvironmentObject private var state: AppState
    let repo: Repo
    let isActive: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Theme.accent : Theme.textFaint)

            VStack(alignment: .leading, spacing: 0) {
                Text(repo.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                Text(repo.path)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 0)

            if hovering {
                Button {
                    state.remove(repo)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
                .help("Remove from this list (your files stay put)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? Theme.cardHover : Theme.card)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.select(repo)
            state.screen = .main
        }
        .onHover { hovering = $0 }
    }
}

struct BackHeader: View {
    @EnvironmentObject private var state: AppState
    let title: String
    /// Where the chevron goes. Defaults to the main menu; multi-step flows pass
    /// their own previous step.
    var back: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if let back { back() } else { state.screen = .main }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
        }
    }
}
