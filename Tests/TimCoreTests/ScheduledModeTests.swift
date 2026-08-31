import XCTest
@testable import TimCore

/// A scheduled Mode runs without anyone present, so the interesting cases are
/// all about it colliding with what the user is doing by hand.
final class ScheduledModeTests: XCTestCase {

    private func nightly() -> ModeSchedule {
        ModeSchedule(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0,
                     weekdays: ModeSchedule.everyDay)
    }

    // MARK: - Registration

    func testALiveScheduleIsRegisteredWithTheSystem() {
        let h = Harness()
        let mode = h.addMode(schedule: nightly())
        h.engine.syncSchedules()

        XCTAssertEqual(h.scheduler.recurring, [RecurringSchedule(modeID: mode.id, schedule: nightly())])
    }

    func testASwitchedOffScheduleIsNotRegistered() {
        let h = Harness()
        var off = nightly()
        off.isEnabled = false
        h.addMode(schedule: off)
        h.engine.syncSchedules()

        XCTAssertTrue(h.scheduler.recurring.isEmpty)
    }

    func testAScheduleOnAModeThatBlocksNothingIsNotRegistered() {
        let h = Harness()
        var empty = h.addEmptyMode()
        empty.schedule = nightly()
        h.engine.upsert(empty)

        XCTAssertTrue(h.scheduler.recurring.isEmpty,
                      "a schedule that would block nothing must not be registered")
    }

    func testAnInvalidScheduleIsNotRegistered() {
        let h = Harness()
        h.addMode(schedule: ModeSchedule(startHour: 9, startMinute: 0,
                                         endHour: 9, endMinute: 5, weekdays: [2]))
        h.engine.syncSchedules()
        XCTAssertTrue(h.scheduler.recurring.isEmpty, "a 5-minute window can never fire")
    }

    func testDeletingAModeDeregistersItsSchedule() {
        let h = Harness()
        let mode = h.addMode(schedule: nightly())
        h.engine.upsert(mode)
        XCTAssertEqual(h.scheduler.recurring.count, 1)

        h.engine.deleteMode(id: mode.id)
        XCTAssertTrue(h.scheduler.recurring.isEmpty, "a deleted Mode must not keep firing")
    }

    func testEditingAModeReplacesTheWholeSet() {
        let h = Harness()
        var mode = h.addMode(schedule: nightly())
        h.engine.upsert(mode)

        mode.schedule?.isEnabled = false
        h.engine.upsert(mode)

        XCTAssertTrue(h.scheduler.recurring.isEmpty)
    }

    // MARK: - Firing

    func testScheduledStartBeginsASession() {
        let h = Harness()
        let mode = h.addMode(schedule: nightly())

        h.engine.beginScheduledSession(modeID: mode.id)

        XCTAssertEqual(h.store.activeSession?.modeID, mode.id)
        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testScheduledEndReleasesItsOwnSession() {
        let h = Harness()
        let mode = h.addMode(schedule: nightly())
        h.engine.beginScheduledSession(modeID: mode.id)

        h.clock.advance(9 * 3600)
        h.engine.endScheduledSession(modeID: mode.id)

        XCTAssertNil(h.store.activeSession)
        XCTAssertEqual(h.store.history.first?.duration, 9 * 3600)
    }

    // MARK: - Collisions with the user

    func testAScheduledStartDoesNotStompAManualSession() {
        let h = Harness()
        let manual = h.addMode(name: "Deep Work")
        let scheduled = h.addMode(name: "Sleep", schedule: nightly())
        h.engine.tim(with: manual)

        h.engine.beginScheduledSession(modeID: scheduled.id)

        XCTAssertEqual(h.store.activeSession?.modeID, manual.id, "the user's session wins")
        XCTAssertEqual(h.shield.appliedMode, manual.id)
        XCTAssertTrue(h.store.history.isEmpty, "and it was not ended")
    }

    func testAScheduledEndDoesNotReleaseSomeoneElsesSession() {
        // Sleep's window ends at 7am while the user is mid Deep Work. Leaving
        // that alone is the whole point of matching on modeID.
        let h = Harness()
        let manual = h.addMode(name: "Deep Work")
        let scheduled = h.addMode(name: "Sleep", schedule: nightly())
        h.engine.tim(with: manual)

        h.engine.endScheduledSession(modeID: scheduled.id)

        XCTAssertNotNil(h.store.activeSession, "still Timmed")
        XCTAssertEqual(h.shield.appliedMode, manual.id)
    }

    func testTappingOutOfAScheduledSessionWorksNormally() {
        // You must always be able to walk to the tag and end a scheduled
        // session early.
        let h = Harness()
        let mode = h.addMode(schedule: nightly())
        h.engine.beginScheduledSession(modeID: mode.id)

        guard case .unTimmed = h.engine.handleTap() else {
            return XCTFail("a tap must release a scheduled session")
        }
        XCTAssertNil(h.store.activeSession)
        XCTAssertNil(h.shield.appliedMode)
    }

    func testAScheduledStartForADeletedModeDoesNothing() {
        let h = Harness()
        let mode = h.addMode(schedule: nightly())
        h.engine.deleteMode(id: mode.id)

        h.engine.beginScheduledSession(modeID: mode.id)

        XCTAssertNil(h.store.activeSession)
        XCTAssertTrue(h.shield.calls.isEmpty)
    }

    func testReconcileReRegistersSchedules() {
        let h = Harness()
        h.addMode(schedule: nightly())
        h.engine.reconcile()
        XCTAssertEqual(h.scheduler.recurring.count, 1)
    }
}

/// The monitor extension is woken with only a string, so a round-trip bug here
/// would mean scheduled sessions silently never start.
final class ScheduleActivityNamingTests: XCTestCase {

