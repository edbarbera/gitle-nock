import SwiftUI

/// The write-action surface of `AppState`: saving, sending, grabbing, undoing,
/// setup, and conflict resolution, plus the shared `runWrite` plumbing they
/// all funnel through. Split out of `AppState.swift` purely to keep that
/// file's primary type declaration a reasonable size — everything here is
/// still part of `AppState` itself, not a separate abstraction.
extension AppState {
    // MARK: - Saving

    /// Opens the file checklist with everything ticked — the default is still
    /// "save it all", picking is the opt-in.
    func beginSave() {
        pickedPaths = Set(status.changes.map(\.path))
        screen = .pickFiles
    }

    func togglePick(_ path: String) {
        if pickedPaths.contains(path) {
            pickedPaths.remove(path)
        } else {
            pickedPaths.insert(path)
        }
    }

    func pickAll() { pickedPaths = Set(status.changes.map(\.path)) }
    func pickNone() { pickedPaths = [] }

    var pickedInOrder: [String] {
        status.changes.map(\.path).filter { pickedPaths.contains($0) }
    }

    /// Runs the secret / big-file check on the picked set before asking for a
    /// description, so a warning arrives before the user has typed anything.
    func reviewPicked() {
        guard let repo = activeRepo, !pickedPaths.isEmpty else { return }
        let report = SafetyRails.review(paths: pickedInOrder, root: repo.path)
        screen = report.isEmpty ? .save : .risks(report)
    }

    /// "Leave those out" — unticks every flagged file and carries on.
    func dropFlagged(_ report: RiskReport) {
        pickedPaths.subtract(report.allPaths)
        if pickedPaths.isEmpty {
            screen = .pickFiles
        } else {
            screen = .save
        }
    }

    /// "Save them anyway" — the user has seen the warning and accepted it.
    func acceptRisks() { screen = .save }

    func save() {
        let message = saveMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let repo = activeRepo else { return }
        let paths = pickedInOrder
        guard !paths.isEmpty else { return }

        runWrite(busy: "Saving your work…", failure: "That didn't work",
                 done: "Saved", icon: "tray.and.arrow.down.fill") {
            GitWriter.save(paths: paths, message: message, in: repo.path)
        } onSuccess: { [weak self] in
            self?.saveMessage = ""
            self?.pickedPaths = []
        }
    }

    // MARK: - Sending

    func send() {
        guard let repo = activeRepo else { return }

        guard status.hasCommits else {
            screen = .result(ActionResult(
                succeeded: false,
                title: "Nothing to send yet",
                detail: "Save some work first, then send it online."
            ))
            return
        }

        // No online home: collect a link rather than dead-ending, which is what
        // the CLI's interactive `gitle send` would offer to do here.
        guard status.hasRemote else {
            remoteURL = ""
            screen = .connect
            return
        }

        // The rail gitle can't reach headless: pushing straight to a shared branch.
        if SafetyRails.isProtected(status.branch) {
            screen = .confirmProtectedSend(status.branch)
            return
        }

        if settings.confirmBeforeSending {
            screen = .confirmSend
        } else {
            performSend(in: repo)
        }
    }

    /// Past the protected-branch warning; honour the ordinary confirm too if it's on.
    func confirmProtectedSend() {
        guard let repo = activeRepo else { return }
        if settings.confirmBeforeSending {
            screen = .confirmSend
        } else {
            performSend(in: repo)
        }
    }

    func confirmSend() {
        guard let repo = activeRepo else { return }
        performSend(in: repo)
    }

    private func performSend(in repo: Repo) {
        let branch = status.branch
        let hasUpstream = status.hasUpstream

        runWrite(busy: "Sending it online…", failure: "Couldn't send",
                 done: "Sent online", icon: "arrow.up") {
            GitWriter.send(branch: branch, hasUpstream: hasUpstream, in: repo.path)
        } explain: { result in
            GitWriter.explainPushFailure(result.message)
        }
    }

    /// Connects a GitHub link typed on the connect screen, then sends.
    func connectAndSend() {
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let repo = activeRepo else { return }

        runWrite(busy: "Connecting…", failure: "Couldn't connect that link",
                 done: "Connected", icon: "link") {
            GitWriter.addRemote(url, in: repo.path)
        } onSuccess: { [weak self] in
            self?.remoteURL = ""
            // Straight into the push; connecting on its own accomplishes nothing.
            self?.send()
        }
    }

