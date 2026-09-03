import XCTest
@testable import DadCore

/// The permission model is a set of decisions about what a household agreed
/// to, so these tests pin the decisions rather than the shape of the code: who
/// may do what at each rung, what an unreadable value falls back to, and who
/// may move the rung at all.
///
/// The two failure modes worth naming, because both are silent: a capability
/// that ends up granted to everybody because a new rung was added without
/// thinking about it, and a permission set that drifts from the rules that
/// produced it. The first is caught by pinning every rung; the second by there
/// being nothing to store.
final class HouseholdTests: XCTestCase {

    private func youngPerson(at level: Int) -> RolePermissions {
        .for(role: .youngPerson, autonomyLevel: level)
    }

    private func grownUp(at level: Int = 0) -> RolePermissions {
        .for(role: .grownUp, autonomyLevel: level)
    }

    private var top: Int { RolePermissions.maxAutonomyLevel }

    // MARK: - A grown-up on their own phone

    func testAGrownUpMayDoEverything() {
        for capability in HouseholdCapability.allCases {
            XCTAssertTrue(grownUp().may(capability),
                          "a grown-up Dadding their own phone is not being governed by anything")
        }
    }

    func testAGrownUpsPermissionsIgnoreTheAutonomyLevel() {
        // Including levels that are not on the ladder at all — the number is
        // inert for this role, not merely clamped.
        for level in [-1, 0, 1, top, 99] {
            XCTAssertEqual(grownUp(at: level).allowed,
                           Set(HouseholdCapability.allCases),
                           "level \(level) changed a grown-up's permissions")
        }
    }

    // MARK: - The bottom of the ladder

    func testAYoungPersonMayAlwaysSpendAnEmergencyOverride() {
        // The allowance is a safety valve, not a privilege: a phone that can
        // never be Un-Dadded is a phone that cannot call anyone.
        for level in RolePermissions.autonomyLevels {
            XCTAssertTrue(youngPerson(at: level).may(.spendEmergencyOverride),
                          "level \(level) took away the only way out")
        }
    }

    func testTheBottomRungGrantsNothingButTheEmergencyOverride() {
        XCTAssertEqual(youngPerson(at: 0).allowed, [.spendEmergencyOverride])
    }

    // MARK: - The rungs

    func testChangingWhatIsInAModeUnlocksBeforeMovingItsWindow() {
        // This ordering is the ladder's, not this table's, and it was the
        // other way round until the two were compared: `AutonomyLadder` tells
        // the young person that rung 1 is "Trusted — choose which apps each
        // Mode takes away" and rung 2 is "Self-scheduling — set your own Sleep
        // window". A rung that promises one thing and pays another is a broken
        // promise, and the titles are what somebody reads.
        XCTAssertTrue(youngPerson(at: 1).may(.editMode))
        XCTAssertFalse(youngPerson(at: 1).may(.changeSchedule))
        XCTAssertFalse(youngPerson(at: 0).may(.editMode))
        XCTAssertTrue(youngPerson(at: 2).may(.changeSchedule))
    }

    func testDeletingAModeCostsMoreThanEditingOne() {
        // They used to unlock together, on the argument that a Mode you can
        // edit is a Mode you can empty. True, and it is the *visibility* that
        // separates them: an emptied Mode still reads "Nothing blocked yet" in
        // the list, where a deleted one leaves no row to read at all.
        XCTAssertEqual(RolePermissions.minimumAutonomyLevel(for: .editMode), 1)
        XCTAssertEqual(RolePermissions.minimumAutonomyLevel(for: .deleteMode), 3)
        XCTAssertTrue(youngPerson(at: 3).may(.deleteMode))
        XCTAssertFalse(youngPerson(at: 2).may(.deleteMode))
    }

    func testTheAllowanceAndTheTagAreTheLastThingsToUnlock() {
        // Both are misuse that leaves no trace on the Modes list: a raised
        // allowance looks like nothing, and a tag paired in a pocket ends the
        // arrangement without changing a single Mode.
        XCTAssertFalse(youngPerson(at: 2).may(.changeAllowance))
        XCTAssertFalse(youngPerson(at: 2).may(.unpairTag))
        XCTAssertTrue(youngPerson(at: top).may(.changeAllowance))
        XCTAssertTrue(youngPerson(at: top).may(.unpairTag))
    }

