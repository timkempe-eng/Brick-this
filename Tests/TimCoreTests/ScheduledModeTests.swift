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

    func testALiveScheduleRegistersItsWindows() {
        let h = Harness()
        let mode = h.addMode(schedule: nightly())
        h.engine.syncSchedules()

        XCTAssertEqual(h.scheduler.registered,
                       [ScheduleActivityNaming.name(modeID: mode.id)],
                       "an every-day schedule collapses to one daily window")
    }

    func testAPartWeekScheduleRegistersOneWindowPerDay() {
        let h = Harness()
        var s = nightly()
        s.weekdays = ModeSchedule.weeknights
        let mode = h.addMode(schedule: s)
        h.engine.syncSchedules()

        XCTAssertEqual(h.scheduler.registered.count, 5)
        XCTAssertTrue(h.scheduler.registered.allSatisfy {
            ScheduleActivityNaming.modeID(from: $0) == mode.id
        })
    }

    func testASwitchedOffScheduleIsNotRegistered() {
        let h = Harness()
        var off = nightly()
        off.isEnabled = false
        h.addMode(schedule: off)
        h.engine.syncSchedules()

        XCTAssertTrue(h.scheduler.registered.isEmpty)
    }

    func testAScheduleOnAModeThatBlocksNothingIsNotRegistered() {
        let h = Harness()
        var empty = h.addEmptyMode()
        empty.schedule = nightly()
        h.engine.upsert(empty)

        XCTAssertTrue(h.scheduler.registered.isEmpty,
                      "a schedule that would block nothing must not be registered")
    }

    func testAnInvalidScheduleIsNotRegistered() {
        let h = Harness()
        h.addMode(schedule: ModeSchedule(startHour: 9, startMinute: 0,
                                         endHour: 9, endMinute: 5, weekdays: [2]))
        h.engine.syncSchedules()
        XCTAssertTrue(h.scheduler.registered.isEmpty, "a 5-minute window can never fire")
    }

    func testDeletingAModeStopsItsWindows() {
        let h = Harness()
        let mode = h.addMode(schedule: nightly())
        h.engine.upsert(mode)
        XCTAssertEqual(h.scheduler.registered.count, 1)

        h.engine.deleteMode(id: mode.id)
        XCTAssertTrue(h.scheduler.registered.isEmpty, "a deleted Mode must not keep firing")
    }

    // MARK: - Firing

    func testScheduledStartBeginsASession() {
        let h = Harness()
        let mode = h.addMode(schedule: nightly())

        h.engine.beginScheduledSession(modeID: mode.id)

        XCTAssertEqual(h.store.activeSession?.modeID, mode.id)
        XCTAssertEqual(h.store.activeSession?.startedBySchedule, true)
        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testScheduledEndReleasesTheSessionItStarted() {
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
        // Sleep's window ends at 7am while the user is mid Deep Work.
        let h = Harness()
        let manual = h.addMode(name: "Deep Work")
        let scheduled = h.addMode(name: "Sleep", schedule: nightly())
        h.engine.tim(with: manual)

        h.engine.endScheduledSession(modeID: scheduled.id)

        XCTAssertNotNil(h.store.activeSession, "still Timmed")
        XCTAssertEqual(h.shield.appliedMode, manual.id)
    }

    func testAScheduledEndDoesNotReleaseAManualSessionOfTheSameMode() {
        // The subtle one: the user taps at 20:00 and picks Sleep BY HAND,
        // meaning "until I tap again". Sleep also has a 22:00–07:00 schedule.
        // Its 07:00 boundary matches on Mode — and must still keep its hands
        // off, because this session wasn't started by the schedule.
        let h = Harness()
        let sleep = h.addMode(name: "Sleep", schedule: nightly())
        h.engine.tim(with: sleep)

        h.engine.endScheduledSession(modeID: sleep.id)

        XCTAssertNotNil(h.store.activeSession,
                        "a schedule boundary must never end a session the user started by hand")
        XCTAssertEqual(h.shield.appliedMode, sleep.id)
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

    func testReconcileRegistersSchedules() {
        let h = Harness()
        h.addMode(schedule: nightly())
        h.engine.reconcile()
        XCTAssertEqual(h.scheduler.registered.count, 1)
    }

    // MARK: - Old records still decode

    func testASessionRecordedBeforeTheScheduleMarkerStillDecodes() throws {
        // startedBySchedule was added after sessions already existed on disk.
        // A missing key must decode as nil, not fail — a failure would mean
        // the lenient decoder silently drops every pre-existing session.
        let old = """
        {"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF",
         "modeID":"6F9619FF-8B86-D011-B42D-00CF4FC964FE",
         "modeName":"Deep Work","startedAt":700000000,"endedAt":700003600,
         "endedByEmergency":false}
        """.data(using: .utf8)!

        let session = try JSONDecoder().decode(TimSession.self, from: old)
        XCTAssertNil(session.startedBySchedule)
        XCTAssertEqual(session.duration, 3600)
    }
}

/// The window arithmetic and the diff are exactly the logic that used to live
/// in the untestable adapter — and where both confirmed scheduler bugs were.
final class ScheduleWindowTests: XCTestCase {

    private func entry(_ id: UUID = UUID(),
                       start: (Int, Int) = (22, 0),
                       end: (Int, Int) = (7, 0),
                       days: Set<Int> = ModeSchedule.everyDay) -> RecurringSchedule {
        RecurringSchedule(modeID: id, schedule: ModeSchedule(
            startHour: start.0, startMinute: start.1,
            endHour: end.0, endMinute: end.1, weekdays: days))
    }

    // MARK: - The cross-midnight weekday fix

    func testAnOvernightWeekdayWindowEndsTheNextMorningNotNextWeek() {
        // Monday 22:00–07:00 must end TUESDAY 07:00. Pinning Monday on both
        // ends would make the next "Monday 07:00" six days out — a phone
        // Timmed for a week.
        let windows = ScheduleWindows.windows(for: entry(days: [2]))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].weekday, 2)
        XCTAssertEqual(windows[0].endWeekday, 3, "ends the following day")
    }

    func testSaturdayNightWrapsToSunday() {
        let windows = ScheduleWindows.windows(for: entry(days: [7]))
        XCTAssertEqual(windows[0].endWeekday, 1, "weekday 7 wraps to 1, not 8")
    }

    func testADaytimeWindowEndsOnItsOwnDay() {
        let windows = ScheduleWindows.windows(for: entry(start: (9, 0), end: (17, 0), days: [2]))
        XCTAssertEqual(windows[0].endWeekday, 2)
    }

    func testADailyWindowPinsNoWeekdayAtEitherEnd() {
        let windows = ScheduleWindows.windows(for: entry())
        XCTAssertEqual(windows.count, 1, "every-day collapses to one window")
        XCTAssertNil(windows[0].weekday)
        XCTAssertNil(windows[0].endWeekday)
    }

    // MARK: - The diff

    func testAnUnchangedSetProducesNoWork() {
        let e = entry()
        let w = ScheduleWindows.windows(for: [e])
        let (stop, start) = ScheduleWindows.diff(from: w, to: w)
        XCTAssertTrue(stop.isEmpty)
        XCTAssertTrue(start.isEmpty)
    }

    func testAddingAModeTouchesOnlyItsOwnWindows() {
        // Sleep's window may be OPEN right now. Adding Gym must not stop it —
        // a stopped open window never delivers its end, and the session runs
        // forever.
        let sleep = entry()
        let gym = entry(start: (17, 0), end: (19, 0), days: [2, 4, 6])
        let old = ScheduleWindows.windows(for: [sleep])
        let new = ScheduleWindows.windows(for: [sleep, gym])

        let (stop, start) = ScheduleWindows.diff(from: old, to: new)
        XCTAssertTrue(stop.isEmpty, "Sleep's live window must not be touched")
        XCTAssertEqual(Set(start.map(\.name)),
                       Set(ScheduleWindows.windows(for: gym).map(\.name)))
    }

    func testRemovingAModeStopsOnlyItsOwnWindows() {
        let sleep = entry()
        let gym = entry(start: (17, 0), end: (19, 0), days: [2, 4, 6])
        let old = ScheduleWindows.windows(for: [sleep, gym])
        let new = ScheduleWindows.windows(for: [sleep])

        let (stop, start) = ScheduleWindows.diff(from: old, to: new)
        XCTAssertEqual(Set(stop), Set(ScheduleWindows.windows(for: gym).map(\.name)))
        XCTAssertTrue(start.isEmpty)
    }

    func testEditingAScheduleStopsAndRestartsItsWindows() {
        let id = UUID()
        let old = ScheduleWindows.windows(for: [entry(id)])
        var edited = entry(id)
        edited = RecurringSchedule(modeID: id, schedule: {
            var s = edited.schedule; s.startHour = 23; return s
        }())
        let new = ScheduleWindows.windows(for: [edited])

        let (stop, start) = ScheduleWindows.diff(from: old, to: new)
        XCTAssertEqual(stop, old.map(\.name))
        XCTAssertEqual(start.map(\.startHour), [23])
    }
}

