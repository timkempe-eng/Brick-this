import XCTest
@testable import DadCore

/// Who a Mode's agreement says wrote it — and why the app cannot simply be
/// told.
///
/// `ModeAgreementTests` covers the record and its arithmetic. This covers the
/// one thing only the engine can decide: `agreedBy` is **derived, never
/// passed**. The app cannot be informed that two people agreed something; it
/// can only observe that a grown-up was here, which on a young person's phone
/// means the tag they hold was tapped.
///
/// A parameter would let a screen assert "agreed together" about a
/// conversation that never happened, and the record is worth nothing the
/// moment it can say that.
final class AgreementWiringTests: XCTestCase {

    private func youngPerson() -> (Harness, DadMode) {
        let h = Harness()
        h.store.household = Household(role: .youngPerson, autonomyLevel: 0)
        h.engine.pair(tagUID: "PARENT")
        return (h, h.addMode(name: "Sleep"))
    }

    // MARK: - Who agreed it

    func testATagTapMakesItAgreedTogether() {
        let (h, sleep) = youngPerson()

        let agreement = h.engine.agree(modeID: sleep.id,
                                       reason: "So I actually sleep",
                                       byTagUID: "PARENT")

        XCTAssertEqual(agreement?.agreedBy, .both)
        XCTAssertFalse(agreement?.isImposed ?? true)
    }

    func testWithoutOneItStaysVisiblyOnePerson() {
        // Not a failure and not an error — a rule one person wrote is a real
        // thing that happens, and the record's whole job is that it does not
        // read the same as one two people wrote.
        let (h, sleep) = youngPerson()

        XCTAssertEqual(h.engine.agree(modeID: sleep.id, reason: "Because")?.agreedBy, .onePerson)
        XCTAssertEqual(h.engine.agree(modeID: sleep.id, reason: "Because",
                                      byTagUID: "SOMEONEELSE")?.agreedBy, .onePerson)
    }

    func testAPhoneThatIsItsOwnersRecordsOnePerson() {
        // One person is who wrote it, which is true rather than a demotion.
        // The board that reads this is only shown on a young person's phone.
        let h = Harness()
        let mode = h.addMode()

        XCTAssertEqual(h.engine.agree(modeID: mode.id, reason: "Mine")?.agreedBy, .onePerson)
    }

    func testAnAgreementForANonexistentModeIsRefused() {
        // Otherwise the side table grows rows describing rules that do not
        // exist, and a household is shown four agreements for three Modes.
        let (h, _) = youngPerson()
        XCTAssertNil(h.engine.agree(modeID: UUID(), reason: "Nothing"))
        XCTAssertTrue(h.store.agreements.isEmpty)
    }

    // MARK: - What survives a rewrite

    func testRewritingTheReasonKeepsTheRecordOfTalkingAboutIt() {
        // The log of a rule having been discussed is what makes the next
        // conversation possible. Rewriting the reason is not a reason to lose
        // it.
        let (h, sleep) = youngPerson()
        h.engine.agree(modeID: sleep.id, reason: "First go", comingUpAgainIn: 30, byTagUID: "PARENT")
        h.clock.advance(days: 31)
        h.engine.renegotiate(modeID: sleep.id, outcome: .keptAsIs, byTagUID: "PARENT")

        let rewritten = h.engine.agree(modeID: sleep.id, reason: "Better words", byTagUID: "PARENT")

        XCTAssertEqual(rewritten?.reason, "Better words")
        XCTAssertEqual(rewritten?.history.count, 1, "the conversation still happened")
    }

    func testTalkingAndChangingNothingIsStillRecorded() {
        // A log that only remembers the times somebody won is not a log of a
        // household.
        let (h, sleep) = youngPerson()
        h.engine.agree(modeID: sleep.id, reason: "So I sleep", comingUpAgainIn: 30, byTagUID: "PARENT")

        let after = h.engine.renegotiate(modeID: sleep.id, outcome: .keptAsIs,
                                         comingUpAgainIn: 60, byTagUID: "PARENT")

        XCTAssertEqual(after?.history.first?.outcome, .keptAsIs)
        XCTAssertEqual(after?.reason, "So I sleep", "nothing changed, including the words")
        XCTAssertTrue(after?.comesUpAgain ?? false)
    }

    func testRenegotiatingSomethingNobodyEverAgreedIsRefused() {
        let (h, sleep) = youngPerson()
        XCTAssertNil(h.engine.renegotiate(modeID: sleep.id, outcome: .changed, byTagUID: "PARENT"))
    }

    // MARK: - The board

    func testTheBoardIsDrivenByTheModesAndNotByTheAgreements() {
        let (h, sleep) = youngPerson()
        let deepWork = h.addMode(name: "Deep Work")
        h.engine.agree(modeID: sleep.id, reason: "So I sleep", byTagUID: "PARENT")

        let board = h.engine.householdAgreements
        XCTAssertEqual(board.total, 2)
        XCTAssertEqual(board.agreedCount, 1)
        XCTAssertEqual(board.unexplainedCount, 1, "Deep Work has nothing written down")
        XCTAssertEqual(board.unexplained.first?.modeID, deepWork.id)
    }

    func testDeletingAModeTakesItsAgreementWithIt() {
        // Housekeeping rather than correctness — the board already ignores an
        // orphan — but a side table that only ever grows is one that ends up
        // holding rules nobody remembers writing.
        let (h, sleep) = youngPerson()
        h.store.household = Household(role: .grownUp, autonomyLevel: 0)
        h.engine.agree(modeID: sleep.id, reason: "So I sleep")

        XCTAssertNil(h.engine.deleteMode(id: sleep.id))
        XCTAssertTrue(h.store.agreements.isEmpty)
    }

    func testAModeIsExplainedOnlyWhenSomethingIsActuallyWritten() {
        // Whitespace is not an explanation, and the standing says so rather
        // than counting a blank as agreed.
        let (h, sleep) = youngPerson()
        h.engine.agree(modeID: sleep.id, reason: "   \n ", byTagUID: "PARENT")

        XCTAssertEqual(h.engine.householdAgreements.entries.first?.standing, .unexplained)
    }
}
