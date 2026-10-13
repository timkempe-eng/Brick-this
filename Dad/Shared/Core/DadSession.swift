import Foundation

/// A session is one stretch of being Dadded: it starts on a tap and ends on
/// the next tap, an auto-release, or an emergency override.
struct DadSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var modeID: UUID
    var modeName: String
    var startedAt: Date
    var endedAt: Date?
    /// True when the session was broken with an emergency override rather
    /// than by tapping the tag. Kept so the stats can tell the difference
    /// between finishing and bailing.
    var endedByEmergency: Bool = false

    /// How this session ended, in full.
    ///
    /// `endedByEmergency` above is one bit of the same answer and is kept
    /// because history already carries it, but one bit is not enough: it
    /// cannot tell a session somebody walked back to the tag for from one a
    /// schedule opened and closed while the phone sat on a table.
    ///
    /// That distinction turned out to be load-bearing. `AutonomyLadder` counts
    /// "clean days" as evidence that somebody is holding a habit, and with
    /// only the one bit a nightly Sleep schedule earned the top rung — which
    /// hands over the tag — in sixty-one nights of nobody touching anything.
    /// Owning a scheduled phone is not consistency.
    ///
    /// Optional for the reason every added stored property here is: the
    /// synthesised decoder does not fall back to a default, and
    /// `LenientDecoding` then skips the record. `nil` is a session recorded
    /// before this existed, and callers must decide what to do with an unknown
    /// ending rather than assume one.
    var endedBy: EndReason?

    /// Why a session stopped. Mirrors `DadEngine.SessionEnd`, and is a
    /// separate type only because Core stores this and the engine's version is
    /// an argument — merging them would put a storage format on a parameter.
    enum EndReason: String, Codable, Hashable {
        /// The tag, the in-app button, or the Un-Dad intent. A person did this.
        case tapped
        /// An override was spent.
        case emergency
        /// A grown-up granted a release at their tag. A person did this.
        case granted
        /// The Mode's timed release ran out. A person chose it — when they
        /// started the session, unless a schedule started it.
        case timed
        /// A schedule boundary, a Mode deleted underneath it, or a new session
        /// replacing it. Nobody was necessarily present.
        case system
    }

    /// Whether a person ended this session themselves.
    ///
    /// A session recorded before the ending existed falls back to the one bit
    /// that *was* stored — it counts unless it was an override. That is the
    /// old meaning of "clean", applied to old data, which is the only honest
    /// thing to do with it: the alternative is retroactively erasing somebody's
    /// ladder progress on the morning they update, and guessing the other way
    /// would credit them for schedules nobody attended. Old scheduled sessions
    /// therefore still count. Nothing recorded them, so nothing can tell.
    var wasEndedByAPerson: Bool {
        switch endedBy {
        case .tapped, .granted:   return true
        // A timer is a person's choice only if a person started the session.
        // A schedule with a timed release is still a schedule.
        case .timed:              return startedBySchedule != true
        case .emergency, .system: return false
        case .none:               return !endedByEmergency
        }
    }

    /// True when a scheduled window started this session, so its end boundary
    /// releases only what it started. Optional, not Bool: a missing key must
    /// decode as nil rather than fail, or every session recorded before this
    /// field existed would be dropped by the lenient decoder.
    var startedBySchedule: Bool?

    /// When a rationing Mode's daily allowance last ran out, or `nil` while it
    /// still has one. `ShieldPolicy` reads it against the current day, so a
    /// session that outlives midnight gets the next day's allowance without
    /// anything having to remember to reset it.
    ///
    /// Kept on the session rather than the Mode because it is a fact about
    /// this stretch of being Dadded, and because a finished session in the
    /// history then records whether the allowance was reached — the one number
    /// worth knowing about a rationed Mode.
    var allowanceSpentAt: Date?

    var isActive: Bool { endedAt == nil }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    /// Full reward hours: the session's time outside `RewardNight`, rounded
    /// down, so fifty-nine minutes is none. Zero while the session is running
    /// — it has no outcome yet — and zero for an end recorded before its
    /// start, which a clock moved backwards can produce.
    func wholeRewardHours(calendar: Calendar) -> Int {
        guard let endedAt else { return 0 }
        let counted = RewardNight.countedSeconds(from: startedAt, to: endedAt, calendar: calendar)
        return Int(counted / 3600)
    }
}


extension DadSession.EndReason {
    /// The stored form of the engine's reason for ending a session.
    init(_ end: DadEngine.SessionEnd) {
        switch end {
        case .tapped:    self = .tapped
        case .emergency: self = .emergency
        case .granted:   self = .granted
        case .timed:     self = .timed
        case .system:    self = .system
        }
    }
}

/// The one definition of "sessions somebody actually finished".
///
/// Two ledgers read it — `AutonomyLadder`, which counts the days and spends
/// them on rungs, and `RewardLedger`, which counts the whole hours and spends
/// them on rewards — and for a while they each wrote the rule out. The copies had already drifted: one filtered
/// on `wasEndedByAPerson`, the other on `wasEndedByAPerson && !endedByEmergency`,
/// where the second clause could not change the answer. A rule stated twice is
/// a rule that will mean two things, and this one decides what somebody is
/// owed.
///
/// A session counts toward the day it *started*, exactly as in `DadStats`: an
/// evening that runs past midnight credits the evening you began, because that
/// is how anybody would describe it out loud.
///
/// One qualifying session makes the day, even if another session that day
/// ended on the emergency button. The day contains the evidence, and counting
/// the bad one against it would let a single override cancel something already
/// earned that morning.
extension Collection where Element == DadSession {

    func daysEndedByAPerson(calendar: Calendar) -> Set<Date> {
        Set(lazy.filter(\.wasEndedByAPerson)
                .map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// Whole reward hours of sessions a person ended — night excluded, see
    /// `RewardNight` — credited to the day each started. Uncapped: the ceiling
    /// is the reward ledger's rule, not a fact about the history.
    ///
    /// Every day in `daysEndedByAPerson` is a key, including one whose
    /// sessions were all under an hour — present at zero rather than absent —
    /// so the two definitions cannot disagree about which days counted.
    ///
    /// Here rather than in `RewardLedger.swift` because measuring a session
    /// needs a `TimeInterval` and a division, and that file's test fails the
    /// build if it contains either.
    func wholeHoursEndedByAPerson(calendar: Calendar) -> [Date: Int] {
        var hours: [Date: Int] = [:]
        for session in self where session.wasEndedByAPerson {
            hours[calendar.startOfDay(for: session.startedAt), default: 0]
                += session.wholeRewardHours(calendar: calendar)
        }
        return hours
    }

    /// Any day there was a session at all, however it ended. What stops a
    /// lapse clock: bailing out with an override is still engagement.
    func daysWithASession(calendar: Calendar) -> Set<Date> {
        Set(lazy.map { calendar.startOfDay(for: $0.startedAt) })
    }
}