/// The end-to-end behaviour the diff exists for.
final class ScheduleSyncTests: XCTestCase {

    private func nightly() -> ModeSchedule {
        ModeSchedule(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0,
                     weekdays: ModeSchedule.everyDay)
    }

    func testRepeatedSyncsWithNoChangeTouchNothing() {
        let h = Harness()
        h.addMode(schedule: nightly())

        h.engine.syncSchedules()
        let (started, stopped) = (h.scheduler.started.count, h.scheduler.stopped.count)
        h.engine.syncSchedules()
        h.engine.reconcile()
        h.engine.reconcile()

        XCTAssertEqual(h.scheduler.started.count, started, "no re-registration")
        XCTAssertEqual(h.scheduler.stopped.count, stopped, "nothing torn down")
    }

    func testEditingOneModeNeverTouchesAnothersLiveWindow() {
        // The confirmed bug this replaces: any change tore down EVERY window,
        // open ones included.
        let h = Harness()
        let sleep = h.addMode(name: "Sleep", schedule: nightly())
        h.engine.syncSchedules()

        var gym = ModeSchedule(startHour: 17, startMinute: 0,
                               endHour: 19, endMinute: 0, weekdays: [2, 4, 6])
        gym.isEnabled = true
        h.addMode(name: "Gym", schedule: gym)
        h.engine.syncSchedules()

        let sleepName = ScheduleActivityNaming.name(modeID: sleep.id)
        XCTAssertFalse(h.scheduler.stopped.contains(sleepName),
                       "Sleep's possibly-open window was torn down by an unrelated edit")
        XCTAssertEqual(h.scheduler.started.filter { $0.name == sleepName }.count, 1,
                       "and was registered exactly once")
    }

