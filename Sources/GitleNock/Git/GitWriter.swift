import Foundation

/// Write operations, run as plain git.
///
/// These used to go through `gitle`, but every one of them sits behind a
/// terminal prompt there — a file checklist, a "save these anyway?", an "are you
/// sure?". A prompt can't be answered from a headless subprocess, so gitle fell
/// back to its safe default and the action never happened. The notch asks those
/// questions itself now (see `SafetyRails` and the confirm screens) and then
/// runs the underlying git command directly.
///
/// `gitle grab` is the exception and still goes through `GitleRunner`: it has no
/// prompts, so it works fine headless.
enum GitWriter {
    // MARK: - Saving

    /// Stages exactly `paths` and commits them.
    ///
    /// Mirrors `gitle save`: `add -A -- <paths>` picks up new, changed and
    /// deleted files alike, and the pathspec on `commit` keeps anything the user
    /// unticked out of the snapshot even if it was already staged.
    static func save(paths: [String], message: String, in repo: String) -> ShellResult {
        guard !paths.isEmpty else {
            return ShellResult(status: -1, stdout: "", stderr: "No files were picked, so nothing was saved.")
        }

        let staged = git(["add", "-A", "--"] + paths, repo)
        guard staged.succeeded else { return staged }

        return git(["commit", "-m", message, "--"] + paths, repo)
    }

    // MARK: - Sending

    /// Pushes, setting up tracking on the first push of a branch.
    static func send(branch: String, hasUpstream: Bool, in repo: String) -> ShellResult {
        hasUpstream
            ? git(["push"], repo)
            : git(["push", "-u", "origin", branch], repo)
    }

    /// Turns git's push failure into plain English. Ported from gitle's
    /// `explainPushError` so the notch says the same thing the CLI would.
    static func explainPushFailure(_ stderr: String) -> String {
        let low = stderr.lowercased()
        if low.contains("rejected") || low.contains("non-fast-forward") || low.contains("fetch first") {
            return "There's newer work online you don't have yet. Grab the latest first, then send again."
        }
        if low.contains("authentication") || low.contains("could not read")
            || low.contains("permission denied") || low.contains("access denied") {
            return "GitHub needs you to sign in. If you use the gh tool, run `gh auth login` once, then try again."
        }
        if low.contains("does not appear to be a git repository") || low.contains("repository not found") {
            return "Couldn't reach the online copy. Check the project is still connected to GitHub."
        }
        return GitleRunner.firstMeaningfulLine(of: stderr) ?? "Couldn't send your work."
    }

    // MARK: - Undoing

    /// Removes the last saved point but keeps every file change it contained.
    static func undoLastSave(in repo: String) -> ShellResult {
        // No parent means this is the very first save. Dropping the ref returns
        // the repo to "nothing saved yet" without touching a single file.
        if git(["rev-parse", "HEAD~1"], repo).succeeded {
            return git(["reset", "--soft", "HEAD~1"], repo)
        }
        return git(["update-ref", "-d", "HEAD"], repo)
    }

    /// Throws away all uncommitted changes. Destructive and not reversible —
    /// only call this behind an explicit confirmation.
    static func discardAllChanges(hasCommits: Bool, in repo: String) -> ShellResult {
        let reset = hasCommits
            ? git(["reset", "--hard", "HEAD"], repo)
            : git(["reset", "-q"], repo)
        guard reset.succeeded else { return reset }

        // -fd also removes newly created files and folders, which `reset` leaves behind.
        return git(["clean", "-fd"], repo)
    }

    // MARK: - Setting up

    static func initRepo(in repo: String) -> ShellResult {
        // -b main names the default line of work "main", the modern convention.
        git(["init", "-b", "main"], repo)
    }

    /// Writes identity globally, matching what `gitle start` does — someone
    /// setting this up once shouldn't have to repeat it per project.
    static func setIdentity(name: String, email: String, in repo: String) -> ShellResult {
        let setName = git(["config", "--global", "user.name", name], repo)
        guard setName.succeeded else { return setName }
        return git(["config", "--global", "user.email", email], repo)
    }

    static func writeGitignore(in repo: String) -> ShellResult {
        let path = (repo as NSString).appendingPathComponent(".gitignore")
        guard !FileManager.default.fileExists(atPath: path) else {
            return ShellResult(status: 0, stdout: "Kept the .gitignore you already had.", stderr: "")
        }
        let body = SafetyRails.detectProject(in: repo).gitignore
        do {
            try body.write(toFile: path, atomically: true, encoding: .utf8)
            return ShellResult(status: 0, stdout: "Created a .gitignore.", stderr: "")
        } catch {
            return ShellResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
    }

    static func addRemote(_ url: String, in repo: String) -> ShellResult {
        git(["remote", "add", "origin", url], repo)
    }

    // MARK: - Conflicts

    static func keepOurs(_ path: String, in repo: String) -> ShellResult {
        git(["checkout", "--ours", "--", path], repo)
    }

    static func keepTheirs(_ path: String, in repo: String) -> ShellResult {
        git(["checkout", "--theirs", "--", path], repo)
    }

    static func markResolved(_ path: String, in repo: String) -> ShellResult {
        git(["add", "--", path], repo)
    }

    /// Finishes the half-done operation once every conflict is settled.
    static func continueOp(_ op: MergeOp, in repo: String) -> ShellResult {
        switch op {
        case .rebase:
            // A rebase continue would open an editor; the message is already written.
            return git(["-c", "core.editor=true", "rebase", "--continue"], repo)
        case .cherryPick:
            return git(["cherry-pick", "--continue", "--no-edit"], repo)
        case .merge:
            return git(["commit", "--no-edit"], repo)
        case .none:
            return ShellResult(status: 0, stdout: "", stderr: "")
        }
    }

    /// Backs the whole thing out and returns to where the user started.
    static func abortOp(_ op: MergeOp, in repo: String) -> ShellResult {
        switch op {
        case .rebase: return git(["rebase", "--abort"], repo)
        case .cherryPick: return git(["cherry-pick", "--abort"], repo)
        case .merge: return git(["merge", "--abort"], repo)
        case .none: return ShellResult(status: 0, stdout: "", stderr: "")
        }
    }

    /// True while a file still carries the `<<<<<<<` markers git left in it, so
    /// a hand-edit that didn't actually resolve anything isn't taken at its word.
    static func stillConflicted(_ path: String, in repo: String) -> Bool {
        let full = (repo as NSString).appendingPathComponent(path)
        guard let body = try? String(contentsOfFile: full, encoding: .utf8) else { return false }
        return body.contains("<<<<<<< ") || body.contains(">>>>>>> ")
    }

    private static func git(_ args: [String], _ repo: String) -> ShellResult {
        Shell.run(GitReader.gitPath, ["-C", repo] + args)
    }
}
