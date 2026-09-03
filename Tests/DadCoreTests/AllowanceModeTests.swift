import XCTest
@testable import DadCore

/// Modes that ration rather than forbid.
///
/// The whole feature is a state machine over a day boundary, driven by events
/// from a process we don't control, so almost everything worth knowing is
/// tested here rather than on a device. The decisions pinned down deliberately,
/// because they are product choices and not implementation details:
///
/// - while the allowance lasts the apps are *there*, but strict still holds;
/// - an allowance the system won't count is no allowance, so Dad blocks instead
///   of quietly enforcing nothing;
/// - a spent allowance is spent for the *day*, and a session that outlives
///   midnight gets the next day's, whether or not anything woke us to say so;
/// - editing a live Mode's allowance restarts today's count, and editing
///   anything else about it does not — or Save would be a way to buy minutes.
final class AllowanceModeTests: XCTestCase {

    private let fifteen = ModeAllowance(minutesPerDay: 15)

    // MARK: - Starting

    func testARationedModeLeavesTheAppsWhereTheyAre() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)

        XCTAssertEqual(h.engine.handleTap(),
                       .dadded(mode: mode, start: .rationing(minutesPerDay: 15)))
        XCTAssertNil(h.shield.appliedMode, "the apps must still be usable")
        XCTAssertEqual(h.shield.rationingMode, mode.id)
        XCTAssertNotNil(h.store.activeSession, "it is still a session")
    }

    func testStrictStillHoldsWhileTheAllowanceLasts() {
        let h = Harness()
        let mode = h.addMode(strict: true, allowance: fifteen)
        h.engine.dad(with: mode)

        // The free period is exactly when someone would reach for the "delete
        // the blocker" escape hatch, so it must not be the one window where
        // strict quietly means nothing.
        XCTAssertEqual(h.shield.calls, [.restrictionsOnly(mode.id)])
    }

    func testTheSystemIsAskedToCountTheRightNumberOfMinutes() {
        let h = Harness()
        let mode = h.addMode(allowance: ModeAllowance(minutesPerDay: 45))
        h.engine.dad(with: mode)

        XCTAssertEqual(h.usage.calls, [.start(mode.id, minutes: 45)])
        XCTAssertTrue(h.usage.watching.contains(mode.id))
    }

    func testAModeThatBlocksNothingNeverRations() {
        // An allowance over an empty selection counts nothing, would never
        // reach its threshold, and would read as "15 min a day" while meaning
        // "no limit at all".
        var mode = DadMode(name: "Empty", symbol: "circle")
        mode.allowance = fifteen
        XCTAssertFalse(mode.rations)
    }

    func testAnAllowanceOutsideItsBoundsBlocksInstead() {
        let h = Harness()
        for minutes in [0, -5, ModeAllowance.maximumMinutes + 1] {
            let mode = h.addMode(name: "M\(minutes)",
                                 allowance: ModeAllowance(minutesPerDay: minutes))
            XCTAssertFalse(mode.rations, "\(minutes) minutes is not an allowance")
            h.engine.dad(with: mode)
            XCTAssertEqual(h.shield.appliedMode, mode.id,
                           "a Mode that cannot ration must still block")
            h.engine.unDad(.tapped)
        }
    }

    func testASwitchedOffAllowanceBlocks() {
        let h = Harness()
        let mode = h.addMode(allowance: ModeAllowance(isEnabled: false, minutesPerDay: 15))
        XCTAssertFalse(mode.rations)
        h.engine.dad(with: mode)
        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testTurningRationingOnMakesAUsableAllowance() {
        // Same decision `isScheduled` carries, and here for the same reason:
        // switched on with nothing stored must not leave a Mode that says it
        // rations and cannot.
        var mode = DadMode(name: "Deep Work", symbol: "circle",
                           blocked: BlockedSelection(payload: Data([1]), appCount: 1))
        XCTAssertFalse(mode.isRationed)
        mode.isRationed = true
        XCTAssertTrue(mode.isRationed)
        XCTAssertTrue(mode.editableAllowance.isValid)
        XCTAssertTrue(mode.rations)
    }

    // MARK: - An allowance nobody counts

    func testWhenTheSystemRefusesToCountUsageTheAppsAreTakenAwayInstead() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.usage.refusing = [mode.id]

        XCTAssertEqual(h.engine.handleTap(), .dadded(mode: mode, start: .rationRefused))
        XCTAssertEqual(h.shield.appliedMode, mode.id,
                       "an allowance nobody counts is an unlimited allowance")
        XCTAssertNotNil(h.store.activeSession?.allowanceSpentAt,
                        "and every later reader must agree it is spent")
    }

    func testARefusedAllowanceIsRetriedTheNextDay() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.usage.refusing = [mode.id]
        h.engine.dad(with: mode)
        XCTAssertEqual(h.shield.appliedMode, mode.id)

        h.usage.refusing = []
        h.clock.advance(days: 1)
        h.engine.reconcile()

        XCTAssertNil(h.shield.appliedMode, "a new day is a new attempt")
        XCTAssertEqual(h.shield.rationingMode, mode.id)
    }

    // MARK: - Spending it

    func testSpendingTheAllowanceRaisesTheShield() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        let reloadsBefore = h.widget.reloadCount

        h.clock.advance(15 * 60)
        h.engine.spendAllowance(modeID: mode.id)

        XCTAssertEqual(h.shield.appliedMode, mode.id)
        XCTAssertEqual(h.store.activeSession?.allowanceSpentAt, h.clock.now)
        XCTAssertGreaterThan(h.widget.reloadCount, reloadsBefore,
                             "the Lock Screen was saying the apps were available")
    }

    func testADuplicateThresholdDoesNotMoveTheMomentItRanOut() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)

        h.clock.advance(15 * 60)
        h.engine.spendAllowance(modeID: mode.id)
        let spentAt = h.store.activeSession?.allowanceSpentAt

        h.clock.advance(60 * 60)
        h.engine.spendAllowance(modeID: mode.id)

        XCTAssertEqual(h.store.activeSession?.allowanceSpentAt, spentAt,
                       "the system can deliver a threshold more than once")
    }

    func testSpendingSomeOtherModesAllowanceChangesNothing() {
        let h = Harness()
        let running = h.addMode(name: "Deep Work", allowance: fifteen)
        let other = h.addMode(name: "Sleep", allowance: fifteen)
        h.engine.dad(with: running)

        h.engine.spendAllowance(modeID: other.id)

        XCTAssertNil(h.shield.appliedMode)
        XCTAssertNil(h.store.activeSession?.allowanceSpentAt)
    }

    func testSpendingWithNoSessionChangesNothing() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.spendAllowance(modeID: mode.id)
        XCTAssertNil(h.store.activeSession)
        XCTAssertTrue(h.shield.calls.isEmpty)
    }

    func testAFinishedSessionRecordsThatTheAllowanceRanOut() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.clock.advance(15 * 60)
        h.engine.spendAllowance(modeID: mode.id)
        h.clock.advance(60)
        h.engine.unDad(.tapped)

        XCTAssertNotNil(h.store.history.last?.allowanceSpentAt,
                        "whether you reached the limit is the one number worth "
                        + "knowing about a rationed Mode")
    }

    // MARK: - The day boundary

    func testANewDayHandsBackTheAllowance() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.spendAllowance(modeID: mode.id)
        XCTAssertEqual(h.shield.appliedMode, mode.id)

        h.clock.advance(days: 1)
        h.engine.renewAllowance(modeID: mode.id)

        XCTAssertNil(h.shield.appliedMode)
        XCTAssertEqual(h.shield.rationingMode, mode.id)
        XCTAssertNil(h.store.activeSession?.allowanceSpentAt)
    }

    func testRenewingWithinTheSameDayIsRefused() {
        // The system delivers the start of the window we registered, and
        // re-registering an already-open one would otherwise hand back an
        // allowance that was spent minutes ago.
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.spendAllowance(modeID: mode.id)

        h.clock.advance(60 * 60)
        h.engine.renewAllowance(modeID: mode.id)

        XCTAssertEqual(h.shield.appliedMode, mode.id, "still the same day")
    }

    func testReconcileHandsBackTheAllowanceEvenIfNothingWokeUsAtMidnight() {
        // The backstop that makes the whole thing safe: a monitor wake that
        // never arrives would otherwise leave the apps hidden for the rest of
        // a multi-day session with nothing able to notice.
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.spendAllowance(modeID: mode.id)

        h.clock.advance(days: 2)
        h.engine.reconcile()

        XCTAssertNil(h.shield.appliedMode)
        XCTAssertNil(h.store.activeSession?.allowanceSpentAt)
    }

    func testReconcileWithinTheDayKeepsTheAppsHidden() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.spendAllowance(modeID: mode.id)

        h.clock.advance(60)
        h.engine.reconcile()

        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testTheDayBoundaryIsTheUsersOwnMidnightNotUTC() {
        // 2026-09-03 23:30 UTC is already the 4th in Sydney. A session that
        // spends its allowance at that instant and reconciles an hour later
        // has crossed midnight *there* and must get the new day's allowance.
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!

        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 3
        components.hour = 13; components.minute = 30   // 23:30 in Sydney
        components.timeZone = TimeZone(identifier: "UTC")!
        let lateEvening = Calendar.utc.date(from: components)!

        let h = Harness(now: lateEvening, calendar: sydney)
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.spendAllowance(modeID: mode.id)
        XCTAssertEqual(h.shield.appliedMode, mode.id)

        h.clock.advance(60 * 60)      // 00:30 in Sydney, still the 3rd in UTC
        h.engine.reconcile()

        XCTAssertNil(h.shield.appliedMode, "midnight is where the user is")
    }

    // MARK: - Re-arming

    func testReconcileReArmsTheCountSoALostRegistrationCannotMeanNoLimit() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)

        h.engine.reconcile()

        XCTAssertEqual(h.usage.calls.filter { $0 == .start(mode.id, minutes: 15) }.count, 2)
        XCTAssertNil(h.shield.appliedMode)
    }

    func testAReArmTheSystemRefusesRaisesTheShield() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        XCTAssertNil(h.shield.appliedMode)

        h.usage.refusing = [mode.id]
        h.engine.reconcile()

        XCTAssertEqual(h.shield.appliedMode, mode.id,
                       "usage that stopped being counted is usage without a limit")
    }

    // MARK: - Ending

    func testEndingASessionStopsTheCount() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.unDad(.tapped)

        XCTAssertFalse(h.usage.watching.contains(mode.id))
    }

    func testDeletingAModeStopsTheCount() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.unDad(.tapped)
        h.engine.deleteMode(id: mode.id)

        XCTAssertEqual(h.usage.calls.last, .stop(mode.id))
    }

    func testAnEmergencyOverrideEndsARationedSessionToo() {
        let h = Harness()
        let mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)

        XCTAssertTrue(h.engine.emergencyUnDad())
        XCTAssertNil(h.store.activeSession)
        XCTAssertFalse(h.usage.watching.contains(mode.id))
    }

    func testSwitchingModesStopsTheOldCount() {
        let h = Harness()
        let first = h.addMode(name: "Deep Work", allowance: fifteen)
        let second = h.addMode(name: "Sleep")
        h.engine.dad(with: first)
        h.engine.dad(with: second)

        XCTAssertFalse(h.usage.watching.contains(first.id))
        XCTAssertEqual(h.shield.appliedMode, second.id)
    }

    // MARK: - Editing a Mode while it is running

    func testChangingTheAllowanceMidSessionRestartsTheCount() {
        let h = Harness()
        var mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.spendAllowance(modeID: mode.id)
        XCTAssertEqual(h.shield.appliedMode, mode.id)

        mode.allowance = ModeAllowance(minutesPerDay: 60)
        h.save(mode)

        XCTAssertNil(h.shield.appliedMode, "the rule changed, so the count starts again")
        XCTAssertNil(h.store.activeSession?.allowanceSpentAt)
        XCTAssertEqual(h.usage.calls.last, .start(mode.id, minutes: 60))
    }

    func testRenamingAModeMidSessionDoesNotBuyMoreMinutes() {
        // Otherwise opening the editor and pressing Save would be the cheat.
        let h = Harness()
        var mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        h.engine.spendAllowance(modeID: mode.id)

        mode.name = "Deeper Work"
        h.save(mode)

        XCTAssertEqual(h.shield.appliedMode, mode.id, "the apps must stay hidden")
        XCTAssertNotNil(h.store.activeSession?.allowanceSpentAt)
    }

    func testTurningRationingOffMidSessionTakesTheAppsAway() {
        let h = Harness()
        var mode = h.addMode(allowance: fifteen)
        h.engine.dad(with: mode)
        XCTAssertNil(h.shield.appliedMode)

        mode.isRationed = false
        h.save(mode)

        XCTAssertEqual(h.shield.appliedMode, mode.id)
        XCTAssertFalse(h.usage.watching.contains(mode.id))
    }

    func testTurningRationingOnMidSessionGivesTheAppsBack() {
        let h = Harness()
        var mode = h.addMode()
        h.engine.dad(with: mode)
        XCTAssertEqual(h.shield.appliedMode, mode.id)

        mode.allowance = fifteen
        h.save(mode)

        XCTAssertNil(h.shield.appliedMode)
        XCTAssertEqual(h.shield.rationingMode, mode.id)
    }

    func testEditingAModeThatIsNotRunningLeavesTheSessionAlone() {
        let h = Harness()
        let running = h.addMode(name: "Deep Work", allowance: fifteen)
        var other = h.addMode(name: "Sleep", allowance: fifteen)
        h.engine.dad(with: running)
        let callsBefore = h.shield.calls

        other.allowance = ModeAllowance(minutesPerDay: 90)
        h.save(other)

        XCTAssertEqual(h.shield.calls, callsBefore)
        XCTAssertFalse(h.usage.watching.contains(other.id))
    }

    // MARK: - Scheduled rationing

    func testAScheduledRationedModeRationsRatherThanBlocks() {
        let h = Harness()
        let mode = h.addMode(schedule: ModeSchedule(startHour: 9, startMinute: 0,
                                                    endHour: 17, endMinute: 0,
                                                    weekdays: ModeSchedule.everyDay),
                             allowance: fifteen)
        h.engine.beginScheduledSession(modeID: mode.id)

        XCTAssertNil(h.shield.appliedMode)
        XCTAssertEqual(h.shield.rationingMode, mode.id)
        XCTAssertEqual(h.store.activeSession?.startedBySchedule, true)
    }
}

