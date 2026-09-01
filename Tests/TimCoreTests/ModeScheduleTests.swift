import XCTest
@testable import TimCore

/// Wall-clock recurrence is where date bugs live: midnight crossings, a
/// weekday whose time has already passed, and schedules that look configured
/// but can never fire.
final class ModeScheduleTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-08-31 is a Monday. Calendar weekday 2.
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

    func testMondayIsWeekdayTwo() {
        XCTAssertEqual(calendar.component(.weekday, from: date("2026-08-31T12:00:00Z")), 2,
                       "the other tests lean on this")
    }

    // MARK: - Midnight crossing

    func testOvernightWindowIsRecognisedAndMeasured() {
        let overnight = schedule(start: (22, 0), end: (7, 0))
        XCTAssertTrue(overnight.crossesMidnight)
        XCTAssertEqual(overnight.duration, 9 * 3600)
    }

    func testDaytimeWindowIsNotAMidnightCrossing() {
        let daytime = schedule(start: (9, 0), end: (17, 30))
        XCTAssertFalse(daytime.crossesMidnight)
        XCTAssertEqual(daytime.duration, 8.5 * 3600)
    }

    func testAWindowEndingAtItsStartIsAFullDay() {
        // 09:00–09:00 reads as "all day", not "zero seconds" — the latter would
        // be an invalid schedule that silently never blocks anything.
        let allDay = schedule(start: (9, 0), end: (9, 0))
        XCTAssertTrue(allDay.crossesMidnight)
        XCTAssertEqual(allDay.duration, 24 * 3600)
    }

    // MARK: - Validity

    func testAScheduleWithNoDaysCanNeverFire() {
        XCTAssertFalse(schedule(days: []).isValid)
        XCTAssertNil(schedule(days: []).nextStart(after: date("2026-08-31T12:00:00Z"),
                                                  calendar: calendar))
    }

    func testAWindowShorterThanTheSchedulerMinimumIsInvalid() {
        XCTAssertFalse(schedule(start: (9, 0), end: (9, 10)).isValid)
        XCTAssertTrue(schedule(start: (9, 0), end: (9, 15)).isValid)
    }

    func testOutOfRangeComponentsAreInvalid() {
        XCTAssertFalse(schedule(start: (25, 0), end: (7, 0)).isValid)
        XCTAssertFalse(schedule(start: (22, 61), end: (7, 0)).isValid)
    }

    // MARK: - Next occurrence

    func testLaterTodayIsChosenWhenTheTimeHasNotPassed() {
        let next = schedule(start: (22, 0), end: (7, 0))
            .nextStart(after: date("2026-08-31T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(next, date("2026-08-31T22:00:00Z"))
    }

    func testTomorrowIsChosenWhenTodaysTimeHasPassed() {
        let next = schedule(start: (22, 0), end: (7, 0))
            .nextStart(after: date("2026-08-31T23:00:00Z"), calendar: calendar)
        XCTAssertEqual(next, date("2026-09-01T22:00:00Z"))
    }

    func testASingleWeekdayWrapsAWholeWeekWhenTodaysTimeHasPassed() {
        // Monday-only, and it's already Monday night. The next one is a week
        // out — the case a 7-day search window would miss.
        let mondayOnly = schedule(start: (22, 0), end: (7, 0), days: [2])
        let next = mondayOnly.nextStart(after: date("2026-08-31T23:00:00Z"), calendar: calendar)
        XCTAssertEqual(next, date("2026-09-07T22:00:00Z"))
    }

    func testWeeknightsSkipsTheWeekend() {
        // Friday 2026-09-04, 23:00. Next weeknight start is Monday.
        let next = schedule(start: (22, 0), end: (7, 0), days: ModeSchedule.weeknights)
            .nextStart(after: date("2026-09-04T23:00:00Z"), calendar: calendar)
        XCTAssertEqual(next, date("2026-09-07T22:00:00Z"))
    }

    func testNextStartIsStrictlyAfterTheGivenMoment() {
        // Standing exactly on the start must yield the *next* one, or a
        // schedule could re-fire in a loop.
        let onTheDot = date("2026-08-31T22:00:00Z")
        let next = schedule(start: (22, 0), end: (7, 0)).nextStart(after: onTheDot,
                                                                   calendar: calendar)
        XCTAssertEqual(next, date("2026-09-01T22:00:00Z"))
    }

    // MARK: - Display

    func testDisplayText() {
        XCTAssertEqual(schedule().displayText(calendar: calendar), "Every day, 22:00–07:00")
        XCTAssertEqual(schedule(days: ModeSchedule.weeknights).displayText(calendar: calendar),
                       "Weeknights, 22:00–07:00")
        XCTAssertEqual(schedule(start: (9, 0), end: (17, 0), days: ModeSchedule.weeknights)
                        .displayText(calendar: calendar),
                       "Weekdays, 09:00–17:00")
    }

    func testDisabledAndInvalidSchedulesSayWhy() {
        var off = schedule()
        off.isEnabled = false
        XCTAssertEqual(off.displayText(calendar: calendar), "Schedule off")
        XCTAssertEqual(schedule(days: []).displayText(calendar: calendar), "Schedule incomplete")
    }

    func testArbitraryDaysListTheirSymbols() {
        let text = schedule(days: [1, 7]).displayText(calendar: calendar)   // Sun + Sat
        XCTAssertTrue(text.hasPrefix("\(calendar.shortWeekdaySymbols[0]) \(calendar.shortWeekdaySymbols[6])"),
                      "got \(text)")
    }
}

/// The switch in the Mode editor, as logic rather than as a view.
///
/// This is the test that was missing. The behaviour lived in a
/// `Binding(get:set:)` inside `ScheduleSection`, so the only thing that could
/// exercise it was a Simulator, and when it broke the Simulator could only say
/// "the switch reads off" — six CI runs without ever naming the cause.
final class ScheduleTogglingTests: XCTestCase {

    func testAModeStartsUnscheduled() {
        XCTAssertFalse(TimMode(name: "Deep Work", symbol: "brain").isScheduled)
    }

    func testSwitchingOnCreatesAScheduleThatCanActuallyFire() {
        var mode = TimMode(name: "Deep Work", symbol: "brain")
        mode.isScheduled = true

        XCTAssertTrue(mode.isScheduled)
        XCTAssertNotNil(mode.schedule)
        // The point of a starter window: switching the schedule on must never
        // leave one that looks set up and silently never fires.
        XCTAssertTrue(mode.schedule?.isValid == true)
    }

    func testSwitchingOffKeepsTheWindowSoTurningItBackOnRestoresIt() {
        var mode = TimMode(name: "Sleep", symbol: "moon")
        mode.isScheduled = true
        mode.editableSchedule.startHour = 23

        mode.isScheduled = false
        XCTAssertFalse(mode.isScheduled)

        mode.isScheduled = true
        XCTAssertEqual(mode.schedule?.startHour, 23,
                       "Toggling off and on again discarded the window you had set.")
    }

    func testSwitchingOnPreservesAnExistingDisabledSchedule() {
        var mode = TimMode(name: "Gym", symbol: "figure.run")
        mode.schedule = ModeSchedule(isEnabled: false,
                                     startHour: 6, startMinute: 30,
                                     endHour: 8, endMinute: 0,
                                     weekdays: ModeSchedule.weeknights)
        mode.isScheduled = true

        XCTAssertEqual(mode.schedule?.startHour, 6)
        XCTAssertEqual(mode.schedule?.weekdays, ModeSchedule.weeknights)
    }

    func testEditingThroughTheEditableScheduleStores() {
        var mode = TimMode(name: "Dinner", symbol: "fork.knife")
        // Reading before anything is stored yields the starter, and writing it
        // back stores it — that is what lets every control below the switch
        // bind directly instead of through an optional.
        mode.editableSchedule.weekdays = [2, 4]
        XCTAssertEqual(mode.schedule?.weekdays, [2, 4])
    }

    func testTheStarterWindowIsValid() {
        XCTAssertTrue(ModeSchedule.starter.isValid)
    }

    func testAScheduledModeThatBlocksNothingIsNeverLive() {
        var mode = TimMode(name: "Deep Work", symbol: "brain")
        mode.isScheduled = true
        XCTAssertFalse(mode.hasLiveSchedule,
                       "A Mode that blocks nothing must never be registered.")
    }
}
