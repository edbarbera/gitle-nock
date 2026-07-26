extension AppState {
    /// Routes the panel to a named screen, seeding whatever that screen needs to
    /// have something to draw. Only reachable through the debug notification,
    /// which is off unless `GITLENOCK_DEBUG=1`.
    func jumpToScreen(_ name: String) {
        if let simple = simpleJumpTarget(name) {
            screen = simple
            return
        }
        performJumpNeedingSetup(name)
    }

    /// Screen names that resolve to a plain assignment, with no extra state to prepare.
    private func simpleJumpTarget(_ name: String) -> MenuScreen? {
        switch name {
        case "files": return .files
        case "repos": return .repos
        case "confirmSend": return .confirmSend
        case "confirmProtectedSend": return .confirmProtectedSend(status.branch.isEmpty ? "main" : status.branch)
        case "connect": return .connect
        case "undo": return .undo
        case "confirmDiscard": return .confirmDiscard
        default: return nil
        }
    }

    /// Screen names whose jump needs more than a plain assignment first.
    private func performJumpNeedingSetup(_ name: String) {
        switch name {
        case "pickFiles": beginSave()
        case "save":
            pickedPaths = Set(status.changes.map(\.path))
            screen = .save
        case "risks":
            pickedPaths = Set(status.changes.map(\.path))
            screen = .risks(SafetyRails.review(paths: Array(pickedPaths), root: activeRepo?.path ?? ""))
        case "setup": beginSetup()
        case "conflicts":
            conflicts = status.changes.prefix(3).map { ConflictFile(path: $0.path) }
            screen = .conflicts
        case "result":
            screen = .result(ActionResult(
                succeeded: false,
                title: "Couldn't send",
                detail: "! [rejected] main -> main (fetch first)\nerror: failed to push some refs"
            ))
        default: screen = .main
        }
    }

    /// Called when the notch collapses, so the next hover starts somewhere sensible.
    func resetTransientScreens() {
        switch screen {
        case .result:
            // An action that finished with the menu shut has its result waiting
            // to be read. Clearing it here would mean hovering after the notch
            // says "Couldn't grab" showed the main menu and no explanation.
            if !resultAwaitingReview { screen = .main }
        case .save, .confirmSend, .pickFiles, .risks,
             .confirmProtectedSend, .connect, .setup, .undo, .confirmDiscard:
            screen = .main
        case .main, .files, .repos, .conflicts:
            // Conflicts survive a collapse: half-resolved state is worth keeping.
            break
        }
    }

    /// Called when the panel opens. Anything waiting to be read has now been
    /// seen, so the next collapse is free to clear it.
    func markResultSeen() {
        resultAwaitingReview = false
    }

}
