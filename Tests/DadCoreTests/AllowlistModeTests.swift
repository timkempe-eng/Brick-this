import XCTest
@testable import DadCore

/// Modes that name what stays rather than what goes.
///
/// A blocklist decays: a Sleep Mode is only as good as your memory, and every
/// app installed after you built it is a silent hole. An allowlist is the one
/// shape on the backlog that improves with time instead.
///
/// Core cannot check the inversion itself — both selections are opaque payloads
/// here, which is hard rule 3 working — so what these tests pin is everything
/// Core *is* responsible for: which style a Mode is, whether it blocks
/// anything, whether it may ration, what it says about itself, and that adding
/// the fields did not quietly delete every Mode already on someone's phone.
final class AllowlistModeTests: XCTestCase {

    /// Deliberately takes a non-optional style, so that making `DadMode.style`
    /// non-optional still compiles this file and the legacy-decode test below
    /// fails *as a test* rather than as a build error. A guard that can only
    /// fire as a compile error in the same file it guards is a weaker guard.
    private func mode(style: DadMode.ModeStyle,
                      blockedApps: Int = 0,
                      allowedApps: Int? = nil) -> DadMode {
        var m = DadMode(name: "Sleep", symbol: "moon")
        m.style = style
        if blockedApps > 0 {
            m.blocked = BlockedSelection(payload: Data([1]), appCount: blockedApps)
        }
        if let allowedApps {
            m.allowed = BlockedSelection(payload: Data([2]), appCount: allowedApps)
        }
        return m
    }

    // MARK: - Decoding what is already on the phone

    func testAModeStoredBeforeAllowlistsExistedStillDecodes() {
        // The failure this guards is silent and total. Swift's synthesised
        // decoder does not fall back to a property's default when the key is
        // absent — it fails the whole record — and `LenientDecoding` then skips
        // that record. A non-optional `style` would therefore have deleted every
        // Mode on every phone that updated, with no error anywhere.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Deep Work","symbol":"brain",
         "blocked":{"payload":"","appCount":3,"categoryCount":0,"webDomainCount":0},
         "isStrict":false}
        """.data(using: .utf8)!

        guard let decoded = try? JSONDecoder().decode(DadMode.self, from: json) else {
            return XCTFail("a Mode from an older build must still decode")
        }
        XCTAssertEqual(decoded.name, "Deep Work")
        XCTAssertEqual(decoded.effectiveStyle, .blocklist, "and read as a blocklist")
        XCTAssertTrue(decoded.allowedSelection.isEmpty)
    }

    func testAWholeArrayIsNotLostToOneOldRecord() {
        // The same guard at the level it actually bites: the store decodes
        // Modes as an array, leniently.
        let old = """
        {"id":"\(UUID().uuidString)","name":"Old","symbol":"a",
         "blocked":{"payload":"","appCount":1,"categoryCount":0,"webDomainCount":0},
         "isStrict":false}
        """
        let data = "[\(old),\(old)]".data(using: .utf8)!
        XCTAssertEqual(LenientDecoding.array(DadMode.self, from: data)?.count, 2)
    }

    func testAFreshModeIsABlocklist() {
        XCTAssertEqual(DadMode(name: "New", symbol: "circle").effectiveStyle, .blocklist)
    }

    // MARK: - What it blocks

    func testABlocklistWithNothingChosenBlocksNothing() {
        XCTAssertFalse(mode(style: .blocklist).blocksAnything)
    }

    func testAnAllowlistAlwaysBlocksSomething() {
        // Even with nothing allowed. "Leave nothing" is a legitimate Sleep
        // Mode, not a misconfiguration — and iOS never shields Phone, so it
        // cannot lock anyone out of a call.
        XCTAssertTrue(mode(style: .allowlist).blocksAnything)
        XCTAssertTrue(mode(style: .allowlist, allowedApps: 2).blocksAnything)
    }

    func testAnAllowlistCanStartASessionWithNothingChosenToBlock() {
        let h = Harness()
        var m = h.addEmptyMode(name: "Sleep")
        m.style = .allowlist
        h.store.modes = [m]

        guard case .dadded = h.engine.handleTap() else {
            return XCTFail("an allowlist Mode is always usable")
        }
        XCTAssertEqual(h.shield.appliedMode, m.id)
    }

    // MARK: - What it says

    func testTheTwoStylesDoNotReadAlike() {
        // The whole risk of inverting a Mode is picking a list and having it
        // mean the opposite of what you intended, so the summaries must not be
        // mistakable for one another.
        let blocking = mode(style: .blocklist, blockedApps: 3).summary
        let allowing = mode(style: .allowlist, allowedApps: 3).summary
        XCTAssertNotEqual(blocking, allowing)
        XCTAssertTrue(allowing.hasPrefix("Only "), allowing)
        XCTAssertFalse(blocking.hasPrefix("Only "), blocking)
    }

    func testAnAllowlistThatKeepsNothingSaysSo() {
        XCTAssertTrue(mode(style: .allowlist).summary.contains("Everything goes"),
                      mode(style: .allowlist).summary)
    }

    // MARK: - Rationing

    func testAnAllowlistModeRefusesToRation() {
        // `DeviceActivityEvent` counts a *named* set and has no "everything
        // except" form, and the categories cannot be enumerated from here. The
        // threshold would count nothing, never fire, and leave a Mode reading
        // "15 min a day" that lets you use the phone all day.
        var m = mode(style: .allowlist, allowedApps: 2)
        m.allowance = ModeAllowance(minutesPerDay: 15)
        XCTAssertFalse(m.rations)
    }

    func testTheSameAllowanceOnABlocklistIsAccepted() {
        var m = mode(style: .blocklist, blockedApps: 2)
        m.allowance = ModeAllowance(minutesPerDay: 15)
        XCTAssertTrue(m.rations)
    }

    func testAnAllowlistModeWithAnAllowanceBlocksRatherThanRations() {
        let h = Harness()
        var m = h.addMode(name: "Sleep", allowance: ModeAllowance(minutesPerDay: 15))
        m.style = .allowlist
        h.store.modes = [m]

        h.engine.dad(with: m)

        XCTAssertEqual(h.shield.appliedMode, m.id, "the apps go, rather than silently not being counted")
        XCTAssertTrue(h.usage.calls.isEmpty, "and nothing is asked to count them")
    }

    // MARK: - Switching between them

    func testSwitchingStyleAndBackKeepsBothLists() {
        // A separate field rather than reinterpreting `blocked`, so flipping a
        // Mode to see what the other shape looks like is not destructive.
        var m = mode(style: .blocklist, blockedApps: 3, allowedApps: 1)
        m.style = .allowlist
        m.style = .blocklist
        XCTAssertEqual(m.blocked.appCount, 3)
        XCTAssertEqual(m.allowedSelection.appCount, 1)
    }
}
