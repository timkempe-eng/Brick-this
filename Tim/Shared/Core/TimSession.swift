import Foundation

/// A session is one stretch of being Timmed: it starts on a tap and ends on
/// the next tap, an auto-release, or an emergency override.
struct TimSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var modeID: UUID
    var modeName: String
    var startedAt: Date
    var endedAt: Date?
    /// True when the session was broken with an emergency override rather
    /// than by tapping the tag. Kept so the stats can tell the difference
    /// between finishing and bailing.
    var endedByEmergency: Bool = false

    var isActive: Bool { endedAt == nil }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}
