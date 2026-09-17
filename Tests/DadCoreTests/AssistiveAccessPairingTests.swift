import XCTest
@testable import DadCore

/// The half of the gesture Dad cannot perform.
///
/// Assistive Access is entered by a person triple-clicking a button, and no
/// API changes that — so the feature is a prompt at the one moment the person
/// is certainly holding the phone, and the tests that matter are about when it
/// is silent.
final class AssistiveAccessPairingTests: XCTestCase {

    // MARK: - When it speaks

    func testAModeThatAsksPromptsWhenTheSessionStarts() {
        let h = Harness()
        var mode = h.addMode(name: "Sleep")
        mode.asksForAssistiveAccess = true
        h.save(mode)

        h.engine.dad(with: mode)

        XCTAssertEqual(h.notifier.notices.count, 1)
        let notice = h.notifier.notices.first
        XCTAssertTrue(notice?.title.contains("Sleep") ?? false, notice?.title ?? "nothing")
        XCTAssertTrue(notice?.body.contains("Triple-click") ?? false, notice?.body ?? "nothing")
    }

    func testEndingASessionSaysNothing() {
        // The prompt is about a phone that just became simpler. Ending is the
        // opposite event, and the way back out is on the Assistive Access
        // screen where somebody inside the mode is already looking.
        let h = Harness()
        var mode = h.addMode(name: "Sleep")
        mode.asksForAssistiveAccess = true
        h.save(mode)

        h.engine.dad(with: mode)
        h.engine.unDad(.tapped)

        XCTAssertEqual(h.notifier.notices.count, 1)
    }

    // MARK: - When it stays quiet

    func testAModeThatDoesNotAskSaysNothing() {
        let h = Harness()
        let mode = h.addMode(name: "Gym")

        h.engine.dad(with: mode)

        XCTAssertTrue(h.notifier.notices.isEmpty)
    }

    func testTheNoticeReplacesRatherThanStacks() {
        // Two taps at the same tag is one phone, not two banners. The id is
        // what the system replaces on, so it has to be the same every time.
        let h = Harness()
        var mode = h.addMode(name: "Sleep")
        mode.asksForAssistiveAccess = true
        h.save(mode)

        h.engine.dad(with: mode)
        h.engine.unDad(.tapped)
        h.engine.dad(with: mode)

        XCTAssertEqual(Set(h.notifier.notices.map(\.id)).count, 1)
        XCTAssertEqual(h.notifier.notices.first?.id, AssistiveAccessPairing.noticeID)
    }

    // MARK: - The flag itself

    func testAModeStoredBeforeThisExistedDecodesAsNotAsking() {
        // The field is Optional for this reason and this reason only: a
        // non-optional one fails the synthesised decoder on every Mode written
        // before this build, and `LenientDecoding` skips what it cannot
        // decode — which would delete somebody's Modes rather than migrate
        // them.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Sleep","symbol":"moon.zzz.fill",
         "blocked":{"payload":"","appCount":0,"categoryCount":0,"webDomainCount":0},
         "isStrict":false}
        """.data(using: .utf8)!

        let mode = try? JSONDecoder().decode(DadMode.self, from: json)

        XCTAssertNotNil(mode, "a Mode written before the flag existed must still decode")
        XCTAssertEqual(mode?.asksForAssistiveAccess, false)
    }

    func testTheFlagRoundTrips() {
        var mode = DadMode(name: "Sleep", symbol: "moon.zzz.fill")
        mode.asksForAssistiveAccess = true

        let data = try? JSONEncoder().encode(mode)
        let back = data.flatMap { try? JSONDecoder().decode(DadMode.self, from: $0) }

        XCTAssertEqual(back?.asksForAssistiveAccess, true)
    }

    func testNoticeCopyIsNilRatherThanEmptyWhenTheModeIsSilent() {
        let mode = DadMode(name: "Gym", symbol: "figure.run")

        XCTAssertNil(AssistiveAccessPairing.noticeOnDad(mode: mode))
    }
}
