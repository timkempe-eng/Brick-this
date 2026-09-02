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
    case dadded(modeName: String, since: Date)
    case free(streakDays: Int)

    static func make(session: DadSession?, stats: DadStats) -> WidgetSnapshot {
        if let session {
            return .dadded(modeName: session.modeName, since: session.startedAt)
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
        case .dadded(let modeName, _):
            return modeName
        case .free(let streak):
            guard streak > 0 else { return Vocab.dadAction }
            return "\(streak) day\(streak == 1 ? "" : "s") in a row"
        }
    }

    var symbolName: String {
        switch self {
        case .dadded: return "lock.iphone"
        case .free:   return "iphone.gen3"
        }
    }

    /// The `.accessoryInline` family is a single line beside the clock, with
    /// no room for a second one.
    var inlineText: String {
        switch self {
        case .dadded(let modeName, _): return "\(Vocab.verbPast) · \(modeName)"
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
