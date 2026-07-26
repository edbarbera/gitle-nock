import XCTest
@testable import GitleNock

/// The app polls every repo it knows about on a timer (default every few
/// seconds — see `AppState.startRefreshTimer`) plus on every hover and every
/// action. That refresh is six-plus subprocess launches per repo per tick, so
/// its cost is the actual "resource utilisation while using the app" concern:
/// CPU spent forking git, and — the specific failure mode `Shell.run`'s
/// timeout branch exists for — subprocesses piling up if one wedges.
final class PerformanceTests: XCTestCase {
    // MARK: - Cost of a single refresh

    /// One `GitReader.status(of:)` call on an ordinary repo — this is what
    /// runs on every hover. Regression guard: if this creeps up, every hover
    /// and every timer tick gets slower for every repo the user has added.
    func testSingleStatusRefreshCost() {
        let dir = TestRepo.makeRepoWithFiles(tracked: 20, untracked: 5)
        defer { TestRepo.cleanup(dir) }

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            _ = GitReader.status(of: dir)
        }
    }

    /// Status parsing cost shouldn't blow up on a repo with hundreds of
    /// changed files (a big vendored drop, a large untracked build folder
    /// before .gitignore catches it) — a real scenario, not a stress-test
    /// contrivance, and the one place `parsePorcelain` does real work.
    func testStatusRefreshCostScalesReasonablyWithManyChangedFiles() {
        let dir = TestRepo.makeRepoWithFiles(tracked: 5, untracked: 500)
        defer { TestRepo.cleanup(dir) }

        let start = Date()
        let status = GitReader.status(of: dir)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(
            status.changes.count, 505,
            "500 new untracked files plus the 5 tracked files re-modified after commit"
        )
        XCTAssertLessThan(elapsed, 5, "a single refresh on a busy repo must stay well under a user-noticeable delay")
    }

    // MARK: - Repeated polling (simulates the refresh timer over time)

    /// Simulates roughly what a few minutes of the default 6s refresh timer
    /// does across the repos list. This is a regression guard against
    /// something turning the concurrent reads in `GitReader.status` back into
    /// a serial chain — that's the change that made "every hover, every repo
    /// switch, every action" noticeably slow before (see the comment in
    /// `GitReader.status`).
    func testRepeatedPollingStaysCheap() {
        let dir = TestRepo.makeRepo()
        defer { TestRepo.cleanup(dir) }

        let iterations = 30
        let start = Date()
        for _ in 0..<iterations {
            _ = GitReader.status(of: dir)
        }
        let elapsed = Date().timeIntervalSince(start)
        let perCall = elapsed / Double(iterations)

        XCTAssertLessThan(
            perCall, 0.5,
            "average refresh cost crept up — check the concurrent reads in GitReader.status"
        )
    }

    // MARK: - Subprocess hygiene under load

    /// The realistic failure this guards: git waiting on a credential prompt
    /// or a lock file, repeated across many refreshes. Each one must be
    /// killed on timeout and leave nothing behind — if `Shell.run`'s timeout
    /// path ever regressed to not terminating the process, this is what
    /// would quietly accumulate zombie/orphaned `sleep` processes under
    /// ordinary, sustained use of the app.
    func testWedgedProcessesAreKilledAndDoNotAccumulate() throws {
        // A uniquely-named script file, launched directly (not via `sh -c`),
        // so its path is guaranteed to show up verbatim in `ps` — a shell
        // may otherwise exec-replace a trailing "sleep 10" and lose any
        // marker text passed as part of a `-c` string.
        let scriptDir = TestRepo.makeTempDir("perf-script")
        defer { TestRepo.cleanup(scriptDir) }
        let scriptPath = (scriptDir as NSString).appendingPathComponent("wedged-\(UUID().uuidString).sh")
        try "#!/bin/sh\nsleep 10\n".write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let rounds = 10
        for _ in 0..<rounds {
            let result = Shell.run(scriptPath, [], timeout: 0.2)
            XCTAssertFalse(result.succeeded)
        }

        // Give the kernel a moment to reap, then confirm nothing survived.
        Thread.sleep(forTimeInterval: 0.5)
        let leftover = Shell.run("/bin/sh", ["-c", "pgrep -f '\(scriptPath)' | wc -l"])
        let count = Int(leftover.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        XCTAssertEqual(count, 0, "\(rounds) timed-out subprocesses must not leave any survivors")
    }

    /// Sustained concurrent reads (several repos refreshing at once, e.g. two
    /// screens or a fast succession of hovers) must not degrade badly versus
    /// doing them one at a time — regression guard on `runConcurrently`.
    func testConcurrentStatusReadsAcrossMultipleRepos() {
        let dirs = (0..<5).map { _ in TestRepo.makeRepo() }
        defer { TestRepo.cleanup(dirs[0], dirs[1], dirs[2], dirs[3], dirs[4]) }

        let start = Date()
        let group = DispatchGroup()
        for dir in dirs {
            group.enter()
            DispatchQueue.global().async {
                _ = GitReader.status(of: dir)
                group.leave()
            }
        }
        group.wait()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 5, "refreshing 5 repos in parallel should not be much slower than refreshing one")
    }
}

private extension TestRepo {
    static func makeRepoWithFiles(tracked: Int, untracked: Int) -> String {
        let dir = makeRepo()
        for index in 0..<tracked {
            write("tracked-\(index).txt", "content \(index)", in: dir)
        }
        if tracked > 0 {
            git(["add", "-A"], in: dir)
            git(["commit", "-m", "add tracked files"], in: dir)
            for index in 0..<tracked {
                write("tracked-\(index).txt", "changed \(index)", in: dir)
            }
        }
        for index in 0..<untracked {
            write("untracked-\(index).txt", "new \(index)", in: dir)
        }
        return dir
    }
}
