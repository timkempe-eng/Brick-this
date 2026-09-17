import XCTest
@testable import DadCore

/// What Dad says on a phone running in Assistive Access. The scene above this
/// is layout only, so this is where the mapping, the copy and — the part that
/// matters — the one button's permission check are pinned.
final class AssistiveAccessScreenTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_756_000_000) // 2025-08-24 02:26 UTC

    private func session(mode: String = "Deep Work", startedAt: Date? = nil) -> DadSession {
        DadSession(modeID: UUID(), modeName: mode, startedAt: startedAt ?? now.addingTimeInterval(-3600))
    }

    private func rationingMode() -> DadMode {
        DadMode(name: "Deep Work", symbol: "brain.head.profile",
                blocked: BlockedSelection(payload: Data([1]), appCount: 1),
                allowance: ModeAllowance(minutesPerDay: 15))
    }

    // MARK: - State mapping

    func testAnActiveSessionReadsAsDadded() {
        let screen = AssistiveAccessScreen.make(session: session(), now: now)

        XCTAssertEqual(screen, .dadded(modeName: "Deep Work", rationing: false, release: .tagOnly))
        XCTAssertEqual(screen.headline, Vocab.activeTitle)
        XCTAssertTrue(screen.isDadded)
    }

    func testNoSessionAndNoBreakReadsAsFree() {
        let screen = AssistiveAccessScreen.make(session: nil, now: now)

        XCTAssertEqual(screen, .free)
        XCTAssertEqual(screen.headline, Vocab.idleTitle)
        XCTAssertFalse(screen.isDadded)
    }

    func testABreakStillRunningReadsAsABreak() {
        let at = now.addingTimeInterval(900)
        let resume = PendingResume(modeID: UUID(), modeName: "Dinner", at: at)

        let screen = AssistiveAccessScreen.make(session: nil, pendingResume: resume, now: now)

        XCTAssertEqual(screen, .onBreak(modeName: "Dinner", until: at))
        XCTAssertEqual(screen.headline, Vocab.breakTitle)
    }

    func testABreakAlreadyDueReadsAsFree() {
        // Due means the Mode is about to start itself again; until it does the
        // phone is free, and saying "you're on a break" about a break that has
        // run out is the kind of stale sentence this screen has least room for.
        let resume = PendingResume(modeID: UUID(), modeName: "Dinner", at: now)

        XCTAssertEqual(AssistiveAccessScreen.make(session: nil, pendingResume: resume, now: now), .free)
    }

    func testASessionBeatsALingeringBreak() {
        let resume = PendingResume(modeID: UUID(), modeName: "Dinner", at: now.addingTimeInterval(900))

        let screen = AssistiveAccessScreen.make(session: session(), pendingResume: resume, now: now)

        XCTAssertTrue(screen.isDadded)
    }

    // MARK: - The third state

    func testARationingModeSaysTheAppsAreStillThere() {
        let screen = AssistiveAccessScreen.make(session: session(), mode: rationingMode(), now: now)

        XCTAssertEqual(screen, .dadded(modeName: "Deep Work", rationing: true, release: .tagOnly))
        XCTAssertEqual(screen.detail, "Deep Work. Your apps are still here for now.")
        XCTAssertEqual(screen.symbolName, "hourglass")
    }

    func testASpentAllowanceReadsAsBlockingRatherThanRationing() {
        var spent = session()
        spent.allowanceSpentAt = now.addingTimeInterval(-600)

        let screen = AssistiveAccessScreen.make(session: spent, mode: rationingMode(), now: now,
                                                calendar: calendar)

        XCTAssertEqual(screen, .dadded(modeName: "Deep Work", rationing: false, release: .tagOnly))
        XCTAssertEqual(screen.symbolName, "lock.iphone")
    }

    // MARK: - The one button

    func testTheTagIsTheOnlyWayOutWhenThePhoneMayNotOverride() {
        let screen = AssistiveAccessScreen.make(session: session(), mayOverride: false,
                                                emergencyOverridesRemaining: 5, now: now)

        XCTAssertEqual(screen, .dadded(modeName: "Deep Work", rationing: false, release: .tagOnly))
        XCTAssertNil(screen.actionTitle)
        XCTAssertNil(screen.actionFootnote)
    }

    func testTheTagIsTheOnlyWayOutWhenTheAllowanceIsSpent() {
        let screen = AssistiveAccessScreen.make(session: session(), mayOverride: true,
                                                emergencyOverridesRemaining: 0, now: now)

        XCTAssertEqual(screen, .dadded(modeName: "Deep Work", rationing: false, release: .tagOnly))
        XCTAssertNil(screen.actionTitle)
    }

    func testTheOverrideIsOfferedWhenItIsAllowedAndSomeAreLeft() {
        let screen = AssistiveAccessScreen.make(session: session(), mayOverride: true,
                                                emergencyOverridesRemaining: 2, now: now)

        XCTAssertEqual(screen, .dadded(modeName: "Deep Work", rationing: false,
                                       release: .emergency(remaining: 2)))
        XCTAssertEqual(screen.actionTitle, Vocab.emergencyUnDad)
        XCTAssertEqual(screen.actionFootnote, "Only for an emergency. 2 left this month.")
    }

    func testTheOverrideIsWithheldByDefault() {
        // The permission defaults to refused, so a call site that forgets to
        // pass it loses the button rather than silently handing a young
        // person's phone an escape hatch its role does not allow.
        let screen = AssistiveAccessScreen.make(session: session(),
                                                emergencyOverridesRemaining: 5, now: now)

        XCTAssertNil(screen.actionTitle)
    }

    func testThereIsNoButtonWhenThePhoneIsFreeOrOnABreak() {
        let resume = PendingResume(modeID: UUID(), modeName: "Dinner", at: now.addingTimeInterval(900))

        for screen in [AssistiveAccessScreen.make(session: nil, mayOverride: true,
                                                  emergencyOverridesRemaining: 5, now: now),
                       AssistiveAccessScreen.make(session: nil, pendingResume: resume,
                                                  mayOverride: true,
                                                  emergencyOverridesRemaining: 5, now: now)] {
            XCTAssertNil(screen.actionTitle, "\(screen)")
            XCTAssertNil(screen.actionFootnote, "\(screen)")
        }
    }

    // MARK: - Copy

    func testEveryStateNamesTheModeAndSaysWhatToDo() {
        let resume = PendingResume(modeID: UUID(), modeName: "Dinner", at: now.addingTimeInterval(900))

        let dadded = AssistiveAccessScreen.make(session: session(), now: now)
        XCTAssertTrue(dadded.detail.contains("Deep Work"), dadded.detail)
        XCTAssertTrue(dadded.detail.contains(Vocab.tagNoun), dadded.detail)

        let onBreak = AssistiveAccessScreen.make(session: nil, pendingResume: resume, now: now)
        XCTAssertTrue(onBreak.detail.contains("Dinner"), onBreak.detail)
        XCTAssertTrue(onBreak.detail.contains(Vocab.tagNoun), onBreak.detail)

        XCTAssertEqual(AssistiveAccessScreen.make(session: nil, now: now).detail, Vocab.idleSubtitle)
    }

    func testTheReleaseHintKeepsTheVerbCapitalised() {
        // Hard rule 4, in the sentences this screen adds to the vocabulary.
        XCTAssertTrue(Vocab.assistiveAccessExitHint.contains("Dad tag"))
        XCTAssertFalse(Vocab.assistiveAccessExitHint.lowercased() == Vocab.assistiveAccessExitHint)
    }

    func testTheDaddedLineNamesTheTripleClickBeforeTheTag() {
        // The order is the whole content of the sentence: leaving Assistive
        // Access needs its passcode, and no amount of tapping substitutes.
        // Somebody who reads it the other way round taps a tag that may not
        // reach anything and concludes the tag is broken.
        let detail = AssistiveAccessScreen.make(session: session(), now: now).detail

        let click = try? XCTUnwrap(detail.range(of: "Triple-click"))
        let tag = try? XCTUnwrap(detail.range(of: Vocab.tagNoun))
        XCTAssertNotNil(click)
        XCTAssertNotNil(tag)
        if let click, let tag { XCTAssertTrue(click.lowerBound < tag.lowerBound, detail) }
    }
}

