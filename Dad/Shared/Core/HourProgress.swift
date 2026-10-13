import Foundation

/// The running session, read against the reward hours: how many it has made so
/// far, and how long until the next one.
///
/// A forecast, not a balance. `RewardLedger` counts a session only once it has
/// ended, and only if a person ended it — so these hours are what the session
/// *would* earn if it were ended that way now, and the copy says so. Showing
/// them in the balance while it runs would let them appear and then vanish if
/// it ended with an override.
///
/// Here rather than in `RewardLedger.swift` because it measures a duration,
/// which that file's source test forbids.
struct HourProgress: Equatable {

    /// Whole hours so far, after whatever the session's day had already
    /// earned — never more than that day has room for.
    let hoursSoFar: RewardLedger.Hours

    /// When the next hour lands, or `nil` when the day's ceiling is reached
    /// and further time earns nothing. Skips the night: started at 22:30, the
    /// next hour lands at 06:30.
    let nextHourAt: Date?

    /// Whether `now` is in `RewardNight`, when nothing is counting.
    let isNight: Bool

    /// - Parameters:
    ///   - session: the running session; `nil` or a finished one gives `nil`.
    ///   - earnedThatDay: what the ledger already credits to the day the
    ///     session started — the day its hours will land on.
    init?(session: DadSession?, earnedThatDay: RewardLedger.Hours, now: Date,
          calendar: Calendar) {
        guard let session, session.isActive else { return nil }
        let room = (RewardLedger.hoursCountedPerDay - earnedThatDay).count
        let counted = RewardNight.countedSeconds(from: session.startedAt, to: now,
                                                 calendar: calendar)
        let elapsed = Int(counted / 3600)
        hoursSoFar = RewardLedger.Hours(min(elapsed, room))
        nextHourAt = elapsed < room
            ? RewardNight.instant(reaching: TimeInterval(elapsed + 1) * 3600,
                                  from: session.startedAt, calendar: calendar)
            : nil
        isNight = RewardNight.isNight(now, calendar: calendar)
    }

    /// Whole minutes until the next hour, rounded up so the line never reads
    /// "next in 0 min" while there is still time to go.
    func minutesToNextHour(at now: Date) -> Int? {
        guard let nextHourAt else { return nil }
        return max(1, Int((nextHourAt.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// One line for the Dadded screen.
    func text(at now: Date) -> String {
        guard let minutes = minutesToNextHour(at: now) else {
            return "Today's \(RewardLedger.hoursCountedPerDay.description) are in"
        }
        if isNight {
            let paused = "Night hours don't count · back at \(RewardNight.endHour):00"
            return hoursSoFar.isZero ? paused : "\(hoursSoFar.description) so far · \(paused)"
        }
        if hoursSoFar.isZero { return "First reward hour in \(minutes) min" }
        return "\(hoursSoFar.description) so far · next in \(minutes) min"
    }

    /// Said once, under the line, because the hours are not banked yet.
    static let caveat = "They count when you \(Vocab.unVerb) yourself."
}
