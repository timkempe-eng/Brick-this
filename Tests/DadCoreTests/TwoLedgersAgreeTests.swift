import XCTest
@testable import DadCore

/// The autonomy ladder and the reward ledger must be reading the *same*
/// sessions — the ladder counting the days, the ledger the whole hours.
///
/// They are separate on purpose — one pot split between "a lift into town" and
/// "setting my own Sleep window" would make the concrete reward beat the
/// abstract one every week — but they read the same evidence, and the two files
/// each wrote the counting rule out when they were built by different hands.
/// The copies had already drifted before they met.
///
/// So this asserts the shape that catches it: build one history containing
/// every kind of ending, and check the two modules agree about it, rather than
/// check each against itself. That is the guard the fan-out taught this repo to
/// write.
final class TwoLedgersAgreeTests: XCTestCase {

    private let calendar: Calendar = .utc
    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func session(daysAgo: Int, _ ending: DadSession.EndReason?,
                         bySchedule: Bool? = nil, legacyEmergency: Bool = false) -> DadSession {
        let start = calendar.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * 86_400))
            .addingTimeInterval(20 * 60 * 60)
        return DadSession(modeID: UUID(),
                          modeName: "Sleep",
                          startedAt: start,
                          endedAt: start.addingTimeInterval(90 * 60),
                          endedByEmergency: legacyEmergency || ending == .emergency,
                          endedBy: ending,
                          startedBySchedule: bySchedule)
    }

    /// One session of every kind there is, on its own day.
    private var everyKindOfHistory: [DadSession] {
        [
            session(daysAgo: 1, .tapped),
            session(daysAgo: 2, .emergency),
            session(daysAgo: 3, .system, bySchedule: true),
            session(daysAgo: 4, .tapped, bySchedule: true),
            // A grown-up's granted release, a timer the person set, and a
            // timer on a session a schedule started.
            session(daysAgo: 8, .granted),
            session(daysAgo: 9, .timed),
            session(daysAgo: 10, .timed, bySchedule: true),
            // Recorded before `endedBy` existed: nothing can tell how it
            // ended, so the fallback is the one bit that was stored.
            session(daysAgo: 5, nil),
            session(daysAgo: 6, nil, legacyEmergency: true),
            // Two on one day, one of each, so the "the day contains the
            // evidence" rule is exercised rather than assumed.
            session(daysAgo: 7, .emergency),
            session(daysAgo: 7, .tapped),
        ]
    }

    func testTheLadderAndTheRewardsCountTheSameDays() {
        let history = everyKindOfHistory
        let ladder = AutonomyLadder(sessions: history, now: now, calendar: calendar)
        let rewards = RewardLedger(sessions: history, now: now, calendar: calendar)

        XCTAssertEqual(Set(rewards.hoursByDay.keys),
                       history.daysEndedByAPerson(calendar: calendar))
        XCTAssertEqual(rewards.hoursByDay.count, ladder.cleanDayCount,
                       """
                       A day that counts toward a rung must be a day the ledger \
                       credits. They read the same history and each used to state \
                       the counting rule itself.
                       """)
    }

    /// And the hours come from exactly those sessions. Every session in the
    /// history is ninety minutes, so each one a person ended is worth one hour
    /// and each one they did not is worth none — the hours are the count of
    /// qualifying sessions, which a rule paying for the wrong ending would
    /// miss in one direction or the other.
    func testTheHoursComeFromTheSessionsTheLadderCounts() {
        let history = everyKindOfHistory
        let rewards = RewardLedger(sessions: history, now: now, calendar: calendar)
        XCTAssertEqual(rewards.earned.count, history.filter(\.wasEndedByAPerson).count)
        XCTAssertEqual(rewards.earned.count, 6)
    }

    /// And the number is not trivially zero or trivially everything, or the
    /// agreement above would hold for a rule that had stopped working.
    func testThatNumberIsNeitherNothingNorEverything() {
        let history = everyKindOfHistory
        let ladder = AutonomyLadder(sessions: history, now: now, calendar: calendar)

        XCTAssertEqual(ladder.cleanDayCount, 6, """
            Six days somebody ended a session on: tapped, tapped after a \
            schedule opened it, one legacy session that was not an override, \
            the day with both a bail and a finish, a granted release, and a \
            timer set by hand.
            """)
        XCTAssertEqual(history.daysWithASession(calendar: calendar).count, 10,
                       "ten distinct days had a session of some kind")
    }

    func testEveryEndingIsRepresentedInThatHistory() {
        // Otherwise the agreement above is over a history missing the case
        // that would break it — which is how a passing suite hides a defect.
        let endings = Set(everyKindOfHistory.map(\.endedBy))
        XCTAssertEqual(endings, [.tapped, .emergency, .granted, .timed, .system, nil])
    }
}
