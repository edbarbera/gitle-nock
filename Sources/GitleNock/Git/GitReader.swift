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

        // Every read below is independent of the others. Run them together —
        // each `git` invocation costs process-launch overhead on top of the work
        // itself, and running six of them back to back is what made a single
        // refresh (every hover, every repo switch, every action) noticeably slow.
        let reads = runConcurrently([
            "hasCommits": { self.git(["rev-parse", "--verify", "HEAD"], path) },
            "branch": { self.git(["rev-parse", "--abbrev-ref", "HEAD"], path) },
            "remotes": { self.git(["remote"], path) },
            // -uall lists files inside untracked folders. Without it git collapses
            // them to "src/", which means nothing to someone who just wants to
            // see their work.
            "porcelain": { self.git(["status", "--porcelain=v1", "-uall"], path) },
            "gitDir": { self.git(["rev-parse", "--absolute-git-dir"], path) },
            // "behind<TAB>ahead" relative to the tracking branch, if one exists.
            "counts": { self.git(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], path) },
        ])

        status.hasCommits = reads["hasCommits"]!.succeeded

        status.branch = reads["branch"]!.succeeded
            ? reads["branch"]!.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            : "main"

        status.hasRemote = !reads["remotes"]!.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        status.changes = parsePorcelain(reads["porcelain"]!.stdout, root: path)

        // A clashing grab leaves a half-done rebase behind. Until it's settled,
        // every other action is blocked, so the menu needs to know first.
        status.mergeOp = mergeOp(fromGitDir: reads["gitDir"]!)
        if status.mergeOp != .none {
            status.conflictedFiles = conflictedFiles(in: path)
        }

        let counts = reads["counts"]!
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

    /// Runs several independent shell calls at once and waits for all of them.
    /// Every git invocation in this file is read-only and side-effect free, so
    /// nothing here needs to run in a particular order relative to the others.
    private static func runConcurrently(_ work: [String: () -> ShellResult]) -> [String: ShellResult] {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "gitlenock.reader", attributes: .concurrent)
        let lock = NSLock()
        var results: [String: ShellResult] = [:]

        for (key, task) in work {
            queue.async(group: group) {
                let result = task()
                lock.lock()
                results[key] = result
                lock.unlock()
            }
        }
        group.wait()
        return results
    }

    /// True if the folder is inside a git repo at all — used when adding a repo.
    static func isRepo(_ path: String) -> Bool {
        git(["rev-parse", "--is-inside-work-tree"], path).succeeded
    }

    /// The name git will stamp on saves. Shown in settings so the user can sanity-check it.
    static func identity(in path: String) -> (name: String, email: String)? {
        let reads = runConcurrently([
            "name": { self.git(["config", "user.name"], path) },
            "email": { self.git(["config", "user.email"], path) },
        ])
        let name = reads["name"]!.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = reads["email"]!.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !email.isEmpty else { return nil }
        return (name, email)
    }

    /// Which half-finished operation, if any, the repo is sitting in.
    ///
    /// Read from the marker files in `.git` rather than by parsing status output,
    /// which is how git itself decides.
    static func currentOp(in path: String) -> MergeOp {
        mergeOp(fromGitDir: git(["rev-parse", "--absolute-git-dir"], path))
    }

    private static func mergeOp(fromGitDir dir: ShellResult) -> MergeOp {
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

    /// The commit HEAD points at. Read either side of a grab so the panel can
    /// say what actually came down, rather than just that something did.
    static func headSHA(in path: String) -> String? {
        let out = git(["rev-parse", "HEAD"], path)
        guard out.succeeded else { return nil }
        let sha = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    /// How many commits arrived between two points, for "3 updates" wording.
    static func commitCount(from old: String, to new: String, in path: String) -> Int {
        let out = git(["rev-list", "--count", "\(old)..\(new)"], path)
        guard out.succeeded else { return 0 }
        return Int(out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Files touched between two commits, in the same shape as working-copy
    /// changes so the panel can render them with the row it already has.
    static func changedFiles(from old: String, to new: String, in path: String) -> [FileChange] {
        let out = git(["diff", "--name-status", "-M", "\(old)..\(new)"], path)
        guard out.succeeded else { return [] }

        return out.stdout.split(separator: "\n").compactMap { line in
            // "M\tpath", "A\tpath", "D\tpath", or "R100\told\tnew" for a rename.
            let fields = line.split(separator: "\t").map(String.init)
            guard let code = fields.first?.first, fields.count >= 2 else { return nil }

            let kind: FileChange.Kind
            switch code {
            case "A": kind = .new
            case "D": kind = .deleted
            case "R", "C": kind = .renamed
            default: kind = .changed
            }
            // A rename reports both names; the new one is what the user recognises.
            return FileChange(kind: kind, path: fields.last!)
        }
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
