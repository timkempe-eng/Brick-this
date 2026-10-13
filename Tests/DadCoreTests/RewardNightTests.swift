import XCTest
@testable import DadCore

/// 23:00 to 06:00 earns no reward hours.
///
/// Local wall-clock time, so one test runs across the night the UK's clocks go
/// forward: a rule written as "seven hours after 23:00" would pay an hour of
/// that night, and this is the case that tells the two apart.
final class RewardNightTests: XCTestCase {

    private let calendar: Calendar = .utc
    private let hour: TimeInterval = 3600

    /// 2025-08-24 at `h` o'clock UTC.
    private func at(_ h: Double, dayOffset: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1_755_993_600)   // 2025-08-24 00:00 UTC
            .addingTimeInterval(Double(dayOffset) * 86_400 + h * hour)
    }

    private func counted(_ from: Date, _ to: Date) -> TimeInterval {
        RewardNight.countedSeconds(from: from, to: to, calendar: calendar)
    }

    func testAnEveningIntoTheMorningCountsOnlyItsDaylight() {
        // 22:00–23:00 and 06:00–07:00.
        XCTAssertEqual(counted(at(22), at(7, dayOffset: 1)), 2 * hour)
    }

    func testTheNightItselfCountsNothing() {
        XCTAssertEqual(counted(at(23), at(6, dayOffset: 1)), 0)
        XCTAssertEqual(counted(at(1), at(5)), 0, "the small hours of the same night")
    }

    func testTheEdgesBelongToTheDay() {
        XCTAssertEqual(counted(at(5), at(8)), 2 * hour, "06:00 onwards counts")
        XCTAssertEqual(counted(at(21), at(23)), 2 * hour, "up to 23:00 counts")
        XCTAssertFalse(RewardNight.isNight(at(6), calendar: calendar))
        XCTAssertTrue(RewardNight.isNight(at(23), calendar: calendar))
        XCTAssertTrue(RewardNight.isNight(at(5.99), calendar: calendar))
        XCTAssertFalse(RewardNight.isNight(at(22.99), calendar: calendar))
    }

    func testSeveralDaysLoseEveryNight() {
        // Two whole days are forty-eight hours, fourteen of them night.
        XCTAssertEqual(counted(at(12), at(12, dayOffset: 2)), 34 * hour)
    }

    func testAnEndBeforeTheStartCountsNothing() {
        XCTAssertEqual(counted(at(14), at(12)), 0)
    }

    func testTheNightIsWallClockTimeOnTheNightTheClocksChange() throws {
        // Europe/London, 2025-03-30: 01:00 becomes 02:00, so that night is six
        // real hours long rather than seven. 22:00 to 07:00 is eight real
        // hours and still counts exactly 22–23 and 06–07.
        var london = Calendar(identifier: .gregorian)
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let start = try XCTUnwrap(london.date(from: DateComponents(year: 2025, month: 3, day: 29,
                                                                   hour: 22)))
        let end = try XCTUnwrap(london.date(from: DateComponents(year: 2025, month: 3, day: 30,
                                                                 hour: 7)))
        XCTAssertEqual(end.timeIntervalSince(start), 8 * hour)
        XCTAssertEqual(RewardNight.countedSeconds(from: start, to: end, calendar: london), 2 * hour)
    }

    // MARK: - When the next hour lands

    private func reaching(_ hours: Double, from start: Date) -> Date {
        RewardNight.instant(reaching: hours * hour, from: start, calendar: calendar)
    }

    func testTheNextHourSkipsTheNight() {
        XCTAssertEqual(reaching(1, from: at(22.5)), at(6.5, dayOffset: 1),
                       "half an hour before the night, half an hour after it")
        XCTAssertEqual(reaching(1, from: at(22)), at(23), "exactly at the edge")
        XCTAssertEqual(reaching(1, from: at(3)), at(7), "started during the night")
        XCTAssertEqual(reaching(3, from: at(12)), at(15), "a plain afternoon")
        XCTAssertEqual(reaching(20, from: at(12)), at(15, dayOffset: 1),
                       "eleven hours to 23:00, then nine more from 06:00")
    }

    func testTheInstantAndTheCountAgree() {
        // The countdown and the ledger use different functions. Walk a day's
        // worth of starts and check each lands where the other says it should.
        for quarter in 0..<96 {
            let start = at(Double(quarter) / 4)
            for target in [1.0, 2, 5, 17] {
                let landing = reaching(target, from: start)
                XCTAssertEqual(counted(start, landing), target * hour, accuracy: 0.001,
                               "from \(Double(quarter) / 4)h, \(target) hours")
            }
        }
    }

    // MARK: - The countdown at night

    func testTheCountdownSaysWhenItIsPausedForTheNight() throws {
        let session = DadSession(modeID: UUID(), modeName: "Evening",
                                 startedAt: at(20), endedAt: nil)
        let night = try XCTUnwrap(HourProgress(session: session, earnedThatDay: .zero,
                                               now: at(1, dayOffset: 1), calendar: calendar))
        XCTAssertEqual(night.hoursSoFar, RewardLedger.Hours(3))
        XCTAssertEqual(night.nextHourAt, at(7, dayOffset: 1))
        XCTAssertEqual(night.text(at: at(1, dayOffset: 1)),
                       "3 hours so far · Night hours don't count · back at 6:00")

        let early = try XCTUnwrap(HourProgress(session: DadSession(modeID: UUID(), modeName: "Sleep",
                                                                   startedAt: at(23.5), endedAt: nil),
                                               earnedThatDay: .zero,
                                               now: at(2, dayOffset: 1), calendar: calendar))
        XCTAssertEqual(early.text(at: at(2, dayOffset: 1)), "Night hours don't count · back at 6:00")
    }
}
