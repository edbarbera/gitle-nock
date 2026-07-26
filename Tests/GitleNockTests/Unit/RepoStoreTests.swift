import XCTest
@testable import GitleNock

/// Uses a throwaway `UserDefaults` suite per test — never `.standard` — so
/// running the suite can't clobber the real app's saved repo list on this
/// machine.
final class RepoStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: RepoStore!

    override func setUp() {
        super.setUp()
        suiteName = "com.gitlenock.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = RepoStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadWithNothingSavedReturnsEmpty() {
        XCTAssertEqual(store.load(), [])
    }

    func testSaveThenLoadRoundTrips() {
        let repos = [Repo(path: "/a"), Repo(path: "/b")]
        store.save(repos)
        XCTAssertEqual(store.load(), repos)
    }

    func testLoadWithCorruptDataReturnsEmptyRatherThanCrashing() {
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "gitlenock.repos")
        XCTAssertEqual(store.load(), [])
    }

    func testActiveIDRoundTrips() {
        XCTAssertNil(store.loadActiveID())
        let id = UUID()
        store.saveActiveID(id)
        XCTAssertEqual(store.loadActiveID(), id)
    }

    func testActiveIDClearsWhenSetToNil() {
        store.saveActiveID(UUID())
        store.saveActiveID(nil)
        XCTAssertNil(store.loadActiveID())
    }

    func testLoadDoesNotFilterUnreachableRepos() {
        // A repo path can be temporarily unreachable (unmounted drive, TCC
        // gate) — the store must return it unfiltered rather than silently
        // dropping it from the user's list.
        let repos = [Repo(path: "/definitely/does/not/exist/anywhere")]
        store.save(repos)
        XCTAssertEqual(store.load(), repos)
    }
}
