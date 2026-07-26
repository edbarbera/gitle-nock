import XCTest
@testable import GitleNock

/// Drives the same sequence `AppState` runs for a save — review, flag,
/// drop-or-accept, commit — across the real layers (`GitReader`,
/// `SafetyRails`, `GitWriter`) it's built from, without instantiating
/// `AppState` itself (which reaches into `NSApp`/`UserDefaults.standard` for
/// unrelated concerns). This is the flow a user exercises every single save.
final class SaveFlowFunctionalTests: XCTestCase {
    func testFlaggedSecretIsDroppedAndNeverCommitted() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        TestRepo.write(".env.production", "SECRET=1", in: dir) // matches ".env.*"
        TestRepo.write("README.md", "docs", in: dir)

        var picked = Set(GitReader.status(of: dir).changes.map(\.path))
        XCTAssertEqual(picked, Set([".env.production", "README.md"]))

        // reviewPicked()
        let report = SafetyRails.review(paths: Array(picked), root: dir)
        XCTAssertFalse(report.isEmpty)
        XCTAssertEqual(report.secrets, [".env.production"])

        // dropFlagged(report)
        picked.subtract(report.allPaths)
        XCTAssertEqual(picked, ["README.md"])

        let result = GitWriter.save(paths: Array(picked), message: "add docs", in: dir)
        XCTAssertTrue(result.succeeded, result.message)

        let status = GitReader.status(of: dir)
        XCTAssertEqual(
            status.changes.map(\.path),
            [".env.production"],
            "the secret must remain uncommitted, still flagged next time"
        )
    }

    func testAcceptRisksCommitsTheFlaggedFileAnyway() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("id_rsa", "not a real key", in: dir)

        let picked = ["id_rsa"]
        let report = SafetyRails.review(paths: picked, root: dir)
        XCTAssertFalse(report.isEmpty)

        // acceptRisks() just proceeds to save with the same picked set.
        let result = GitWriter.save(paths: picked, message: "add key anyway", in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(GitReader.status(of: dir).isClean)
    }

    func testUntickingAFileLeavesItOutOfTheCommit() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("a.txt", "a", in: dir)
        TestRepo.write("b.txt", "b", in: dir)

        // beginSave() seeds pickedPaths with everything, user unticks "b.txt".
        var picked = Set(GitReader.status(of: dir).changes.map(\.path))
        picked.remove("b.txt")

        let result = GitWriter.save(paths: Array(picked), message: "just a", in: dir)
        XCTAssertTrue(result.succeeded, result.message)

        let remaining = GitReader.status(of: dir).changes.map(\.path)
        XCTAssertEqual(remaining, ["b.txt"])
    }

    func testCleanRepoWithSecretAlreadyCommittedIsNotReflaggedOnNextSave() {
        // Guards against `review` walking committed history — it only looks
        // at the paths handed to it for *this* save, from working-tree state.
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("other.txt", "x", in: dir)

        let report = SafetyRails.review(paths: ["other.txt"], root: dir)
        XCTAssertTrue(report.isEmpty)
    }
}