/// The one decision, on its own.
final class ShieldPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func session(spentAt: Date? = nil) -> DadSession {
        var s = DadSession(modeID: UUID(), modeName: "Deep Work", startedAt: now)
        s.allowanceSpentAt = spentAt
        return s
    }

    private func mode(rationing: Bool) -> DadMode {
        DadMode(name: "Deep Work", symbol: "circle",
                blocked: BlockedSelection(payload: Data([1]), appCount: 1),
                allowance: rationing ? ModeAllowance(minutesPerDay: 15) : nil)
    }

    func testNoSessionIsOff() {
        XCTAssertEqual(ShieldPolicy.state(session: nil, mode: mode(rationing: true),
                                          now: now, calendar: .utc), .off)
    }

    func testAFinishedSessionIsOff() {
        var finished = session()
        finished.endedAt = now
        XCTAssertEqual(ShieldPolicy.state(session: finished, mode: mode(rationing: true),
                                          now: now, calendar: .utc), .off)
    }

    func testADeletedModeReadsAsBlocking() {
        // reconcile() ends such a session; until it does, the honest answer is
        // that the user's apps are gone and we can't say which.
        XCTAssertEqual(ShieldPolicy.state(session: session(), mode: nil,
                                          now: now, calendar: .utc), .blocking)
    }

    func testAPlainModeBlocks() {
        XCTAssertEqual(ShieldPolicy.state(session: session(), mode: mode(rationing: false),
                                          now: now, calendar: .utc), .blocking)
    }

    func testAnUnspentAllowanceRations() {
        XCTAssertEqual(ShieldPolicy.state(session: session(), mode: mode(rationing: true),
                                          now: now, calendar: .utc), .rationing)
    }

    func testAnAllowanceSpentTodayBlocks() {
        XCTAssertEqual(ShieldPolicy.state(session: session(spentAt: now),
                                          mode: mode(rationing: true),
                                          now: now.addingTimeInterval(600),
                                          calendar: .utc), .blocking)
    }

    func testAnAllowanceSpentYesterdayRationsAgain() {
        XCTAssertEqual(ShieldPolicy.state(session: session(spentAt: now),
                                          mode: mode(rationing: true),
                                          now: now.addingTimeInterval(24 * 60 * 60),
                                          calendar: .utc), .rationing)
    }
}

