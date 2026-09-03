import XCTest
@testable import DadCore

/// The ladder measures a habit somebody is holding, not a phone that runs
/// itself.
///
/// Found by review, and it was the same shape as the rung-count bug: the
/// ladder counted "clean days" as any day with a session that wasn't an
/// emergency override, and `DadSession` only ever stored that one bit. So a
/// nightly Sleep schedule — a window opening and closing while the phone sat
/// on a table — climbed all four rungs in sixty-one nights of nobody touching
/// anything. Rung four hands over the tag.
final class LadderParticipationTests: XCTestCase {

    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func nights(_ count: Int, endedBy: DadSession.EndReason?) -> [DadSession] {
        (1...count).map { offset in
            let day = now.addingTimeInterval(-Double(offset) * 24 * 60 * 60)
            var s = DadSession(modeID: UUID(), modeName: "Sleep", startedAt: day)
            s.endedAt = day.addingTimeInterval(8 * 3600)
            s.endedBy = endedBy
            s.endedByEmergency = endedBy == .emergency
            s.startedBySchedule = endedBy == .system ? true : nil
            return s
        }
    }

    private func ladder(_ sessions: [DadSession]) -> AutonomyLadder {
        AutonomyLadder(sessions: sessions, now: now, calendar: utc)
    }

    func testAPhoneThatDadsItselfEveryNightEarnsNothing() {
        // Sixty-one nights, every one opened and closed by the schedule.
        // Owning a scheduled phone is not consistency.
        let ladder = ladder(nights(61, endedBy: .system))
        XCTAssertEqual(ladder.cleanDayCount, 0)
        XCTAssertEqual(ladder.rung, .gettingStarted)
        XCTAssertFalse(RolePermissions.for(role: .youngPerson, autonomyLevel: ladder.level)
                        .may(.unpairTag), "the tag is not handed over for doing nothing")
    }

    func testWalkingBackToTheTagIsWhatCounts() {
        let ladder = ladder(nights(61, endedBy: .tapped))
        XCTAssertEqual(ladder.cleanDayCount, 61)
        XCTAssertGreaterThan(ladder.rung, .gettingStarted)
    }

    func testAnOverrideStillDoesNotCount() {
        XCTAssertEqual(ladder(nights(61, endedBy: .emergency)).cleanDayCount, 0)
    }

    func testATimedReleaseIsNotParticipationEither() {
        // "Dad me for an hour" and then walking away is the phone finishing
        // the session, not the person.
        var timed = nights(30, endedBy: .system)
        for i in timed.indices { timed[i].startedBySchedule = nil }
        XCTAssertEqual(ladder(timed).cleanDayCount, 0)
    }

    func testAMixedDayCountsIfThePersonEndedAnyOfIt() {
        let day = now.addingTimeInterval(-24 * 60 * 60)
        var scheduled = DadSession(modeID: UUID(), modeName: "Sleep", startedAt: day)
        scheduled.endedAt = day.addingTimeInterval(3600)
        scheduled.endedBy = .system
        var tapped = DadSession(modeID: UUID(), modeName: "Deep Work",
                                startedAt: day.addingTimeInterval(2 * 3600))
        tapped.endedAt = day.addingTimeInterval(3 * 3600)
        tapped.endedBy = .tapped

        XCTAssertEqual(ladder([scheduled, tapped]).cleanDayCount, 1,
                       "the day contains the evidence")
    }

    // MARK: - What is already on somebody's phone

    func testSessionsRecordedBeforeTheEndingWasStoredKeepTheirOldMeaning() {
        // Retroactively erasing somebody's ladder progress on the morning they
        // update is not an option. Old records fall back to the one bit that
        // was stored, which is the old definition of clean applied to old data.
        XCTAssertEqual(ladder(nights(30, endedBy: nil)).cleanDayCount, 30)

        var bailed = nights(30, endedBy: nil)
        for i in bailed.indices { bailed[i].endedByEmergency = true }
        XCTAssertEqual(ladder(bailed).cleanDayCount, 0,
                       "and an old override is still an override")
    }

    // MARK: - The engine records it

    func testTheEngineWritesDownHowEachSessionEnded() {
        let h = Harness()
        let mode = h.addMode()

        h.engine.dad(with: mode)
        h.engine.handleTap()
        XCTAssertEqual(h.store.history.last?.endedBy, .tapped)

        h.engine.dad(with: mode)
        h.engine.emergencyUnDad()
        XCTAssertEqual(h.store.history.last?.endedBy, .emergency)

        // Starting a second Mode closes the first, and nobody ended it.
        h.engine.dad(with: mode)
        h.engine.dad(with: h.addMode(name: "Other"))
        XCTAssertEqual(h.store.history.last?.endedBy, .system)
    }

    func testAScheduledNightEndedByItsOwnBoundaryIsRecordedAsTheSystems() {
        let h = Harness()
        let sleep = h.addMode(name: "Sleep",
                              schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                                     endHour: 7, endMinute: 0,
                                                     weekdays: ModeSchedule.everyDay))
        h.engine.beginScheduledSession(modeID: sleep.id)
        h.engine.endScheduledSession(modeID: sleep.id)

        XCTAssertEqual(h.store.history.last?.endedBy, .system)
        XCTAssertFalse(h.store.history.last?.wasEndedByAPerson ?? true)
    }
}
