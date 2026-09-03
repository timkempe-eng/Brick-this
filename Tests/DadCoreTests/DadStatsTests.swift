import XCTest
@testable import DadCore

/// Streaks, week boundaries and midnight-crossing sessions are the parts most
/// likely to be quietly wrong, so they get the most attention here.
final class DadStatsTests: XCTestCase {

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
                         emergency: Bool = false) -> DadSession {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let start = day.addingTimeInterval(12 * 3600)
        return DadSession(modeID: UUID(),
                          modeName: "Deep Work",
                          startedAt: start,
                          endedAt: start.addingTimeInterval(minutes * 60),
                          endedByEmergency: emergency)
    }

    private func stats(_ sessions: [DadSession]) -> DadStats {
        DadStats(sessions: sessions, now: now, calendar: calendar)
    }

    // MARK: - What keeps a streak

    func testABailedDayStillKeepsTheStreak() {
        // The decision, and the same one `AutonomyLadder` makes about lapses:
        // a day you Dadded and then spent an override on is a day you Dadded.
        // Bailing out is still engagement, and a streak that punished it would
        // teach somebody to leave the phone blocked rather than admit they
        // needed it — which is the behaviour this product least wants.
        //
        // Spelled out rather than implied by the other tests, because every
        // one of them builds sessions that ended cleanly. A mutation swapping
        // this for the ladder's *clean*-day rule survived the whole suite, and
        // the home screen, the widget and the household streak all read it.
        let bailedEveryDay = (0..<4).map { session(daysAgo: $0, emergency: true) }

        XCTAssertEqual(stats(bailedEveryDay).currentStreak, 4)
        XCTAssertEqual(stats(bailedEveryDay).longestStreak, 4)
        XCTAssertEqual(stats(bailedEveryDay).cleanFinishes, 0,
                       "and the honest number about *how* they ended is reported separately")
    }

    func testASessionStillRunningPutsTodayInTheStreak() {
        // Somebody who Dadded an hour ago has Dadded today, and the streak
        // counts days somebody Dadded. It used to wait for them to tap out —
        // an accident of the filter that keeps unfinished sessions out of the
        // *totals*, where they belong out, because a session with no end has
        // no duration and would make every total drift upward as you watch.
        //
        // Two different questions, two different filters.
        let yesterday = session(daysAgo: 1)
        let running = DadSession(modeID: UUID(), modeName: "Deep Work",
                                 startedAt: now.addingTimeInterval(-3600),
                                 endedAt: nil)

        let withoutIt = DadStats(sessions: [yesterday], now: now, calendar: calendar)
        let withIt = DadStats(sessions: [yesterday], activeSession: running,
                              now: now, calendar: calendar)

        XCTAssertEqual(withoutIt.currentStreak, 1, "yesterday alone is still a current streak")
        XCTAssertEqual(withIt.currentStreak, 2, "and today counts the moment you Dad")

        XCTAssertEqual(withIt.sessionCount, 1, "but the totals still only count finished sessions")
        XCTAssertEqual(withIt.totalTime, withoutIt.totalTime,
                       "a session with no end has no duration to add")
    }

    func testARunningSessionEarnsNoRungOnItsOwn() {
        // The line between the two numbers. A streak is engagement and counts
        // it immediately; a rung is evidence somebody finished, and an
        // unfinished session is not that. The ladder reads
        // `daysEndedByAPerson`, which this does not touch.
        let running = DadSession(modeID: UUID(), modeName: "Deep Work",
                                 startedAt: now.addingTimeInterval(-3600),
                                 endedAt: nil)
        let ladder = AutonomyLadder(sessions: [running], now: now, calendar: calendar)

        XCTAssertEqual(ladder.cleanDayCount, 0)
    }

    func testAMixedDayIsStillOneDay() {
        // Two sessions, one bailed and one finished at the tag. A day is a
        // day; the streak counts days, not sessions.
        let mixed = [session(daysAgo: 0, emergency: true), session(daysAgo: 0)]
        XCTAssertEqual(stats(mixed).currentStreak, 1)
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
        let running = DadSession(modeID: UUID(), modeName: "Sleep", startedAt: now, endedAt: nil)
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
        let overnight = DadSession(modeID: UUID(), modeName: "Sleep",
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
        XCTAssertEqual(TimeInterval(45).dadDurationText, "45s")
        XCTAssertEqual(TimeInterval(8 * 60).dadDurationText, "8m")
        XCTAssertEqual(TimeInterval(3600).dadDurationText, "1h 0m")
        XCTAssertEqual(TimeInterval(3600 + 42 * 60).dadDurationText, "1h 42m")
    }
}

