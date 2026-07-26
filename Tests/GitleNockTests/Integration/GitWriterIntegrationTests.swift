import XCTest
@testable import GitleNock

final class GitWriterIntegrationTests: XCTestCase {
    // MARK: - save

    func testSaveStagesAndCommitsOnlyPickedPaths() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        TestRepo.write("picked.txt", "a", in: dir)
        TestRepo.write("unpicked.txt", "b", in: dir)

        let result = GitWriter.save(paths: ["picked.txt"], message: "save one", in: dir)
        XCTAssertTrue(result.succeeded, result.message)

        let status = GitReader.status(of: dir)
        XCTAssertEqual(status.changes.map(\.path), ["unpicked.txt"], "unpicked file must remain uncommitted")
        XCTAssertEqual(GitReader.lastSaveMessage(in: dir), "save one")
    }

    func testSaveWithEmptyPathsFailsWithoutTouchingGit() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        let result = GitWriter.save(paths: [], message: "nope", in: dir)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.stderr, "No files were picked, so nothing was saved.")
        XCTAssertEqual(GitReader.lastSaveMessage(in: dir), "initial", "must not have created a commit")
    }

    func testSavePicksUpDeletedFiles() throws {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        try FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent("hello.txt"))

        let result = GitWriter.save(paths: ["hello.txt"], message: "remove hello", in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(GitReader.status(of: dir).isClean)
    }

    // MARK: - send / explainPushFailure

    func testSendFirstPushSetsUpstream() {
        let remote = TestRepo.makeBareRemote()
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(remote, dir) }
        TestRepo.git(["remote", "add", "origin", remote], in: dir)

        let result = GitWriter.send(branch: "main", hasUpstream: false, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(GitReader.status(of: dir).hasUpstream)
    }

    func testSendWithExistingUpstream() {
        let remote = TestRepo.makeBareRemote()
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(remote, dir) }
        TestRepo.git(["remote", "add", "origin", remote], in: dir)
        XCTAssertTrue(GitWriter.send(branch: "main", hasUpstream: false, in: dir).succeeded)

        TestRepo.write("more.txt", "x", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "more"], in: dir)

        let result = GitWriter.send(branch: "main", hasUpstream: true, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
    }

    func testExplainPushFailureWording() {
        XCTAssertTrue(GitWriter.explainPushFailure("! [rejected] main -> main (fetch first)")
            .contains("Grab the latest"))
        XCTAssertTrue(GitWriter.explainPushFailure("remote: Permission denied")
            .contains("sign in"))
        XCTAssertTrue(GitWriter.explainPushFailure("fatal: repository not found")
            .contains("Couldn't reach"))
    }

    // MARK: - undoLastSave

    func testUndoLastSaveWithParentKeepsFileChanges() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("second.txt", "x", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.git(["commit", "-m", "second"], in: dir)

        let result = GitWriter.undoLastSave(in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertEqual(GitReader.lastSaveMessage(in: dir), "initial")
        // Soft reset: the file from the undone commit is still on disk, now unstaged/staged.
        XCTAssertTrue(FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("second.txt")))
    }

    func testUndoLastSaveOnFirstCommitClearsHistoryButKeepsFiles() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        let result = GitWriter.undoLastSave(in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertFalse(GitReader.status(of: dir).hasCommits)
        XCTAssertTrue(FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("hello.txt")))
    }

    // MARK: - discardAllChanges

    func testDiscardAllChangesWithCommitsResetsAndCleans() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("hello.txt", "modified\n", in: dir)
        TestRepo.write("untracked-new.txt", "new", in: dir)

        let result = GitWriter.discardAllChanges(hasCommits: true, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(GitReader.status(of: dir).isClean)
        XCTAssertEqual(TestRepo.contents("hello.txt", in: dir), "hello\n")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("untracked-new.txt"))
        )
    }

    func testDiscardAllChangesWithoutCommitsClearsIndexAndWorkingTree() {
        let dir = TestRepo.makeRepo(withCommit: false)
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("staged.txt", "x", in: dir)
        TestRepo.git(["add", "-A"], in: dir)
        TestRepo.write("untracked.txt", "x", in: dir)

        let result = GitWriter.discardAllChanges(hasCommits: false, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertFalse(GitReader.hasAnythingToSave(in: dir))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("untracked.txt"))
        )
    }

    // MARK: - initRepo / writeGitignore / addRemote

    func testInitRepoCreatesMainBranch() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }

        let result = GitWriter.initRepo(in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(GitReader.isRepo(dir))
        XCTAssertEqual(GitReader.status(of: dir).branch, "main")
    }

    func testWriteGitignoreCreatesDetectedStarter() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("package.json", "{}", in: dir)

        let result = GitWriter.writeGitignore(in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        let contents = TestRepo.contents(".gitignore", in: dir)
        XCTAssertTrue(contents?.contains("node_modules/") ?? false)
    }

    func testWriteGitignoreDoesNotOverwriteExisting() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write(".gitignore", "# mine\n", in: dir)

        let result = GitWriter.writeGitignore(in: dir)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(TestRepo.contents(".gitignore", in: dir), "# mine\n")
    }

    func testAddRemote() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        let result = GitWriter.addRemote("https://example.com/repo.git", in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(GitReader.status(of: dir).hasRemote)
    }

    // MARK: - setIdentity (must never touch the real global git config)

    func testSetIdentityWritesToIsolatedGlobalConfig() {
        let isolation = IsolatedGlobalGitConfig()
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        let result = GitWriter.setIdentity(name: "Isolated Tester", email: "isolated@example.com", in: dir)
        XCTAssertTrue(result.succeeded, result.message)

        let written = try? String(contentsOfFile: isolation.path, encoding: .utf8)
        XCTAssertTrue(written?.contains("Isolated Tester") ?? false)
        XCTAssertTrue(written?.contains("isolated@example.com") ?? false)
    }

    // MARK: - stillConflicted

    func testStillConflictedDetectsMarkerLines() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("conflicted.txt", "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n", in: dir)

        XCTAssertTrue(GitWriter.stillConflicted("conflicted.txt", in: dir))

        TestRepo.write("conflicted.txt", "resolved\n", in: dir)
        XCTAssertFalse(GitWriter.stillConflicted("conflicted.txt", in: dir))
    }
}
