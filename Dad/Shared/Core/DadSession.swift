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
        /// A timed release, a schedule boundary, a Mode deleted underneath it.
        /// Nobody was necessarily present.
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
        case .tapped:             return true
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
}


extension DadSession.EndReason {
    /// The stored form of the engine's reason for ending a session.
    init(_ end: DadEngine.SessionEnd) {
        switch end {
        case .tapped:    self = .tapped
        case .emergency: self = .emergency
        case .system:    self = .system
        }
    }
}

/// The one definition of "days somebody actually did this".
///
/// Two ledgers count these days — `AutonomyLadder`, which spends them on
/// rungs, and `RewardLedger`, which spends them on rewards — and for a while
/// they each wrote the rule out. The copies had already drifted: one filtered
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

    /// Any day there was a session at all, however it ended. What stops a
    /// lapse clock: bailing out with an override is still engagement.
    func daysWithASession(calendar: Calendar) -> Set<Date> {
        Set(lazy.map { calendar.startOfDay(for: $0.startedAt) })
    }
}
