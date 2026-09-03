import XCTest
@testable import DadCore

/// The autonomy ladder and the reward ledger must be spending the *same* days.
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
                          endedAt: start.addingTimeInterval(30 * 60),
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

        XCTAssertEqual(rewards.earned.count, ladder.cleanDayCount,
                       """
                       A day that buys a rung must be a day that buys a reward. \
                       They read the same history and each used to state the \
                       counting rule itself.
                       """)
    }

    /// And the number is not trivially zero or trivially everything, or the
    /// agreement above would hold for a rule that had stopped working.
    func testThatNumberIsNeitherNothingNorEverything() {
        let history = everyKindOfHistory
        let ladder = AutonomyLadder(sessions: history, now: now, calendar: calendar)

        XCTAssertEqual(ladder.cleanDayCount, 4, """
            Four days somebody ended a session on: tapped, tapped after a \
            schedule opened it, one legacy session that was not an override, \
            and the day with both a bail and a finish.
            """)
        XCTAssertEqual(history.daysWithASession(calendar: calendar).count, 7,
                       "seven distinct days had a session of some kind")
    }

    func testEveryEndingIsRepresentedInThatHistory() {
        // Otherwise the agreement above is over a history missing the case
        // that would break it — which is how a passing suite hides a defect.
        let endings = Set(everyKindOfHistory.map(\.endedBy))
        XCTAssertEqual(endings, [.tapped, .emergency, .system, nil])
    }
}
