import XCTest
@testable import DadCore

/// What the home screen's setup card offers, and when it stops.
///
/// Read from the engine rather than built by hand wherever the input is
/// something the engine owns, so a test passes only if the checklist and the
/// tap agree about what "set up" means.
final class SetupChecklistTests: XCTestCase {

    func testAFreshInstallHasEveryStepLeft() {
        // The starter Modes arrive empty. A checklist that counted them as
        // "apps chosen" would hide the one step a new phone cannot work without.
        let checklist = SetupChecklist(modes: DadMode.starterModes,
                                       pairedTagCount: 0, hasEverStarted: false)
        XCTAssertTrue(checklist.done.isEmpty)
        XCTAssertEqual(checklist.next, .chooseApps)
        XCTAssertFalse(checklist.isComplete)
    }

    func testStepsAreOfferedAppsThenTagThenTry() {
        let h = Harness()
        h.addEmptyMode()
        XCTAssertEqual(h.engine.setupChecklist.next, .chooseApps)

        h.addMode()
        XCTAssertEqual(h.engine.setupChecklist.next, .pairTag)

        h.engine.pair(tagUID: "KITCHEN")
        XCTAssertEqual(h.engine.setupChecklist.next, .tryIt)

        h.engine.handleTap(tagUID: "KITCHEN")
        XCTAssertNil(h.engine.setupChecklist.next)
        XCTAssertTrue(h.engine.setupChecklist.isComplete)
    }

    func testAppsAreOfferedFirstEvenWhenATagIsAlreadyPaired() {
        // A paired tag with nothing to hide is the dead end this exists for.
        let h = Harness()
        h.addEmptyMode()
        h.engine.pair(tagUID: "KITCHEN")
        XCTAssertEqual(h.engine.setupChecklist.next, .chooseApps)
        XCTAssertTrue(h.engine.setupChecklist.done.contains(.pairTag))
    }

    func testTryingItStaysDoneAfterComingBackIn() {
        let h = Harness()
        h.addMode()
        h.engine.handleTap()
        XCTAssertTrue(h.engine.setupChecklist.done.contains(.tryIt), "while outside")
        h.engine.handleTap()
        XCTAssertNil(h.store.activeSession)
        XCTAssertTrue(h.engine.setupChecklist.done.contains(.tryIt), "and after")
    }

    func testEmptyingEveryModeOffersTheAppsStepAgain() {
        // Derived, not latched: somebody who takes every app back out has a
        // phone a tap does nothing on, and the card should say so again.
        let h = Harness()
        var mode = h.addMode()
        XCTAssertTrue(h.engine.setupChecklist.done.contains(.chooseApps))
        mode.blocked = BlockedSelection()
        h.save(mode)
        XCTAssertEqual(h.engine.setupChecklist.next, .chooseApps)
    }

    func testAnAllowlistModeCountsAsAppsChosen() {
        // "Leave only these" with nothing left is a real Sleep Mode, and the
        // engine starts it — so the checklist must not keep asking for apps.
        let h = Harness()
        var mode = h.addEmptyMode()
        mode.style = .allowlist
        h.save(mode)
        XCTAssertTrue(h.engine.setupChecklist.done.contains(.chooseApps))
    }

    /// The seam the checklist was written for: whenever it still offers the
    /// apps step, a bare tap must refuse with nothing to choose — which is
    /// what makes the app say `Vocab.nothingToHideYet` rather than show an
    /// empty "which Mode?" question — and whenever it does not, a tap must
    /// start something.
    func testTheAppsStepAgreesWithWhatATapDoes() {
        let shapes: [(String, (Harness) -> Void)] = [
            ("no Modes", { _ in }),
            ("starter Modes", { h in h.store.modes = DadMode.starterModes }),
            ("one empty", { h in h.addEmptyMode() }),
            ("one with apps", { h in h.addMode() }),
            ("empty and full", { h in h.addEmptyMode(); h.addMode(name: "Gym") }),
            ("allowlist", { h in
                var m = h.addEmptyMode(); m.style = .allowlist; h.save(m) }),
        ]
        for (name, build) in shapes {
            let h = Harness()
            build(h)
            let offersApps = h.engine.setupChecklist.next == .chooseApps
            let result = h.engine.handleTap()
            if offersApps {
                guard case .needsModeChoice(let among) = result else {
                    return XCTFail("\(name): the card asks for apps but a tap did \(result)")
                }
                XCTAssertTrue(among.isEmpty, "\(name): offered \(among.map(\.name))")
            } else {
                guard case .dadded = result else {
                    return XCTFail("\(name): apps are chosen but a tap did \(result)")
                }
            }
        }
    }
}
