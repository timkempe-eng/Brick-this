import XCTest
@testable import DadCore

/// The reward hours through the engine, at the places they used to leak.
///
/// `RewardLedgerTests` covers the arithmetic over a history somebody hands it.
/// These cover how that history gets written: which endings keep a session's
/// hours, and what happens to them when the bounded history lets the session
/// go. Each was a way for hours to disappear with nobody doing anything wrong.
final class RewardHoursEndToEndTests: XCTestCase {

    private let calendar: Calendar = .utc
    private let hour: TimeInterval = 3600

    private func ended(_ startedAt: Date, lasting: TimeInterval,
                       _ ending: DadSession.EndReason = .tapped,
                       bySchedule: Bool? = nil) -> DadSession {
        DadSession(modeID: UUID(), modeName: "Evening",
                   startedAt: startedAt,
                   endedAt: startedAt.addingTimeInterval(lasting),
                   endedByEmergency: ending == .emergency,
                   endedBy: ending,
                   startedBySchedule: bySchedule)
    }

    // MARK: - A granted break keeps the hours before it

    func testAGrantedBreakKeepsTheHoursBeforeIt() {
        // Three hours in, an ask, a grown-up's tag. The session used to end
        // `.system`, which earns nothing — three hours gone for following
        // every rule there is.
        let h = Harness()
        let mode = h.addMode()
        h.engine.pair(tagUID: "PARENT")
        h.engine.dad(with: mode)
        h.clock.advance(3 * hour + 5 * 60)
        h.engine.requestRelease()
        h.engine.grantRelease(byTagUID: "PARENT")

        XCTAssertEqual(h.store.history.last?.endedBy, .granted)
        XCTAssertEqual(h.engine.rewardLedger.earned, RewardLedger.Hours(3))
    }

    // MARK: - A timer the person set keeps its hours

    func testATimedReleaseKeepsItsHours() {
        let h = Harness()
        let mode = h.addMode(autoRelease: 2 * hour)
        h.engine.dad(with: mode)
        h.clock.advance(2 * hour + 60)
        h.engine.reconcile()

        XCTAssertNil(h.store.activeSession, "the timer released it")
        XCTAssertEqual(h.store.history.last?.endedBy, .timed)
        XCTAssertEqual(h.engine.rewardLedger.earned, RewardLedger.Hours(2))
    }

    func testATimerOnASessionAScheduleStartedIsStillTheSchedule() {
        // Nobody chose that timer at the moment it ran. It is the overnight
        // Sleep window again, by another route.
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        XCTAssertFalse(ended(start, lasting: 8 * hour, .timed, bySchedule: true).wasEndedByAPerson)
        XCTAssertTrue(ended(start, lasting: 8 * hour, .timed, bySchedule: nil).wasEndedByAPerson)
        XCTAssertTrue(ended(start, lasting: 8 * hour, .granted).wasEndedByAPerson)
    }

    func testTheStoredSchemaKnowsAboutTheNewEndings() {
        // A build that predates `.granted` and `.timed` drops any session
        // carrying one and writes the shorter history back. The bump to 3 is
        // what makes that build read `.tooNew` and leave the history alone.
        XCTAssertGreaterThanOrEqual(SchemaCoding.current, 3)
    }

    // MARK: - The trim does not take hours with it

    /// A full history: `head` first (the oldest, next to be trimmed), then
    /// five-minute sessions on earlier days that earn nothing, up to the limit.
    private func fullHistory(after head: [DadSession], now: Date) -> [DadSession] {
        let fillerCount = DadEngine.historyLimit - head.count
        let filler = (0..<fillerCount).map { i in
            ended(now.addingTimeInterval(-Double(fillerCount - i) * 600 - hour),
                  lasting: 300)
        }
        return head + filler
    }

