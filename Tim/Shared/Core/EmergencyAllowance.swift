import Foundation

/// Five overrides per rolling 30 days.
///
/// Brick makes you email support once you're out. That's friction for its own
/// sake — the limit exists to make you *notice* you're reaching for the hatch,
/// not to lock you out of your own phone, so these come back on their own.
///
/// Pure date arithmetic over a list of timestamps, kept apart from storage so
/// the window edges can be tested exactly.
enum EmergencyAllowance {
    static let perWindow = 5
    static let window: TimeInterval = 30 * 24 * 60 * 60

    /// Uses still inside the window at `now`.
    static func recent(uses: [Date], now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-window)
        return uses.filter { $0 > cutoff }
    }

    static func remaining(uses: [Date], now: Date) -> Int {
        max(0, perWindow - recent(uses: uses, now: now).count)
    }

    /// The new list of uses after spending one, or `nil` when the allowance is
    /// gone. Returning the list rather than mutating keeps this pure — and
    /// pruning expired entries here stops the array growing without bound.
    static func consume(uses: [Date], now: Date) -> [Date]? {
        guard remaining(uses: uses, now: now) > 0 else { return nil }
        return recent(uses: uses, now: now) + [now]
    }
}
