import XCTest
@testable import DadCore

/// Where the ladder meets the permission table.
///
/// `AutonomyLadder` computes what has been earned; `RolePermissions` decides
/// what a level buys; `Household` stores what a grown-up granted. Each is
/// tested on its own. These are about the seam, which is where the last defect
/// lived: two modules that each passed their own suite and disagreed about the
/// thing they shared.
final class EarnedAutonomyTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// `count` consecutive days each with one clean session, oldest first.
    private func cleanRun(_ count: Int, endingBefore now: Date) -> [DadSession] {
        (1...max(count, 1)).map { offset in
            let day = now.addingTimeInterval(-Double(offset) * 24 * 60 * 60)
            var s = DadSession(modeID: UUID(), modeName: "Deep Work", startedAt: day)
            s.endedAt = day.addingTimeInterval(3600)
            return s
        }
    }

    private func harness(role: HouseholdRole, granted: Int, history: [DadSession]) -> Harness {
        let h = Harness(now: start)
        h.store.household = Household(role: role, autonomyLevel: granted)
        h.store.history = history
        return h
    }

    // MARK: - Earning pays without anyone doing anything

    func testHoldingTheHabitUnlocksARungWithNobodyPressingAnything() {
        // The promise, end to end: history in, capability out. If this needed
        // a grown-up to notice and act, the reward would not be predictable
        // and the ladder would be decoration.
        let bare = harness(role: .youngPerson, granted: 0, history: [])
        XCTAssertFalse(bare.engine.may(.editMode))

        let steady = harness(role: .youngPerson, granted: 0,
                             history: cleanRun(40, endingBefore: start))
        XCTAssertGreaterThan(steady.engine.autonomyLevel, 0)
        XCTAssertTrue(steady.engine.may(.editMode))
    }

    func testTheEngineAndTheLadderAgreeOnTheLevel() {
        let h = harness(role: .youngPerson, granted: 0,
                        history: cleanRun(40, endingBefore: start))
        XCTAssertEqual(h.engine.autonomyLevel, h.engine.ladder.level)
    }

    // MARK: - A granted floor

    func testAGrownUpMayStartSomebodyHigherThanTheyHaveEarned() {
        let h = harness(role: .youngPerson, granted: 2, history: [])
        XCTAssertEqual(h.engine.ladder.level, 0, "nothing earned yet")
        XCTAssertEqual(h.engine.autonomyLevel, 2)
        XCTAssertTrue(h.engine.may(.changeSchedule))
    }

    func testAFloorSetMonthsAgoDoesNotCapWhatIsEarnedSince() {
        // The failure this guards: a grown-up sets 1 on day one, the young
        // person holds the habit for two months, and the app quietly refuses
        // to hand over anything because the stored number never moved.
        let h = harness(role: .youngPerson, granted: 1,
                        history: cleanRun(70, endingBefore: start))
        XCTAssertGreaterThan(h.engine.autonomyLevel, 1)
        XCTAssertEqual(h.engine.autonomyLevel, h.engine.ladder.level)
    }

    func testALapseCannotReachBelowWhatWasGranted() {
        // A granted rung is a decision between two people, and arithmetic does
        // not get to undo a conversation.
        let longAgo = start.addingTimeInterval(-120 * 24 * 60 * 60)
        let h = harness(role: .youngPerson, granted: 2,
                        history: cleanRun(40, endingBefore: longAgo))
        XCTAssertTrue(h.engine.ladder.isWithheld, "this test needs a real lapse")
        XCTAssertGreaterThanOrEqual(h.engine.autonomyLevel, 2)
        XCTAssertTrue(h.engine.may(.changeSchedule))
    }

    // MARK: - Grown-ups

    func testAGrownUpIsNotScored() {
        // Running the ladder over an adult's own history would be
        // scorekeeping nobody asked for, and they hold everything anyway.
        //
        // The history here is deliberately long and clean: with an empty one
        // the ladder returns zero and the guard is invisible, which is exactly
        // how the first version of this test let a mutation through.
        let h = harness(role: .grownUp, granted: 0,
                        history: cleanRun(70, endingBefore: start))
        XCTAssertGreaterThan(h.engine.ladder.level, 0, "the ladder would score them")
        XCTAssertEqual(h.engine.autonomyLevel, 0, "and the engine declines to")

        for capability in HouseholdCapability.allCases {
            XCTAssertTrue(h.engine.may(capability), "\(capability)")
        }
    }

    // MARK: - The seam itself

    func testEveryLevelTheLadderCanProduceIsOneThePermissionTableUnderstands() {
        // The shape of the bug that made this file necessary: the ladder
        // produced a level the permission table treated as unreadable, and the
        // young person at the top of the ladder was silently returned to the
        // bottom.
        for rung in AutonomyLadder.Rung.allCases {
            XCTAssertEqual(RolePermissions.normalisedLevel(rung.rawValue), rung.rawValue,
                           "\(rung.title) is not a level permissions understand")
        }
    }

    func testTheTopOfTheLadderIsWhereTheProductEnds() {
        // A young person at the top runs Dad the way an adult does, bar the
        // one thing that is a conversation rather than a toggle.
        let top = AutonomyLadder.Rung.allCases.last!.rawValue
        let h = harness(role: .youngPerson, granted: top, history: [])
        for capability in HouseholdCapability.allCases where capability != .turnDadOff {
            XCTAssertTrue(h.engine.may(capability), "\(capability) at the top rung")
        }
        XCTAssertFalse(h.engine.may(.turnDadOff))
    }
}

