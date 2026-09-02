import XCTest
@testable import DadCore

/// The state machine that is the whole product. Before the ports-and-adapters
/// split none of this could be exercised at all.
final class DadEngineTests: XCTestCase {

    // MARK: - Toggling

    func testTapStartsASessionAndAppliesTheShield() {
        let h = Harness()
        let mode = h.addMode()

        let result = h.engine.handleTap()

        XCTAssertEqual(result, .dadded(mode: mode))
        XCTAssertEqual(h.store.activeSession?.modeID, mode.id)
        XCTAssertEqual(h.store.activeSession?.startedAt, h.clock.now)
        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testSecondTapReleasesAndArchivesTheSession() {
        let h = Harness()
        h.addMode()
        h.engine.handleTap()

        h.clock.advance(90 * 60)
        let result = h.engine.handleTap()

        guard case .unDadded(let session) = result else {
            return XCTFail("expected .unDadded, got \(result)")
        }
        XCTAssertEqual(session.duration, 90 * 60)
        XCTAssertFalse(session.endedByEmergency)
        XCTAssertNil(h.store.activeSession)
        XCTAssertEqual(h.store.history.count, 1)
        XCTAssertNil(h.shield.appliedMode, "the shield must come down")
        XCTAssertEqual(h.scheduler.cancelCount, 1)
    }

    func testReleasingIgnoresAPreferredMode() {
        // A tap while Dadded can only mean "release" — a Mode attached to the
        // automation must not start a second session.
        let h = Harness()
        h.addMode(name: "A")
        let other = h.addMode(name: "B")
        h.engine.handleTap(preferredMode: h.store.modes[0])

        let result = h.engine.handleTap(preferredMode: other)

        guard case .unDadded = result else { return XCTFail("expected .unDadded") }
        XCTAssertNil(h.store.activeSession)
    }

    // MARK: - Choosing a Mode

    func testASingleUsableModeIsChosenAutomatically() {
        let h = Harness()
        let usable = h.addMode(name: "Deep Work")
        h.addEmptyMode()   // present but blocks nothing, so not a candidate

        XCTAssertEqual(h.engine.handleTap(), .dadded(mode: usable))
    }

    func testAmbiguousModesAskTheUser() {
        let h = Harness()
        h.addMode(name: "A")
        h.addMode(name: "B")

        XCTAssertEqual(h.engine.handleTap(), .needsModeChoice)
        XCTAssertNil(h.store.activeSession)
        XCTAssertTrue(h.shield.calls.isEmpty, "nothing should be shielded yet")
    }

    func testNoUsableModeAsksTheUser() {
        let h = Harness()
        h.addEmptyMode()

        XCTAssertEqual(h.engine.handleTap(), .needsModeChoice)
        XCTAssertNil(h.store.activeSession)
    }

    func testAnEmptyModeNeverStartsASession() {
        // Starting a session that blocks nothing would look like it worked
        // and do nothing at all — the worst possible outcome.
        let h = Harness()
        let empty = h.addEmptyMode()

        XCTAssertEqual(h.engine.handleTap(preferredMode: empty), .needsModeChoice)
        XCTAssertNil(h.store.activeSession)
        XCTAssertTrue(h.shield.calls.isEmpty)
    }

    // MARK: - Tag pairing

    func testAnyTagWorksBeforeOneIsPaired() {
        let h = Harness()
        h.addMode()

        guard case .dadded = h.engine.handleTap(tagUID: "DEADBEEF") else {
            return XCTFail("an unpaired install should accept any tag")
        }
    }

    func testAPairedTagIsAccepted() {
        let h = Harness()
        h.addMode()
        h.engine.pair(tagUID: "ABC123")

        guard case .dadded = h.engine.handleTap(tagUID: "ABC123") else {
            return XCTFail("expected the paired tag to work")
        }
    }

    func testAnUnknownTagChangesNothing() {
        let h = Harness()
        h.addMode()
        h.engine.pair(tagUID: "ABC123")

        XCTAssertEqual(h.engine.handleTap(tagUID: "OTHER"), .unknownTag)
        XCTAssertNil(h.store.activeSession)
        XCTAssertTrue(h.shield.calls.isEmpty)
    }

    func testAnUnknownTagCannotReleaseAnActiveSession() {
        // The important direction: a stranger's tag must not un-Dad you.
        let h = Harness()
        h.addMode()
        h.engine.pair(tagUID: "MINE")
        h.engine.handleTap(tagUID: "MINE")

        XCTAssertEqual(h.engine.handleTap(tagUID: "THEIRS"), .unknownTag)
        XCTAssertNotNil(h.store.activeSession, "still Dadded")
        XCTAssertEqual(h.shield.appliedMode, h.store.modes[0].id)
    }

    func testPairingIsIdempotent() {
        let h = Harness()
        h.engine.pair(tagUID: "ABC")
        h.engine.pair(tagUID: "ABC")
        XCTAssertEqual(h.store.pairedTagUIDs, ["ABC"])
    }

    // MARK: - Timed release

    func testNoScheduleWhenTheModeRunsUntilTapped() {
        let h = Harness()
        h.addMode(autoRelease: nil)
        h.engine.handleTap()
        XCTAssertTrue(h.scheduler.scheduled.isEmpty)
    }

    func testTimedModeSchedulesItsRelease() {
        let h = Harness()
        h.addMode(autoRelease: 60 * 60)
        h.engine.handleTap()

        XCTAssertEqual(h.scheduler.scheduled, [h.clock.now.addingTimeInterval(60 * 60)])
    }

    func testShortDurationsAreRaisedToTheSchedulerMinimum() {
        // DeviceActivity won't monitor an interval under 15 minutes. Rounding
        // up is honest; scheduling something that never fires is not.
        let h = Harness()
        h.addMode(autoRelease: 60)
        h.engine.handleTap()

        XCTAssertEqual(h.scheduler.scheduled,
                       [h.clock.now.addingTimeInterval(DadEngine.minimumScheduledRelease)])
    }

    // MARK: - Emergency overrides

    func testEmergencyReleaseSpendsOneAndMarksTheSession() {
        let h = Harness()
        h.addMode()
        h.engine.handleTap()

        XCTAssertTrue(h.engine.emergencyUnDad())
        XCTAssertNil(h.store.activeSession)
        XCTAssertEqual(h.store.history.first?.endedByEmergency, true)
        XCTAssertEqual(h.engine.emergencyUnDadsRemaining, EmergencyAllowance.perWindow - 1)
        XCTAssertNil(h.shield.appliedMode)
    }

    func testExhaustedAllowanceLeavesThePhoneDadded() {
        // The one that matters: a failed override must not half-release.
        let h = Harness()
        h.addMode()
        h.store.emergencyUses = (0..<EmergencyAllowance.perWindow).map {
            h.clock.now.addingTimeInterval(-Double($0) * 3600)
        }
        h.engine.handleTap()

        XCTAssertFalse(h.engine.emergencyUnDad())
        XCTAssertNotNil(h.store.activeSession, "must stay Dadded")
        XCTAssertEqual(h.shield.appliedMode, h.store.modes[0].id, "the shield must stay up")
        XCTAssertEqual(h.store.history.count, 0, "nothing archived")
    }

    func testEmergencyWhenNotDaddedCostsNothing() {
        let h = Harness()
        XCTAssertTrue(h.engine.emergencyUnDad())
        XCTAssertEqual(h.engine.emergencyUnDadsRemaining, EmergencyAllowance.perWindow)
    }

    func testAllowanceComesBackAfterThirtyDays() {
        let h = Harness()
        h.store.emergencyUses = (0..<EmergencyAllowance.perWindow).map { _ in h.clock.now }
        XCTAssertEqual(h.engine.emergencyUnDadsRemaining, 0)

        h.clock.advance(days: 31)
        XCTAssertEqual(h.engine.emergencyUnDadsRemaining, EmergencyAllowance.perWindow)
    }

    // MARK: - Reconciliation

    func testReconcileRestoresAShieldLostToACrash() {
        let h = Harness()
        let mode = h.addMode()
        h.store.activeSession = DadSession(modeID: mode.id, modeName: mode.name, startedAt: h.clock.now)

        h.engine.reconcile()

        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testReconcileClearsAShieldWithNoSessionBehindIt() {
        // The dangerous direction: apps blocked with nothing in the app able
        // to release them.
        let h = Harness()
        h.engine.reconcile()
        XCTAssertEqual(h.shield.calls, [.clear])
    }

    func testReconcileEndsASessionWhoseModeWasDeleted() {
        let h = Harness()
        let mode = h.addMode()
        h.engine.handleTap()
        h.engine.deleteMode(id: mode.id)

        h.engine.reconcile()

        XCTAssertNil(h.store.activeSession)
        XCTAssertNil(h.shield.appliedMode)
        XCTAssertEqual(h.store.history.count, 1)
    }

    // MARK: - History

    func testHistoryIsBoundedAndKeepsTheNewest() {
        let h = Harness()
        h.addMode()
        let overflow = DadEngine.historyLimit + 10
        h.store.history = (0..<overflow).map { i in
            DadSession(modeID: UUID(), modeName: "old \(i)",
                       startedAt: h.clock.now, endedAt: h.clock.now)
        }

        h.engine.handleTap()
        h.engine.handleTap()

        XCTAssertEqual(h.store.history.count, DadEngine.historyLimit)
        XCTAssertEqual(h.store.history.last?.modeName, "Deep Work", "newest kept")
        XCTAssertNotEqual(h.store.history.first?.modeName, "old 0", "oldest dropped")
    }

    // MARK: - Modes

    func testUpsertAddsThenReplaces() {
        let h = Harness()
        var mode = DadMode(name: "Work", symbol: "circle")
        h.engine.upsert(mode)
        XCTAssertEqual(h.store.modes.count, 1)

        mode.name = "Deep Work"
        h.engine.upsert(mode)
        XCTAssertEqual(h.store.modes.count, 1, "same id must replace, not append")
        XCTAssertEqual(h.store.modes.first?.name, "Deep Work")
    }

    func testDeleteMode() {
        let h = Harness()
        let mode = h.addMode()
        h.engine.deleteMode(id: mode.id)
        XCTAssertTrue(h.store.modes.isEmpty)
    }
}

/// `dad(with:)` is reachable from the App Intents as well as from `handleTap`,
/// so it has to behave when called in states `handleTap` would have screened out.
final class DadEngineDirectStartTests: XCTestCase {

    func testStartingWhileAlreadyDaddedClosesOutTheOldSession() {
        let h = Harness()
        let first = h.addMode(name: "A")
        let second = h.addMode(name: "B")

        h.engine.dad(with: first)
        h.clock.advance(10 * 60)
        h.engine.dad(with: second)

        XCTAssertEqual(h.store.history.count, 1, "the first session must not vanish")
        XCTAssertEqual(h.store.history.first?.modeName, "A")
        XCTAssertEqual(h.store.history.first?.duration, 10 * 60)
        XCTAssertEqual(h.store.activeSession?.modeID, second.id)
        XCTAssertEqual(h.shield.appliedMode, second.id)
    }

    func testStartingWhileAlreadyDaddedDoesNotSpendAnOverride() {
        let h = Harness()
        h.engine.dad(with: h.addMode(name: "A"))
        h.engine.dad(with: h.addMode(name: "B"))
        XCTAssertEqual(h.engine.emergencyUnDadsRemaining, EmergencyAllowance.perWindow)
    }
}
