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

    func isDue(now: Date) -> Bool { now >= at }
}
