import XCTest
@testable import DadCore

/// A tag that names the Mode it starts.
///
/// `TagPairingTests` covers the mapping. These cover the thing a person
/// actually does: touching a phone to a sticker on the fridge and having
/// Dinner start rather than whatever the app would otherwise have guessed.
/// Brick charges $59 a puck for this; here the stickers are thirty cents,
/// which is the best value on the whole backlog.
final class TagPerModeTests: XCTestCase {

    func testTheKitchenTagStartsDinnerAndTheDeskTagStartsDeepWork() {
        let h = Harness()
        let dinner = h.addMode(name: "Dinner")
        let deepWork = h.addMode(name: "Deep Work")
        h.engine.pair(tagUID: "KITCHEN", to: dinner.id)
        h.engine.pair(tagUID: "DESK", to: deepWork.id)

        guard case .dadded(let started, _) = h.engine.handleTap(tagUID: "KITCHEN") else {
            return XCTFail("the kitchen tag must Dad")
        }
        XCTAssertEqual(started.id, dinner.id)

        h.engine.handleTap(tagUID: "KITCHEN")
        guard case .dadded(let second, _) = h.engine.handleTap(tagUID: "DESK") else {
            return XCTFail("the desk tag must Dad")
        }
        XCTAssertEqual(second.id, deepWork.id)
    }

    func testWithoutTheTagNamingAModeTheAppStillHasToChoose() {
        // The behaviour every tag had before this existed, and the behaviour a
        // tag paired by an older build keeps after the migration.
        let h = Harness()
        h.addMode(name: "Dinner")
        h.addMode(name: "Deep Work")
        h.engine.pair(tagUID: "PLAIN")

        XCTAssertEqual(h.engine.handleTap(tagUID: "PLAIN"), .needsModeChoice)
    }

    func testAnExplicitChoiceStillBeatsWhatTheTagNames() {
        // The request comes from a person answering a question; the tag from a
        // sticker somebody labelled months ago.
        let h = Harness()
        let dinner = h.addMode(name: "Dinner")
        let sleep = h.addMode(name: "Sleep")
        h.engine.pair(tagUID: "KITCHEN", to: dinner.id)

        guard case .dadded(let started, _) =
                h.engine.handleTap(tagUID: "KITCHEN", preferredMode: sleep) else {
            return XCTFail("expected .dadded")
        }
        XCTAssertEqual(started.id, sleep.id)
    }

    func testATagNamingADeletedModeFallsBackToTogglingRatherThanGoingDead() {
        // A sticker on the fridge that silently does nothing is the failure
        // this codebase hates most, and it would surface weeks after the
        // delete with nothing connecting the two. The person never touched the
        // sticker — deleting a Mode is a statement about Modes.
        let h = Harness()
        let dinner = h.addMode(name: "Dinner")
        let only = h.addMode(name: "Deep Work")
        h.engine.pair(tagUID: "KITCHEN", to: dinner.id)
        h.engine.deleteMode(id: dinner.id)

        guard case .dadded(let started, _) = h.engine.handleTap(tagUID: "KITCHEN") else {
            return XCTFail("the tag must still work")
        }
        XCTAssertEqual(started.id, only.id, "it toggles, as it did before it was named")
    }

    func testAStrangersTagIsStillRefused() {
        let h = Harness()
        let dinner = h.addMode(name: "Dinner")
        h.engine.pair(tagUID: "KITCHEN", to: dinner.id)

        XCTAssertEqual(h.engine.handleTap(tagUID: "STRANGER"), .unknownTag)
        XCTAssertNil(h.store.activeSession)
    }

    func testUntilSomethingIsPairedAnyTagWorks() {
        // Otherwise a fresh install is unusable: there is nothing to pair
        // *with* until a tag has been read once.
        let h = Harness()
        h.addMode()
        guard case .dadded = h.engine.handleTap(tagUID: "WHATEVER") else {
            return XCTFail("a fresh install must not be locked out")
        }
    }

    func testATaggedModeIsStillReleasedByAnyPairedTag() {
        // Deliberate. The tag names what a tap *starts*; it does not own the
        // session. Making Dinner releasable only at the kitchen tag would
        // strand someone whose phone Dadded itself on a schedule while they
        // were out.
        let h = Harness()
        let dinner = h.addMode(name: "Dinner")
        h.engine.pair(tagUID: "KITCHEN", to: dinner.id)
        h.engine.pair(tagUID: "DESK")
        h.engine.handleTap(tagUID: "KITCHEN")

        guard case .unDadded = h.engine.handleTap(tagUID: "DESK") else {
            return XCTFail("any paired tag releases")
        }
        XCTAssertNil(h.store.activeSession)
    }
}
