import XCTest
@testable import TimCore

/// Streaks, week boundaries and midnight-crossing sessions are the parts most
/// likely to be quietly wrong, so they get the most attention here.
final class TimStatsTests: XCTestCase {

    /// Pinned to UTC so a machine in another time zone doesn't shift day
    /// boundaries under the tests.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_756_000_000) // 2025-08-24 02:26 UTC

    /// A finished session starting `daysAgo` days before `now`, at midday.
    private func session(daysAgo: Int,
                         minutes: Double = 60,
                         emergency: Bool = false) -> TimSession {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let start = day.addingTimeInterval(12 * 3600)
        return TimSession(modeID: UUID(),
                          modeName: "Deep Work",
                          startedAt: start,
                          endedAt: start.addingTimeInterval(minutes * 60),
                          endedByEmergency: emergency)
    }

    private func stats(_ sessions: [TimSession]) -> TimStats {
        TimStats(sessions: sessions, now: now, calendar: calendar)
    }

    // MARK: - Totals

    func testEmptyHistoryIsAllZeroAndDoesNotDivideByZero() {
        let s = stats([])
        XCTAssertEqual(s.sessionCount, 0)
        XCTAssertEqual(s.totalTime, 0)
        XCTAssertEqual(s.currentStreak, 0)
        XCTAssertEqual(s.longestStreak, 0)
        XCTAssertNil(s.cleanFinishRate)
    }

    func testInFlightSessionIsExcludedFromTotals() {
        // No endedAt: the session is still running, so it has no duration to
        // count and must not inflate the totals.
        let running = TimSession(modeID: UUID(), modeName: "Sleep", startedAt: now, endedAt: nil)
        let s = stats([session(daysAgo: 0, minutes: 30), running])
        XCTAssertEqual(s.sessionCount, 1)
        XCTAssertEqual(s.totalTime, 30 * 60)
    }

    func testTotalsAndLongestSession() {
        let s = stats([session(daysAgo: 0, minutes: 30),
                       session(daysAgo: 1, minutes: 90),
                       session(daysAgo: 2, minutes: 15)])
        XCTAssertEqual(s.sessionCount, 3)
        XCTAssertEqual(s.totalTime, (30 + 90 + 15) * 60)
        XCTAssertEqual(s.longestSession, 90 * 60)
    }

    func testCleanFinishesAndBails() {
        let s = stats([session(daysAgo: 0),
                       session(daysAgo: 1, emergency: true),
                       session(daysAgo: 2),
                       session(daysAgo: 3)])
        XCTAssertEqual(s.cleanFinishes, 3)
        XCTAssertEqual(s.emergencyBails, 1)
        XCTAssertEqual(s.cleanFinishRate!, 0.75, accuracy: 0.0001)
    }

    // MARK: - Streaks

    func testStreakCountsBackFromToday() {
        let s = stats([session(daysAgo: 0), session(daysAgo: 1), session(daysAgo: 2)])
        XCTAssertEqual(s.currentStreak, 3)
    }

    func testStreakSurvivesADayThatIsNotOverYet() {
        // Nothing today, but yesterday and the day before. The day isn't
        // finished, so the streak should still be live rather than reset to 0.
        let s = stats([session(daysAgo: 1), session(daysAgo: 2)])
        XCTAssertEqual(s.currentStreak, 2)
    }

    func testStreakBreaksAfterAFullMissedDay() {
        // Last session was two days ago: yesterday was missed entirely.
        let s = stats([session(daysAgo: 2), session(daysAgo: 3)])
        XCTAssertEqual(s.currentStreak, 0)
    }

    func testMultipleSessionsInOneDayCountAsOneDay() {
        let s = stats([session(daysAgo: 0, minutes: 10),
                       session(daysAgo: 0, minutes: 20),
                       session(daysAgo: 1)])
        XCTAssertEqual(s.currentStreak, 2)
    }

    func testLongestStreakIgnoresGapsAndBeatsCurrent() {
        // A 4-day run a fortnight back, and a 1-day run today.
        let old = (10...13).map { session(daysAgo: $0) }
        let s = stats(old + [session(daysAgo: 0)])
        XCTAssertEqual(s.currentStreak, 1)
        XCTAssertEqual(s.longestStreak, 4)
    }

    func testSessionCrossingMidnightCreditsTheDayItStarted() {
        // Started 23:30 yesterday, ended 00:30 today. Counts as yesterday —
        // that's how you'd describe it out loud.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let start = yesterday.addingTimeInterval(23.5 * 3600)
        let overnight = TimSession(modeID: UUID(), modeName: "Sleep",
                                   startedAt: start,
                                   endedAt: start.addingTimeInterval(3600))
        let s = stats([overnight])
        XCTAssertEqual(s.currentStreak, 1, "a streak ending yesterday is still current")
        XCTAssertEqual(s.lastDays(2).first?.total, 3600, "credited to yesterday, not today")
    }

    // MARK: - Chart data

    func testLastDaysIsOldestFirstAndKeepsEmptyDays() {
        let s = stats([session(daysAgo: 0, minutes: 10), session(daysAgo: 3, minutes: 20)])
        let days = s.lastDays(4)

        XCTAssertEqual(days.count, 4)
        XCTAssertTrue(days.map(\.date) == days.map(\.date).sorted(), "oldest first")
        XCTAssertEqual(days[0].total, 20 * 60)  // 3 days ago
        XCTAssertEqual(days[1].total, 0)        // gap preserved
        XCTAssertEqual(days[2].total, 0)
        XCTAssertEqual(days[3].total, 10 * 60)  // today
    }

    func testLastDaysSumsMultipleSessionsInADay()  {
        let s = stats([session(daysAgo: 1, minutes: 15), session(daysAgo: 1, minutes: 45)])
        XCTAssertEqual(s.lastDays(2)[0].total, 60 * 60)
    }
}

final class FormattingTests: XCTestCase {
    func testDurationText() {
        XCTAssertEqual(TimeInterval(45).timDurationText, "45s")
        XCTAssertEqual(TimeInterval(8 * 60).timDurationText, "8m")
        XCTAssertEqual(TimeInterval(3600).timDurationText, "1h 0m")
        XCTAssertEqual(TimeInterval(3600 + 42 * 60).timDurationText, "1h 42m")
    }
}

final class VocabularyTests: XCTestCase {
    /// The verb is the product. If the doubling rule ever regresses to
    /// "Timed"/"Timing" the whole thing reads as a typo.
    func testVerbDoublesTheFinalConsonant() {
        XCTAssertEqual(Vocab.verbPast, "Timmed")
        XCTAssertEqual(Vocab.verbGerund, "Timming")
        XCTAssertEqual(Vocab.unVerb, "Un-Tim")
    }

    func testStatusCopyUsesTheVerbCorrectly() {
        XCTAssertEqual(Vocab.activeTitle, "Your phone is Timmed")
        XCTAssertEqual(Vocab.sessionSummary(duration: "1h 42m"), "You were Timmed for 1h 42m.")
    }
}
