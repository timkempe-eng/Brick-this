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
