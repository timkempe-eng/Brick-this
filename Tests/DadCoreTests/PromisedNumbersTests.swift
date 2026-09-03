import XCTest
@testable import DadCore

/// The constants the product makes a promise about.
///
/// Found by mutation testing, and it is the "assertions that could not fail"
/// lesson in a new costume. Every existing test spells the allowance
/// `EmergencyAllowance.perWindow` — which is correct style, and means the whole
/// suite moves with the constant. Change 5 to 500 and 240 tests still pass,
/// while Settings goes on saying "of 500" and the README goes on saying five.
/// The mutation harness reported it as a survivor; the README claimed it turned
/// the suite red. The README was wrong.
///
/// So these are the one place a literal is correct: each number below is
/// written down somewhere a person will read it, and this file is what makes
/// changing one a deliberate act rather than a silent contradiction.
final class PromisedNumbersTests: XCTestCase {

    /// "Five overrides per rolling 30 days" — Settings, the README, and
    /// docs/brick-teardown.md, where it is the specific thing Dad does better
    /// than Brick's "email support once you're out".
    func testFiveEmergencyOverrides() {
        XCTAssertEqual(EmergencyAllowance.perWindow, 5)
    }

    func testARollingThirtyDayWindow() {
        XCTAssertEqual(EmergencyAllowance.window, 30 * 24 * 60 * 60)
    }

    /// Not user-facing, but a decision rather than an accident: the shield
    /// extension decodes this array under a tight memory budget, so the tail is
    /// bounded. Unbounded history is a crash on someone's phone a year from now.
    func testHistoryIsBoundedAtFiveHundredSessions() {
        XCTAssertEqual(DadEngine.historyLimit, 500)
    }

    /// Apple's floor, not ours: `DeviceActivitySchedule` will not monitor a
    /// shorter interval. Lowering it would make timed releases, breaks and
    /// short schedules silently never fire — the failure this codebase spends
    /// the most effort avoiding.
    func testTheFifteenMinuteFloorIsApplesNotOurs() {
        XCTAssertEqual(DadEngine.minimumScheduledRelease, 15 * 60)
    }
}