/// The rungs that widen the emergency allowance actually widen it.
///
/// Found by review. `AutonomyLadder.Rung.selfGoverning.unlocks` told the young
/// person the rung bought "a wider emergency Un-Dad allowance", and
/// `emergencyAllowance` computed 7 for it — but nothing read either property.
/// `EmergencyAllowance.remaining` was hard-wired to five, Settings rendered
/// "of 5", and the sixth override was refused. The rung's own test asserted
/// the ladder's arithmetic against itself and never asked the engine, which is
/// exactly how the rung-count bug survived too.
final class EmergencyCeilingTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func harness(role: HouseholdRole, level: Int) -> Harness {
        let h = Harness(now: start)
        h.store.household = Household(role: role, autonomyLevel: level)
        return h
    }

    func testTheCeilingTheEngineUsesIsTheOneTheRungPromises() {
        for rung in AutonomyLadder.Rung.allCases {
            let h = harness(role: .youngPerson, level: rung.rawValue)
            XCTAssertEqual(h.engine.emergencyCeiling, rung.emergencyAllowance,
                           "\(rung.title) promises \(rung.emergencyAllowance)")
        }
    }

    func testAWidenedAllowanceCanActuallyBeSpent() {
        // The failure as a user meets it: the screen says the allowance grew,
        // and the sixth press does nothing.
        let top = AutonomyLadder.Rung.allCases.last!
        XCTAssertGreaterThan(top.emergencyAllowance, EmergencyAllowance.perWindow,
                             "this test is only meaningful if the top rung widens it")

        let h = harness(role: .youngPerson, level: top.rawValue)
        let mode = h.addMode()

        for use in 1...top.emergencyAllowance {
            h.engine.dad(with: mode)
            XCTAssertTrue(h.engine.emergencyUnDad(), "override \(use) of \(top.emergencyAllowance)")
        }
        h.engine.dad(with: mode)
        XCTAssertFalse(h.engine.emergencyUnDad(), "and the one past the ceiling is refused")
    }

    func testTheCountShownAgreesWithTheCountAllowed() {
        let top = AutonomyLadder.Rung.allCases.last!
        let h = harness(role: .youngPerson, level: top.rawValue)
        XCTAssertEqual(h.engine.emergencyUnDadsRemaining, top.emergencyAllowance)

        h.engine.dad(with: h.addMode())
        h.engine.emergencyUnDad()
        XCTAssertEqual(h.engine.emergencyUnDadsRemaining, top.emergencyAllowance - 1)
    }

    func testAGrownUpGetsTheBaseAllowance() {
        // They are not on a ladder, and widening an allowance nobody is
        // metering would mean nothing.
        let h = harness(role: .grownUp, level: 0)
        XCTAssertEqual(h.engine.emergencyCeiling, EmergencyAllowance.perWindow)
    }

    func testTheBottomRungIsStillFive() {
        let h = harness(role: .youngPerson, level: 0)
        XCTAssertEqual(h.engine.emergencyCeiling, EmergencyAllowance.perWindow)
    }
}

