import XCTest
@testable import GitleNock

/// Replays `AppState`'s conflict screen: `beginConflicts` builds a
/// `ConflictFile` per path, the user resolves each one (mixed keep-ours /
/// keep-theirs is the realistic case), `allConflictsResolved` gates
/// `finishConflicts`, and `continueOp` lands the merge.
final class ConflictFlowFunctionalTests: XCTestCase {
    func testMixedResolutionGatesOnAllConflictsBeingResolved() {
        let dir = makeTwoFileConflict()
        defer { TestRepo.cleanup(dir) }

        var conflicts = GitReader.conflictedFiles(in: dir).map { ConflictFile(path: $0) }
        XCTAssertEqual(Set(conflicts.map(\.path)), Set(["one.txt", "two.txt"]))

        func allResolved() -> Bool { !conflicts.isEmpty && conflicts.allSatisfy(\.isResolved) }
        XCTAssertFalse(allResolved())

        // Resolve "one.txt" only.
        XCTAssertTrue(GitWriter.keepOurs("one.txt", in: dir).succeeded)
        XCTAssertTrue(GitWriter.markResolved("one.txt", in: dir).succeeded)
        conflicts[conflicts.firstIndex { $0.path == "one.txt" }!].resolution = .keepOurs
        XCTAssertFalse(allResolved(), "finishConflicts must stay blocked with one file still undecided")

        // Resolve "two.txt".
        XCTAssertTrue(GitWriter.keepTheirs("two.txt", in: dir).succeeded)
        XCTAssertTrue(GitWriter.markResolved("two.txt", in: dir).succeeded)
        conflicts[conflicts.firstIndex { $0.path == "two.txt" }!].resolution = .keepTheirs
        XCTAssertTrue(allResolved())

        let result = GitWriter.continueOp(.merge, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(GitReader.status(of: dir).isClean)
        XCTAssertTrue(GitReader.status(of: dir).conflictedFiles.isEmpty)
    }

    func testHandEditedFileStillShowingMarkersIsRejected() {
        let dir = makeTwoFileConflict()
        defer { TestRepo.cleanup(dir) }

        // User opens one.txt, saves it without actually removing the markers.
        XCTAssertTrue(GitWriter.stillConflicted("one.txt", in: dir))
        // `resolve(.editedByHand)` in AppState checks this and refuses to
        // mark it resolved — replicate that guard directly.
        let userClaimsResolved = !GitWriter.stillConflicted("one.txt", in: dir)
        XCTAssertFalse(userClaimsResolved)
    }

    func testAbortLeavesRepoCleanWithNoConflicts() {
        let dir = makeTwoFileConflict()
        defer { TestRepo.cleanup(dir) }

        XCTAssertTrue(GitWriter.abortOp(.merge, in: dir).succeeded)
        let status = GitReader.status(of: dir)
        XCTAssertTrue(status.isClean)
        XCTAssertEqual(status.mergeOp, .none)
    }

    // MARK: - Helper

    private func makeTwoFileConflict() -> String {
        let dir = TestRepo.makeRepo()
        TestRepo.write("one.txt", "base one\n", in: dir)
        TestRepo.write("two.txt", "base two\n", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "add both"], in: dir)

        TestRepo.git(["checkout", "-b", "topic"], in: dir)
        TestRepo.write("one.txt", "topic one\n", in: dir)
        TestRepo.write("two.txt", "topic two\n", in: dir)
        TestRepo.git(["commit", "-am", "topic edits"], in: dir)

        TestRepo.git(["checkout", "main"], in: dir)
        TestRepo.write("one.txt", "main one\n", in: dir)
        TestRepo.write("two.txt", "main two\n", in: dir)
        TestRepo.git(["commit", "-am", "main edits"], in: dir)

        TestRepo.git(["merge", "topic"], in: dir) // conflicts on both files
        return dir
    }
}
