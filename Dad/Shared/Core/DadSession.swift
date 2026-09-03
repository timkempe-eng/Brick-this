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
