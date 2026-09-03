import XCTest
@testable import DadCore

/// Sitting one night out, wired to the engine.
///
/// `ScheduleSkip.swift` owns the arithmetic and tests it thoroughly. These are
/// about the seam: that a recorded skip actually stops the session starting,
/// that it stops exactly one night, and that it cannot be used as a way out of
/// a session already running — which would make it an unbudgeted emergency
/// override with no counter on it.
final class SkipTonightTests: XCTestCase {

    /// A calendar pinned to UTC so "tonight" means the same thing everywhere.
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 22:00 on the day an occurrence names, in the pinned calendar.
    private func nightOf(_ occurrence: ScheduleOccurrence, plusDays days: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = occurrence.year
        parts.month = occurrence.month
        parts.day = occurrence.day + days
        parts.hour = 22
        return utc.date(from: parts)!
    }

    private func nightly(_ h: Harness) -> DadMode {
        h.addMode(name: "Sleep",
                  schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                         endHour: 7, endMinute: 0,
                                         weekdays: ModeSchedule.everyDay))
    }

    // MARK: - The skip reaches the boundary

    func testASkippedNightDoesNotStartTheSession() {
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        XCTAssertNotNil(h.engine.skipNextNight(modeID: sleep.id))

        // The system delivers the window's start anyway — the window repeats,
        // and tearing it down for one night is the open-window failure this
        // codebase avoids. The refusal has to happen here.
        h.clock.now = nightOf(h.store.scheduleSkips[0].occurrence)
        h.engine.beginScheduledSession(modeID: sleep.id)

        XCTAssertNil(h.store.activeSession)
        XCTAssertNil(h.shield.appliedMode)
    }

    func testTheNightAfterStillRuns() {
        // "Skip tonight", not "skip this Mode". A skip that quietly became
        // permanent would be the schedule being turned off, which is the thing
        // this exists to prevent.
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        let skip = h.engine.skipNextNight(modeID: sleep.id)!

        h.clock.now = nightOf(skip.occurrence, plusDays: 1)
        h.engine.beginScheduledSession(modeID: sleep.id)

        XCTAssertEqual(h.store.activeSession?.modeID, sleep.id)
        XCTAssertEqual(h.store.activeSession?.startedBySchedule, true)
    }

    func testAnUnskippedNightRunsNormally() {
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        h.engine.beginScheduledSession(modeID: sleep.id)
        XCTAssertEqual(h.store.activeSession?.modeID, sleep.id)
    }

    // MARK: - It is not a way out

    func testSkippingCannotReleaseASessionAlreadyRunning() {
        // Otherwise "skip tonight" would be an emergency override with no
        // counter on it, reachable from a button rather than the tag.
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        h.engine.beginScheduledSession(modeID: sleep.id)
        XCTAssertEqual(h.shield.appliedMode, sleep.id)

        h.engine.skipNextNight(modeID: sleep.id)

        XCTAssertNotNil(h.store.activeSession, "still Dadded")
        XCTAssertEqual(h.shield.appliedMode, sleep.id, "and still shielded")
    }

    // MARK: - Nothing to skip

    func testAModeWithNoScheduleHasNoNightToSkip() {
        let h = Harness(calendar: utc)
        let plain = h.addMode()
        XCTAssertNil(h.engine.nextSkippableNight(modeID: plain.id))
        XCTAssertNil(h.engine.skipNextNight(modeID: plain.id))
        XCTAssertTrue(h.store.scheduleSkips.isEmpty)
    }

    func testAScheduleThatBlocksNothingHasNoNightToSkip() {
        // It is never registered with the system, so there is no window
        // coming — and a button that records a skip against one would be the
        // looks-configured-does-nothing failure in miniature.
        let h = Harness(calendar: utc)
        var empty = h.addEmptyMode(name: "Sleep")
        empty.schedule = ModeSchedule(startHour: 22, startMinute: 0,
                                      endHour: 7, endMinute: 0,
                                      weekdays: ModeSchedule.everyDay)
        h.store.modes = [empty]
        XCTAssertNil(h.engine.nextSkippableNight(modeID: empty.id))
    }

    func testSkippingTwiceIsTheSameAsSkippingOnce() {
        // This failed the first time it was written, and the failure was real:
        // `ScheduleSkipping.adding` de-dupes and promises that tapping twice
        // is the same as tapping once, but `nextSkip` advances *past* skipped
        // occurrences to find the night that will actually run — so the second
        // press was handed a different night and skipped tomorrow too. A
        // button labelled "Skip tonight" pressed twice would have taken two
        // nights off the schedule.
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        h.engine.skipNextNight(modeID: sleep.id)
        let first = h.store.scheduleSkips

        h.engine.skipNextNight(modeID: sleep.id)

        XCTAssertEqual(h.store.scheduleSkips, first,
                       "there is no second night to un-skip by accident")
        XCTAssertEqual(h.store.scheduleSkips.count, 1)
    }

    func testTheButtonCanSayTonightIsAlreadySkipped() {
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        XCTAssertFalse(h.engine.isNextNightSkipped(modeID: sleep.id))

        h.engine.skipNextNight(modeID: sleep.id)

        XCTAssertTrue(h.engine.isNextNightSkipped(modeID: sleep.id))
    }

    func testTheNightASkipLandsOnIsNotTheNightItWillNextRun() {
        // The distinction the bug above collapsed. Both questions are
        // legitimate and they have different answers once a night is skipped:
        // a button asks "what would I skip", a warning asks "when does this
        // next actually happen".
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        let tonight = h.engine.nextSkippableNight(modeID: sleep.id)!
        h.engine.skipNextNight(modeID: sleep.id)

        XCTAssertEqual(h.engine.nextSkippableNight(modeID: sleep.id), tonight,
                       "the button still points at tonight")
        let running = ScheduleSkipping.nextRunningStart(of: sleep.schedule!,
                                                        modeID: sleep.id,
                                                        after: h.clock.now,
                                                        skips: h.store.scheduleSkips,
                                                        calendar: utc)
        XCTAssertNotNil(running)
        XCTAssertNotEqual(ScheduleOccurrence(startingAt: running!, calendar: utc),
                          tonight.occurrence, "but it will next run the night after")
    }

    func testSkippingOneModeDoesNotSkipAnother() {
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        let school = h.addMode(name: "School",
                               schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                                      endHour: 7, endMinute: 0,
                                                      weekdays: ModeSchedule.everyDay))
        h.engine.skipNextNight(modeID: sleep.id)

        h.engine.beginScheduledSession(modeID: school.id)
        XCTAssertEqual(h.store.activeSession?.modeID, school.id)
    }

    // MARK: - Warning

    func testTheWarningNamesTheModeThatIsComing() {
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        XCTAssertEqual(h.engine.nextScheduleWarning?.modeID, sleep.id)
    }

    func testThereIsNoWarningWhileASessionIsRunning() {
        // "Sleep in ten minutes" is a lie when the phone is already Dadded.
        let h = Harness(calendar: utc)
        let sleep = nightly(h)
        h.engine.dad(with: sleep)
        XCTAssertNil(h.engine.nextScheduleWarning)
    }
}
