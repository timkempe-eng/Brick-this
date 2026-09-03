import Foundation

/// Everything the Lock Screen widget needs to draw itself.
///
/// The widget runs in its own process and only reads. Keeping the decision of
/// *what it says* here — rather than in the widget extension — means the copy
/// and the state mapping are covered by `swift test`, and the extension is
/// left with nothing but layout.
///
/// `since` is carried as a `Date` rather than a formatted duration on purpose:
/// the widget feeds it to a live-updating timer view, which ticks without the
/// system reloading the timeline. A pre-formatted string would freeze at
/// whatever second the snapshot was built.
enum WidgetSnapshot: Equatable {
    /// - Parameter rationing: the session is running on a Mode that rations
    ///   rather than forbids, and today's allowance is not spent — so the apps
    ///   are still *there*. That is a different answer to "can I use my phone"
    ///   than a plain Dadded session, and it is the whole question the widget
    ///   exists to settle from the Lock Screen.
    case dadded(modeName: String, since: Date, rationing: Bool)
    case free(streakDays: Int)

    /// - Parameter mode: the Mode the session names, so the snapshot can tell
    ///   rationing from blocking. Defaulted because most callers — and every
    ///   test that predates allowances — are asking about a Mode that blocks
    ///   outright, where the answer does not depend on it.
    static func make(session: DadSession?,
                     mode: DadMode? = nil,
                     stats: DadStats,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> WidgetSnapshot {
        if let session {
            let state = ShieldPolicy.state(session: session, mode: mode,
                                           now: now, calendar: calendar)
            return .dadded(modeName: session.modeName,
                           since: session.startedAt,
                           rationing: state == .rationing)
        }
        return .free(streakDays: stats.currentStreak)
    }

    /// The one word you read from across the room.
    var headline: String {
        switch self {
        case .dadded: return Vocab.verbPast
        case .free:   return "Free"
        }
    }

    /// The line under it.
    var detail: String {
        switch self {
        case .dadded(let modeName, _, let rationing):
            return rationing ? "\(modeName) · \(Vocab.rationedNoun)" : modeName
        case .free(let streak):
            guard streak > 0 else { return Vocab.dadAction }
            return "\(streak) day\(streak == 1 ? "" : "s") in a row"
        }
    }

    /// Rationing gets its own glyph, because it is a third state and the
    /// point of the widget is that one look answers the question.
    var symbolName: String {
        switch self {
        case .dadded(_, _, let rationing): return rationing ? "hourglass" : "lock.iphone"
        case .free:                        return "iphone.gen3"
        }
    }

    /// The `.accessoryInline` family is a single line beside the clock, with
    /// no room for a second one.
    var inlineText: String {
        switch self {
        case .dadded(let modeName, _, let rationing):
            return rationing
                ? "\(modeName) · \(Vocab.rationedNoun)"
                : "\(Vocab.verbPast) · \(modeName)"
        case .free(let streak):
            guard streak > 0 else { return Vocab.appName }
            return "\(streak) day \(Vocab.streakNoun)"
        }
    }

    var isDadded: Bool {
        if case .dadded = self { return true }
        return false
    }

    /// When the system should rebuild the timeline.
    ///
    /// `nil` while Dadded: the elapsed time is drawn by a self-updating timer
    /// view, and the only thing that can change the *state* is the session
    /// ending — which the engine announces through `WidgetRefreshing` rather
    /// than the widget having to poll for.
    ///
    /// While free, the streak can lapse silently at midnight with nothing to
    /// announce it, so that is the one moment worth waking up for.
    func nextRefresh(after now: Date, calendar: Calendar = .current) -> Date? {
        guard case .free = self else { return nil }
        return calendar.nextDate(after: now,
                                 matching: DateComponents(hour: 0, minute: 0, second: 0),
                                 matchingPolicy: .nextTime)
    }
}