    func testHoursFromATrimmedSessionStayInTheBalance() throws {
        let h = Harness()
        let mode = h.addMode()
        let longAgo = h.clock.now.addingTimeInterval(-40 * 86_400)
        h.store.history = fullHistory(after: [ended(longAgo, lasting: 3 * hour)],
                                      now: h.clock.now)
        XCTAssertEqual(h.engine.rewardLedger.earned, RewardLedger.Hours(3))

        // One more session pushes the oldest off the end.
        h.engine.dad(with: mode)
        h.clock.advance(10 * 60)
        h.engine.unDad(.tapped)

        XCTAssertEqual(h.store.history.count, DadEngine.historyLimit)
        XCTAssertFalse(h.store.history.contains { $0.startedAt == longAgo }, "trimmed")
        XCTAssertEqual(h.engine.rewardLedger.earned, RewardLedger.Hours(3),
                       "and its hours were not trimmed with it")
        let archived = try XCTUnwrap(h.store.archivedRewardHours.first)
        XCTAssertEqual(archived.day, calendar.startOfDay(for: longAgo))
        XCTAssertEqual(archived.hours, RewardLedger.Hours(3))
    }

    func testADaySplitByTheTrimEarnsItsCeilingOnce() {
        // Three hours archived and three still in the history, on the same
        // day. Capped separately that is eight; it is four.
        let h = Harness()
        let mode = h.addMode()
        let day = h.clock.now.addingTimeInterval(-40 * 86_400)
        h.store.history = fullHistory(after: [ended(day, lasting: 3 * hour),
                                              ended(day.addingTimeInterval(4 * hour),
                                                    lasting: 3 * hour)],
                                      now: h.clock.now)
        h.engine.dad(with: mode)
        h.clock.advance(10 * 60)
        h.engine.unDad(.tapped)

        XCTAssertEqual(h.store.archivedRewardHours.count, 1, "only the first was trimmed")
        XCTAssertEqual(h.engine.rewardLedger.hoursByDay[calendar.startOfDay(for: day)],
                       RewardLedger.hoursCountedPerDay)
    }

    func testATrimmedSessionThatEarnedNothingWritesNothing() {
        // An override earns nothing; so does forty minutes ended at the tag,
        // though that one's day is a clean day and so has a key at zero. A
        // row of nothing per short session would grow without bound.
        let earnedNothing: [(TimeInterval, DadSession.EndReason)] = [(3 * hour, .emergency), (40 * 60, .tapped)]
        for (length, ending) in earnedNothing {
            let h = Harness()
            let mode = h.addMode()
            let longAgo = h.clock.now.addingTimeInterval(-40 * 86_400)
            h.store.history = fullHistory(after: [ended(longAgo, lasting: length, ending)],
                                          now: h.clock.now)
            h.engine.dad(with: mode)
            h.clock.advance(10 * 60)
            h.engine.unDad(.tapped)

            XCTAssertTrue(h.store.archivedRewardHours.isEmpty, "\(ending)")
        }
    }

    func testTwoTrimsFromTheSameDayAddUp() {
        // The day leaves the history one session at a time, and each trim
        // adds to what the last one wrote rather than replacing it.
        let h = Harness()
        let mode = h.addMode()
        let day = h.clock.now.addingTimeInterval(-40 * 86_400)
        h.store.history = fullHistory(after: [ended(day, lasting: 1 * hour),
                                              ended(day.addingTimeInterval(2 * hour),
                                                    lasting: 2 * hour)],
                                      now: h.clock.now)
        for _ in 0..<2 {
            h.engine.dad(with: mode)
            h.clock.advance(10 * 60)
            h.engine.unDad(.tapped)
        }

        XCTAssertEqual(h.store.archivedRewardHours,
                       [.init(day: calendar.startOfDay(for: day), hours: RewardLedger.Hours(3))])
        XCTAssertEqual(h.engine.rewardLedger.earned, RewardLedger.Hours(3))
    }