/// A round-trip bug in activity naming means a window that is registered,
/// fires, and is silently ignored — in a process nobody can watch.
final class ActivityNamingTests: XCTestCase {

    func testAScheduledWindowRoundTrips() {
        let id = UUID()
        XCTAssertEqual(ScheduleActivityNaming.activity(named: ScheduleActivityNaming.name(modeID: id)),
                       .scheduledWindow(modeID: id))
        XCTAssertEqual(ScheduleActivityNaming.activity(named: ScheduleActivityNaming.name(modeID: id, weekday: 3)),
                       .scheduledWindow(modeID: id))
    }

    func testAnAllowanceDayRoundTrips() {
        let id = UUID()
        XCTAssertEqual(ScheduleActivityNaming.activity(named: ScheduleActivityNaming.allowanceName(modeID: id)),
                       .allowanceDay(modeID: id))
    }

    func testTheReleaseWindowIsRecognised() {
        XCTAssertEqual(ScheduleActivityNaming.activity(named: ScheduleActivityNaming.release), .release)
    }

    func testTheTwoPrefixesDoNotCollide() {
        // Both start "dad.", and the allowance name is checked first — so a
        // scheduled window must not be mistaken for an allowance day, or a
        // Mode's schedule would silently hand out minutes instead.
        let id = UUID()
        XCTAssertNotEqual(ScheduleActivityNaming.activity(named: ScheduleActivityNaming.name(modeID: id)),
                          .allowanceDay(modeID: id))
        XCTAssertNotEqual(ScheduleActivityNaming.activity(named: ScheduleActivityNaming.allowanceName(modeID: id)),
                          .scheduledWindow(modeID: id))
    }

