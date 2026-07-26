import XCTest
@testable import GitleNock

/// Fast, minimal sanity checks — "is the ground the app stands on there at
/// all". Meant to run first and fail loud before the slower suites bother.
/// No repo-with-hundreds-of-files, no multi-clone journeys: just the handful
/// of things that, if broken, make every other test's failure meaningless.
final class SmokeTests: XCTestCase {
    func testGitIsReachable() {
        XCTAssertNotNil(Shell.which("git"), "without git, nothing else in this app can work")
    }

    func testShellCanRunAProcessAndGetOutputBack() {
        XCTAssertEqual(Shell.run("/bin/echo", ["ok"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
    }

    func testFreshFolderIsNotARepo() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        XCTAssertFalse(GitReader.isRepo(dir))
    }

    func testInitTurnsAFolderIntoARepo() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        XCTAssertTrue(GitWriter.initRepo(in: dir).succeeded)
        XCTAssertTrue(GitReader.isRepo(dir))
    }

    func testEmptyStatusHeadlineIsNotSetUpYet() {
        XCTAssertEqual(RepoStatus.empty.headline, "Not set up yet")
    }

    func testSecretDetectionBasicCase() {
        XCTAssertTrue(SafetyRails.looksLikeSecret(".env"))
        XCTAssertFalse(SafetyRails.looksLikeSecret("README.md"))
    }

    func testSaveThenStatusRoundTrip() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("x.txt", "x", in: dir)
        XCTAssertTrue(GitWriter.save(paths: ["x.txt"], message: "smoke", in: dir).succeeded)
        XCTAssertTrue(GitReader.status(of: dir).isClean)
    }

    /// gitle is an optional companion tool — the app must degrade gracefully
    /// without it, not crash looking for it.
    func testGitleAbsenceIsHandledGracefully() {
        XCTAssertNoThrow(GitleRunner.isInstalled)
    }
}
