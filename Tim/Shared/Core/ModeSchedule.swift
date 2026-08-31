import Foundation

/// A recurring window during which a Mode runs on its own — "Sleep, every
/// night, 10pm to 7am" — so the phone Tims itself without a tap.
///
/// Stored as wall-clock components rather than instants, deliberately: 10pm
/// means 10pm after a flight or a daylight-saving change, not "whatever
/// instant 10pm was when you set it".
struct ModeSchedule: Codable, Hashable {

    var isEnabled: Bool = true

    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    /// `Calendar`'s convention: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int>

    static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    static let weeknights: Set<Int> = [2, 3, 4, 5, 6]

    private var startMinutes: Int { startHour * 60 + startMinute }
    private var endMinutes: Int { endHour * 60 + endMinute }

    /// True for a window like 22:00–07:00, which ends on the following day.
    var crossesMidnight: Bool { endMinutes <= startMinutes }

    /// How long the window lasts, in seconds.
    var duration: TimeInterval {
        let minutes = crossesMidnight
            ? (24 * 60 - startMinutes) + endMinutes
            : endMinutes - startMinutes
        return TimeInterval(minutes * 60)
    }

    /// DeviceActivity won't monitor an interval shorter than 15 minutes, and a
    /// schedule with no days never fires. Either is a schedule that would look
    /// set up and silently do nothing.
    var isValid: Bool {
        !weekdays.isEmpty
            && duration >= TimEngine.minimumScheduledRelease
            && (0..<24).contains(startHour) && (0..<60).contains(startMinute)
            && (0..<24).contains(endHour) && (0..<60).contains(endMinute)
    }

    /// The next moment this schedule starts, strictly after `date`.
    ///
    /// Returns `nil` for a schedule that can never fire. Searches eight days so
    /// that a single-weekday schedule still finds its next occurrence when
    /// today is that weekday but the time has already passed.
    func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isValid else { return nil }

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            guard let start = calendar.date(bySettingHour: startHour,
                                            minute: startMinute,
                                            second: 0,
                                            of: day) else { continue }
            if start > date { return start }
        }
        return nil
    }

    /// "Weeknights, 22:00–07:00" — shown under the Mode in the list.
    func displayText(calendar: Calendar = .current) -> String {
        guard isEnabled else { return "Schedule off" }
        guard isValid else { return "Schedule incomplete" }

        let time = String(format: "%02d:%02d–%02d:%02d", startHour, startMinute, endHour, endMinute)
        return "\(dayText(calendar: calendar)), \(time)"
    }

    private func dayText(calendar: Calendar) -> String {
        if weekdays == Self.everyDay { return "Every day" }
        if weekdays == Self.weeknights { return crossesMidnight ? "Weeknights" : "Weekdays" }

        // Calendar weekday 1 is Sunday; `shortWeekdaySymbols` is indexed the same
        // way, offset by one.
        let symbols = calendar.shortWeekdaySymbols
        return weekdays.sorted()
            .compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
            .joined(separator: " ")
    }
}