    func testDailyNameRoundTrips() {
        let id = UUID()
        let name = ScheduleActivityNaming.name(modeID: id)
        XCTAssertEqual(ScheduleActivityNaming.modeID(from: name), id)
    }

    func testPerWeekdayNameRoundTrips() {
        let id = UUID()
        for weekday in 1...7 {
            let name = ScheduleActivityNaming.name(modeID: id, weekday: weekday)
            XCTAssertEqual(ScheduleActivityNaming.modeID(from: name), id,
                           "weekday \(weekday) lost its mode")
        }
    }

    func testEachWeekdayGetsItsOwnName() {
        let id = UUID()
        let names = Set((1...7).map { ScheduleActivityNaming.name(modeID: id, weekday: $0) })
        XCTAssertEqual(names.count, 7, "colliding names would overwrite each other")
    }

    func testTheReleaseActivityIsNotMistakenForASchedule() {
        XCTAssertTrue(ScheduleActivityNaming.isRelease(ScheduleActivityNaming.release))
        XCTAssertNil(ScheduleActivityNaming.modeID(from: ScheduleActivityNaming.release))
    }

    func testUnrecognisedNamesYieldNothing() {
        XCTAssertNil(ScheduleActivityNaming.modeID(from: "something.else"))
        XCTAssertNil(ScheduleActivityNaming.modeID(from: "tim.schedule.not-a-uuid"))
        XCTAssertNil(ScheduleActivityNaming.modeID(from: ""))
    }
}

/// Re-registering a DeviceActivity window tears the old one down first, and
/// tearing down a window that is currently *open* means its end is never
/// delivered — the scheduled session would then run forever. `syncSchedules`
/// is called on every foreground, so doing nothing when nothing changed is a
/// correctness requirement, not an optimisation.
final class ScheduleSyncIdempotenceTests: XCTestCase {

    private func nightly() -> ModeSchedule {
        ModeSchedule(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0,
                     weekdays: ModeSchedule.everyDay)
    }

    /// Counts how many times the system was actually asked to re-register.
    private final class CountingScheduler: SessionScheduling {
        var setCount = 0
        var last: [RecurringSchedule] = []
        func scheduleRelease(at date: Date) {}
        func cancelScheduledRelease() {}
        func setRecurringSchedules(_ schedules: [RecurringSchedule]) {
            setCount += 1
            last = schedules
        }
    }

    private func makeEngine() -> (FakeStore, CountingScheduler, TimEngine) {
        let store = FakeStore()
        let scheduler = CountingScheduler()
        let engine = TimEngine(store: store, shield: SpyShield(),
                               scheduler: scheduler,
                               clock: TestClock(Date(timeIntervalSince1970: 1_756_000_000)))
        return (store, scheduler, engine)
    }

    private func mode(_ name: String, schedule: ModeSchedule?) -> TimMode {
        TimMode(name: name, symbol: "circle",
                blocked: BlockedSelection(payload: Data([1]), appCount: 1),
                schedule: schedule)
    }

    func testRepeatedSyncsWithNoChangeTouchTheSystemOnce() {
        let (store, scheduler, engine) = makeEngine()
        store.modes = [mode("Sleep", schedule: nightly())]

        engine.syncSchedules()
        engine.syncSchedules()
        engine.syncSchedules()

        XCTAssertEqual(scheduler.setCount, 1, "an unchanged set must not be re-registered")
    }

    func testRepeatedForegroundReconcilesDoNotDisturbALiveWindow() {
        let (store, scheduler, engine) = makeEngine()
        store.modes = [mode("Sleep", schedule: nightly())]
        engine.reconcile()
        let afterFirst = scheduler.setCount

        for _ in 0..<10 { engine.reconcile() }

        XCTAssertEqual(scheduler.setCount, afterFirst,
                       "opening the app during a scheduled window must not tear it down")
    }

    func testAChangedScheduleIsRegistered() {
        let (store, scheduler, engine) = makeEngine()
        var sleep = mode("Sleep", schedule: nightly())
        store.modes = [sleep]
        engine.syncSchedules()

        sleep.schedule?.startHour = 23
        store.modes = [sleep]
        engine.syncSchedules()

        XCTAssertEqual(scheduler.setCount, 2)
        XCTAssertEqual(scheduler.last.first?.schedule.startHour, 23)
    }

    func testAddingAndRemovingAModeEachResync() {
        let (store, scheduler, engine) = makeEngine()
        let sleep = mode("Sleep", schedule: nightly())

        store.modes = [sleep]
        engine.syncSchedules()
        XCTAssertEqual(scheduler.setCount, 1)

        store.modes = []
        engine.syncSchedules()
        XCTAssertEqual(scheduler.setCount, 2)
        XCTAssertTrue(scheduler.last.isEmpty)
    }

    func testWeekdaySetOrderDoesNotCauseASpuriousResync() {
        // weekdays is a Set, so a round trip through storage can reorder it.
        // Comparing sets rather than arrays is what stops that re-registering.
        let (store, scheduler, engine) = makeEngine()
        var s = nightly()
        s.weekdays = [6, 2, 4, 3, 5]
        store.modes = [mode("Work", schedule: s)]
        engine.syncSchedules()

        var reordered = s
        reordered.weekdays = [2, 3, 4, 5, 6]
        store.modes = [mode2(store, reordered)]
        engine.syncSchedules()

        XCTAssertEqual(scheduler.setCount, 1, "same days in a different order is the same schedule")
    }

    /// Rebuilds the stored mode with a new schedule but the same id.
    private func mode2(_ store: FakeStore, _ schedule: ModeSchedule) -> TimMode {
        var m = store.modes[0]
        m.schedule = schedule
        return m
    }
}
