import XCTest
@testable import DadCore

/// Apps and sites no Mode may take away.
///
/// Core cannot check the subtraction itself — both selections are opaque
/// payloads here, which is hard rule 3 doing its job — so what these tests pin
/// down is the thing Core *is* responsible for: that the list reaches every
/// place a restriction is applied, on every path, every time. The arithmetic
/// happens in `DadMode+FamilyControls` and is one `subtracting` call; the
/// failure mode worth guarding is not that it subtracts wrongly, it is that
/// some path forgets to pass it and the safety net is silently absent exactly
/// once — on the schedule that fires at 3am, or after a crash.
final class NeverBlockedTests: XCTestCase {

    private let safe = BlockedSelection(payload: Data([9, 9]), appCount: 2)

    func testTheShieldIsToldOnATap() {
        let h = Harness()
        h.store.neverBlocked = safe
        h.addMode()

        h.engine.handleTap()

        XCTAssertEqual(h.shield.lastNeverBlocked, safe)
    }

    func testTheShieldIsToldOnReconcile() {
        // The path after a crash, and the one nobody watches.
        let h = Harness()
        let mode = h.addMode()
        h.engine.dad(with: mode)
        h.store.neverBlocked = safe

        h.engine.reconcile()

        XCTAssertEqual(h.shield.lastNeverBlocked, safe)
    }

    func testTheShieldIsToldWhenAScheduleStartsASession() {
        let h = Harness()
        h.store.neverBlocked = safe
        let mode = h.addMode(schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                                    endHour: 7, endMinute: 0,
                                                    weekdays: ModeSchedule.everyDay))

        h.engine.beginScheduledSession(modeID: mode.id)

        XCTAssertEqual(h.shield.lastNeverBlocked, safe)
    }

    func testTheShieldIsToldWhenAnAllowanceRunsOut() {
        let h = Harness()
        h.store.neverBlocked = safe
        let mode = h.addMode(allowance: ModeAllowance(minutesPerDay: 15))
        h.engine.dad(with: mode)
        XCTAssertNil(h.shield.lastNeverBlocked, "nothing is hidden yet")

        h.engine.spendAllowance(modeID: mode.id)

        XCTAssertEqual(h.shield.lastNeverBlocked, safe)
    }

    func testProtectedAppsDoNotSpendARationedModesAllowance() {
        // Otherwise ten minutes in the banking app you protected would cost
        // you ten minutes of the apps you were actually rationing.
        let h = Harness()
        h.store.neverBlocked = safe
        let mode = h.addMode(allowance: ModeAllowance(minutesPerDay: 15))

        h.engine.dad(with: mode)

        XCTAssertEqual(h.usage.lastNeverBlocked, safe)
    }

    func testAChangeTakesEffectOnTheNextThingThatAppliesTheShield() {
        let h = Harness()
        let mode = h.addMode()
        h.engine.dad(with: mode)
        XCTAssertEqual(h.shield.lastNeverBlocked, BlockedSelection())

        h.store.neverBlocked = safe
        h.engine.reconcile()

        XCTAssertEqual(h.shield.lastNeverBlocked, safe)
    }

    func testAnEmptyListIsTheOldBehaviourRatherThanASpecialCase() {
        // Nothing protected must be an ordinary value, not a nil to branch on,
        // or every call site grows a second path that only runs for people who
        // never opened Settings.
        let h = Harness()
        h.addMode()
        h.engine.handleTap()

        XCTAssertEqual(h.shield.lastNeverBlocked, BlockedSelection())
        XCTAssertTrue(h.store.neverBlocked.isEmpty)
    }
}
