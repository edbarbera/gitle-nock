import XCTest
@testable import GitleNock

/// Exercises `GitReader` against real git repos on disk — the porcelain
/// parsing and plumbing calls are only trustworthy if proven against actual
/// git output, not a stubbed one.
final class GitReaderIntegrationTests: XCTestCase {
    func testStatusOfNonRepoFolder() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }

        let status = GitReader.status(of: dir)
        XCTAssertFalse(status.isRepo)
        XCTAssertFalse(status.accessDenied)
    }

    func testStatusOfUnreadableFolderReportsAccessDenied() throws {
        try XCTSkipIf(geteuid() == 0, "root bypasses POSIX permission bits, so this probe doesn't apply")
        let dir = TestRepo.makeTempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir)
            TestRepo.cleanup(dir)
        }
        try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir)

        let status = GitReader.status(of: dir)
        XCTAssertFalse(status.isRepo)
        XCTAssertTrue(status.accessDenied)
    }

    func testStatusOfFreshRepoWithNoCommits() {
        let dir = TestRepo.makeRepo(withCommit: false)
        defer { TestRepo.cleanup(dir) }

        let status = GitReader.status(of: dir)
        XCTAssertTrue(status.isRepo)
        XCTAssertFalse(status.hasCommits)
        XCTAssertEqual(status.branch, "main")
        XCTAssertFalse(status.hasRemote)
    }

    func testStatusOfCleanRepoAfterCommit() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        let status = GitReader.status(of: dir)
        XCTAssertTrue(status.isRepo)
        XCTAssertTrue(status.hasCommits)
        XCTAssertTrue(status.isClean)
        XCTAssertEqual(status.mergeOp, .none)
    }

    func testStatusReportsNewChangedDeletedFiles() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        // A second tracked file, committed, so there's something to delete later.
        TestRepo.write("to-delete.txt", "bye\n", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "second"], in: dir)

        // Three independent, uncommitted changes against that history.
        TestRepo.write("hello.txt", "changed\n", in: dir)
        TestRepo.write("new-file.txt", "new\n", in: dir)
        try! FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent("to-delete.txt"))

        let status = GitReader.status(of: dir)
        let byPath = Dictionary(uniqueKeysWithValues: status.changes.map { ($0.path, $0.kind) })

        XCTAssertEqual(byPath["new-file.txt"], .new)
        XCTAssertEqual(byPath["hello.txt"], .changed)
        XCTAssertEqual(byPath["to-delete.txt"], .deleted)
    }

    func testStatusUntrackedFolderContentsAreListedNotCollapsed() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("src/deep/file.txt", "x", in: dir)

        let status = GitReader.status(of: dir)
        XCTAssertTrue(status.changes.contains { $0.path == "src/deep/file.txt" },
                      "expected -uall behaviour: full paths, not a collapsed 'src/' entry")
    }

    func testStatusAheadAndBehindAgainstUpstream() {
        let remote = TestRepo.makeBareRemote()
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(remote, dir) }

        TestRepo.git(["remote", "add", "origin", remote], in: dir)
        TestRepo.git(["push", "-u", "origin", "main"], in: dir)

        // Someone else pushes a commit.
        let other = TestRepo.makeTempDir("clone")
        TestRepo.git(["clone", remote, other], in: NSTemporaryDirectory())
        TestRepo.git(["config", "user.name", "Other"], in: other)
        TestRepo.git(["config", "user.email", "other@example.com"], in: other)
        TestRepo.write("from-other.txt", "hi", in: other)
        TestRepo.git(["add", "-A"], in: other)
        TestRepo.git(["commit", "-m", "other's work"], in: other)
        TestRepo.git(["push"], in: other)
        defer { TestRepo.cleanup(other) }

        // Local makes its own unpushed commit.
        TestRepo.write("from-me.txt", "hi", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "my work"], in: dir)
        TestRepo.git(["fetch"], in: dir)

        let status = GitReader.status(of: dir)
        XCTAssertTrue(status.hasUpstream)
        XCTAssertEqual(status.ahead, 1)
        XCTAssertEqual(status.behind, 1)
    }

    func testIsRepo() {
        let repo = TestRepo.makeRepo()
        let notRepo = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(repo, notRepo) }

        XCTAssertTrue(GitReader.isRepo(repo))
        XCTAssertFalse(GitReader.isRepo(notRepo))
    }

    func testIdentityReadsLocalConfig() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        let identity = GitReader.identity(in: dir)
        XCTAssertEqual(identity?.name, "Test User")
        XCTAssertEqual(identity?.email, "test@example.com")
    }

    func testCurrentOpDuringRebaseConflict() {
        let (dir, _) = makeConflictedRebase()
        defer { TestRepo.cleanup(dir) }

        XCTAssertEqual(GitReader.currentOp(in: dir), .rebase)
    }

    func testConflictedFilesDuringRebase() {
        let (dir, conflictPath) = makeConflictedRebase()
        defer { TestRepo.cleanup(dir) }

        XCTAssertEqual(GitReader.conflictedFiles(in: dir), [conflictPath])
    }

    func testLastSaveMessage() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        XCTAssertEqual(GitReader.lastSaveMessage(in: dir), "initial")
    }

    func testLastSaveMessageNilBeforeAnyCommit() {
        let dir = TestRepo.makeRepo(withCommit: false)
        defer { TestRepo.cleanup(dir) }
        XCTAssertNil(GitReader.lastSaveMessage(in: dir))
    }

    func testHeadSHAAndCommitCountAndChangedFiles() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        let old = GitReader.headSHA(in: dir)!

        TestRepo.write("a.txt", "1", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "add a"], in: dir)
        TestRepo.write("b.txt", "1", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "add b"], in: dir)

        let new = GitReader.headSHA(in: dir)!
        XCTAssertNotEqual(old, new)
        XCTAssertEqual(GitReader.commitCount(from: old, to: new, in: dir), 2)

        let files = GitReader.changedFiles(from: old, to: new, in: dir)
        XCTAssertEqual(Set(files.map(\.path)), Set(["a.txt", "b.txt"]))
        XCTAssertTrue(files.allSatisfy { $0.kind == .new })
    }

    func testHasAnythingToSave() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        XCTAssertFalse(GitReader.hasAnythingToSave(in: dir))

        TestRepo.write("new.txt", "x", in: dir)
        XCTAssertTrue(GitReader.hasAnythingToSave(in: dir))
    }

    // MARK: - Helpers

    /// Two branches editing the same line of the same file, rebased onto each
    /// other so git can't resolve it automatically.
    private func makeConflictedRebase() -> (dir: String, conflictPath: String) {
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
        TestRepo.git(["rebase", "main"], in: dir) // fails with a conflict, left mid-rebase

        return (dir, "shared.txt")
    }
}
