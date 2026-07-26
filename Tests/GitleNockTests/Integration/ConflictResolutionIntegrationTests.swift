import XCTest
@testable import GitleNock

/// The conflict-resolution primitives (`keepOurs`/`keepTheirs`/`markResolved`/
/// `continueOp`/`abortOp`) only mean anything mid-merge, so these drive a real
/// rebase conflict end to end rather than asserting on argument lists.
final class ConflictResolutionIntegrationTests: XCTestCase {
    func testKeepTheirsThenContinueRebaseFinishes() {
        let dir = makeConflictedRebase()
        defer { TestRepo.cleanup(dir) }

        XCTAssertEqual(GitReader.currentOp(in: dir), .rebase)
        XCTAssertTrue(GitWriter.stillConflicted("shared.txt", in: dir), "the conflict markers must still be there before anyone resolves it")

        XCTAssertTrue(GitWriter.keepTheirs("shared.txt", in: dir).succeeded)
        XCTAssertTrue(GitWriter.markResolved("shared.txt", in: dir).succeeded)

        let result = GitWriter.continueOp(.rebase, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertEqual(GitReader.currentOp(in: dir), .none)
        // "theirs" during a rebase of feature onto main is the incoming
        // commit's own content — the feature branch's edit.
        XCTAssertEqual(TestRepo.contents("shared.txt", in: dir), "feature version\n")
    }

    func testKeepOursThenContinueRebase() {
        let dir = makeConflictedRebase()
        defer { TestRepo.cleanup(dir) }

        XCTAssertTrue(GitWriter.keepOurs("shared.txt", in: dir).succeeded)
        XCTAssertTrue(GitWriter.markResolved("shared.txt", in: dir).succeeded)
        XCTAssertTrue(GitWriter.continueOp(.rebase, in: dir).succeeded)
        XCTAssertEqual(TestRepo.contents("shared.txt", in: dir), "main version\n")
    }

    func testAbortRebaseReturnsToPreRebaseState() {
        let dir = makeConflictedRebase()
        defer { TestRepo.cleanup(dir) }

        let result = GitWriter.abortOp(.rebase, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertEqual(GitReader.currentOp(in: dir), .none)
        XCTAssertEqual(TestRepo.contents("shared.txt", in: dir), "feature version\n")
    }

    func testEditedByHandRefusesWhileMarkersRemain() {
        let dir = makeConflictedRebase()
        defer { TestRepo.cleanup(dir) }

        // The user "resolves" by hand but leaves the conflict markers in —
        // `stillConflicted` must catch this before it's ever staged.
        XCTAssertTrue(GitWriter.stillConflicted("shared.txt", in: dir))
    }

    func testMergeConflictContinueUsesCommitNoEdit() {
        let dir = TestRepo.makeRepo()
        TestRepo.write("shared.txt", "base\n", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "add shared"], in: dir)

        TestRepo.git(["checkout", "-b", "topic"], in: dir)
        TestRepo.write("shared.txt", "topic\n", in: dir)
        TestRepo.git(["commit", "-am", "topic edit"], in: dir)

        TestRepo.git(["checkout", "main"], in: dir)
        TestRepo.write("shared.txt", "main\n", in: dir)
        TestRepo.git(["commit", "-am", "main edit"], in: dir)

        TestRepo.git(["merge", "topic"], in: dir) // conflicts, stays mid-merge
        defer { TestRepo.cleanup(dir) }

        XCTAssertEqual(GitReader.currentOp(in: dir), .merge)
        XCTAssertTrue(GitWriter.keepTheirs("shared.txt", in: dir).succeeded)
        XCTAssertTrue(GitWriter.markResolved("shared.txt", in: dir).succeeded)

        let result = GitWriter.continueOp(.merge, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertEqual(GitReader.currentOp(in: dir), .none)
        XCTAssertTrue(GitReader.status(of: dir).isClean)
    }

    // MARK: - Helper

    private func makeConflictedRebase() -> String {
        let dir = TestRepo.makeRepo()
        TestRepo.write("shared.txt", "base\n", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "add shared"], in: dir)

        TestRepo.git(["checkout", "-b", "feature"], in: dir)
        TestRepo.write("shared.txt", "feature version\n", in: dir)
        TestRepo.git(["commit", "-am", "feature edit"], in: dir)

        TestRepo.git(["checkout", "main"], in: dir)
        TestRepo.write("shared.txt", "main version\n", in: dir)
        TestRepo.git(["commit", "-am", "main edit"], in: dir)

        TestRepo.git(["checkout", "feature"], in: dir)
        TestRepo.git(["rebase", "main"], in: dir)
        return dir
    }
}
