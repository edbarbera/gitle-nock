import XCTest
@testable import GitleNock

final class SafetyRailsTests: XCTestCase {
    // MARK: - Secret detection

    func testLooksLikeSecretMatchesKnownPatterns() {
        for name in [".env", ".env.local", "id_rsa", "id_ed25519", "server.pem",
                     "cert.key", "credentials.json", ".npmrc", "backup.p12"] {
            XCTAssertTrue(SafetyRails.looksLikeSecret(name), "\(name) should be flagged")
        }
    }

    func testLooksLikeSecretIgnoresOrdinaryFiles() {
        for name in ["README.md", "main.swift", "package.json", "notes.txt", "keychain-icon.png"] {
            XCTAssertFalse(SafetyRails.looksLikeSecret(name), "\(name) should not be flagged")
        }
    }

    func testLooksLikeSecretMatchesOnBasenameNotFullPath() {
        XCTAssertTrue(SafetyRails.looksLikeSecret("config/nested/.env"))
    }

    // MARK: - Protected branches

    func testProtectedBranches() {
        XCTAssertTrue(SafetyRails.isProtected("main"))
        XCTAssertTrue(SafetyRails.isProtected("master"))
        XCTAssertFalse(SafetyRails.isProtected("feature/login"))
    }

    // MARK: - review(paths:root:)

    func testReviewFlagsSecretsAndLargeFiles() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }

        TestRepo.write("README.md", "hi", in: dir)
        TestRepo.write(".env", "SECRET=1", in: dir)
        TestRepo.writeSparseFile("video.mp4", sizeBytes: 20 * 1024 * 1024, in: dir)

        let report = SafetyRails.review(paths: ["README.md", ".env", "video.mp4"], root: dir)

        XCTAssertEqual(report.secrets, [".env"])
        XCTAssertEqual(report.large.map(\.path), ["video.mp4"])
        XCTAssertFalse(report.isEmpty)
        XCTAssertEqual(Set(report.allPaths), Set([".env", "video.mp4"]))
    }

    func testReviewIsEmptyWhenNothingSuspicious() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("README.md", "hi", in: dir)

        let report = SafetyRails.review(paths: ["README.md"], root: dir)
        XCTAssertTrue(report.isEmpty)
    }

    func testReviewIgnoresMissingPaths() {
        // A path that was deleted before review runs (e.g. staged deletion)
        // must not crash the size check.
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }

        let report = SafetyRails.review(paths: ["gone.txt"], root: dir)
        XCTAssertTrue(report.isEmpty)
    }

    func testReviewDoesNotFlagDirectoriesAsLargeFiles() throws {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        try FileManager.default.createDirectory(
            atPath: (dir as NSString).appendingPathComponent("sub"),
            withIntermediateDirectories: true
        )

        let report = SafetyRails.review(paths: ["sub"], root: dir)
        XCTAssertTrue(report.large.isEmpty)
    }

    func testReviewBoundaryJustUnderAndOverLargeThreshold() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        TestRepo.writeSparseFile("just-under.bin", sizeBytes: SafetyRails.largeFileBytes, in: dir)
        TestRepo.writeSparseFile("just-over.bin", sizeBytes: SafetyRails.largeFileBytes + 1, in: dir)

        let report = SafetyRails.review(paths: ["just-under.bin", "just-over.bin"], root: dir)
        XCTAssertEqual(report.large.map(\.path), ["just-over.bin"], "exactly-at-threshold files are not 'above' it")
    }

    // MARK: - humanSize

    func testHumanSizeFormatting() {
        XCTAssertEqual(SafetyRails.humanSize(512), "512 B")
        XCTAssertEqual(SafetyRails.humanSize(2 * 1024), "2.0 KB")
        XCTAssertEqual(SafetyRails.humanSize(5 * 1024 * 1024), "5.0 MB")
        XCTAssertEqual(SafetyRails.humanSize(2 * 1024 * 1024 * 1024), "2.0 GB")
    }

    // MARK: - detectProject

    func testDetectProjectRecognisesNode() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("package.json", "{}", in: dir)

        let kind = SafetyRails.detectProject(in: dir)
        XCTAssertEqual(kind.name, "Node.js")
        XCTAssertTrue(kind.matched)
        XCTAssertTrue(kind.gitignore.contains("node_modules/"))
        XCTAssertTrue(kind.gitignore.contains(".env"), "every starter must still exclude secrets")
    }

    func testDetectProjectRecognisesSwiftPackage() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("Package.swift", "// swift-tools-version: 5.9", in: dir)

        XCTAssertEqual(SafetyRails.detectProject(in: dir).name, "Swift")
    }

    func testDetectProjectFallsBackWhenUnrecognised() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }

        let kind = SafetyRails.detectProject(in: dir)
        XCTAssertFalse(kind.matched)
        XCTAssertEqual(kind.name, "this folder")
        // The common block (OS files, logs, secrets) still applies even unmatched.
        XCTAssertTrue(kind.gitignore.contains(".DS_Store"))
    }

    func testDetectProjectPicksFirstMatchWhenMultipleMarkersPresent() {
        let dir = TestRepo.makeTempDir()
        defer { TestRepo.cleanup(dir) }
        TestRepo.write("package.json", "{}", in: dir)
        TestRepo.write("go.mod", "module x", in: dir)

        // Node is checked before Go in `detectProject`; pins the documented order.
        XCTAssertEqual(SafetyRails.detectProject(in: dir).name, "Node.js")
    }
}
