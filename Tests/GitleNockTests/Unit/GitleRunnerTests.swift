import XCTest
@testable import GitleNock

final class GitleRunnerTests: XCTestCase {
    func testIsInstalledMatchesWhich() {
        XCTAssertEqual(GitleRunner.isInstalled, Shell.which("gitle") != nil)
    }

    func testRunWithoutGitleInstalledReportsFriendlyError() throws {
        try XCTSkipIf(GitleRunner.isInstalled, "this probes the not-installed path specifically")
        let result = GitleRunner.run(.grab, in: NSTemporaryDirectory())
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.stderr.contains("isn't installed"))
    }

    func testFirstMeaningfulLineSkipsPureDecorationLines() {
        // "✓", "→" and bare 2-letter "ok" all trim down to <= 2 chars and are
        // skipped; the first line with real content wins.
        let output = "✓\n→\nok\nreal content here"
        XCTAssertEqual(GitleRunner.firstMeaningfulLine(of: output), "real content here")
    }

    func testFirstMeaningfulLineStripsANSIEscapes() {
        let output = "\u{1B}[32mHello there\u{1B}[0m"
        XCTAssertEqual(GitleRunner.firstMeaningfulLine(of: output), "Hello there")
    }

    func testFirstMeaningfulLineSkipsTooShortLines() {
        let output = "—\nok\nactual message"
        XCTAssertEqual(GitleRunner.firstMeaningfulLine(of: output), "actual message")
    }

    func testFirstMeaningfulLineNilForEmptyOutput() {
        XCTAssertNil(GitleRunner.firstMeaningfulLine(of: ""))
    }

    func testActionArguments() {
        XCTAssertEqual(GitleRunner.Action.grab.arguments, ["grab"])
    }
}
