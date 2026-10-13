import XCTest
@testable import DadCore

/// Full Brick: everything goes, nothing this app can grant stays.
///
/// What it shields is decided in `DadMode+FamilyControls`, which only compiles
/// on Apple platforms. What Core decides — that it always blocks, never
/// rations, is always strict, and keeps nothing however it was configured
/// before — is here.
final class FullBrickTests: XCTestCase {

    func testThePresetIsAFullBrick() {
        let mode = DadMode.fullBrickPreset
        XCTAssertTrue(mode.isFullBrick)
        XCTAssertTrue(mode.blocksAnything, "nothing to pick, and still blocks")
        XCTAssertTrue(mode.deniesAppRemoval, "always strict")
        XCTAssertFalse(mode.isStrict, "without writing the strict flag itself")
        XCTAssertEqual(mode.summary, "Full Brick — everything but calls")
    }

    func testItKeepsNothingEvenIfTheModeOnceKeptSomething() {
        // A Mode switched to Full Brick from an allowlist still holds its old
        // survivors. They must not survive into the shield.
        var mode = DadMode(name: "Sleep", symbol: "moon")
        mode.style = .allowlist
        mode.allowed = BlockedSelection(payload: Data([1]), appCount: 2)
        XCTAssertFalse(mode.allowedSelection.isEmpty)

        mode.isFullBrick = true
        XCTAssertEqual(mode.effectiveStyle, .allowlist)
        XCTAssertTrue(mode.allowedSelection.isEmpty)

        mode.isFullBrick = false
        XCTAssertFalse(mode.allowedSelection.isEmpty, "switching it off gives the list back")
    }

    func testABlocklistModeTurnedFullBrickBlocksEverything() {
        var mode = DadMode(name: "Empty", symbol: "circle")
        XCTAssertFalse(mode.blocksAnything)
        mode.isFullBrick = true
        XCTAssertEqual(mode.effectiveStyle, .allowlist)
        XCTAssertTrue(mode.blocksAnything)
    }

    func testItNeverRations() {
        // An allowance counts a named set; "everything" cannot be counted, so
        // a rationed Full Brick would read "15 min a day" and limit nothing.
        var mode = DadMode.fullBrickPreset
        mode.allowance = ModeAllowance(minutesPerDay: 15)
        XCTAssertFalse(mode.rations)
    }

    func testItIsNotAStarterMode() {
        // It blocks from the moment it exists. As a starter it would be the
        // only usable Mode on a fresh install, and a bare tap would start it.
        XCTAssertFalse(DadMode.starterModes.contains(where: \.isFullBrick))
        XCTAssertTrue(DadMode.starterModes.allSatisfy { !$0.blocksAnything })
    }

    func testAModeStoredBeforeFullBrickDecodesAsNotOne() throws {
        let json = Data(#"{"id":"\#(UUID().uuidString)","name":"Gym","symbol":"x","isStrict":false,"blocked":{"payload":"","appCount":0,"categoryCount":0,"webDomainCount":0}}"#.utf8)
        let mode = try JSONDecoder().decode(DadMode.self, from: json)
        XCTAssertFalse(mode.isFullBrick)
    }

    func testOffIsNotWritten() throws {
        // `nil`, not `false`, so turning it off leaves the stored Mode exactly
        // as an older build wrote it.
        var mode = DadMode.fullBrickPreset
        mode.isFullBrick = false
        let text = String(decoding: try JSONEncoder().encode(mode), as: UTF8.self)
        XCTAssertFalse(text.contains("fullBrick"), text)
    }

    func testABareTapOnAPhoneWhoseOnlyModeIsFullBrickStartsIt() {
        // Choosing it is what makes it the sole usable Mode; then a tap means
        // it, as for any other. Pinned so the behaviour is a decision.
        let h = Harness()
        h.store.modes = DadMode.starterModes + [DadMode.fullBrickPreset]
        h.engine.pair(tagUID: "TAG")
        guard case .dadded(let mode, _) = h.engine.handleTap(tagUID: "TAG") else {
            return XCTFail("expected the tap to start Full Brick")
        }
        XCTAssertTrue(mode.isFullBrick)
        XCTAssertTrue(h.shield.appliedMode == mode.id)
    }
}
