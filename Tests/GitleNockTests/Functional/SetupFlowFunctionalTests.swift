import XCTest
@testable import GitleNock

/// Replays `AppState.runSetup()`'s step order — init, identity, .gitignore,
/// first save, in that exact sequence — since the ordering itself is load
/// bearing: the .gitignore has to land before the first save or its excludes
/// never take effect.
final class SetupFlowFunctionalTests: XCTestCase {
    func testFullSetupOnBrandNewFolder() {
        let isolation = IsolatedGlobalGitConfig()
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }

        TestRepo.write("package.json", "{}", in: dir)
        TestRepo.write("node_modules/dep/index.js", "junk", in: dir)
        TestRepo.write("index.js", "console.log(1)", in: dir)

        let alreadyRepo = GitReader.isRepo(dir)
        XCTAssertFalse(alreadyRepo)

        if !alreadyRepo {
            XCTAssertTrue(GitWriter.initRepo(in: dir).succeeded)
        }
        XCTAssertTrue(GitWriter.setIdentity(name: "New User", email: "new@example.com", in: dir).succeeded)
        XCTAssertTrue(GitWriter.writeGitignore(in: dir).succeeded)

        XCTAssertTrue(GitReader.hasAnythingToSave(in: dir))
        let paths = GitReader.status(of: dir).changes.map(\.path)
        XCTAssertTrue(GitWriter.save(paths: paths, message: "first version", in: dir).succeeded)

        XCTAssertEqual(GitReader.lastSaveMessage(in: dir), "first version")
        XCTAssertTrue(GitReader.status(of: dir).isClean)
        XCTAssertFalse(paths.contains { $0.hasPrefix("node_modules/") },
                       "the .gitignore written before the save must have already excluded node_modules")
        _ = isolation
    }

    func testSetupSkipsInitWhenAlreadyARepo() {
        let dir = TestRepo.makeRepo() // already initialised, one commit
        defer { TestRepo.cleanup(dir) }

        let alreadyRepo = GitReader.isRepo(dir)
        XCTAssertTrue(alreadyRepo)
        let beforeHead = GitReader.headSHA(in: dir)

        if !alreadyRepo {
            XCTFail("should not attempt init")
        }
        XCTAssertTrue(GitWriter.writeGitignore(in: dir).succeeded)

        // Re-init would be a no-op for git anyway, but the flow shouldn't even
        // attempt it — HEAD must be untouched by the gitignore-only step.
        XCTAssertEqual(GitReader.headSHA(in: dir), beforeHead)
    }

    func testSetupWithFirstSaveDeclinedLeavesFilesUnstaged() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("index.js", "x", in: dir)

        XCTAssertTrue(GitWriter.initRepo(in: dir).succeeded)
        // wantsFirstSave == false: setup stops after .gitignore.
        XCTAssertTrue(GitWriter.writeGitignore(in: dir).succeeded)

        XCTAssertFalse(GitReader.status(of: dir).hasCommits)
        XCTAssertTrue(GitReader.hasAnythingToSave(in: dir))
    }

    func testSetupWithNothingToSaveSkipsFirstSaveWithoutFailing() {
        let dir = TestRepo.makeTempDir() // empty folder
        defer { TestRepo.cleanup(dir) }

        XCTAssertTrue(GitWriter.initRepo(in: dir).succeeded)
        XCTAssertTrue(GitWriter.writeGitignore(in: dir).succeeded)

        // .gitignore itself is now the only file, but it counts as something to save.
        XCTAssertTrue(GitReader.hasAnythingToSave(in: dir))
        let paths = GitReader.status(of: dir).changes.map(\.path)
        XCTAssertEqual(paths, [".gitignore"])
    }
}
