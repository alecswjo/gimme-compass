import XCTest
@testable import Gimme

final class RuleBasedInterpreterTests: XCTestCase {

    private let interpreter = RuleBasedInterpreter()

    func testMapsKnownSlangToCategory() async {
        let result = await interpreter.interpret("Zyns")
        XCTAssertEqual(result.searchText, "convenience store")
        XCTAssertEqual(result.displayLabel, "convenience store")
    }

    func testMappingIsCaseAndWhitespaceInsensitive() async {
        let result = await interpreter.interpret("  GAS  ")
        XCTAssertEqual(result.searchText, "gas station")
    }

    func testCollapsesInternalWhitespaceBeforeLookup() async {
        let result = await interpreter.interpret("ice   cream")
        XCTAssertEqual(result.searchText, "ice cream shop")
    }

    func testUnknownQueryPassesThroughNormalized() async {
        let result = await interpreter.interpret("  Birria Tacos ")
        XCTAssertEqual(result.searchText, "birria tacos")
        XCTAssertEqual(result.displayLabel, "birria tacos")
    }

    func testNormalize() {
        XCTAssertEqual(RuleBasedInterpreter.normalize("  Hello   World  "), "hello world")
        XCTAssertEqual(RuleBasedInterpreter.normalize(""), "")
    }
}

final class RecentQueriesStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: RecentQueriesStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "gimme.tests.recents")!
        defaults.removePersistentDomain(forName: "gimme.tests.recents")
        store = RecentQueriesStore(defaults: defaults)
    }

    func testAddsNewestFirst() {
        store.add("gas")
        store.add("zyns")
        XCTAssertEqual(store.all(), ["zyns", "gas"])
    }

    func testDedupesCaseInsensitivelyKeepingNewest() {
        store.add("Zyns")
        store.add("gas")
        store.add("zyns")
        XCTAssertEqual(store.all(), ["zyns", "gas"])
    }

    func testCapsAtMaxCount() {
        for i in 1...12 {
            store.add("query \(i)")
        }
        XCTAssertEqual(store.all().count, RecentQueriesStore.maxCount)
        XCTAssertEqual(store.all().first, "query 12")
    }

    func testIgnoresBlankQueries() {
        store.add("   ")
        XCTAssertTrue(store.all().isEmpty)
    }
}
