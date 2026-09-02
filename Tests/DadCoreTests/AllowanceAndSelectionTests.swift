import XCTest
@testable import DadCore

final class EmergencyAllowanceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    func testFullAllowanceWhenUnused() {
        XCTAssertEqual(EmergencyAllowance.remaining(uses: [], now: now),
                       EmergencyAllowance.perWindow)
    }

    func testUsesExactlyOnTheWindowEdgeHaveExpired() {
        // `> cutoff` excludes the boundary, so a use exactly 30 days old is
        // spent and returned. Pinning this stops the edge drifting.
        let edge = now.addingTimeInterval(-EmergencyAllowance.window)
        XCTAssertEqual(EmergencyAllowance.remaining(uses: [edge], now: now),
                       EmergencyAllowance.perWindow)

        let justInside = edge.addingTimeInterval(1)
        XCTAssertEqual(EmergencyAllowance.remaining(uses: [justInside], now: now),
                       EmergencyAllowance.perWindow - 1)
    }

    func testConsumeReturnsNilWhenExhausted() {
        let spent = Array(repeating: now, count: EmergencyAllowance.perWindow)
        XCTAssertNil(EmergencyAllowance.consume(uses: spent, now: now))
    }

    func testConsumePrunesExpiredEntriesSoTheListCannotGrowForever() {
        let ancient = (0..<50).map { now.addingTimeInterval(-EmergencyAllowance.window - Double($0)) }
        let result = EmergencyAllowance.consume(uses: ancient, now: now)
        XCTAssertEqual(result?.count, 1, "expired uses are dropped, not carried")
    }

    func testRemainingNeverGoesNegative() {
        let overSpent = Array(repeating: now, count: EmergencyAllowance.perWindow + 10)
        XCTAssertEqual(EmergencyAllowance.remaining(uses: overSpent, now: now), 0)
    }
}

final class BlockedSelectionTests: XCTestCase {

    func testEmptySelection() {
        let empty = BlockedSelection()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.summary, "Nothing blocked yet")
    }

    func testSingularAndPluralAgree() {
        XCTAssertEqual(BlockedSelection(appCount: 1).summary, "1 app")
        XCTAssertEqual(BlockedSelection(appCount: 3).summary, "3 apps")
        XCTAssertEqual(BlockedSelection(categoryCount: 1).summary, "1 category")
        XCTAssertEqual(BlockedSelection(categoryCount: 2).summary, "2 categories")
        XCTAssertEqual(BlockedSelection(webDomainCount: 1).summary, "1 site")
        XCTAssertEqual(BlockedSelection(webDomainCount: 4).summary, "4 sites")
    }

    func testCombinedSummary() {
        let mixed = BlockedSelection(appCount: 3, categoryCount: 1, webDomainCount: 2)
        XCTAssertEqual(mixed.summary, "3 apps · 1 category · 2 sites")
        XCTAssertEqual(mixed.totalCount, 6)
    }

    /// The payload is opaque to Core but must survive a persistence round trip
    /// untouched — it's the only thing that can rebuild the real token set.
    func testPayloadSurvivesCoding() throws {
        let original = BlockedSelection(payload: Data([0xDE, 0xAD]), appCount: 2)
        let restored = try JSONDecoder().decode(
            BlockedSelection.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }
}

final class DadModeTests: XCTestCase {

    func testBlocksAnythingFollowsTheCounts() {
        XCTAssertFalse(DadMode(name: "x", symbol: "c").blocksAnything)
        XCTAssertTrue(DadMode(name: "x", symbol: "c",
                              blocked: BlockedSelection(appCount: 1)).blocksAnything)
    }

    func testStrictIsCalledOutInTheSummary() {
        let mode = DadMode(name: "Sleep", symbol: "moon",
                           blocked: BlockedSelection(appCount: 2), isStrict: true)
        XCTAssertEqual(mode.summary, "2 apps · strict")
    }

    func testModeSurvivesCoding() throws {
        let original = DadMode(name: "Deep Work", symbol: "brain",
                               blocked: BlockedSelection(payload: Data([1]), appCount: 4),
                               isStrict: true, autoUnDadAfter: 3600)
        let restored = try JSONDecoder().decode(DadMode.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }
}
