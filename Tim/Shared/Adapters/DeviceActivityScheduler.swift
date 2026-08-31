import Foundation
import DeviceActivity

/// `SessionScheduling` over DeviceActivity.
///
/// The system wakes `DeviceActivityMonitorExtension` at the edges of each
/// window, which is what makes both "Tim me for an hour" and "Sleep, every
/// night at 10" survive a force-quit, a reboot, or the app being jetsammed.
struct DeviceActivityScheduler: SessionScheduling {

    static let releaseActivity = DeviceActivityName(ScheduleActivityNaming.release)

    private let calendar: Calendar
    private let center = DeviceActivityCenter()

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - One-shot release

    func scheduleRelease(at date: Date) {
        // DeviceActivitySchedule is expressed in date components, not instants.
        // Hour and minute is the granularity it works in; the engine has
        // already applied the 15-minute floor.
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute], from: Date()),
            intervalEnd: calendar.dateComponents([.hour, .minute], from: date),
            repeats: false
        )
        try? center.startMonitoring(Self.releaseActivity, during: schedule)
    }

    func cancelScheduledRelease() {
        center.stopMonitoring([Self.releaseActivity])
    }

    // MARK: - Recurring windows

    /// Replaces the registered set wholesale: everything of ours is torn down,
    /// then the current set is registered. Declarative, so a Mode that was
    /// deleted or switched off cannot leave a live window behind.
    func setRecurringSchedules(_ schedules: [RecurringSchedule]) {
        let ours = center.activities.filter {
            ScheduleActivityNaming.modeID(from: $0.rawValue) != nil
        }
        if !ours.isEmpty { center.stopMonitoring(ours) }

        for entry in schedules {
            for (name, schedule) in windows(for: entry) {
                try? center.startMonitoring(DeviceActivityName(name), during: schedule)
            }
        }
    }

    /// An every-day schedule needs one repeating window; anything else needs
    /// one per weekday, because `DeviceActivitySchedule` can only pin a single
    /// weekday per window.
    ///
    /// That distinction matters: the system caps how many activities an app may
    /// monitor, and collapsing the common case from seven windows to one is
    /// what keeps a handful of scheduled Modes inside the budget.
    private func windows(for entry: RecurringSchedule) -> [(String, DeviceActivitySchedule)] {
        let s = entry.schedule

        if s.weekdays == ModeSchedule.everyDay {
            return [(
                ScheduleActivityNaming.name(modeID: entry.modeID),
                DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: s.startHour, minute: s.startMinute),
                    intervalEnd: DateComponents(hour: s.endHour, minute: s.endMinute),
                    repeats: true
                )
            )]
        }

        return s.weekdays.sorted().map { weekday in
            (
                ScheduleActivityNaming.name(modeID: entry.modeID, weekday: weekday),
                DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: s.startHour, minute: s.startMinute, weekday: weekday),
                    intervalEnd: DateComponents(hour: s.endHour, minute: s.endMinute, weekday: weekday),
                    repeats: true
                )
            )
        }
    }
}