final class VocabularyTests: XCTestCase {
    /// The verb is the product. If the doubling rule ever regresses to
    /// "Timed"/"Timing" the whole thing reads as a typo.
    func testVerbDoublesTheFinalConsonant() {
        XCTAssertEqual(Vocab.verbPast, "Dadded")
        XCTAssertEqual(Vocab.verbGerund, "Dadding")
        XCTAssertEqual(Vocab.unVerb, "Un-Dad")
    }

    func testStatusCopyUsesTheVerbCorrectly() {
        XCTAssertEqual(Vocab.activeTitle, "Your phone is Dadded")
        XCTAssertEqual(Vocab.sessionSummary(duration: "1h 42m"), "You were Dadded for 1h 42m.")
    }

    /// naming.md: capital T mid-sentence, always. A lowercase verb anywhere in
    /// the produced copy reads as a typo and undoes the whole conceit.
    func testTheVerbIsNeverLowercasedInProducedCopy() {
        let copy = [
            Vocab.activeTitle,
            Vocab.idleSubtitle,
            Vocab.activeSubtitle(mode: "Deep Work"),
            Vocab.shieldTitle,
            Vocab.shieldSubtitle(mode: "Deep Work"),
            Vocab.shieldSecondaryButton,
            Vocab.dadAction,
            Vocab.unDadAction,
            Vocab.emergencyUnDad,
            Vocab.sessionSummary(duration: "1h"),
            Vocab.tagline,
        ]
        for line in copy {
            XCTAssertFalse(line.contains("dad") && !line.contains("Dad"),
                           "lowercase verb in: \(line)")
            for bad in ["dadded", "dadding", "un-dad", "dad your", "dad my"] {
                XCTAssertFalse(line.lowercased().contains(bad) && !line.contains("Dad"),
                               "lowercase verb form '\(bad)' in: \(line)")
            }
        }
    }
}

/// What the stats say about rationing.
final class AllowanceStatsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func session(startedAt: Date, spentAt: Date?) -> DadSession {
        var s = DadSession(modeID: UUID(), modeName: "Deep Work", startedAt: startedAt)
        s.endedAt = startedAt.addingTimeInterval(3600)
        s.allowanceSpentAt = spentAt
        return s
    }

    func testNothingRationedIsZeroRatherThanAbsent() {
        let stats = DadStats(sessions: [session(startedAt: now, spentAt: nil)],
                             now: now, calendar: .utc)
        XCTAssertEqual(stats.allowancesReached, 0)
        XCTAssertEqual(stats.daysAllowanceReached, 0)
    }

    func testSessionsThatReachedTheLimitAreCounted() {
        let stats = DadStats(sessions: [
            session(startedAt: now, spentAt: now),
            session(startedAt: now, spentAt: nil),
            session(startedAt: now, spentAt: now.addingTimeInterval(60)),
        ], now: now, calendar: .utc)
        XCTAssertEqual(stats.allowancesReached, 2)
    }

    func testTwoSessionsInOneEveningAreOneDayOfRunningOut() {
        // Counted by day for the same reason the allowance itself is.
        let stats = DadStats(sessions: [
            session(startedAt: now, spentAt: now),
            session(startedAt: now, spentAt: now.addingTimeInterval(2 * 3600)),
        ], now: now, calendar: .utc)
        XCTAssertEqual(stats.allowancesReached, 2)
        XCTAssertEqual(stats.daysAllowanceReached, 1)
    }

    func testDifferentDaysCountSeparately() {
        let stats = DadStats(sessions: [
            session(startedAt: now, spentAt: now),
            session(startedAt: now, spentAt: now.addingTimeInterval(24 * 3600)),
        ], now: now, calendar: .utc)
        XCTAssertEqual(stats.daysAllowanceReached, 2)
    }

    func testAnUnfinishedSessionIsNotCountedYet() {
        // Same rule as every other total here: an in-flight session has no
        // duration and no place in a tally.
        var live = DadSession(modeID: UUID(), modeName: "Deep Work", startedAt: now)
        live.allowanceSpentAt = now
        XCTAssertEqual(DadStats(sessions: [live], now: now, calendar: .utc).allowancesReached, 0)
    }
}
