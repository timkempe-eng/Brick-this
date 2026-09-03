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
