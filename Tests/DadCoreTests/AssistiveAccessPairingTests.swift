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

    /// The seam, and it was open: the engine reads the household's role and
    /// hands it to the copy, and nothing checked that it read anything at all.
    /// Hardcoding `.grownUp` there passed the whole suite — a young person's
    /// phone would have been told to press a button and met a passcode with no
    /// explanation, which is the one failure this copy exists to prevent.
    func testTheEngineTellsTheCopyWhosePhoneThisIs() {
        let h = Harness()
        h.store.household = Household(role: .youngPerson, autonomyLevel: 0)
        var mode = h.addMode(name: "Sleep")
        mode.asksForAssistiveAccess = true
        h.save(mode)

        h.engine.dad(with: mode)

        XCTAssertEqual(h.notifier.notices.first?.body,
                       Vocab.assistiveAccessPromptBody(role: .youngPerson))
    }

    func testAGrownUpsPhoneGetsTheGrownUpsSentence() {
        let h = Harness()
        h.store.household = Household(role: .grownUp, autonomyLevel: 0)
        var mode = h.addMode(name: "Sleep")
        mode.asksForAssistiveAccess = true
        h.save(mode)

        h.engine.dad(with: mode)

        XCTAssertEqual(h.notifier.notices.first?.body,
                       Vocab.assistiveAccessPromptBody(role: .grownUp))
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

        for role in HouseholdRole.allCases {
            XCTAssertNil(AssistiveAccessPairing.noticeOnDad(mode: mode, role: role), "\(role)")
        }
    }

    // MARK: - Who can actually finish it

    /// Measured on a phone on 2026-09-17: the triple-click asked for the Screen
    /// Time passcode. Apple's setup page says the Assistive Access passcode "is
    /// used to enter or exit", so this is not a one-device quirk — entry is
    /// gated, and a young person's phone cannot complete the gesture alone.
    func testAYoungPersonIsToldWhatTheyNeedRatherThanJustToPress() {
        var mode = DadMode(name: "Sleep", symbol: "moon.zzz.fill")
        mode.asksForAssistiveAccess = true

        let notice = AssistiveAccessPairing.noticeOnDad(mode: mode, role: .youngPerson)

        // The whole point: it names the passcode and who holds it. Telling a
        // phone that cannot finish to press a button is how somebody concludes
        // the app is broken.
        XCTAssertTrue(notice?.body.contains("grown-up") ?? false, notice?.body ?? "nothing")
        XCTAssertTrue(notice?.body.contains("passcode") ?? false, notice?.body ?? "nothing")
    }

    func testAGrownUpIsToldItWillAskForTheirPasscode() {
        var mode = DadMode(name: "Sleep", symbol: "moon.zzz.fill")
        mode.asksForAssistiveAccess = true

        let notice = AssistiveAccessPairing.noticeOnDad(mode: mode, role: .grownUp)

        XCTAssertTrue(notice?.body.contains("Triple-click") ?? false, notice?.body ?? "nothing")
        XCTAssertTrue(notice?.body.contains("passcode") ?? false, notice?.body ?? "nothing")
    }

    func testEveryRoleGetsASentenceThatMentionsThePasscode() {
        // Walk the whole enum rather than the two that exist today: a role
        // added later with no copy of its own would otherwise ship a prompt
        // nobody wrote, and the compiler only catches that if the switch is
        // exhaustive — which it is, so this guards the sentence rather than
        // the switch.
        var mode = DadMode(name: "Sleep", symbol: "moon.zzz.fill")
        mode.asksForAssistiveAccess = true

        for role in HouseholdRole.allCases {
            let body = AssistiveAccessPairing.noticeOnDad(mode: mode, role: role)?.body
            XCTAssertTrue(body?.contains("passcode") ?? false, "\(role): \(body ?? "nothing")")
        }
    }
}
