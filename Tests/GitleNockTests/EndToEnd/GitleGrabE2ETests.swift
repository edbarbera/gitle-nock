import XCTest
@testable import GitleNock

/// Exercises the one action still routed through the real `gitle` binary
/// (`GitleRunner.run(.grab, ...)`), against a real remote — skipped
/// wherever gitle isn't installed (`FullLifecycleE2ETests` covers the
/// same journey deterministically with plain `git pull` instead).
///
/// Confirmed empirically (not assumed) that `gitle grab` is `fetch` +
/// `rebase`: a conflicting grab leaves `rebase-merge`/`REBASE_HEAD` behind,
/// which is exactly what `GitReader.currentOp` keys off.
final class GitleGrabE2ETests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(GitleRunner.isInstalled, "gitle is not installed on this machine")
    }

    func testGrabWithNoConflictFastForwardsAndReportsWhatArrived() {
        let remote = TestRepo.makeBareRemote()
        let devA = clone(remote, identity: ("Dev A", "a@example.com"))
        let devB = clone(remote, identity: ("Dev B", "b@example.com"))
        defer { TestRepo.cleanup(remote, devA, devB) }

        TestRepo.write("shared.txt", "v1\n", in: devA)
        XCTAssertTrue(GitWriter.save(paths: ["shared.txt"], message: "v1", in: devA).succeeded)
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: false, in: devA).succeeded)

        // Mirrors AppState.grab(): snapshot HEAD before, run grab, diff after.
        let before = GitReader.headSHA(in: devB) // nil: devB has no commits yet
        let grab = GitleRunner.run(.grab, in: devB)
        XCTAssertTrue(grab.succeeded, grab.message)

        let after = GitReader.headSHA(in: devB)
        XCTAssertNotNil(after)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(TestRepo.contents("shared.txt", in: devB), "v1\n")
        XCTAssertTrue(GitReader.status(of: devB).isClean)
    }

    func testGrabWithConflictLeavesRebaseInProgressAndIsRecoverable() {
        let remote = TestRepo.makeBareRemote()
        let devA = clone(remote, identity: ("Dev A", "a@example.com"))
        let devB = clone(remote, identity: ("Dev B", "b@example.com"))
        defer { TestRepo.cleanup(remote, devA, devB) }

        TestRepo.write("shared.txt", "base\n", in: devA)
        XCTAssertTrue(GitWriter.save(paths: ["shared.txt"], message: "base", in: devA).succeeded)
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: false, in: devA).succeeded)

        XCTAssertTrue(GitleRunner.run(.grab, in: devB).succeeded)
        TestRepo.git(["branch", "--set-upstream-to=origin/main", "main"], in: devB)

        // Both sides edit the same line: devB locally (unpushed), devA remotely.
        TestRepo.write("shared.txt", "dev B edit\n", in: devB)
        TestRepo.git(["add", "-A"], in: devB)
        TestRepo.git(["commit", "-m", "b edit"], in: devB)

        TestRepo.write("shared.txt", "dev A edit\n", in: devA)
        XCTAssertTrue(GitWriter.save(paths: ["shared.txt"], message: "a edit", in: devA).succeeded)
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: true, in: devA).succeeded)

        let grab = GitleRunner.run(.grab, in: devB)
        XCTAssertFalse(grab.succeeded, "expected the clashing grab gitle warns about")

        let status = GitReader.status(of: devB)
        XCTAssertEqual(status.mergeOp, .rebase)
        XCTAssertEqual(status.conflictedFiles, ["shared.txt"])

        // Resolve exactly as the conflicts screen does, using the op it discovered.
        // "theirs" in a rebase = devB's own replayed commit
        XCTAssertTrue(GitWriter.keepTheirs("shared.txt", in: devB).succeeded)
        XCTAssertTrue(GitWriter.markResolved("shared.txt", in: devB).succeeded)
        let finish = GitWriter.continueOp(status.mergeOp, in: devB)
        XCTAssertTrue(finish.succeeded, finish.message)

        XCTAssertEqual(GitReader.currentOp(in: devB), .none)
        XCTAssertEqual(TestRepo.contents("shared.txt", in: devB), "dev B edit\n")
        XCTAssertTrue(GitReader.status(of: devB).isClean)

        // The rebase replays devB's commit on top of devA's — a fast-forward push.
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: true, in: devB).succeeded)
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
