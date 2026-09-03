import XCTest
@testable import DadCore

/// The arrangement, enforced where it cannot be routed around.
///
/// `Household.swift` decides *what* a role may do. These tests are about
/// *where* that decision is applied, which is the part that actually protects
/// anyone: hiding a control in the UI is a lock on the door of a room with no
/// walls, because an App Intent run from a Shortcut reaches the same engine
/// with no view in between. So every refusal below is asserted against
/// `DadEngine`, not against a view model.
///
/// The other half of each test is that a refusal is *named*. A control that
/// silently does nothing teaches a young person the app is broken, and an app
/// they think is broken is one they go around.
final class HouseholdEnforcementTests: XCTestCase {

    private func harness(role: HouseholdRole, level: Int) -> Harness {
        let h = Harness()
        h.store.household = Household(role: role, autonomyLevel: level)
        return h
    }

    // MARK: - The shipped product is unchanged

    func testASoloAdultIsRefusedNothingTheyCouldDoBefore() {
        // Every install before households existed decodes as `.solo`, and this
        // is the test that says so out loud: adding roles must not quietly
        // take a capability away from someone who never asked for a role.
        let h = Harness()
        XCTAssertEqual(h.store.household, .solo)
        let mode = h.addMode()

        XCTAssertNil(h.engine.upsert(mode))
        XCTAssertNil(h.engine.deleteMode(id: mode.id))
        XCTAssertNil(h.engine.forgetAllTags())
        for capability in HouseholdCapability.allCases where capability != .turnDadOff {
            XCTAssertTrue(h.engine.may(capability), "\(capability)")
        }
    }

    // MARK: - A young person at the bottom of the ladder

    func testEditingAModeIsRefusedAndNamed() {
        let h = harness(role: .youngPerson, level: 0)
        var mode = h.addMode()
        mode.name = "Renamed"

        XCTAssertEqual(h.engine.upsert(mode), .editMode)
        XCTAssertEqual(h.store.modes.first?.name, "Deep Work", "and nothing changed")
    }

    func testDeletingAModeIsRefusedAndTheModeSurvives() {
        let h = harness(role: .youngPerson, level: 0)
        let mode = h.addMode()

        XCTAssertEqual(h.engine.deleteMode(id: mode.id), .deleteMode)
        XCTAssertEqual(h.store.modes.count, 1)
    }

    func testUnpairingTheTagIsRefused() {
        // With no tag paired, any tag works — and any tag is a sticker you can
        // buy. Forgetting the pairing is how a phone leaves the arrangement.
        let h = harness(role: .youngPerson, level: 0)
        h.engine.pair(tagUID: "DEADBEEF")

        XCTAssertEqual(h.engine.forgetAllTags(), .unpairTag)
        XCTAssertEqual(h.store.tags.uids, ["DEADBEEF"])
    }

    // MARK: - The rungs actually differ

    func testAScheduleChangeIsChargedToTheScheduleCapabilityNotTheBroaderOne() {
        // If a schedule edit needed `editMode`, the rung that hands out
        // schedules would do the work of three and the ladder would collapse
        // into one step.
        let h = harness(role: .youngPerson, level: 0)
        var mode = h.addMode()
        mode.schedule = ModeSchedule(startHour: 22, startMinute: 0,
                                     endHour: 7, endMinute: 0,
                                     weekdays: ModeSchedule.everyDay)

        XCTAssertEqual(h.engine.upsert(mode), .changeSchedule)
    }

    func testAnAllowanceChangeIsChargedToItsOwnCapability() {
        let h = harness(role: .youngPerson, level: 0)
        var mode = h.addMode()
        mode.allowance = ModeAllowance(minutesPerDay: 30)

        XCTAssertEqual(h.engine.upsert(mode), .changeAllowance)
    }

