import XCTest
@testable import GitleNock

/// Scratch git repos for tests that need real git state instead of mocks —
/// this app is a thin wrapper over git/gitle, so the wrapper's own logic is
/// only proven correct by running the real binaries against real repos.
enum TestRepo {
    @discardableResult
    static func git(_ args: [String], in dir: String) -> ShellResult {
        Shell.run(GitReader.gitPath, ["-C", dir] + args)
    }

    static func makeTempDir(_ label: String = "") -> String {
        let dir = NSTemporaryDirectory()
            .appending("gitlenock-tests-\(label.isEmpty ? "" : "\(label)-")\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// An initialised repo with local (not global) identity set, so commits
    /// succeed without touching the developer's real git config.
    @discardableResult
    static func makeRepo(withCommit: Bool = true, branch: String = "main") -> String {
        let dir = makeTempDir("repo")
        git(["init", "-b", branch], in: dir)
        git(["config", "user.name", "Test User"], in: dir)
        git(["config", "user.email", "test@example.com"], in: dir)
        // Local identity above is enough for commits, but a bare env with no
        // global config at all still fails some git plumbing that shells out
        // to `git var GIT_COMMITTER_IDENT`; keep it consistent everywhere.
        if withCommit {
            write("hello.txt", "hello\n", in: dir)
            git(["add", "-A"], in: dir)
            git(["commit", "-m", "initial"], in: dir)
        }
        return dir
    }

    /// A bare repo to stand in for "origin" — real push/pull, no network.
    static func makeBareRemote() -> String {
        let dir = makeTempDir("remote")
        git(["init", "--bare", "-b", "main"], in: dir)
        return dir
    }

    static func write(_ name: String, _ contents: String, in dir: String) {
        let path = (dir as NSString).appendingPathComponent(name)
        let parent = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try! contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func contents(_ name: String, in dir: String) -> String? {
        try? String(contentsOfFile: (dir as NSString).appendingPathComponent(name), encoding: .utf8)
    }

    /// A sparse file that reports as large without actually writing megabytes
    /// of real data to disk.
    static func writeSparseFile(_ name: String, sizeBytes: Int64, in dir: String) {
        let path = (dir as NSString).appendingPathComponent(name)
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            XCTFail("could not open \(path) for writing")
            return
        }
        defer { try? handle.close() }
        try? handle.truncate(atOffset: UInt64(sizeBytes))
    }

    static func cleanup(_ dirs: String...) {
        for dir in dirs { try? FileManager.default.removeItem(atPath: dir) }
    }

    static func headSHA(in dir: String) -> String {
        git(["rev-parse", "HEAD"], in: dir).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Points `git`'s global config at a throwaway file for the lifetime of the
/// test, so `GitWriter.setIdentity` (which writes `--global`) never touches
/// the real developer's `~/.gitconfig`. `GIT_CONFIG_GLOBAL` is read by every
/// child `git` process `Shell.run` spawns, since it inherits the current
/// environment.
final class IsolatedGlobalGitConfig {
    let path: String

    init() {
        path = TestRepo.makeTempDir("global-gitconfig") + "/.gitconfig"
        setenv("GIT_CONFIG_GLOBAL", path, 1)
    }

    deinit {
        unsetenv("GIT_CONFIG_GLOBAL")
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }
}
