import SwiftUI

extension AppState {
    // MARK: - Conflicts

    func beginConflicts() {
        conflicts = status.conflictedFiles.map { ConflictFile(path: $0) }
        screen = .conflicts
    }

    func resolve(_ path: String, as resolution: ConflictFile.Resolution) {
        guard let repo = activeRepo,
              conflicts.contains(where: { $0.path == path }),
              resolution != .undecided
        else { return }

        // git here is a subprocess like any other, so it goes to the shared queue
        // rather than stalling the panel mid-tap.
        Self.gitQueue.async {
            switch resolution {
            case .keepOurs:
                guard GitWriter.keepOurs(path, in: repo.path).succeeded else { return }
            case .keepTheirs:
                guard GitWriter.keepTheirs(path, in: repo.path).succeeded else { return }
            case .editedByHand:
                // Taking the user's word here would stage the `<<<<<<<` markers,
                // which is worse than leaving the file conflicted. Check first.
                guard !GitWriter.stillConflicted(path, in: repo.path) else {
                    DispatchQueue.main.async {
                        self.screen = .result(ActionResult(
                            succeeded: false,
                            title: "Still needs work",
                            detail: "\(path) still has the <<<<<<< and >>>>>>> marker lines in it. Remove them, "
                                + "keep the version you want, save the file, then mark it done."
                        ))
                    }
                    return
                }
            case .undecided:
                return
            }

            guard GitWriter.markResolved(path, in: repo.path).succeeded else { return }

            DispatchQueue.main.async {
                guard self.activeRepo?.id == repo.id,
                      let index = self.conflicts.firstIndex(where: { $0.path == path })
                else { return }
                self.conflicts[index].resolution = resolution
            }
        }
    }

    var allConflictsResolved: Bool {
        !conflicts.isEmpty && conflicts.allSatisfy(\.isResolved)
    }

    func finishConflicts() {
        guard let repo = activeRepo, allConflictsResolved else { return }
        let mergeOp = status.mergeOp
        runWrite(busy: "Finishing up…", failure: "Couldn't finish",
                 done: "Sorted", icon: "checkmark") {
            GitWriter.continueOp(mergeOp, in: repo.path)
        } onSuccess: { [weak self] in
            self?.conflicts = []
        }
    }

    func abortConflicts() {
        guard let repo = activeRepo else { return }
        let mergeOp = status.mergeOp
        runWrite(busy: "Undoing it…", failure: "Couldn't back out",
                 done: "Backed out", icon: "arrow.uturn.backward") {
            GitWriter.abortOp(mergeOp, in: repo.path)
        } onSuccess: { [weak self] in
            self?.conflicts = []
        }
    }

    // MARK: - Running writes

    /// Runs one write off the main thread, shows the spinner, then re-reads state.
    ///
    /// On success this lands back on the main screen — the refreshed status
    /// already says what happened ("Everything saved and sent"), so parking on a
    /// separate success card was just an extra tap for no new information. A
    /// failure still gets its own screen, since there's no headline for that.
    ///
    /// `explain` turns a failure into user-facing wording; without it the first
    /// meaningful line of the tool's own output is used.
    ///
    /// `summary` runs on the git queue after a successful write, for actions
    /// whose outcome needs more subprocesses to describe — a grab has to diff
    /// two commits before it can say what arrived. Returning nil means there was
    /// nothing worth a screen. It must not touch main-actor state.
    func runWrite(
        busy: String,
        failure: String,
        done: String? = nil,
        icon: String = "checkmark",
        summary: (@Sendable () -> ActionResult?)? = nil,
        work: @escaping () -> ShellResult,
        explain: ((ShellResult) -> String)? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        guard !isBusy, let repo = activeRepo else { return }

        isBusy = true
        busyLabel = busy
        screen = .main
        show(PanelActivity(kind: .working, icon: "circle.dashed", text: busy))

        Self.gitQueue.async {
            let result = work()
            let detail = result.succeeded
                ? nil
                : (explain?(result) ?? GitleRunner.firstMeaningfulLine(of: result.message))
            let outcome = result.succeeded ? summary?() : nil
            // Re-read on this queue too; the main thread must not wait on git.
            let read = Self.readRepoState(repo.path)

            DispatchQueue.main.async {
                self.isBusy = false
                self.busyLabel = ""
                self.status = read.status
                self.lastSaveMessage = read.lastSaveMessage
                if result.succeeded {
                    // The summary knows more than the generic label does — "Got 3
                    // updates" beats "Up to date" when three actually landed.
                    self.show(PanelActivity(kind: .success, icon: icon, text: outcome?.title ?? done ?? "Done"))
                    if let outcome {
                        self.screen = .result(outcome)
                        self.resultAwaitingReview = true
                    }
                    onSuccess?()
                } else if !self.isBusy, case .main = self.screen {
                    self.show(PanelActivity(kind: .failure, icon: "exclamationmark", text: failure))
                    // onSuccess may have kicked off another write (connect → send)
                    // or routed elsewhere; don't bury that under a failure card —
                    // this only fires when nothing else already claimed the screen.
                    self.screen = .result(ActionResult(succeeded: false, title: failure, detail: detail))
                    self.resultAwaitingReview = true
                }
            }
        }
    }

    /// Publishes a note to the collapsed notch. A `.working` note stays put
    /// until the outcome replaces it; the outcome itself fades on its own.
    func show(_ next: PanelActivity) {
        activityToken &+= 1
        var note = next
        note.token = activityToken
        withAnimation(Theme.snap) { activity = note }

        guard next.kind != .working else { return }
        let token = activityToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.activity?.token == token else { return }
            withAnimation(Theme.snap) { self.activity = nil }
        }

        // A result nobody opened shouldn't still be sitting there an hour later,
        // waiting to greet the next hover with stale news.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.activityToken == token, self.resultAwaitingReview else { return }
            self.resultAwaitingReview = false
            if case .result = self.screen { self.screen = .main }
        }
    }

}
