import Foundation

/// The hours of the night that earn no reward: 23:00 to 06:00, local time.
///
/// Sleeping with the phone Dadded is good; it is not the effort a reward is
/// for. Before this the daily ceiling was the only thing standing between a
/// tapped-out overnight session and four hours for being asleep. Now the night
/// simply does not count, and the ceiling is left to do its other job.
///
/// A session's counted time is everything in it outside these hours, and it
/// earns one reward hour per full counted hour. So 22:00 to 07:00 counts
/// 22:00–23:00 and 06:00–07:00: two hours, from one session held unbroken
/// through the night between them.
///
/// Local wall-clock time, through the injected calendar, so 23:00 means 23:00
/// on the day the clocks change and in whatever zone the household is in.
enum RewardNight {

    /// When the night starts and ends, as hours of the day. Promised numbers:
    /// the Rewards screen prints them, so `PromisedNumbersTests` pins them.
    static let startHour = 23
    static let endHour = 6

    /// Seconds between `start` and `end` that fall outside the night. Zero
    /// when `end` is not after `start`.
    static func countedSeconds(from start: Date, to end: Date, calendar: Calendar) -> TimeInterval {
        guard end > start else { return 0 }
        var night: TimeInterval = 0
        for interval in nights(overlapping: start, end, calendar: calendar) {
            let overlapStart = max(interval.start, start)
            let overlapEnd = min(interval.end, end)
            if overlapEnd > overlapStart { night += overlapEnd.timeIntervalSince(overlapStart) }
        }
        return end.timeIntervalSince(start) - night
    }

    /// Whether `date` falls in the night.
    static func isNight(_ date: Date, calendar: Calendar) -> Bool {
        nights(overlapping: date, date, calendar: calendar)
            .contains { $0.start <= date && date < $0.end }
    }

    /// The instant at which a session started at `start` has `target` seconds
    /// counted — the moment its next reward hour lands.
    static func instant(reaching target: TimeInterval, from start: Date,
                        calendar: Calendar) -> Date {
        var cursor = start
        var remaining = max(0, target)
        // Each pass crosses at most one night, and a reward hour is never more
        // than one day's daylight away, so this ends in a handful of passes.
        while true {
            if let current = nights(overlapping: cursor, cursor, calendar: calendar)
                .first(where: { $0.start <= cursor && cursor < $0.end }) {
                cursor = current.end
                continue
            }
            guard let next = nextNightStart(after: cursor, calendar: calendar) else {
                return cursor.addingTimeInterval(remaining)
            }
            let daylight = next.timeIntervalSince(cursor)
            if remaining <= daylight { return cursor.addingTimeInterval(remaining) }
            remaining -= daylight
            cursor = next
        }
    }

    // MARK: -

    /// Every night that could touch `[from, to]`: the one that began the
    /// evening before `from`'s day, through the one beginning on `to`'s day.
    private static func nights(overlapping from: Date, _ to: Date,
                               calendar: Calendar) -> [DateInterval] {
        guard let first = calendar.date(byAdding: .day, value: -1,
                                        to: calendar.startOfDay(for: from)) else { return [] }
        let last = calendar.startOfDay(for: to)
        var result: [DateInterval] = []
        var day = first
        while day <= last {
            if let interval = night(beginningOn: day, calendar: calendar) { result.append(interval) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private static func night(beginningOn day: Date, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
              let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: nextDay),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Tonight's 23:00. Only asked from outside a night — between 06:00 and
    /// 23:00 — so tonight's is always the next one; looking at tomorrow's too
    /// was dead code, which a mutation found.
    ///
    /// The `> date` check is not reachable from `instant(reaching:)`. It is
    /// there because the loop there subtracts the daylight this returns, and a
    /// start at or behind `date` would make that loop run forever rather than
    /// fail; `nil` ends it instead.
    private static func nextNightStart(after date: Date, calendar: Calendar) -> Date? {
        guard let start = night(beginningOn: calendar.startOfDay(for: date),
                                calendar: calendar)?.start,
              start > date else { return nil }
        return start
    }
}