    func testAFailedRegistrationIsNotRecordedAsSynced() {
        // The system caps monitored activities. When registration fails, the
        // sync must say so and leave the stored state alone, so the next sync
        // retries instead of trusting a registration that never happened.
        let h = Harness()
        let mode = h.addMode(schedule: nightly())
        h.scheduler.failingNames = [ScheduleActivityNaming.name(modeID: mode.id)]

        XCTAssertFalse(h.engine.syncSchedules())
        XCTAssertTrue(h.store.syncedSchedules.isEmpty, "a failed sync is not recorded")

        h.scheduler.failingNames = []
        XCTAssertTrue(h.engine.syncSchedules(), "the next sync retries and succeeds")
        XCTAssertEqual(h.store.syncedSchedules.count, 1)
    }
}

/// A timed session must end on time even when the process didn't survive to
/// see it.
final class TimedReleaseRecoveryTests: XCTestCase {

    func testReconcileEndsAnOverdueTimedSession() {
        // "Tim me for 15 minutes", process dies, user comes back an hour
        // later. The session is past its deadline: end it, don't re-shield it.
        let h = Harness()
        h.addMode(autoRelease: 15 * 60)
        h.engine.handleTap()
        h.clock.advance(3600)

        h.engine.reconcile()

        XCTAssertNil(h.store.activeSession, "an overdue timed session ends at reconcile")
        XCTAssertNil(h.shield.appliedMode)
        XCTAssertEqual(h.store.history.count, 1)
    }

    func testReconcileReArmsAReleaseThatIsStillInTheFuture() {
        let h = Harness()
        h.addMode(autoRelease: 60 * 60)
        h.engine.handleTap()
        let armedAtStart = h.scheduler.scheduled

        h.clock.advance(10 * 60)
        h.engine.reconcile()

        XCTAssertNotNil(h.store.activeSession, "still inside the window")
        XCTAssertEqual(h.scheduler.scheduled.count, armedAtStart.count + 1,
                       "the release is re-armed in case the first registration was lost")
        XCTAssertEqual(h.scheduler.scheduled.last, armedAtStart.last,
                       "at the same deadline — derived from the session start, not from now")
    }

    func testReconcileLeavesAnUntimedSessionAlone() {
        let h = Harness()
        h.addMode(autoRelease: nil)
        h.engine.handleTap()
        h.clock.advance(24 * 3600)

        h.engine.reconcile()

        XCTAssertNotNil(h.store.activeSession, "until-I-tap-again means exactly that")
        XCTAssertTrue(h.scheduler.scheduled.isEmpty)
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
