import XCTest
@testable import DadCore

/// A tag's name is what a Shortcut chooses it by.
///
/// An NFC automation in Shortcuts hands its action nothing about the tag that
/// fired it, so "the Work tag" has to be picked by name when the automation is
/// built, and the action then taps on that tag's behalf. Everything here is
/// about that name staying attached to the right sticker, and about the
/// on-its-behalf tap being the same tap the sticker makes.
final class TagNameTests: XCTestCase {

    // MARK: - The name

    func testANameIsTrimmedAndBlankIsNoName() {
        var pairing = TagPairing(uids: ["HOME"])
        pairing.rename("HOME", to: "  Home \n")
        XCTAssertEqual(pairing.pair(for: "HOME")?.name, "Home")

        pairing.rename("HOME", to: "   ")
        XCTAssertNil(pairing.pair(for: "HOME")?.name,
                     "a blank name would be a blank row in the Shortcuts picker")
    }

    func testAnUnnamedTagStillHasSomethingToShow() {
        let pair = TagPairing.Pair(uid: "04A1B2C3D4")
        XCTAssertNil(pair.name)
        XCTAssertTrue(pair.displayName.hasSuffix("C3D4"))
        XCTAssertEqual(TagPairing.Pair(uid: "04A1B2C3D4", name: "Work").displayName, "Work")
    }

    func testRenamingATagYouHaveNotPairedPairsNothing() {
        // Naming is ungated and pairing is not, in a household. A rename that
        // added the row would be the gate's back door.
        var pairing = TagPairing(uids: ["HOME"])
        pairing.rename("POCKET", to: "Mine")
        XCTAssertEqual(pairing.uids, ["HOME"])
    }

    func testRePointingATagKeepsItsName() {
        // The automation was built against "Work". Changing what Work starts
        // must not turn it into "Clover tag ···D4" under the Shortcut's feet.
        let deepWork = UUID()
        var pairing = TagPairing(uids: ["WORK"])
        pairing.rename("WORK", to: "Work")
        pairing.pair("WORK", to: deepWork)
        XCTAssertEqual(pairing.pair(for: "WORK")?.name, "Work")
        XCTAssertEqual(pairing.modeIDs(for: "WORK").first, deepWork)
    }

    func testAnEmptyPairingNamesNoTag() {
        // `isPaired` says yes to anything when nothing is paired. `pair(for:)`
        // must not: there is no row to offer Shortcuts.
        XCTAssertNil(TagPairing().pair(for: "ANYTHING"))
    }

    // MARK: - On disk

    func testARowWrittenBeforeNamesExistedReadsBackUnnamed() throws {
        let stored = #"[{"uid":"HOME","modeID":"\#(UUID().uuidString)"},{"uid":"WORK"}]"#
        let pairing = try JSONDecoder().decode(TagPairing.self, from: Data(stored.utf8))
        XCTAssertEqual(pairing.uids, ["HOME", "WORK"])
        XCTAssertNil(pairing.pair(for: "HOME")?.name)
        XCTAssertNotNil(pairing.modeIDs(for: "HOME").first, "and its Mode survived")
    }

    func testANameSurvivesARoundTrip() throws {
        var pairing = TagPairing(uids: ["HOME", "WORK"])
        pairing.rename("WORK", to: "Work")
        let back = try JSONDecoder().decode(TagPairing.self,
                                            from: JSONEncoder().encode(pairing))
        XCTAssertEqual(back, pairing)
        XCTAssertEqual(back.pair(for: "WORK")?.name, "Work")
    }

    // MARK: - Through the engine

    func testHomeAndWorkEachStartTheirOwnMode() {
        // The feature, end to end. `handleTap(tagUID:)` is the call the
        // Shortcuts action makes with the tag it was built around, and the
        // call the in-app scan makes with the tag it read — so this is both.
        let h = Harness()
        let evening = h.addMode(name: "Evening")
        let deepWork = h.addMode(name: "Deep Work")
        h.engine.pair(tagUID: "HOME", to: evening.id)
        h.engine.pair(tagUID: "WORK", to: deepWork.id)
        h.engine.rename(tagUID: "HOME", to: "Home")
        h.engine.rename(tagUID: "WORK", to: "Work")

        guard case .dadded(let started, _) = h.engine.handleTap(tagUID: "WORK") else {
            return XCTFail("the Work tag should start a session")
        }
        XCTAssertEqual(started.id, deepWork.id)

        guard case .unDadded = h.engine.handleTap(tagUID: "WORK") else {
            return XCTFail("and tapping it again should bring the phone back in")
        }

        guard case .dadded(let again, _) = h.engine.handleTap(tagUID: "HOME") else {
            return XCTFail("the Home tag should start a session")
        }
        XCTAssertEqual(again.id, evening.id)
    }

    func testAnyPairedTagBringsThePhoneBackIn() {
        // Outside on the Work tag, home on the train: the Home tag releases.
        // A tag names the Mode it *starts*; it is not a key to one session.
        let h = Harness()
        let evening = h.addMode(name: "Evening")
        let deepWork = h.addMode(name: "Deep Work")
        h.engine.pair(tagUID: "HOME", to: evening.id)
        h.engine.pair(tagUID: "WORK", to: deepWork.id)

        h.engine.handleTap(tagUID: "WORK")
        guard case .unDadded = h.engine.handleTap(tagUID: "HOME") else {
            return XCTFail("expected the Home tag to release a Work session")
        }
    }

    func testATagUnpairedSinceTheShortcutWasBuiltIsRefused() {
        // The automation still says "Work". The tag is gone from the list, and
        // another one is still paired, so Work is now a stranger's tag.
        let h = Harness()
        h.addMode()
        h.engine.pair(tagUID: "HOME")
        h.engine.pair(tagUID: "WORK")
        XCTAssertNil(h.engine.unpair(tagUID: "WORK"))

        XCTAssertEqual(h.store.tags.uids, ["HOME"])
        XCTAssertEqual(h.engine.handleTap(tagUID: "WORK"), .unknownTag)
    }

    func testAYoungPersonMayNameATagButNotUnpairOne() {
        let h = Harness()
        h.store.household = Household(role: .youngPerson, autonomyLevel: 0)
        h.engine.pair(tagUID: "KITCHEN")

        h.engine.rename(tagUID: "KITCHEN", to: "Kitchen")
        XCTAssertEqual(h.store.tags.pair(for: "KITCHEN")?.name, "Kitchen")

        XCTAssertEqual(h.engine.unpair(tagUID: "KITCHEN"), .unpairTag)
        XCTAssertEqual(h.store.tags.uids, ["KITCHEN"], "and the tag is still paired")
    }
}
