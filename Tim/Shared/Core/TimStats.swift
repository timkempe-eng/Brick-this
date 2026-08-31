import Foundation

/// Everything the stats screen shows, derived from the session history.
///
/// Deliberately Foundation-only and free of any stored state: it takes the
/// sessions, a calendar and a reference "now", and returns numbers. That makes
/// the awkward parts — streaks across midnight, week boundaries, time zones —
/// testable without a device.
struct TimStats {

    let sessions: [TimSession]
    let calendar: Calendar
    let now: Date

    /// - Parameter calendar: injected so tests can pin a time zone. The app
    ///   passes `.current`, which is what the user's day boundaries actually are.
    init(sessions: [TimSession], now: Date = Date(), calendar: Calendar = .current) {
        // Only finished sessions count. An in-flight one has no duration yet
        // and would make every total drift upward as you look at it.
        self.sessions = sessions.filter { $0.endedAt != nil }
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Totals

    var sessionCount: Int { sessions.count }

    var totalTime: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }

    var timeThisWeek: TimeInterval {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return sessions.filter { $0.startedAt >= weekStart }.reduce(0) { $0 + $1.duration }
    }

    var longestSession: TimeInterval { sessions.map(\.duration).max() ?? 0 }

    /// Sessions ended by walking back to the tag, rather than by spending an
    /// emergency override. The number worth watching.
    var cleanFinishes: Int { sessions.filter { !$0.endedByEmergency }.count }

    var emergencyBails: Int { sessions.filter(\.endedByEmergency).count }

    /// 0...1, or nil when there's nothing to divide.
    var cleanFinishRate: Double? {
        guard sessionCount > 0 else { return nil }
        return Double(cleanFinishes) / Double(sessionCount)
    }

    // MARK: - Streaks
    //
    // A day counts if at least one session *started* that day. Using the start
    // rather than the end means a session that runs past midnight credits the
    // evening you began it, which is how anyone would describe it out loud.

    private var activeDays: Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// Consecutive days up to today. Today not having a session yet does not
    /// break the streak — the day isn't over — so a streak ending yesterday
    /// still counts as current.
    var currentStreak: Int {
        let days = activeDays
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    var longestStreak: Int {
        let days = activeDays.sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var running = 1
        for (previous, day) in zip(days, days.dropFirst()) {
            if calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                running += 1
                longest = max(longest, running)
            } else {
                running = 1
            }
        }
        return longest
    }

    // MARK: - Chart data

    struct Day: Identifiable, Hashable {
        let date: Date
        let total: TimeInterval
        var id: Date { date }
    }

    /// Oldest first, one entry per day including empty ones, so the bar chart
    /// keeps its gaps instead of silently compressing them.
    func lastDays(_ count: Int) -> [Day] {
        let today = calendar.startOfDay(for: now)
        var totals: [Date: TimeInterval] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            totals[day, default: 0] += session.duration
        }

        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: day, total: totals[day] ?? 0)
        }
    }
}
