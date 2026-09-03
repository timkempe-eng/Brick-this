import XCTest
@testable import DadCore

/// Skipping one night, and the notice that comes ten minutes before one.
///
/// Everything here is pinned to an explicit time zone. A test that leans on
/// `.current` passes on the container and on a laptop in a different zone for
/// different reasons, and neither of them is the reason it was written.
final class ScheduleSkipTests: XCTestCase {

    // MARK: - Fixtures

    /// UTC, for everything that is not specifically about a clock change.
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-08-31 is a Monday; calendar weekday 2. `ModeScheduleTests` pins the
    /// same fact, and every date below is chosen against it.
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.date(from: iso)!
    }

    private func schedule(start: (Int, Int) = (22, 0),
                          end: (Int, Int) = (7, 0),
                          days: Set<Int> = ModeSchedule.everyDay) -> ModeSchedule {
        ModeSchedule(startHour: start.0, startMinute: start.1,
                     endHour: end.0, endMinute: end.1, weekdays: days)
    }

    private func occurrence(_ y: Int, _ m: Int, _ d: Int) -> ScheduleOccurrence {
        ScheduleOccurrence(year: y, month: m, day: d)
    }

    // MARK: - The occurrence identifier

    func testAnOccurrenceIsNamedByTheWallClockDayTheWindowStartsOn() {
        let start = date("2026-09-03T22:00:00Z")
        XCTAssertEqual(ScheduleOccurrence(startingAt: start, calendar: utc),
                       occurrence(2026, 9, 3))
    }

    func testAnOvernightWindowBelongsToTheDayItStartedNotTheDayItEnds() {
        // 22:00 Thursday to 07:00 Friday is "Thursday night" to anyone
        // describing it out loud, and "skip tonight" said on Thursday has to
        // mean this one.
        let start = date("2026-09-03T22:00:00Z")
        let end = date("2026-09-04T07:00:00Z")
        XCTAssertEqual(ScheduleOccurrence(startingAt: start, calendar: utc), occurrence(2026, 9, 3))
        XCTAssertNotEqual(ScheduleOccurrence(startingAt: end, calendar: utc), occurrence(2026, 9, 3))
    }

    func testOccurrencesOrderByDate() {
        XCTAssertLessThan(occurrence(2026, 9, 3), occurrence(2026, 9, 4))
        XCTAssertLessThan(occurrence(2026, 9, 30), occurrence(2026, 10, 1))
        XCTAssertLessThan(occurrence(2026, 12, 31), occurrence(2027, 1, 1))
    }

    func testAnOccurrenceNamesADayThatHappensOnce() {
        // The whole reason the identifier is a date rather than a weekday or a
        // day of the month: those repeat, so a skip recorded in March would
        // suppress a window in June.
        let march = ScheduleOccurrence(startingAt: date("2026-03-05T22:00:00Z"), calendar: utc)
        let june = ScheduleOccurrence(startingAt: date("2026-06-05T22:00:00Z"), calendar: utc)
        XCTAssertNotEqual(march, june)

        let id = UUID()
        let skips = [ScheduleSkip(modeID: id, occurrence: march)]
        XCTAssertFalse(ScheduleSkipping.isSkipped(skips, modeID: id,
                                                  windowStartingAt: date("2026-06-05T22:00:00Z"),
                                                  calendar: utc),
                       "a March skip suppressed a June window")
    }

    func testAnOccurrenceReadsAsADate() {
        XCTAssertEqual("\(occurrence(2026, 9, 3))", "2026-09-03")
    }

    func testAnOccurrenceRoundTripsThroughStorage() {
        let skip = ScheduleSkip(modeID: UUID(), occurrence: occurrence(2026, 9, 3))
        let data = try! JSONEncoder().encode(skip)
        XCTAssertEqual(try! JSONDecoder().decode(ScheduleSkip.self, from: data), skip)
    }

    // MARK: - Should this window run

    func testAWindowWithNoSkipRuns() {
        let id = UUID()
        let resolved = ScheduleSkipping.resolve(skips: [], modeID: id,
                                                windowStartingAt: date("2026-09-03T22:00:00Z"),
                                                now: date("2026-09-03T22:00:00Z"),
                                                calendar: utc)
        XCTAssertTrue(resolved.shouldRun)
    }

    func testASkippedWindowDoesNotRun() {
        let id = UUID()
        let skips = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))]
        let resolved = ScheduleSkipping.resolve(skips: skips, modeID: id,
                                                windowStartingAt: date("2026-09-03T22:00:00Z"),
                                                now: date("2026-09-03T22:00:00Z"),
                                                calendar: utc)
        XCTAssertFalse(resolved.shouldRun)
    }

    func testASkipOnlySilencesTheModeItWasRecordedAgainst() {
        let sleep = UUID()
        let dinner = UUID()
        let skips = [ScheduleSkip(modeID: sleep, occurrence: occurrence(2026, 9, 3))]
        let start = date("2026-09-03T22:00:00Z")

        XCTAssertFalse(ScheduleSkipping.resolve(skips: skips, modeID: sleep,
                                                windowStartingAt: start, now: start,
                                                calendar: utc).shouldRun)
        XCTAssertTrue(ScheduleSkipping.resolve(skips: skips, modeID: dinner,
                                               windowStartingAt: start, now: start,
                                               calendar: utc).shouldRun,
                      "skipping Sleep tonight also silenced Dinner")
    }

    func testASkipSilencesOneNightAndNotTheNextOne() {
        let id = UUID()
        let skips = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))]
        XCTAssertFalse(ScheduleSkipping.resolve(skips: skips, modeID: id,
                                                windowStartingAt: date("2026-09-03T22:00:00Z"),
                                                now: date("2026-09-03T22:00:00Z"),
                                                calendar: utc).shouldRun)
        XCTAssertTrue(ScheduleSkipping.resolve(skips: skips, modeID: id,
                                               windowStartingAt: date("2026-09-04T22:00:00Z"),
                                               now: date("2026-09-04T22:00:00Z"),
                                               calendar: utc).shouldRun,
                      "one skip took out two nights")
    }

    func testResolvingASkipDoesNotSpendItSoARedeliveredBoundaryIsStillSkipped() {
        // DeviceActivity can deliver intervalDidStart more than once — a
        // restart inside the window will do it. Consuming the skip on first use
        // would let the second delivery start the session that was refused.
        let id = UUID()
        let start = date("2026-09-03T22:00:00Z")
        let skips = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))]

        let first = ScheduleSkipping.resolve(skips: skips, modeID: id,
                                             windowStartingAt: start, now: start, calendar: utc)
        XCTAssertFalse(first.shouldRun)

        let second = ScheduleSkipping.resolve(skips: first.skips, modeID: id,
                                              windowStartingAt: start,
                                              now: date("2026-09-03T23:30:00Z"), calendar: utc)
        XCTAssertFalse(second.shouldRun, "the skip was spent by being used once")
    }

    func testABoundaryDeliveredLateStillNamesTheWindowsOwnOccurrence() {
        // The occurrence comes from the window's scheduled start, not from the
        // clock, so a 23:50 window reported a few seconds after midnight is
        // still filed under the day it belongs to.
        let id = UUID()
        let start = date("2026-09-03T23:50:00Z")
        let skips = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))]
        let resolved = ScheduleSkipping.resolve(skips: skips, modeID: id,
                                                windowStartingAt: start,
                                                now: date("2026-09-04T00:00:04Z"),
                                                calendar: utc)
        XCTAssertFalse(resolved.shouldRun)
    }

    // MARK: - Expiry

    func testASkipForTodayIsStillLive() {
        let id = UUID()
        let skips = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))]
        XCTAssertEqual(ScheduleSkipping.live(skips, now: date("2026-09-03T09:00:00Z"),
                                             calendar: utc),
                       skips)
    }

    func testASkipSurvivesTheMidnightInsideTheNightItSkipped() {
        // 22:00–07:00 skipped on the 3rd is still the current occurrence at
        // 02:00 on the 4th. Pruning at midnight would drop a skip whose window
        // has not finished.
        let id = UUID()
        let skips = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))]
        XCTAssertEqual(ScheduleSkipping.live(skips, now: date("2026-09-04T02:00:00Z"),
                                             calendar: utc),
                       skips)
    }

    func testASkipIsGoneOnceItsOccurrenceCannotStillBeRunning() {
        let id = UUID()
        let skips = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))]
        XCTAssertEqual(ScheduleSkipping.live(skips, now: date("2026-09-05T00:00:01Z"),
                                             calendar: utc),
                       [], "a two-day-old skip was still being stored")
    }

    func testTheStoredListDoesNotGrowWithoutBound() {
        // A year of nightly skips, resolved once. What comes back is the
        // handful that can still matter, not 365 entries — the same pruning
        // EmergencyAllowance.consume does while it answers.
        let id = UUID()
        var skips: [ScheduleSkip] = []
        for day in 1...28 { skips.append(ScheduleSkip(modeID: id, occurrence: occurrence(2026, 2, day))) }
        for day in 1...31 { skips.append(ScheduleSkip(modeID: id, occurrence: occurrence(2026, 3, day))) }

        let resolved = ScheduleSkipping.resolve(skips: skips, modeID: id,
                                                windowStartingAt: date("2026-03-31T22:00:00Z"),
                                                now: date("2026-03-31T22:00:00Z"),
                                                calendar: utc)
        XCTAssertEqual(resolved.skips.map(\.occurrence),
                       [occurrence(2026, 3, 30), occurrence(2026, 3, 31)])
    }

    func testAnExpiredSkipCannotSuppressAnythingEvenBeforeItIsPruned() {
        // Pruning keeps the list small; it is not what keeps the answer right.
        // A stale skip left in the list is inert because it names a day that
        // has gone.
        let id = UUID()
        let stale = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 3, 5))]
        XCTAssertTrue(ScheduleSkipping.isSkipped(stale, modeID: id,
                                                 windowStartingAt: date("2026-03-05T22:00:00Z"),
                                                 calendar: utc))
        XCTAssertFalse(ScheduleSkipping.isSkipped(stale, modeID: id,
                                                  windowStartingAt: date("2026-06-05T22:00:00Z"),
                                                  calendar: utc))
    }

    // MARK: - Recording a skip

    func testSkippingTonightRecordsTheNextOccurrence() {
        let id = UUID()
        let skip = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                             after: date("2026-09-03T19:00:00Z"),
                                             skips: [], calendar: utc)
        XCTAssertEqual(skip, ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3)))
    }

    func testSkippingAfterTonightsWindowHasPassedTakesTomorrow() {
        // 07:30, after the overnight window ended. "Skip tonight" now means the
        // window that starts this evening.
        let id = UUID()
        let skip = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                             after: date("2026-09-04T07:30:00Z"),
                                             skips: [], calendar: utc)
        XCTAssertEqual(skip?.occurrence, occurrence(2026, 9, 4))
    }

    func testSkippingWhileTonightIsAlreadyRunningTakesTomorrowInstead() {
        // 23:00, inside a window that opened at 22:00. `nextStart` is strictly
        // after now, so the occurrence on offer has not begun — which is how
        // skipping is structurally unable to touch a running session.
        let id = UUID()
        let skip = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                             after: date("2026-09-03T23:00:00Z"),
                                             skips: [], calendar: utc)
        XCTAssertEqual(skip?.occurrence, occurrence(2026, 9, 4),
                       "skipping reached back into the window already running")
    }

    func testSkippingDoesNotUnSkipTheWindowAlreadyRunning() {
        // The other half of the same guarantee: having skipped tomorrow, the
        // answer for the window that is open right now is unchanged.
        let id = UUID()
        let running = date("2026-09-03T22:00:00Z")
        let skipped = ScheduleSkipping.adding(
            ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                      after: date("2026-09-03T23:00:00Z"),
                                      skips: [], calendar: utc)!,
            to: [], now: date("2026-09-03T23:00:00Z"), calendar: utc)

        XCTAssertTrue(ScheduleSkipping.resolve(skips: skipped, modeID: id,
                                               windowStartingAt: running,
                                               now: date("2026-09-03T23:00:00Z"),
                                               calendar: utc).shouldRun)
    }

    func testSkippingTwiceIsTheSameAsSkippingOnce() {
        let id = UUID()
        let now = date("2026-09-03T19:00:00Z")
        let skip = ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))
        let once = ScheduleSkipping.adding(skip, to: [], now: now, calendar: utc)
        let twice = ScheduleSkipping.adding(skip, to: once, now: now, calendar: utc)
        XCTAssertEqual(twice.count, 1)
        XCTAssertEqual(twice, once)
    }

    func testSkippingAgainAfterSkippingTonightTakesTomorrow() {
        let id = UUID()
        let now = date("2026-09-03T19:00:00Z")
        let tonight = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                                after: now, skips: [], calendar: utc)!
        let stored = ScheduleSkipping.adding(tonight, to: [], now: now, calendar: utc)
        let tomorrow = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                                 after: now, skips: stored, calendar: utc)
        XCTAssertEqual(tomorrow?.occurrence, occurrence(2026, 9, 4))
    }

    func testRecordingASkipPrunesTheDeadOnes() {
        let id = UUID()
        let now = date("2026-09-03T19:00:00Z")
        let stale = ScheduleSkip(modeID: id, occurrence: occurrence(2026, 3, 5))
        let fresh = ScheduleSkip(modeID: id, occurrence: occurrence(2026, 9, 3))
        XCTAssertEqual(ScheduleSkipping.adding(fresh, to: [stale], now: now, calendar: utc),
                       [fresh])
    }

    func testAScheduleThatCanNeverFireHasNothingToSkip() {
        // Never invent a skip against a window that was not coming — a button
        // bound to this has an honest reason to be disabled.
        XCTAssertNil(ScheduleSkipping.nextSkip(of: schedule(days: []), modeID: UUID(),
                                               after: date("2026-09-03T19:00:00Z"),
                                               skips: [], calendar: utc))
    }

    func testSkippingASingleWeekdayScheduleTakesTheOneAWeekOut() {
        // Monday-only, already Monday night. Skipping "tonight" here is next
        // Monday, and the 8-day search in `nextStart` is what finds it.
        let id = UUID()
        let skip = ScheduleSkipping.nextSkip(of: schedule(days: [2]), modeID: id,
                                             after: date("2026-08-31T23:00:00Z"),
                                             skips: [], calendar: utc)
        XCTAssertEqual(skip?.occurrence, occurrence(2026, 9, 7))
    }

    func testSeveralNightsInARowCanBeSkipped() {
        let id = UUID()
        var skips: [ScheduleSkip] = []
        let now = date("2026-09-03T19:00:00Z")
        for _ in 0..<5 {
            guard let next = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                                       after: now, skips: skips, calendar: utc)
            else { return XCTFail("ran out of occurrences to skip") }
            skips = ScheduleSkipping.adding(next, to: skips, now: now, calendar: utc)
        }
        XCTAssertEqual(skips.map(\.occurrence).sorted(),
                       [occurrence(2026, 9, 3), occurrence(2026, 9, 4), occurrence(2026, 9, 5),
                        occurrence(2026, 9, 6), occurrence(2026, 9, 7)])

        XCTAssertEqual(ScheduleSkipping.nextRunningStart(of: schedule(), modeID: id,
                                                         after: now, skips: skips, calendar: utc),
                       date("2026-09-08T22:00:00Z"))
    }

    // MARK: - Daylight saving

    /// Europe/London, where the clocks go forward on 2026-03-29 and back on
    /// 2026-10-25.
    private var london: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    func testASkipRecordedBeforeTheClocksGoForwardStillMatchesThatNight() {
        // The case that decided the identifier. Record the skip on Saturday
        // evening for Sunday's 22:00 window; the clocks go forward at 01:00 on
        // Sunday, so Sunday's 22:00 is an hour earlier in absolute terms than
        // Saturday's was. A stored instant would miss it; a stored day does not.
        let id = UUID()
        let saturdayEvening = date("2026-03-28T20:00:00Z")

        let skip = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                             after: saturdayEvening, skips: [],
                                             calendar: london)
        XCTAssertEqual(skip?.occurrence, occurrence(2026, 3, 28))

        // Skip Saturday, then Sunday, and check Sunday's window is the one that
        // gets silenced across the change.
        let stored = ScheduleSkipping.adding(skip!, to: [], now: saturdayEvening, calendar: london)
        let sunday = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                               after: saturdayEvening, skips: stored,
                                               calendar: london)!
        XCTAssertEqual(sunday.occurrence, occurrence(2026, 3, 29))

        let sundayNight = ScheduleSkipping.nextRunningStart(of: schedule(), modeID: id,
                                                            after: date("2026-03-29T12:00:00Z"),
                                                            skips: [], calendar: london)!
        XCTAssertEqual(sundayNight, date("2026-03-29T21:00:00Z"),
                       "22:00 BST is 21:00 UTC — the hour a stored instant would have got wrong")

        let all = ScheduleSkipping.adding(sunday, to: stored, now: saturdayEvening, calendar: london)
        XCTAssertFalse(ScheduleSkipping.resolve(skips: all, modeID: id,
                                                windowStartingAt: sundayNight,
                                                now: sundayNight, calendar: london).shouldRun)
    }

    func testASkipRecordedBeforeTheClocksGoBackStillMatchesThatNight() {
        let id = UUID()
        let saturdayEvening = date("2026-10-24T19:00:00Z")   // 20:00 BST
        let skips = ScheduleSkipping.adding(
            ScheduleSkip(modeID: id, occurrence: occurrence(2026, 10, 25)),
            to: [], now: saturdayEvening, calendar: london)

        let sundayNight = ScheduleSkipping.nextRunningStart(of: schedule(), modeID: id,
                                                            after: date("2026-10-25T12:00:00Z"),
                                                            skips: [], calendar: london)!
        XCTAssertEqual(sundayNight, date("2026-10-25T22:00:00Z"), "22:00 GMT after the change")
        XCTAssertFalse(ScheduleSkipping.resolve(skips: skips, modeID: id,
                                                windowStartingAt: sundayNight,
                                                now: sundayNight, calendar: london).shouldRun)
    }

    func testTheGraceDayIsMeasuredInCalendarDaysNotInHours() {
        // The night the clocks go back is 25 hours long. Measuring the grace in
        // seconds would expire a skip an hour early on exactly the night the
        // arithmetic is hardest.
        let id = UUID()
        let skips = [ScheduleSkip(modeID: id, occurrence: occurrence(2026, 10, 25))]
        // 23:30 on the 26th, London: the 25th's occurrence is the day before,
        // so still kept.
        XCTAssertEqual(ScheduleSkipping.live(skips, now: date("2026-10-26T23:30:00Z"),
                                             calendar: london),
                       skips)
        XCTAssertEqual(ScheduleSkipping.live(skips, now: date("2026-10-27T00:30:00Z"),
                                             calendar: london),
                       [])
    }

    func testAStartOnAnHourThatDoesNotExistStillNamesItsOwnDay() {
        // America/Los_Angeles skips 02:00–03:00 on 2026-03-08. Foundation moves
        // a 02:30 start to 03:00; the day it belongs to is unchanged, so the
        // skip still matches.
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let id = UUID()
        let overnight = schedule(start: (2, 30), end: (7, 0))
        let start = ScheduleSkipping.nextRunningStart(of: overnight, modeID: id,
                                                      after: date("2026-03-08T08:00:00Z"),
                                                      skips: [], calendar: la)!
        XCTAssertEqual(ScheduleOccurrence(startingAt: start, calendar: la), occurrence(2026, 3, 8))
        XCTAssertEqual(la.dateComponents([.hour], from: start).hour, 3,
                       "02:30 does not exist that morning; Foundation moves it to 03:00")
    }

    func testTheOccurrenceFollowsTheWallClockAcrossATimeZoneChange() {
        // Wall-clock storage means 22:00 is 22:00 wherever you land, and the
        // occurrence is the local day that 22:00 falls on. An identifier built
        // from an instant would name a different day in each zone for the same
        // night's window.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let id = UUID()
        let afternoon = date("2026-09-03T09:00:00Z")   // 18:00 in Tokyo

        let inTokyo = ScheduleSkipping.nextSkip(of: schedule(), modeID: id,
                                                after: afternoon, skips: [], calendar: tokyo)!
        XCTAssertEqual(inTokyo.occurrence, occurrence(2026, 9, 3))

        let start = ScheduleSkipping.nextRunningStart(of: schedule(), modeID: id,
                                                      after: afternoon, skips: [],
                                                      calendar: tokyo)!
        XCTAssertEqual(start, date("2026-09-03T13:00:00Z"), "22:00 JST")
        XCTAssertFalse(ScheduleSkipping.resolve(skips: [inTokyo], modeID: id,
                                                windowStartingAt: start, now: start,
                                                calendar: tokyo).shouldRun)
    }
}