    func testAnEditIsNotAlsoChargedAsAScheduleChange() {
        // The normalisation that stops one change being refused twice for two
        // different reasons — which would make the higher rung unreachable.
        // Rung 1 grants `editMode` and not `changeSchedule`, so renaming a
        // Mode here must go through while touching its window would not.
        let level = RolePermissions.minimumAutonomyLevel(for: .editMode) ?? 0
        let h = harness(role: .youngPerson, level: level)
        XCTAssertFalse(h.engine.may(.changeSchedule),
                       "this test is only meaningful below changeSchedule")

        var mode = h.addMode()
        mode.name = "Homework"

        XCTAssertNil(h.engine.upsert(mode))
        XCTAssertEqual(h.store.modes.first?.name, "Homework")
    }

    func testClimbingTheLadderActuallyUnlocksTheThing() {
        let mode = Harness().addMode()
        for capability in [HouseholdCapability.editMode, .deleteMode, .changeSchedule,
                           .changeAllowance, .unpairTag, .spendEmergencyOverride] {
            guard let level = RolePermissions.minimumAutonomyLevel(for: capability) else {
                return XCTFail("\(capability) is reachable, so it needs a rung")
            }
            _ = mode
            let at = harness(role: .youngPerson, level: level)
            XCTAssertTrue(at.engine.may(capability), "\(capability) at its rung")

            // Rung 0 is the bottom, and out-of-range levels collapse to it, so
            // "below" is not a state that exists for anything granted there.
            guard level > 0 else { continue }
            let below = harness(role: .youngPerson, level: level - 1)
            XCTAssertFalse(below.engine.may(capability), "\(capability) below its rung")
        }
    }

    // MARK: - The override is never withheld, and that is the decision

    func testEveryReachableArrangementKeepsTheEmergencyOverride() {
        // Written as a test because it is a product decision, not an accident
        // of where the rungs happened to land: a phone with no way out at all
        // is one nobody will agree to carry, and the allowance is already
        // bounded at five a month and self-restoring. Out-of-range levels
        // collapse to the bottom rung, so this really is every state.
        for level in -3...6 {
            let h = harness(role: .youngPerson, level: level)
            XCTAssertTrue(h.engine.may(.spendEmergencyOverride), "level \(level)")
        }
        XCTAssertEqual(RolePermissions.minimumAutonomyLevel(for: .spendEmergencyOverride), 0)
    }

    func testAYoungPersonAtTheBottomCanStillGetOutInAnEmergency() {
        let h = harness(role: .youngPerson, level: 0)
        h.engine.dad(with: h.addMode())

        XCTAssertTrue(h.engine.emergencyUnDad())
        XCTAssertNil(h.store.activeSession)
        XCTAssertEqual(h.store.emergencyUses.count, 1, "and it is still charged")
    }

    func testTurningDadOffIsOnNoRungAtAll() {
        // `nil`, not a sentinel level nobody reaches. The difference matters:
        // a sentinel is a number somebody eventually raises the ladder past.
        XCTAssertNil(RolePermissions.minimumAutonomyLevel(for: .turnDadOff))
        for level in -3...6 {
            XCTAssertFalse(harness(role: .youngPerson, level: level).engine.may(.turnDadOff),
                           "level \(level)")
        }
    }

    // MARK: - Tapping is never refused

    func testTappingTheTagAlwaysWorksWhateverTheRole() {
        // Deliberate: the tag is the product, and a phone that cannot be
        // Dadded or Un-Dadded at its own tag is not a stricter arrangement, it
        // is a broken one. Every capability above is about changing the
        // *rules*; none of them is about using them.
        let h = harness(role: .youngPerson, level: -1)
        let mode = h.addMode()

        guard case .dadded = h.engine.handleTap() else { return XCTFail("must Dad") }
        guard case .unDadded = h.engine.handleTap() else { return XCTFail("must Un-Dad") }
    }
}

/// An edit must not achieve, cheaply, what a dearer rung gates.
///
/// Found by review. The refusal check compared *fields* — did the schedule
/// change, did the allowance change — and charged everything else to
/// `editMode`, the cheapest rung. But a Mode that blocks nothing is never
/// registered with the scheduler, so clearing a Mode's app list took its
/// schedule down without ever naming a schedule. One rung bought the two above
/// it by side effect, and no screen said so.
final class EditSideEffectTests: XCTestCase {

