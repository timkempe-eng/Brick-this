import Foundation

/// What the shield should be doing right now, for a given session and Mode.
///
/// One decision, in one tested place. Four callers need the answer and they
/// run in three different processes — the app starting a session, `reconcile()`
/// on every foreground, the DeviceActivity monitor when an allowance runs out
/// or a new day begins, and the widget deciding what to draw. Working it out
/// separately in each would be four chances to disagree about whether the
/// user's apps are currently taken away.
enum ShieldState: Equatable {
    /// No session. Nothing restricted.
    case off

    /// A session is running on a Mode that rations rather than forbids, and
    /// today's allowance is not spent. The apps are still there; only the
    /// Mode's other restrictions (strict) apply.
    case rationing

    /// A session is running and the apps are taken away — either because the
    /// Mode blocks outright, or because its allowance is spent for today.
    case blocking

    var isBlocking: Bool { self == .blocking }
}

enum ShieldPolicy {

    /// - Parameters:
    ///   - mode: the Mode the session names, or `nil` if it has been deleted.
    ///     A session whose Mode is gone can no longer be described, let alone
    ///     rationed, so it reads as blocking and `reconcile()` ends it.
    static func state(session: DadSession?,
                      mode: DadMode?,
                      now: Date,
                      calendar: Calendar = .current) -> ShieldState {
        guard let session, session.isActive else { return .off }
        guard let mode, mode.rations else { return .blocking }
        return isAllowanceSpent(session: session, now: now, calendar: calendar)
            ? .blocking
            : .rationing
    }

    /// Whether the allowance has run out *for the day `now` falls in*.
    ///
    /// The day boundary is decided here rather than left to the system, and
    /// that is deliberate. The allowance renews at midnight, which the
    /// DeviceActivity monitor is woken for — but a wake that never arrives
    /// (the extension jetsammed, the device off) would otherwise leave the
    /// apps hidden for the rest of a multi-day session with nothing able to
    /// notice. Deriving it from the stored instant means the next foreground
    /// puts it right, the same way an overdue timed release is put right.
    static func isAllowanceSpent(session: DadSession,
                                 now: Date,
                                 calendar: Calendar = .current) -> Bool {
        guard let spentAt = session.allowanceSpentAt else { return false }
        return calendar.isDate(spentAt, inSameDayAs: now)
    }
}