/// The notice before a scheduled Mode starts: when it fires, and the four ways
/// it correctly does not.
final class ScheduleWarningTests: XCTestCase {

    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.date(from: iso)!
    }

    private func schedule(start: (Int, Int) = (22, 0),
                          end: (Int, Int) = (7, 0),
                          days: Set<Int> = ModeSchedule.everyDay) -> ModeSchedule {
        ModeSchedule(startHour: start.0, startMinute: start.1,
                     endHour: end.0, endMinute: end.1, weekdays: days)
    }

    private func mode(_ schedule: ModeSchedule?,
                      name: String = "Sleep",
                      apps: Int = 3) -> DadMode {
        DadMode(name: name,
                symbol: "moon.zzz.fill",
                blocked: BlockedSelection(payload: Data([1]), appCount: apps),
                schedule: schedule)
    }

    // MARK: - When it fires

    func testTheDefaultNoticeIsTenMinutes() {
        // The number in the copy. Spelled literally here because a suite that
        // only refers to it symbolically moves with it silently, and the
        // sentence the user reads does not.
        XCTAssertEqual(ScheduleWarning.defaultLeadTime, 10 * 60)
    }

    func testTheWarningFiresTenMinutesBeforeTheWindowOpens() {
        let sleep = mode(schedule())
        let warning = ScheduleWarning.next(for: sleep, now: date("2026-09-03T19:00:00Z"),
                                           calendar: utc)
        XCTAssertEqual(warning?.fireAt, date("2026-09-03T21:50:00Z"))
        XCTAssertEqual(warning?.windowStart, date("2026-09-03T22:00:00Z"))
        XCTAssertEqual(warning?.modeID, sleep.id)
        XCTAssertEqual(warning?.leadTime, ScheduleWarning.defaultLeadTime)
    }

    func testTheLeadTimeIsAParameter() {
        let warning = ScheduleWarning.next(for: mode(schedule()),
                                           now: date("2026-09-03T19:00:00Z"),
                                           leadTime: 30 * 60, calendar: utc)
        XCTAssertEqual(warning?.fireAt, date("2026-09-03T21:30:00Z"))
    }

    func testAWarningMomentAlreadyPastYieldsTheNextNightRatherThanALateNotice() {
        // 21:55 — five minutes to go. "Sleep in ten minutes" delivered now
        // would be false, so tonight gets no notice and the answer is
        // tomorrow's.
        let warning = ScheduleWarning.next(for: mode(schedule()),
                                           now: date("2026-09-03T21:55:00Z"),
                                           calendar: utc)
        XCTAssertEqual(warning?.fireAt, date("2026-09-04T21:50:00Z"))
        XCTAssertEqual(warning?.windowStart, date("2026-09-04T22:00:00Z"))
    }

    func testTheWarningNeverFiresInThePast() {
        // Walk the last quarter of an hour a minute at a time. Whatever the
        // answer is, it is never an instant that has already gone.
        let sleep = mode(schedule())
        for minute in 45...59 {
            let now = date(String(format: "2026-09-03T21:%02d:00Z", minute))
            guard let warning = ScheduleWarning.next(for: sleep, now: now, calendar: utc) else {
                return XCTFail("no warning at 21:\(minute)")
            }
            XCTAssertGreaterThan(warning.fireAt, now, "warning scheduled in the past at 21:\(minute)")
        }
    }

    func testTheWarningExactlyOnTheLeadTimeBoundaryBelongsToTheNextNight() {
        // At 21:50 the notice would be delivered this instant, warning about
        // something ten minutes away — defensible, but it makes "fires strictly
        // in the future" untrue and the adapter has nothing to schedule.
        let warning = ScheduleWarning.next(for: mode(schedule()),
                                           now: date("2026-09-03T21:50:00Z"),
                                           calendar: utc)
        XCTAssertEqual(warning?.windowStart, date("2026-09-04T22:00:00Z"))
    }

    func testTheWarningFollowsTheScheduleAcrossAWeekendGap() {
        // Weeknights, asked on Friday evening. The next window is Monday.
        let warning = ScheduleWarning.next(for: mode(schedule(days: ModeSchedule.weeknights)),
                                           now: date("2026-09-04T23:00:00Z"), calendar: utc)
        XCTAssertEqual(warning?.windowStart, date("2026-09-07T22:00:00Z"))
        XCTAssertEqual(warning?.fireAt, date("2026-09-07T21:50:00Z"))
    }

    // MARK: - When it correctly says nothing

    func testAModeSkippedTonightWarnsAboutTomorrowInstead() {
        let sleep = mode(schedule())
        let now = date("2026-09-03T19:00:00Z")
        let skips = [ScheduleSkip(modeID: sleep.id,
                                  occurrence: ScheduleOccurrence(startingAt: date("2026-09-03T22:00:00Z"),
                                                                 calendar: utc))]
        let warning = ScheduleWarning.next(for: sleep, now: now, skips: skips, calendar: utc)
        XCTAssertEqual(warning?.windowStart, date("2026-09-04T22:00:00Z"),
                       "warned about a night that was skipped")
    }

    func testAModeSkippedEveryRemainingNightOfItsWeekWarnsAboutTheOneAfter() {
        let sleep = mode(schedule(days: [2]))   // Mondays only
        let now = date("2026-08-31T19:00:00Z")  // Monday
        let skips = [ScheduleSkip(modeID: sleep.id,
                                  occurrence: ScheduleOccurrence(startingAt: date("2026-08-31T22:00:00Z"),
                                                                 calendar: utc))]
        let warning = ScheduleWarning.next(for: sleep, now: now, skips: skips, calendar: utc)
        XCTAssertEqual(warning?.windowStart, date("2026-09-07T22:00:00Z"))
    }

    func testAModeAlreadyRunningDoesNotWarn() {
        // `beginScheduledSession` refuses to stomp a session, so the window
        // being warned about would not open. A notice about it would be a lie.
        XCTAssertNil(ScheduleWarning.next(for: mode(schedule()),
                                          now: date("2026-09-03T19:00:00Z"),
                                          isSessionActive: true, calendar: utc))
    }

    func testAModeWithNoLiveScheduleDoesNotWarn() {
        XCTAssertNil(ScheduleWarning.next(for: mode(nil), now: date("2026-09-03T19:00:00Z"),
                                          calendar: utc))

        var off = schedule()
        off.isEnabled = false
        XCTAssertNil(ScheduleWarning.next(for: mode(off), now: date("2026-09-03T19:00:00Z"),
                                          calendar: utc))
    }

    func testAModeThatBlocksNothingDoesNotWarn() {
        // Same guard `beginScheduledSession` applies, so the warning and the
        // start can never disagree about whether the night is happening.
        XCTAssertNil(ScheduleWarning.next(for: mode(schedule(), apps: 0),
                                          now: date("2026-09-03T19:00:00Z"), calendar: utc))
    }

    func testAScheduleThatCanNeverFireDoesNotWarn() {
        XCTAssertNil(ScheduleWarning.next(for: mode(schedule(days: [])),
                                          now: date("2026-09-03T19:00:00Z"), calendar: utc))
    }

    func testANonPositiveLeadTimeIsNotAWarning() {
        // A notice delivered at or after the thing it warns about is not a
        // warning; better nothing than a Mode that looks configured to warn and
        // announces itself as it lands.
        XCTAssertNil(ScheduleWarning.next(for: mode(schedule()),
                                          now: date("2026-09-03T19:00:00Z"),
                                          leadTime: 0, calendar: utc))
        XCTAssertNil(ScheduleWarning.next(for: mode(schedule()),
                                          now: date("2026-09-03T19:00:00Z"),
                                          leadTime: -600, calendar: utc))
    }

    // MARK: - Across Modes

    func testTheSoonestWarningWins() {
        let dinner = mode(schedule(start: (18, 30), end: (19, 30)), name: "Dinner")
        let sleep = mode(schedule(), name: "Sleep")
        let warning = ScheduleWarning.next(among: [sleep, dinner],
                                           now: date("2026-09-03T12:00:00Z"), calendar: utc)
        XCTAssertEqual(warning?.modeID, dinner.id)
        XCTAssertEqual(warning?.fireAt, date("2026-09-03T18:20:00Z"))
    }

    func testAModesSkipMovesTheAnswerToAnotherMode() {
        let dinner = mode(schedule(start: (18, 30), end: (19, 30)), name: "Dinner")
        let sleep = mode(schedule(), name: "Sleep")
        let skips = [ScheduleSkip(modeID: dinner.id,
                                  occurrence: ScheduleOccurrence(startingAt: date("2026-09-03T18:30:00Z"),
                                                                 calendar: utc))]
        let warning = ScheduleWarning.next(among: [sleep, dinner],
                                           now: date("2026-09-03T12:00:00Z"),
                                           skips: skips, calendar: utc)
        XCTAssertEqual(warning?.modeID, sleep.id, "tonight's dinner was skipped")
        XCTAssertEqual(warning?.fireAt, date("2026-09-03T21:50:00Z"))
    }

    func testTheAnswerIsStableWhenTwoModesStartTogether() {
        // Cancelling and re-registering the same notification on every launch
        // is what an unstable answer costs.
        let a = mode(schedule(), name: "Sleep")
        let b = mode(schedule(), name: "Wind Down")
        let now = date("2026-09-03T12:00:00Z")
        let expected = [a, b].min { $0.id.uuidString < $1.id.uuidString }?.id

        XCTAssertEqual(ScheduleWarning.next(among: [a, b], now: now, calendar: utc)?.modeID,
                       expected)
        XCTAssertEqual(ScheduleWarning.next(among: [b, a], now: now, calendar: utc)?.modeID,
                       expected)
    }

    func testNoModesMeansNoWarning() {
        XCTAssertNil(ScheduleWarning.next(among: [], now: date("2026-09-03T12:00:00Z"),
                                          calendar: utc))
    }

    // MARK: - Daylight saving

    func testTheWarningIsTenMinutesOfRealTimeOnTheNightTheClocksGoForward() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!

        let sleep = mode(schedule())
        let warning = ScheduleWarning.next(for: sleep, now: date("2026-03-29T12:00:00Z"),
                                           calendar: london)
        // 22:00 BST is 21:00 UTC. Ten minutes before is ten minutes before, in
        // seconds, whatever the clocks did that morning.
        XCTAssertEqual(warning?.windowStart, date("2026-03-29T21:00:00Z"))
        XCTAssertEqual(warning?.fireAt, date("2026-03-29T20:50:00Z"))
    }
}
