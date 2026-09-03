import XCTest
@testable import DadCore

/// The seam between the engine and `ShieldGap`.
///
/// `ShieldGapTests` covers the judgement against hand-built observations.
/// These cover the part only the engine can get wrong: what it feeds in, and
/// the one value it has to persist for the bound to mean anything.
///
/// The stamp is the whole of it. `lastShieldConfirmedAt` is the left edge of
/// every bound the report gives, and its two failure directions are not
/// symmetric: a stamp left over from an earlier session narrows a later gap
/// and *hides* it, which is the one this feature must never do.
final class ShieldGapWiringTests: XCTestCase {

    func testAConfirmationIsOnlyRecordedWhenTheSystemSaysItMay() {
        let h = Harness()
        let mode = h.addMode()
        h.engine.dad(with: mode)

        h.shield.authorization = .notApproved
        h.engine.reconcile()
        XCTAssertNil(h.store.lastShieldConfirmedAt,
                     "nothing was being held, so nothing may be recorded as held")

        h.shield.authorization = .approved
        h.engine.reconcile()
        XCTAssertEqual(h.store.lastShieldConfirmedAt, h.clock.now)
    }

    func testNotBeingAbleToAskIsNotAConfirmation() {
        // And it is not an accusation either. `.unknown` records nothing and
        // reports nothing — the report's own tests pin the second half.
        let h = Harness()
        h.engine.dad(with: h.addMode())

        h.shield.authorization = .unknown
        h.engine.reconcile()
        XCTAssertNil(h.store.lastShieldConfirmedAt)
    }

    func testAStampFromAnEarlierSessionCannotNarrowALaterGap() {
        // The asymmetry: too-wide a bound over-reports by minutes, too-narrow
        // a bound hides the gap entirely. So the stamp is cleared at both
        // ends of a session rather than merely overwritten at the next
        // foreground, which might not come.
        let h = Harness()
        let mode = h.addMode()

        h.engine.dad(with: mode)
        h.engine.reconcile()
        XCTAssertNotNil(h.store.lastShieldConfirmedAt)

        h.engine.unDad(.tapped)
        XCTAssertNil(h.store.lastShieldConfirmedAt, "nothing is held between sessions")

        h.clock.advance(days: 1)
        h.engine.dad(with: mode)
        XCTAssertNil(h.store.lastShieldConfirmedAt, "and a new session starts unconfirmed")
    }

    func testAFailedApplyIsNotRecordedAsAConfirmation() {
        // Stamped after applying, never before. A confirmation the shield did
        // not actually get is the one lie the bound cannot survive.
        let h = Harness()
        h.engine.dad(with: h.addMode())
        h.shield.authorization = .notApproved

        h.engine.reconcile()

        XCTAssertNil(h.store.lastShieldConfirmedAt)
        XCTAssertNotNil(h.engine.shieldGap.headline ?? h.engine.shieldGap.setupNote,
                        "a session running with no authorization is worth saying something about")
    }

    // MARK: - Who it is addressed to

    func testAnAdultDaddingThemselvesIsNotToldAboutIt() {
        // A running tally of the times Dad lost sight of the shield turns a
        // boundary somebody chose into a self-audit they did not. They already
        // know their phone rebooted.
        let h = Harness()
        h.engine.dad(with: h.addMode())
        h.shield.authorization = .notApproved
        h.clock.advance(60 * 60)

        XCTAssertEqual(h.store.household.role, .grownUp, "the default this rests on")
        XCTAssertNil(h.engine.shieldGap.headline)
    }

    func testAHouseholdIsToldPlainly() {
        let h = Harness()
        h.store.household = Household(role: .youngPerson, autonomyLevel: 0)
        h.engine.dad(with: h.addMode())
        h.shield.authorization = .notApproved
        h.clock.advance(60 * 60)

        XCTAssertNotNil(h.engine.shieldGap.headline)
    }

    // MARK: - What it is fed

    func testTheActiveSessionIsAmongTheIntervalsItRulesOccurrencesOutWith() {
        // Built from `history` plus the active session. Leaving the live one
        // out would report a window as unattended while it was being attended.
        let h = Harness()
        let mode = h.addMode()
        h.engine.dad(with: mode)
        h.clock.advance(60 * 60)

        XCTAssertTrue(h.engine.shieldGap.gaps.isEmpty,
                      "the phone is Dadded right now; nothing is missing")
    }
}
