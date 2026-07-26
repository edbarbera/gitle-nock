import XCTest
@testable import GitleNock

final class ShellTests: XCTestCase {
    func testWhichFindsGit() {
        XCTAssertNotNil(Shell.which("git"), "git must be discoverable for the whole app to function")
    }

    func testWhichReturnsNilForUnknownTool() {
        XCTAssertNil(Shell.which("definitely-not-a-real-tool-xyz"))
    }

    func testRunCapturesStdout() {
        let result = Shell.run("/bin/echo", ["hello"])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testRunCapturesFailureStatusAndStderr() {
        let result = Shell.run("/bin/sh", ["-c", "echo oops 1>&2; exit 7"])
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.message, "oops")
    }

    func testMessagePrefersStderrOverStdout() {
        let result = ShellResult(status: 1, stdout: "out", stderr: "err")
        XCTAssertEqual(result.message, "err")
    }

    func testMessageFallsBackToStdoutWhenStderrEmpty() {
        let result = ShellResult(status: 1, stdout: "out", stderr: "  \n")
        XCTAssertEqual(result.message, "out")
    }

    func testRunHonoursWorkingDirectory() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("marker.txt", "x", in: dir)

        let result = Shell.run("/bin/ls", [], in: dir)
        XCTAssertTrue(result.stdout.contains("marker.txt"))
    }

    /// A wedged subprocess (git waiting on a credential prompt, a lock file)
    /// must be killed, not left to hang the app. This is the exact case the
    /// timeout branch in `Shell.run` exists for.
    func testRunTimesOutAndKillsWedgedProcess() {
        let start = Date()
        let result = Shell.run("/bin/sleep", ["10"], timeout: 0.3)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.stderr.contains("Timed out"), "got: \(result.stderr)")
        XCTAssertLessThan(elapsed, 3, "timeout handling itself must not add multi-second latency")
    }

    /// Writing >64KB (a pipe's kernel buffer) to stdout and stderr at the same
    /// time deadlocks any reader that drains one pipe to EOF before touching
    /// the other. This is why `Shell.run` reads both concurrently.
    func testRunDoesNotDeadlockOnLargeDualStreamOutput() {
        let script = """
        for i in $(seq 1 4000); do
            echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            echo "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" 1>&2
        done
        """
        let expectation = XCTestExpectation(description: "shell call returns")
        var result: ShellResult?
        DispatchQueue.global().async {
            result = Shell.run("/bin/sh", ["-c", script], timeout: 15)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)

        guard let result else { return XCTFail("Shell.run never returned — likely deadlocked") }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.split(separator: "\n").count, 4000)
        XCTAssertEqual(result.stderr.split(separator: "\n").count, 4000)
    }

    func testRunReportsLaunchFailureRatherThanCrashing() {
        let result = Shell.run("/path/does/not/exist/binary", ["--flag"])
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.status, -1)
    }
}