    // MARK: - Grabbing

    /// The one action still handled by gitle: `grab` has no prompts, so it works
    /// headless and keeps its friendly conflict wording.
    func grab() {
        guard let repo = activeRepo else { return }

        // `work` and `summary` both run on `gitQueue`, in that order, so this
        // hands the pre-grab commit from one to the other without locking.
        let before = Handoff<String>()

        runWrite(busy: "Grabbing the latest…", failure: "Couldn't grab",
                 done: "Up to date", icon: "arrow.down",
                 summary: {
                     guard let old = before.value,
                           let new = GitReader.headSHA(in: repo.path),
                           old != new
                     else { return nil }   // nothing came down; no screen worth showing

                     let files = GitReader.changedFiles(from: old, to: new, in: repo.path)
                     let commits = GitReader.commitCount(from: old, to: new, in: repo.path)
                     return ActionResult(
                         succeeded: true,
                         title: "Got \(commits) update\(commits == 1 ? "" : "s")",
                         detail: nil,
                         files: files
                     )
                 },
                 work: {
                     before.value = GitReader.headSHA(in: repo.path)
                     return GitleRunner.run(.grab, in: repo.path)
                 })
    }

    // MARK: - Undoing

    func beginUndo() { screen = .undo }

    func undoLastSave() {
        guard let repo = activeRepo else { return }
        runWrite(busy: "Undoing your last save…", failure: "Couldn't undo",
                 done: "Undone", icon: "arrow.uturn.backward") {
            GitWriter.undoLastSave(in: repo.path)
        }
    }

    func discardAllChanges() {
        guard let repo = activeRepo else { return }
        let hasCommits = status.hasCommits
        runWrite(busy: "Discarding changes…", failure: "Couldn't discard",
                 done: "Changes discarded", icon: "trash") {
            GitWriter.discardAllChanges(hasCommits: hasCommits, in: repo.path)
        }
    }

    // MARK: - Setting up

    func beginSetup() {
        // Pre-fill from the global git config so a returning user just confirms.
        setupName = gitIdentity?.name ?? ""
        setupEmail = gitIdentity?.email ?? ""
        setupWantsGitignore = true
        setupWantsFirstSave = true
        screen = .setup
    }

    /// Runs every setup step in one go: init, identity, .gitignore, first save.
    func runSetup() {
        guard let repo = activeRepo else { return }
        let name = setupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = setupEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsGitignore = setupWantsGitignore
        let wantsFirstSave = setupWantsFirstSave
        let alreadyRepo = status.isRepo

        runWrite(busy: "Setting things up…", failure: "Setup didn't finish",
                 done: "All set up", icon: "sparkles") {
            if !alreadyRepo {
                let initialised = GitWriter.initRepo(in: repo.path)
                guard initialised.succeeded else { return initialised }
            }

            if !name.isEmpty && !email.isEmpty {
                let identity = GitWriter.setIdentity(name: name, email: email, in: repo.path)
                guard identity.succeeded else { return identity }
            }

            if wantsGitignore {
                let ignored = GitWriter.writeGitignore(in: repo.path)
                guard ignored.succeeded else { return ignored }
            }

            // The first save comes last so the .gitignore written above is already
            // in force — otherwise the junk it excludes lands in the very first snapshot.
            if wantsFirstSave && GitReader.hasAnythingToSave(in: repo.path) {
                let paths = GitReader.status(of: repo.path).changes.map(\.path)
                let saved = GitWriter.save(paths: paths, message: "first version", in: repo.path)
                guard saved.succeeded else { return saved }
            }

            return ShellResult(status: 0, stdout: "This folder is now yours to save and share.", stderr: "")
        }
    }

    /// A one-slot mailbox for handing a value from a write's `work` closure to
    /// its `summary` closure. Both run on `gitQueue`, one strictly after the
    /// other, so no synchronisation is needed.
    final class Handoff<T>: @unchecked Sendable {
        var value: T?
    }
}