/// The ratchet has to be a stored fact, not a property of how much history fits.
///
/// Found by review. `AutonomyLadder` promises a high-water mark that "can only
/// ever go up, so no amount of future history, and no passage of time, can take
/// an earned rung away". It reads `store.history`, which `archive` truncates to
/// 500 sessions — so above roughly eight sessions a day, which is exactly what a
/// rationed Mode produces, the oldest clean days fell off the end and the mark
/// dropped. Instantaneously, and invisibly: `withheldRungs` stayed zero, so
/// nothing warned, which is the one thing `DemotionWarning` exists to prevent.
final class LadderRatchetTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func harness() -> Harness {
        let h = Harness(now: start)
        h.store.household = Household(role: .youngPerson, autonomyLevel: 0)
        return h
    }

    /// One clean, person-ended session per day, oldest first.
    private func day(_ offsetFromStart: Int) -> DadSession {
        let at = start.addingTimeInterval(Double(offsetFromStart) * 24 * 60 * 60)
        var s = DadSession(modeID: UUID(), modeName: "Deep Work", startedAt: at)
        s.endedAt = at.addingTimeInterval(3600)
        s.endedBy = .tapped
        return s
    }

    func testARungIsRecordedTheMomentItIsEarned() {
        let h = harness()
        h.store.history = (0..<40).map(day)
        h.clock.now = start.addingTimeInterval(41 * 24 * 60 * 60)
        XCTAssertEqual(h.store.household.autonomyLevel, 0, "nothing written yet")

        // Any finished session archives, which is the one moment the ladder's
        // inputs change.
        let mode = h.addMode()
        h.engine.dad(with: mode)
        h.engine.handleTap()

        XCTAssertGreaterThan(h.store.household.autonomyLevel, 0)
        XCTAssertEqual(h.store.household.autonomyLevel, h.engine.ladder.level)
    }

    func testHistoryFallingOffTheEndCannotTakeARungBack() {
        // The failure, reproduced: fill the history to its cap with recent,
        // frequent sessions so the older clean days are gone.
        let h = harness()
        h.store.history = (0..<60).map(day)
        h.clock.now = start.addingTimeInterval(61 * 24 * 60 * 60)
        let mode = h.addMode()
        h.engine.dad(with: mode)
        h.engine.handleTap()
        let earned = h.store.household.autonomyLevel
        XCTAssertGreaterThan(earned, 0, "this test needs a rung to have been earned")

        // Now bury it: many sessions on one day, enough to push the cap.
        var recent: [DadSession] = []
        for i in 0..<DadEngine.historyLimit {
            let at = h.clock.now.addingTimeInterval(Double(i) * 60)
            var s = DadSession(modeID: mode.id, modeName: mode.name, startedAt: at)
            s.endedAt = at.addingTimeInterval(30)
            s.endedBy = .tapped
            recent.append(s)
        }
        h.store.history = Array((h.store.history + recent).suffix(DadEngine.historyLimit))
        XCTAssertLessThan(h.engine.ladder.level, earned,
                          "the ladder alone would now demote — that is the bug")

        XCTAssertEqual(h.engine.autonomyLevel, earned, "but the engine remembers")
        XCTAssertTrue(h.engine.may(.editMode))
    }

    func testTheRecordedRungIsNeverAboveWhatThePermissionTableUnderstands() {
        let h = harness()
        h.store.history = (0..<200).map(day)
        h.clock.now = start.addingTimeInterval(201 * 24 * 60 * 60)
        let mode = h.addMode()
        h.engine.dad(with: mode)
        h.engine.handleTap()

        XCTAssertEqual(h.store.household.autonomyLevel,
                       RolePermissions.normalisedLevel(h.store.household.autonomyLevel))
    }

    func testAGrownUpsLevelIsNeverWrittenTo() {
        let h = Harness(now: start)
        h.store.history = (0..<200).map(day)
        h.clock.now = start.addingTimeInterval(201 * 24 * 60 * 60)
        let mode = h.addMode()
        h.engine.dad(with: mode)
        h.engine.handleTap()

        XCTAssertEqual(h.store.household.autonomyLevel, 0)
    }
}

/// A rung's copy and a rung's effect cannot disagree, because there is one of
/// them.
final class RungPermissionAgreementTests: XCTestCase {

    func testTheRungBooleansAreTheSameTableTheEngineConsults() {
        // These were four hand-written comparisons against rung numbers — a
        // second permission table, read by nothing but its own tests, which
        // had already drifted: `canCreateModes` claimed rung three while the
        // engine charged a new Mode to `editMode` at rung one.
        for rung in AutonomyLadder.Rung.allCases {
            let permissions = RolePermissions.for(role: .youngPerson, autonomyLevel: rung.rawValue)
            XCTAssertEqual(rung.canEditModeApps, permissions.may(.editMode), rung.title)
            XCTAssertEqual(rung.canSetOwnSleepWindow, permissions.may(.changeSchedule), rung.title)
            XCTAssertEqual(rung.canCreateModes, permissions.may(.deleteMode), rung.title)
            XCTAssertEqual(rung.keepsTheTag, permissions.may(.unpairTag), rung.title)
        }
    }

    func testWhatARungSaysItUnlocksIsWhatThatRungIsFirstToGrant() {
        // The titles are what somebody reads, so each capability must first
        // appear at the rung whose copy claims it.
        XCTAssertTrue(AutonomyLadder.Rung.trusted.canEditModeApps)
        XCTAssertFalse(AutonomyLadder.Rung.gettingStarted.canEditModeApps)
        XCTAssertTrue(AutonomyLadder.Rung.selfScheduling.canSetOwnSleepWindow)
        XCTAssertFalse(AutonomyLadder.Rung.trusted.canSetOwnSleepWindow)
        XCTAssertTrue(AutonomyLadder.Rung.keeperOfTheTag.keepsTheTag)
        XCTAssertFalse(AutonomyLadder.Rung.selfGoverning.keepsTheTag)
    }
}
