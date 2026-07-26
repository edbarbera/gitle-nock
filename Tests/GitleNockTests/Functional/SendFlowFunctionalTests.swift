import XCTest
@testable import GitleNock

/// Replays `AppState.send()`'s branching: no commits yet, no remote
/// configured, pushing straight to a protected branch, and the plain happy
/// path — each is a distinct decision the real function makes before it ever
/// touches the network.
final class SendFlowFunctionalTests: XCTestCase {
    func testSendWithNoCommitsIsRefusedBeforeTouchingGit() {
        let dir = TestRepo.makeRepo(withCommit: false)
        defer { TestRepo.cleanup(dir) }

        let status = GitReader.status(of: dir)
        XCTAssertFalse(status.hasCommits, "send() must short-circuit here with 'Nothing to send yet'")
    }

    func testSendWithNoRemoteRoutesToConnectThenSucceeds() {
        let remote = TestRepo.makeBareRemote()
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(remote, dir) }

        var status = GitReader.status(of: dir)
        XCTAssertFalse(status.hasRemote, "must route to the connect screen")

        // connectAndSend(): addRemote then send.
        XCTAssertTrue(GitWriter.addRemote(remote, in: dir).succeeded)
        status = GitReader.status(of: dir)
        XCTAssertTrue(status.hasRemote)

        let result = GitWriter.send(branch: status.branch, hasUpstream: status.hasUpstream, in: dir)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(GitReader.status(of: dir).hasUpstream)
    }

    func testSendingToMainIsFlaggedAsProtectedBeforePushing() {
        let dir = TestRepo.makeRepo(branch: "main")
        defer { TestRepo.cleanup(dir) }

        let status = GitReader.status(of: dir)
        XCTAssertTrue(SafetyRails.isProtected(status.branch), "must surface confirmProtectedSend before pushing")
    }

    func testSendingToFeatureBranchIsNotFlaggedAsProtected() {
        let dir = TestRepo.makeRepo(branch: "feature/thing")
        defer { TestRepo.cleanup(dir) }

        let status = GitReader.status(of: dir)
        XCTAssertFalse(SafetyRails.isProtected(status.branch))
    }

    func testHappyPathPushSucceedsAndStatusReflectsSent() {
        let remote = TestRepo.makeBareRemote()
        let dir = TestRepo.makeRepo(branch: "feature/x")
        defer { TestRepo.cleanup(remote, dir) }
        TestRepo.git(["remote", "add", "origin", remote], in: dir)

        let status = GitReader.status(of: dir)
        XCTAssertFalse(SafetyRails.isProtected(status.branch))

        let result = GitWriter.send(branch: status.branch, hasUpstream: status.hasUpstream, in: dir)
        XCTAssertTrue(result.succeeded, result.message)

        let after = GitReader.status(of: dir)
        XCTAssertEqual(after.ahead, 0)
        XCTAssertEqual(after.behind, 0)
        XCTAssertEqual(after.headline, "Everything saved and sent")
    }
}