    private func youngPerson(at level: Int) -> Harness {
        let h = Harness()
        h.store.household = Household(role: .youngPerson, autonomyLevel: level)
        return h
    }

    private var editOnly: Int { RolePermissions.minimumAutonomyLevel(for: .editMode) ?? 0 }

    func testEmptyingAModeCannotTakeDownItsScheduleFromTheEditRung() {
        // Protected by the *deletion* rung rather than the schedule one, and
        // that is not a coincidence: deletion sits above schedules, so the
        // rung that owns unmaking a Mode covers unmaking it by emptying it.
        let h = youngPerson(at: editOnly)
        XCTAssertTrue(h.engine.may(.editMode))
        XCTAssertFalse(h.engine.may(.changeSchedule))
        XCTAssertFalse(h.engine.may(.deleteMode))

        var sleep = h.addMode(name: "Sleep",
                              schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                                     endHour: 7, endMinute: 0,
                                                     weekdays: ModeSchedule.everyDay))
        h.engine.syncSchedules()
        XCTAssertEqual(h.engine.desiredSchedules.count, 1)

        sleep.blocked = BlockedSelection()          // "pick apps" → none
        XCTAssertNotNil(h.engine.upsert(sleep), "refused")

        XCTAssertEqual(h.engine.desiredSchedules.count, 1, "Sleep still runs tonight")
        XCTAssertTrue(h.store.modes.first?.blocksAnything ?? false)
    }

    func testEmptyingAModeIsChargedToDeletingIt() {
        // Emptying a Mode is deleting it with the row left behind.
        let h = youngPerson(at: editOnly)
        var mode = h.addMode()
        mode.blocked = BlockedSelection()

        XCTAssertEqual(h.engine.upsert(mode), .deleteMode)
    }

    func testCreatingAModeCannotSmuggleInAScheduleYouMayNotChange() {
        // Comparing against a previous cannot see what a *new* Mode brings, so
        // "create a Mode" would otherwise be the way to set a schedule the
        // rung above you owns.
        let h = youngPerson(at: editOnly)
        var fresh = DadMode(name: "Homework", symbol: "book",
                            blocked: BlockedSelection(payload: Data([1]), appCount: 1))
        fresh.schedule = ModeSchedule(startHour: 18, startMinute: 0,
                                      endHour: 20, endMinute: 0,
                                      weekdays: ModeSchedule.everyDay)

        XCTAssertEqual(h.engine.upsert(fresh), .changeSchedule)
        XCTAssertTrue(h.store.modes.filter { $0.name == "Homework" }.isEmpty)
    }

    func testCreatingAModeCannotSmuggleInAnAllowanceEither() {
        let h = youngPerson(at: editOnly)
        var fresh = DadMode(name: "Games", symbol: "gamecontroller",
                            blocked: BlockedSelection(payload: Data([1]), appCount: 1))
        fresh.allowance = ModeAllowance(minutesPerDay: 120)

        XCTAssertEqual(h.engine.upsert(fresh), .changeAllowance)
    }

    func testAPlainNewModeIsStillAllowedAtTheEditRung() {
        // The guard must not become "no new Modes at all" — creating one is
        // what the rung is for.
        let h = youngPerson(at: editOnly)
        let fresh = DadMode(name: "Reading", symbol: "book",
                            blocked: BlockedSelection(payload: Data([1]), appCount: 1))
        XCTAssertNil(h.engine.upsert(fresh))
        XCTAssertEqual(h.store.modes.count, 1)
    }

    func testASoloAdultIsUnaffectedByAnyOfThis() {
        let h = Harness()
        var mode = h.addMode(name: "Sleep",
                             schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                                    endHour: 7, endMinute: 0,
                                                    weekdays: ModeSchedule.everyDay))
        mode.blocked = BlockedSelection()
        XCTAssertNil(h.engine.upsert(mode), "their own phone, their own rules")
    }
}