    func testNoRungEverLetsAYoungPersonTurnDadOff() {
        for level in RolePermissions.autonomyLevels {
            XCTAssertFalse(youngPerson(at: level).may(.turnDadOff),
                           "level \(level) unlocked the off switch")
        }
        XCTAssertNil(RolePermissions.minimumAutonomyLevel(for: .turnDadOff))
    }

    func testTheTopRungIsEverythingExceptTurningDadOff() {
        // The exit from the top of the ladder is the role changing, which two
        // people agree to. It is not one more toggle.
        XCTAssertEqual(youngPerson(at: top).allowed,
                       Set(HouseholdCapability.allCases).subtracting([.turnDadOff]))
    }

    func testTurningDadOffIsTheOnlyCapabilityOffTheLadder() {
        let unreachable = HouseholdCapability.allCases
            .filter { RolePermissions.minimumAutonomyLevel(for: $0) == nil }
        XCTAssertEqual(Set(unreachable), [.turnDadOff])
    }

    func testPermissionsOnlyEverGrowWithTheLevel() {
        // A ladder that takes something away on the way up is not a ladder,
        // and would be indistinguishable from a table someone edited wrongly.
        for level in RolePermissions.autonomyLevels.dropFirst() {
            XCTAssertTrue(youngPerson(at: level).allowed.isSuperset(of: youngPerson(at: level - 1).allowed),
                          "level \(level) removed something level \(level - 1) had")
        }
    }

    func testEveryRungUnlocksSomething() {
        // Guards against a rung that exists in the range but grants exactly
        // what the one below it grants — a level that looks earned and does
        // nothing.
        for level in RolePermissions.autonomyLevels.dropFirst() {
            XCTAssertNotEqual(youngPerson(at: level).allowed, youngPerson(at: level - 1).allowed,
                              "level \(level) is indistinguishable from level \(level - 1)")
        }
    }

    func testEveryRungOfTheLadderIsReachable() {
        for capability in HouseholdCapability.allCases {
            guard let minimum = RolePermissions.minimumAutonomyLevel(for: capability) else { continue }
            XCTAssertTrue(RolePermissions.autonomyLevels.contains(minimum),
                          "\(capability) unlocks at level \(minimum), which is not on the ladder")
        }
    }

    // MARK: - Levels this build cannot read

    func testALevelAboveTheLadderFallsToTheBottomRatherThanTheTop() {
        // A rung invented by a later build is not evidence of trust this build
        // can act on. Guessing high hands out permissions nobody agreed to.
        XCTAssertEqual(youngPerson(at: top + 1).allowed, youngPerson(at: 0).allowed)
        XCTAssertEqual(RolePermissions.normalisedLevel(99), 0)
    }

    func testANegativeLevelFallsToTheBottom() {
        XCTAssertEqual(youngPerson(at: -3).allowed, youngPerson(at: 0).allowed)
        XCTAssertEqual(RolePermissions.normalisedLevel(-1), 0)
    }

    func testALevelOnTheLadderIsLeftAlone() {
        for level in RolePermissions.autonomyLevels {
            XCTAssertEqual(RolePermissions.normalisedLevel(level), level)
        }
    }

    // MARK: - Who may move the level

    func testAGrownUpMayAlwaysLowerALevel() {
        let phone = Household(role: .youngPerson, autonomyLevel: top)
        XCTAssertTrue(phone.mayChangeAutonomyLevel(to: 0, by: .grownUp))
    }

    func testAGrownUpMayRaiseALevel() {
        let phone = Household(role: .youngPerson, autonomyLevel: 0)
        XCTAssertTrue(phone.mayChangeAutonomyLevel(to: top, by: .grownUp))
    }

    func testAYoungPersonMayNotRaiseTheirOwnLevel() {
        let phone = Household(role: .youngPerson, autonomyLevel: 1)
        XCTAssertFalse(phone.mayChangeAutonomyLevel(to: 2, by: .youngPerson))
    }

    func testAYoungPersonMayNotLowerTheirOwnLevelEither() {
        // Giving up permissions harms nobody, but a number that moves without
        // the grown-up knowing is no longer a record of an agreement — and it
        // moves in the direction that reads as progress being lost.
        let phone = Household(role: .youngPerson, autonomyLevel: 2)
        XCTAssertFalse(phone.mayChangeAutonomyLevel(to: 1, by: .youngPerson))
    }

    func testSavingWithoutMovingTheSliderIsNotAPermissionError() {
        // Refusing a no-op teaches callers to skip the guard entirely.
        let phone = Household(role: .youngPerson, autonomyLevel: 2)
        XCTAssertTrue(phone.mayChangeAutonomyLevel(to: 2, by: .youngPerson))
        XCTAssertTrue(phone.mayChangeAutonomyLevel(to: 2, by: .grownUp))
    }

