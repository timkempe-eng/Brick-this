import Foundation

/// A session that ended by hand and will start itself again shortly — the
/// break in "release on a leash".
///
/// Every review of a blocker has the same sentence in it: you unblock to check
/// one thing and lose an hour. Brick has no answer to it — "once you Unbrick
/// your phone, you're back to full access". A break is the answer: you still
/// had to walk to the tag, but you do not have to remember to walk back.
///
/// Opt-in per Mode and off by default, so a Mode without one behaves exactly
/// as it always has.
struct PendingResume: Codable, Equatable, Hashable {
    let modeID: UUID
    let modeName: String

    /// When the Mode starts itself again.
    let at: Date

    /// Whether the session this break came from was started by a schedule.
    ///
    /// Carried through, and it matters: tap out of Sleep at 2am on a Mode that
    /// takes breaks and the resumed session would otherwise be a hand-started
    /// one, which the 07:00 boundary deliberately refuses to end — leaving the
    /// phone Dadded all day. A break interrupts a scheduled session; it does
    /// not convert it into a different kind.
    var startedBySchedule: Bool?

    func isDue(now: Date) -> Bool { now >= at }
}