    func testArchivedHoursAddToTheSameDayBeforeTheCeiling() {
        let start = Date(timeIntervalSince1970: 1_756_000_000).addingTimeInterval(-3 * 86_400)
        let day = calendar.startOfDay(for: start)
        let ledger = RewardLedger(sessions: [ended(start, lasting: 2 * hour)],
                                  archived: [.init(day: day, hours: RewardLedger.Hours(1))],
                                  now: Date(timeIntervalSince1970: 1_756_000_000),
                                  calendar: calendar)
        XCTAssertEqual(ledger.hoursByDay[day], RewardLedger.Hours(3))

        let over = RewardLedger(sessions: [ended(start, lasting: 2 * hour)],
                                archived: [.init(day: day, hours: RewardLedger.Hours(3))],
                                now: Date(timeIntervalSince1970: 1_756_000_000),
                                calendar: calendar)
        XCTAssertEqual(over.hoursByDay[day], RewardLedger.hoursCountedPerDay)
    }

    func testAnArchivedRowMissingAFieldDecodesRatherThanVanishing() {
        // Dropped, it would be the hours this list exists to keep.
        let json = Data(#"[{"day":0},{"hours":2},{}]"#.utf8)
        let rows = LenientDecoding.array(RewardLedger.ArchivedDay.self, from: json)
        XCTAssertEqual(rows?.count, 3)
        XCTAssertEqual(rows?[1].hours, RewardLedger.Hours(2))
    }

    // MARK: - Progress while it runs

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func running(for elapsed: TimeInterval) -> DadSession {
        DadSession(modeID: UUID(), modeName: "Evening",
                   startedAt: now.addingTimeInterval(-elapsed), endedAt: nil)
    }

    func testNoProgressWithoutARunningSession() {
        XCTAssertNil(HourProgress(session: nil, earnedThatDay: .zero, now: now))
        XCTAssertNil(HourProgress(session: ended(now, lasting: hour),
                                  earnedThatDay: .zero, now: now))
    }

    func testTheFirstHourCountsDown() {
        let p = HourProgress(session: running(for: 42 * 60), earnedThatDay: .zero, now: now)
        XCTAssertEqual(p?.hoursSoFar, RewardLedger.Hours(0))
        XCTAssertEqual(p?.text(at: now), "First reward hour in 18 min")
    }

    func testLaterHoursSaySoFarAndNext() {
        let p = HourProgress(session: running(for: 2 * hour + 18 * 60),
                             earnedThatDay: .zero, now: now)
        XCTAssertEqual(p?.hoursSoFar, RewardLedger.Hours(2))
        XCTAssertEqual(p?.text(at: now), "2 hours so far · next in 42 min")
    }

    func testTheCountdownStopsAtTheDaysCeiling() {
        // Three already earned today: one more fits, and then nothing —
        // however long it has run.
        let p = HourProgress(session: running(for: 3 * hour + 10 * 60),
                             earnedThatDay: RewardLedger.Hours(3), now: now)
        XCTAssertEqual(p?.hoursSoFar, RewardLedger.Hours(1))
        XCTAssertNil(p?.nextHourAt)
        XCTAssertEqual(p?.text(at: now), "Today's 4 hours are in")

        let full = HourProgress(session: running(for: 10 * 60),
                                earnedThatDay: RewardLedger.hoursCountedPerDay, now: now)
        XCTAssertEqual(full?.hoursSoFar, RewardLedger.Hours(0))
        XCTAssertNil(full?.nextHourAt)
    }

    func testTheMinutesRoundUpSoTheyNeverReadZero() {
        let p = HourProgress(session: running(for: hour - 10), earnedThatDay: .zero, now: now)
        XCTAssertEqual(p?.minutesToNextHour(at: now), 1)
        let q = HourProgress(session: running(for: 30), earnedThatDay: .zero, now: now)
        XCTAssertEqual(q?.minutesToNextHour(at: now), 60)
    }

    func testTheEngineReadsWhatTheSessionsDayHasAlreadyEarned() {
        let h = Harness()
        let mode = h.addMode()
        h.engine.dad(with: mode)
        h.clock.advance(2 * hour)
        h.engine.unDad(.tapped)
        XCTAssertEqual(h.engine.hoursEarnedOnRunningSessionsDay, .zero, "nothing running")

        h.engine.dad(with: mode)
        XCTAssertEqual(h.engine.hoursEarnedOnRunningSessionsDay, RewardLedger.Hours(2))
    }
}
