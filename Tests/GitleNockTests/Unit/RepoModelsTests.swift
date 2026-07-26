import XCTest
@testable import GitleNock

final class RepoModelsTests: XCTestCase {
    // MARK: - Repo

    func testRepoNameIsLastPathComponent() {
        let repo = Repo(path: "/Users/ed/Documents/projects/gitle-nock")
        XCTAssertEqual(repo.name, "gitle-nock")
    }

    // MARK: - FileChange

    func testFileChangeFilenameAndSymbols() {
        XCTAssertEqual(FileChange(kind: .new, path: "src/a.swift").filename, "a.swift")
        XCTAssertEqual(FileChange.Kind.new.symbol, "plus.circle.fill")
        XCTAssertEqual(FileChange.Kind.changed.symbol, "pencil.circle.fill")
        XCTAssertEqual(FileChange.Kind.deleted.symbol, "minus.circle.fill")
        XCTAssertEqual(FileChange.Kind.renamed.symbol, "arrow.triangle.turn.up.right.circle.fill")
    }

    func testFileChangeIdentityIsPath() {
        let change = FileChange(kind: .changed, path: "a/b.txt")
        XCTAssertEqual(change.id, "a/b.txt")
    }

    // MARK: - MergeOp

    func testMergeOpSideLabelsFlipForRebase() {
        // In a rebase, HEAD is "what's already there" and the incoming commits
        // being replayed are "your changes" — the opposite of merge/cherry-pick,
        // where HEAD is the user's own work.
        let rebase = MergeOp.rebase.sideLabels
        XCTAssertEqual(rebase.ours, "what's already there")
        XCTAssertEqual(rebase.theirs, "your changes")

        let merge = MergeOp.merge.sideLabels
        XCTAssertEqual(merge.ours, "your version")

        let cherryPick = MergeOp.cherryPick.sideLabels
        XCTAssertEqual(cherryPick.ours, "your version")
        XCTAssertEqual(cherryPick.theirs, "the commit you're bringing in")
    }

    func testMergeOpVerbs() {
        XCTAssertEqual(MergeOp.rebase.verb, "grab")
        XCTAssertEqual(MergeOp.cherryPick.verb, "copy")
        XCTAssertEqual(MergeOp.merge.verb, "merge")
    }

    // MARK: - ConflictFile

    func testConflictFileIsResolved() {
        var file = ConflictFile(path: "a.txt")
        XCTAssertFalse(file.isResolved)
        file.resolution = .keepOurs
        XCTAssertTrue(file.isResolved)
    }

    // MARK: - RiskReport

    func testRiskReportEmptyAndAllPaths() {
        XCTAssertTrue(RiskReport().isEmpty)

        let report = RiskReport(secrets: [".env"], large: [.init(path: "big.bin", size: 100)])
        XCTAssertFalse(report.isEmpty)
        XCTAssertEqual(report.allPaths, [".env", "big.bin"])
    }

    // MARK: - RepoStatus.headline — the single most user-visible piece of logic

    func testHeadlineAccessDeniedOutranksEverything() {
        var status = RepoStatus()
        status.accessDenied = true
        status.isRepo = true
        XCTAssertEqual(status.headline, "Can't open this folder")
    }

    func testHeadlineNotSetUpYet() {
        XCTAssertEqual(RepoStatus.empty.headline, "Not set up yet")
    }

    func testHeadlineConflictsOutrankBehindAndDirty() {
        var status = RepoStatus()
        status.isRepo = true
        status.conflictedFiles = ["a.txt", "b.txt"]
        status.behind = 2
        status.changes = [FileChange(kind: .changed, path: "c.txt")]
        XCTAssertEqual(status.headline, "2 files need your help")
    }

    func testHeadlineSingularConflict() {
        var status = RepoStatus()
        status.isRepo = true
        status.conflictedFiles = ["a.txt"]
        XCTAssertEqual(status.headline, "1 file needs your help")
    }

    func testHeadlineBehindAndDirtyTogether() {
        var status = RepoStatus()
        status.isRepo = true
        status.behind = 3
        status.changes = [FileChange(kind: .new, path: "a"), FileChange(kind: .new, path: "b")]
        XCTAssertEqual(status.headline, "2 unsaved · 3 waiting online")
    }

    func testHeadlineBehindOnly() {
        var status = RepoStatus()
        status.isRepo = true
        status.behind = 1
        XCTAssertEqual(status.headline, "1 update waiting online")

        status.behind = 5
        XCTAssertEqual(status.headline, "5 updates waiting online")
    }

    func testHeadlineDirtyOnly() {
        var status = RepoStatus()
        status.isRepo = true
        status.changes = [FileChange(kind: .new, path: "a")]
        XCTAssertEqual(status.headline, "1 unsaved change")
    }

    func testHeadlineAheadOnly() {
        var status = RepoStatus()
        status.isRepo = true
        status.ahead = 2
        XCTAssertEqual(status.headline, "2 saves not sent yet")

        status.ahead = 1
        XCTAssertEqual(status.headline, "1 save not sent yet")
    }

    func testHeadlineEverythingSavedAndSent() {
        var status = RepoStatus()
        status.isRepo = true
        XCTAssertEqual(status.headline, "Everything saved and sent")
    }

    func testIsCleanAndHasConflicts() {
        var status = RepoStatus()
        XCTAssertTrue(status.isClean)
        status.changes = [FileChange(kind: .new, path: "a")]
        XCTAssertFalse(status.isClean)

        XCTAssertFalse(status.hasConflicts)
        status.conflictedFiles = ["a"]
        XCTAssertTrue(status.hasConflicts)
    }
}
