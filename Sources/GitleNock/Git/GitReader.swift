import Foundation

/// Reads repo state with plumbing git commands.
///
/// Deliberately not `gitle status`: that output is prose written for humans and
/// would break this parser every time the wording is polished. Actions the user
/// takes still go through gitle — see `GitleRunner`.
enum GitReader {
    static var gitPath: String { Shell.which("git") ?? "/usr/bin/git" }

    static func status(of path: String) -> RepoStatus {
        var status = RepoStatus()

        let top = git(["rev-parse", "--show-toplevel"], path)
        guard top.succeeded else {
            // If the folder can't even be listed, this is a permission wall rather
            // than a folder nobody set up. Listing is the probe TCC answers
            // honestly — stat lies and git's error wording isn't dependable.
            let listable = (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            status.accessDenied = !listable
            return status
        }
        status.isRepo = true

        status.hasCommits = git(["rev-parse", "--verify", "HEAD"], path).succeeded

        let branch = git(["rev-parse", "--abbrev-ref", "HEAD"], path)
        status.branch = branch.succeeded
            ? branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            : "main"

        let remotes = git(["remote"], path)
        status.hasRemote = !remotes.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // -uall lists files inside untracked folders. Without it git collapses them
        // to "src/", which means nothing to someone who just wants to see their work.
        status.changes = parsePorcelain(
            git(["status", "--porcelain=v1", "-uall"], path).stdout,
            root: path
        )

        // A clashing grab leaves a half-done rebase behind. Until it's settled,
        // every other action is blocked, so the menu needs to know first.
        status.mergeOp = currentOp(in: path)
        if status.mergeOp != .none {
            status.conflictedFiles = conflictedFiles(in: path)
        }

        // "behind<TAB>ahead" relative to the tracking branch, if one exists.
        let counts = git(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], path)
        if counts.succeeded {
            let parts = counts.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0 == "\t" || $0 == " " })
            if parts.count == 2 {
                status.hasUpstream = true
                status.behind = Int(parts[0]) ?? 0
                status.ahead = Int(parts[1]) ?? 0
            }
        }

        return status
    }

    /// True if the folder is inside a git repo at all — used when adding a repo.
    static func isRepo(_ path: String) -> Bool {
        git(["rev-parse", "--is-inside-work-tree"], path).succeeded
    }

    /// The name git will stamp on saves. Shown in settings so the user can sanity-check it.
    static func identity(in path: String) -> (name: String, email: String)? {
        let name = git(["config", "user.name"], path).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = git(["config", "user.email"], path).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !email.isEmpty else { return nil }
        return (name, email)
    }

    /// Which half-finished operation, if any, the repo is sitting in.
    ///
    /// Read from the marker files in `.git` rather than by parsing status output,
    /// which is how git itself decides.
    static func currentOp(in path: String) -> MergeOp {
        let dir = git(["rev-parse", "--absolute-git-dir"], path)
        guard dir.succeeded else { return .none }
        let gitDir = dir.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        func marker(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: (gitDir as NSString).appendingPathComponent(name))
        }

        if marker("rebase-merge") || marker("rebase-apply") { return .rebase }
        if marker("CHERRY_PICK_HEAD") { return .cherryPick }
        if marker("MERGE_HEAD") { return .merge }
        return .none
    }

    /// Paths git couldn't merge on its own — status code `U` on either side.
    static func conflictedFiles(in path: String) -> [String] {
        let out = git(["diff", "--name-only", "--diff-filter=U"], path)
        guard out.succeeded else { return [] }
        return out.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The description on the most recent save, shown before undoing it so the
    /// user can see exactly what they're about to remove.
    static func lastSaveMessage(in path: String) -> String? {
        let out = git(["log", "-1", "--pretty=%s"], path)
        guard out.succeeded else { return nil }
        let subject = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? nil : subject
    }

    /// True when the folder has files in it, so setup can offer a first save.
    static func hasAnythingToSave(in path: String) -> Bool {
        !git(["status", "--porcelain=v1", "-uall"], path)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private static func git(_ args: [String], _ path: String) -> ShellResult {
        Shell.run(gitPath, ["-C", path] + args)
    }

    private static func parsePorcelain(_ raw: String, root: String) -> [FileChange] {
        // A path can appear twice — staged one way and unstaged another, e.g.
        // deleted from the index while still present on disk. The user thinks in
        // files, not in index entries, so collapse to one row each.
        var byPath: [String: FileChange.Kind] = [:]
        var order: [String] = []

        for line in raw.split(separator: "\n") {
            guard line.count > 3 else { continue }
            let code = String(line.prefix(2))
            var file = String(line.dropFirst(3))

            // Renames arrive as "old -> new"; the new name is what the user recognises.
            if let arrow = file.range(of: " -> ") {
                file = String(file[arrow.upperBound...])
            }
            file = file.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            let kind: FileChange.Kind
            if code.contains("?") || code.contains("A") {
                kind = .new
            } else if code.contains("D") {
                kind = .deleted
            } else if code.contains("R") {
                kind = .renamed
            } else {
                kind = .changed
            }

            if let existing = byPath[file] {
                // Conflicting verdicts: the disk is the tiebreaker.
                if existing != kind {
                    let full = (root as NSString).appendingPathComponent(file)
                    byPath[file] = FileManager.default.fileExists(atPath: full) ? .changed : .deleted
                }
            } else {
                byPath[file] = kind
                order.append(file)
            }
        }

        return order.compactMap { path in
            byPath[path].map { FileChange(kind: $0, path: path) }
        }
    }
}