    func testAnythingElseIsUnrecognisedRatherThanGuessedAt() {
        for name in ["", "dad.", "dad.schedule.not-a-uuid", "dad.allowance.",
                     ScheduleActivityNaming.allowanceSpent, "com.someone.else"] {
            XCTAssertEqual(ScheduleActivityNaming.activity(named: name), .unrecognised, name)
        }
    }
}

final class ModeAllowanceTests: XCTestCase {

    func testTheBoundsAreWhereTheySay() {
        XCTAssertFalse(ModeAllowance(minutesPerDay: 0).isValid)
        XCTAssertTrue(ModeAllowance(minutesPerDay: 1).isValid)
        XCTAssertTrue(ModeAllowance(minutesPerDay: ModeAllowance.maximumMinutes).isValid)
        XCTAssertFalse(ModeAllowance(minutesPerDay: ModeAllowance.maximumMinutes + 1).isValid)
    }

    func testEveryOfferedLengthIsOneTheEngineWillAccept() {
        for minutes in ModeAllowance.offered {
            XCTAssertTrue(ModeAllowance(minutesPerDay: minutes).isValid, "\(minutes)")
        }
    }

    func testWholeHoursReadAsHours() {
        XCTAssertEqual(ModeAllowance(minutesPerDay: 60).displayText, "1h a day")
        XCTAssertEqual(ModeAllowance(minutesPerDay: 120).displayText, "2h a day")
        XCTAssertEqual(ModeAllowance(minutesPerDay: 45).displayText, "45 min a day")
    }

    func testTheModeSummaryMentionsTheAllowance() {
        var mode = DadMode(name: "Deep Work", symbol: "circle",
                           blocked: BlockedSelection(payload: Data([1]), appCount: 2))
        mode.allowance = ModeAllowance(minutesPerDay: 15)
        XCTAssertTrue(mode.summary.contains("15 min a day"), mode.summary)
    }
}
