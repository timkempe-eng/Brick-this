import Foundation

/// One concrete window the system should watch: either a daily repeat, or a
/// repeat pinned to a single weekday.
///
/// This is the pure form of what `DeviceActivitySchedule` expresses, kept in
/// Core so the two things most likely to be quietly wrong — the cross-midnight
/// weekday arithmetic, and the decision of which windows to touch when the set
/// changes — are covered by `swift test` instead of failing silently on a
/// device. The adapter's only job is to map this onto the system type.
struct ScheduledWindow: Codable, Hashable {
    /// From `ScheduleActivityNaming`; the monitor extension parses the Mode
    /// back out of it.
    let name: String

    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int

    /// `nil` means a daily repeat: one window instead of seven.
    let weekday: Int?

    var crossesMidnight: Bool {
        endHour * 60 + endMinute <= startHour * 60 + startMinute
    }

    /// The weekday the window *ends* on. For an overnight window this is the
    /// following day — pinning the same weekday on both ends would make
    /// "Monday 22:00 to 07:00" end the *following* Monday, six days late,
    /// leaving the phone Dadded for a week.
    var endWeekday: Int? {
        guard let weekday else { return nil }
        return crossesMidnight ? (weekday % 7) + 1 : weekday
    }
}

enum ScheduleWindows {

    /// The windows a schedule needs. An every-day schedule collapses to a
    /// single daily repeat, because the system caps how many activities an app
    /// may monitor; anything else costs one window per weekday.
    static func windows(for entry: RecurringSchedule) -> [ScheduledWindow] {
        let s = entry.schedule

        if s.weekdays == ModeSchedule.everyDay {
            return [ScheduledWindow(
                name: ScheduleActivityNaming.name(modeID: entry.modeID),
                startHour: s.startHour, startMinute: s.startMinute,
                endHour: s.endHour, endMinute: s.endMinute,
                weekday: nil
            )]
        }

        return s.weekdays.sorted().map { weekday in
            ScheduledWindow(
                name: ScheduleActivityNaming.name(modeID: entry.modeID, weekday: weekday),
                startHour: s.startHour, startMinute: s.startMinute,
                endHour: s.endHour, endMinute: s.endMinute,
                weekday: weekday
            )
        }
    }

    static func windows(for entries: [RecurringSchedule]) -> [ScheduledWindow] {
        entries.flatMap { windows(for: $0) }
    }

    /// Which windows to stop and which to start to get from `old` to `new`.
    ///
    /// The point of diffing rather than replacing wholesale: stopping a window
    /// that is currently *open* means the system never delivers its end, so a
    /// scheduled session would run forever. A window that hasn't changed is
    /// therefore never touched — editing one Mode's schedule must not disturb
    /// another Mode's night in progress.
    static func diff(from old: [ScheduledWindow],
                     to new: [ScheduledWindow]) -> (stop: [String], start: [ScheduledWindow]) {
        let oldByName = Dictionary(uniqueKeysWithValues: old.map { ($0.name, $0) })
        let newByName = Dictionary(uniqueKeysWithValues: new.map { ($0.name, $0) })

        let stop = oldByName
            .filter { name, window in newByName[name] != window }
            .keys.sorted()
        let start = new
            .filter { oldByName[$0.name] != $0 }
            .sorted { $0.name < $1.name }

        return (stop, start)
    }
}