    func testNobodyMaySetALevelThatIsNotOnTheLadder() {
        // Not even a grown-up: the stored number would read back as 0, which
        // is a setting that looks applied and quietly isn't.
        let phone = Household(role: .youngPerson, autonomyLevel: 1)
        XCTAssertFalse(phone.mayChangeAutonomyLevel(to: top + 1, by: .grownUp))
        XCTAssertFalse(phone.mayChangeAutonomyLevel(to: -1, by: .grownUp))
    }

    func testAChangeKnowsWhichWayItIsGoing() {
        XCTAssertTrue(AutonomyLevelChange(from: 1, to: 2).isRaising)
        XCTAssertTrue(AutonomyLevelChange(from: 2, to: 1).isLowering)
        XCTAssertTrue(AutonomyLevelChange(from: 2, to: 2).isNoOp)
        XCTAssertFalse(AutonomyLevelChange(from: 2, to: 2).isRaising)
        XCTAssertFalse(AutonomyLevelChange(from: 2, to: 2).isLowering)
    }

    // MARK: - Applying a change

    func testARefusedChangeLeavesTheHouseholdUntouched() {
        let phone = Household(role: .youngPerson, autonomyLevel: 1)
        XCTAssertNil(phone.changingAutonomyLevel(to: 3, by: .youngPerson))
        XCTAssertEqual(phone.autonomyLevel, 1, "the value must be impossible to half-apply")
    }

    func testAnAcceptedChangeReturnsTheNewLevelAndKeepsTheRole() {
        let phone = Household(role: .youngPerson, autonomyLevel: 1)
        let raised = phone.changingAutonomyLevel(to: 2, by: .grownUp)
        XCTAssertEqual(raised, Household(role: .youngPerson, autonomyLevel: 2))
        XCTAssertTrue(raised?.may(.changeSchedule) ?? false, "the derived permissions must move with it")
    }

    // MARK: - The household itself

    func testAFreshInstallIsOneGrownUpAtTheBottomOfTheLadder() {
        XCTAssertEqual(Household.solo.role, .grownUp)
        XCTAssertEqual(Household.solo.autonomyLevel, 0,
                       "the rung a phone inherits the day it changes hands should be the bottom one")
        XCTAssertTrue(Household.solo.may(.turnDadOff))
    }

    func testAPhoneHandedToAGrownUpAndBackKeepsItsRung() {
        var phone = Household(role: .youngPerson, autonomyLevel: 2)
        phone.role = .grownUp
        XCTAssertTrue(phone.may(.turnDadOff))

        phone.role = .youngPerson
        XCTAssertEqual(phone.autonomyLevel, 2, "an afternoon as a grown-up must not erase months of ladder")
        XCTAssertTrue(phone.may(.changeSchedule))
        XCTAssertFalse(phone.may(.unpairTag))
    }

    // MARK: - Storage

    func testAHouseholdRoundTripsThroughJSON() throws {
        let phone = Household(role: .youngPerson, autonomyLevel: 2)
        let data = try JSONEncoder().encode(phone)
        XCTAssertEqual(try JSONDecoder().decode(Household.self, from: data), phone)
    }

    func testAnUnknownStoredRoleReadsAsAGrownUp() throws {
        // A role written by a newer build. Guessing `youngPerson` would leave a
        // solo adult unable to turn Dad off, unpair the tag or edit a Mode,
        // with no grown-up to ask — a bricked phone with no way out. Guessing
        // `grownUp` costs a conversation instead.
        let data = Data(#"{"role":"guardianAngel","autonomyLevel":0}"#.utf8)
        let phone = try JSONDecoder().decode(Household.self, from: data)
        XCTAssertEqual(phone.role, .grownUp)
        XCTAssertTrue(phone.may(.turnDadOff))
    }

    func testAKnownStoredRoleIsNotSwallowedByTheFallback() {
        // The fallback must only catch strings this build genuinely cannot
        // read — otherwise every young person's phone quietly becomes an
        // adult's.
        let data = Data(#"{"role":"youngPerson","autonomyLevel":3}"#.utf8)
        let phone = try? JSONDecoder().decode(Household.self, from: data)
        XCTAssertEqual(phone?.role, .youngPerson)
        XCTAssertFalse(phone?.may(.turnDadOff) ?? true)
    }
}
