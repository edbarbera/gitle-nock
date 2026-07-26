import XCTest
@testable import GitleNock

/// Two "developers" (plain clones, no mocking) sharing one bare "origin",
/// driven entirely through `GitReader`/`GitWriter`/`SafetyRails` in the same
/// sequence the notch panel uses — setup, save, send, a rejected push, a real
/// merge conflict, resolution, and a final send. This is the closest thing to
/// a UI-level end-to-end test the app has: the SwiftUI/AppKit layer above
/// this is a thin, mostly declarative view over exactly this engine, and it
/// has no window to drive (`LSUIElement`, notch-only panel), so there's no
/// XCUITest target here — this proves the underlying engine's full journey
/// instead. Uses plain `git pull` (not `gitle grab`) so the outcome is fully
/// deterministic and doesn't depend on gitle being installed; see
/// `GitleGrabE2ETests` for the gitle-specific counterpart.
final class FullLifecycleE2ETests: XCTestCase {
    func testTwoDeveloperLifecycleWithConflictAndRecovery() {
        let remote = TestRepo.makeBareRemote()
        let devA = clone(remote, identity: ("Dev A", "a@example.com"))
        let devB = clone(remote, identity: ("Dev B", "b@example.com"))
        defer { TestRepo.cleanup(remote, devA, devB) }

        // 1. Dev A does first-run setup and sends the initial version.
        TestRepo.write("README.md", "hello project\n", in: devA)
        TestRepo.write("shared.txt", "line one\n", in: devA)
        XCTAssertTrue(GitWriter.writeGitignore(in: devA).succeeded)
        let initialPaths = GitReader.status(of: devA).changes.map(\.path)
        XCTAssertTrue(GitWriter.save(paths: initialPaths, message: "first version", in: devA).succeeded)
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: false, in: devA).succeeded)

        // 2. Dev B pulls it down and tracks main explicitly — the clone predates
        //    origin/main existing, so it wasn't wired up automatically.
        XCTAssertTrue(TestRepo.git(["pull", "origin", "main"], in: devB).succeeded)
        TestRepo.git(["branch", "--set-upstream-to=origin/main", "main"], in: devB)
        XCTAssertEqual(TestRepo.contents("shared.txt", in: devB), "line one\n")

        // 3. Dev B commits a local change but doesn't push yet.
        TestRepo.write("shared.txt", "dev B's edit\n", in: devB)
        TestRepo.git(["add", "-A"], in: devB)
        TestRepo.git(["commit", "-m", "dev B edit"], in: devB)

        // 4. Meanwhile Dev A changes the same line and sends first.
        TestRepo.write("shared.txt", "dev A's edit\n", in: devA)
        XCTAssertTrue(GitWriter.save(paths: ["shared.txt"], message: "dev A edit", in: devA).succeeded)
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: true, in: devA).succeeded)

        // 5. Dev B's push is now rejected, and the app must say why in plain English.
        let rejected = GitWriter.send(branch: "main", hasUpstream: true, in: devB)
        XCTAssertFalse(rejected.succeeded)
        XCTAssertTrue(GitWriter.explainPushFailure(rejected.message).contains("Grab the latest"))

        // 6. Dev B grabs — a real conflict, since both sides touched the same line.
        //    Pin the merge strategy so the "ours"/"theirs" mapping below is deterministic.
        TestRepo.git(["config", "pull.rebase", "false"], in: devB)
        let grabResult = TestRepo.git(["pull"], in: devB)
        XCTAssertFalse(grabResult.succeeded, "expected a conflicting pull")
        XCTAssertEqual(GitReader.currentOp(in: devB), .merge)
        XCTAssertEqual(GitReader.conflictedFiles(in: devB), ["shared.txt"])
        XCTAssertTrue(GitWriter.stillConflicted("shared.txt", in: devB))

        // 7. Dev B resolves in favour of the incoming (origin/Dev A) version.
        XCTAssertTrue(GitWriter.keepTheirs("shared.txt", in: devB).succeeded)
        XCTAssertFalse(GitWriter.stillConflicted("shared.txt", in: devB))
        XCTAssertTrue(GitWriter.markResolved("shared.txt", in: devB).succeeded)

        XCTAssertEqual(GitReader.status(of: devB).mergeOp, .merge)
        let finish = GitWriter.continueOp(.merge, in: devB)
        XCTAssertTrue(finish.succeeded, finish.message)
        XCTAssertEqual(GitReader.currentOp(in: devB), .none)
        XCTAssertTrue(GitReader.status(of: devB).isClean)
        XCTAssertEqual(TestRepo.contents("shared.txt", in: devB), "dev A's edit\n")

        // 8. Dev B can now send the merge commit.
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: true, in: devB).succeeded)

        // 9. Dev A grabs and sees the merge come back, converged.
        XCTAssertTrue(TestRepo.git(["pull"], in: devA).succeeded)
        XCTAssertEqual(TestRepo.contents("shared.txt", in: devA), "dev A's edit\n")
        XCTAssertEqual(GitReader.status(of: devA).headline, "Everything saved and sent")
        XCTAssertEqual(GitReader.status(of: devB).headline, "Everything saved and sent")
    }

    func testUndoAndDiscardSurviveARealSendHistory() {
        let remote = TestRepo.makeBareRemote()
        let dev = clone(remote, identity: ("Dev", "dev@example.com"))
        defer { TestRepo.cleanup(remote, dev) }

        TestRepo.write("a.txt", "1", in: dev)
        XCTAssertTrue(GitWriter.save(paths: ["a.txt"], message: "commit one", in: dev).succeeded)
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: false, in: dev).succeeded)

        TestRepo.write("a.txt", "2", in: dev)
        XCTAssertTrue(GitWriter.save(paths: ["a.txt"], message: "commit two", in: dev).succeeded)

        // Undo the unsent commit — the previous, already-sent one must survive untouched.
        XCTAssertTrue(GitWriter.undoLastSave(in: dev).succeeded)
        XCTAssertEqual(GitReader.lastSaveMessage(in: dev), "commit one")
        XCTAssertEqual(TestRepo.contents("a.txt", in: dev), "2", "soft reset keeps the file change on disk")

        // Discard drops that now-uncommitted change entirely.
        XCTAssertTrue(GitWriter.discardAllChanges(hasCommits: true, in: dev).succeeded)
        XCTAssertEqual(TestRepo.contents("a.txt", in: dev), "1")
        XCTAssertTrue(GitReader.status(of: dev).isClean)
    }

    // MARK: - Helper

    private func clone(_ remote: String, identity: (name: String, email: String)) -> String {
        let dir = TestRepo.makeTempDir("clone")
        TestRepo.git(["clone", remote, dir], in: NSTemporaryDirectory())
        TestRepo.git(["config", "user.name", identity.name], in: dir)
        TestRepo.git(["config", "user.email", identity.email], in: dir)
        return dir
    }
}
