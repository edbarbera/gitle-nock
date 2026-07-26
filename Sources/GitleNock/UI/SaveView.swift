import SwiftUI

/// Asks the one question a save needs: what did you change?
struct SaveView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var focused: Bool

    private var trimmed: String {
        state.saveMessage.trimmingCharacters(in: .whitespaces)
    }

    private var pickedSummary: String {
        let picked = state.pickedPaths.count
        let total = state.status.changes.count
        if picked == total {
            return "\(picked) file\(picked == 1 ? "" : "s") will be saved."
        }
        return "\(picked) of \(total) files will be saved — the rest stay as they are."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Back lands on the checklist, not the menu: the picking step is what
            // came before, and stepping over it would lose the selection.
            BackHeader(
                title: "Describe what you changed",
                subtitle: "In your own words — this is how you'll recognise it later",
                back: { state.screen = .pickFiles }
            )

            PanelTextField(
                placeholder: "fixed the login page",
                text: $state.saveMessage,
                focused: $focused,
                lines: 1...3,
                onSubmit: { state.save() }
            )

            HStack(spacing: 8) {
                // Reflects the checklist, not the whole repo — the two differ as
                // soon as anything was unticked, and quietly saying "all 12"
                // would be a lie.
                Text(pickedSummary)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 0)
                ForEach(SaveView.suggestions, id: \.self) { hint in
                    ChipButton(title: hint, tint: Theme.warn) {
                        state.saveMessage = hint
                        focused = true
                    }
                }
            }

            // Naming them here is the last chance to spot a file that shouldn't
            // be going in, and it keeps the screen from being one text box
            // floating in an empty panel.
            PanelScroll {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.status.changes.filter { state.pickedPaths.contains($0.path) }) { change in
                        FileRow(change: change)
                    }
                }
            }

            ActionButton(
                title: "Save it",
                icon: "tray.and.arrow.down.fill",
                tint: Theme.warn,
                fills: true
            ) { state.save() }
                .disabled(trimmed.isEmpty)
        }
        .onAppear { focused = true }
    }

    /// Starters for the blank page, in the same plain voice the rest of the app
    /// uses. Tapping one fills the box rather than saving straight away.
    private static let suggestions = ["work in progress", "small fixes", "first draft"]
}

/// The panel's text input. Stock `TextField` chrome is a bright system box that
/// looks pasted on top of glass, so the field draws its own.
struct PanelTextField: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var lines: ClosedRange<Int> = 1...1
    var monospaced: Bool = false
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(monospaced ? Theme.mono(12) : Theme.body(13))
            .foregroundStyle(Theme.text)
            .lineLimit(lines)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(Theme.isDark ? .black.opacity(0.22) : .white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(
                        focused.wrappedValue ? Theme.accent.opacity(0.8) : Theme.stroke,
                        lineWidth: focused.wrappedValue ? 1.5 : 0.8
                    )
            )
            .shadow(color: Theme.accent.opacity(focused.wrappedValue ? 0.22 : 0), radius: 10)
            .animation(Theme.hover, value: focused.wrappedValue)
            .focused(focused)
            .onSubmit(onSubmit)
    }
}

// MARK: - What changed

struct FilesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackHeader(
                title: "What changed",
                subtitle: "\(state.status.changes.count) file\(state.status.changes.count == 1 ? "" : "s") since your last save"
            )

            PanelScroll {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.status.changes) { change in
                        FileRow(change: change)
                    }
                }
            }

            ActionButton(
                title: "Save these",
                icon: "tray.and.arrow.down.fill",
                tint: Theme.warn,
                fills: true
            ) { state.beginSave() }
        }
    }
}

/// One changed file. Shared by the read-only list and the save checklist, so a
/// file looks the same wherever it's mentioned.
struct FileRow: View {
    let change: FileChange
    var trailing: String? = nil

    static func tint(for kind: FileChange.Kind) -> Color {
        switch kind {
        case .new: return Theme.good
        case .changed: return Theme.warn
        case .deleted: return Theme.bad
        case .renamed: return Theme.accent
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: change.kind.symbol)
                .font(.system(size: 12))
                .foregroundStyle(Self.tint(for: change.kind))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(change.filename)
                    .font(Theme.body(12.5, .medium))
                    .foregroundStyle(Theme.text)
                Text(change.path)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 0)

            Text(trailing ?? change.kind.rawValue)
                .font(Theme.display(10, .medium))
                .foregroundStyle(Self.tint(for: change.kind).opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Self.tint(for: change.kind).opacity(0.13)))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .plainSurface(cornerRadius: 11)
    }
}

// MARK: - Projects

struct ReposView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackHeader(
                title: "Your projects",
                subtitle: state.repos.count == 1 ? "1 folder being watched" : "\(state.repos.count) folders being watched"
            )

            PanelScroll {
                VStack(spacing: 5) {
                    ForEach(state.repos) { repo in
                        RepoRow(repo: repo, isActive: repo.id == state.activeRepo?.id)
                    }
                }
            }

            ActionButton(title: "Add a project", icon: "folder.badge.plus", tint: Theme.accent, fills: true) {
                state.addRepo()
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
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(isActive ? Theme.accent : Theme.stroke, lineWidth: isActive ? 5 : 1.2)
                    .frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                    .font(Theme.display(12.5, isActive ? .semibold : .medium))
                    .foregroundStyle(Theme.text)
                Text(repo.path)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 0)

            if isActive {
                StatusPill(text: "Open", tint: Theme.accent)
            }

            Button {
                state.remove(repo)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.surface))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove from this list (your files stay put)")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .plainSurface(cornerRadius: 12, tint: isActive ? Theme.accent : nil)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : .clear)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.select(repo)
            state.screen = .main
        }
        .animation(Theme.hover, value: hovering)
        .onHover { hovering = $0 }
    }
}