/// The seam. Two surfaces answer "is this phone Dadded" from the same stored
/// state, in two different processes, and neither one's own suite can see them
/// disagree — which is the shape every real defect in the fan-out had.
final class AssistiveAccessAgreesWithTheWidgetTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testBothSurfacesAgreeAboutEveryStoredState() {
        let live = DadSession(modeID: UUID(), modeName: "Deep Work",
                              startedAt: now.addingTimeInterval(-3600))
        var spent = live
        spent.allowanceSpentAt = now.addingTimeInterval(-600)

        let rationing = DadMode(name: "Deep Work", symbol: "brain.head.profile",
                                blocked: BlockedSelection(payload: Data([1]), appCount: 1),
                                allowance: ModeAllowance(minutesPerDay: 15))
        let blocking = DadMode(name: "Deep Work", symbol: "brain.head.profile",
                               blocked: BlockedSelection(payload: Data([1]), appCount: 1))

        let breaks = [nil,
                      PendingResume(modeID: UUID(), modeName: "Dinner", at: now.addingTimeInterval(900)),
                      PendingResume(modeID: UUID(), modeName: "Dinner", at: now)]

        for session in [nil, live, spent] {
            for mode in [nil, rationing, blocking] {
                for pending in breaks {
                    let screen = AssistiveAccessScreen.make(session: session, mode: mode,
                                                            pendingResume: pending,
                                                            now: now, calendar: calendar)
                    let widget = WidgetSnapshot.make(session: session, mode: mode,
                                                     stats: DadStats(sessions: [], now: now,
                                                                     calendar: calendar),
                                                     pendingResume: pending,
                                                     now: now, calendar: calendar)
                    let context = "session: \(session != nil), mode: \(mode?.rations ?? false), "
                        + "break: \(pending?.at.timeIntervalSince1970 ?? 0)"

                    XCTAssertEqual(screen.isDadded, widget.isDadded, context)
                    XCTAssertEqual(screen.symbolName, widget.symbolName, context)

                    if case .dadded(let screenMode, let screenRationing, _) = screen {
                        guard case .dadded(let widgetMode, _, let widgetRationing) = widget else {
                            return XCTFail("widget disagreed: \(context)")
                        }
                        XCTAssertEqual(screenMode, widgetMode, context)
                        XCTAssertEqual(screenRationing, widgetRationing, context)
                    }
                    if case .onBreak(let screenMode, let screenUntil) = screen {
                        guard case .onBreak(let widgetMode, let widgetUntil) = widget else {
                            return XCTFail("widget disagreed: \(context)")
                        }
                        XCTAssertEqual(screenMode, widgetMode, context)
                        XCTAssertEqual(screenUntil, widgetUntil, context)
                    }
                }
            }
        }
    }
}
