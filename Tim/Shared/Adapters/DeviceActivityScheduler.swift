import Foundation
import DeviceActivity

/// `SessionScheduling` over DeviceActivity.
///
/// The system wakes `DeviceActivityMonitorExtension` at the edges of each
/// window, which is what makes both "Tim me for an hour" and "Sleep, every
/// night at 10" survive a force-quit, a reboot, or the app being jetsammed.
///
/// Deliberately thin: which windows exist, when they start and end (including
/// the cross-midnight weekday arithmetic), and which to touch on a change are
/// all decided in Core (`ScheduleWindows`), where they are tested. This file
/// only maps that onto the system type.
struct DeviceActivityScheduler: SessionScheduling {

    static let releaseActivity = DeviceActivityName(ScheduleActivityNaming.release)

    private let calendar: Calendar
    private let center = DeviceActivityCenter()

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - One-shot release

    func scheduleRelease(at date: Date) {
        // Full year/month/day components, not just hour and minute: a
        // component-only schedule resolves to the NEXT matching occurrence,
        // so a bare {14:23} registered at 14:23:45 can mean tomorrow — and
        // "Tim me for an hour" would release a day late.
        //
        // Skip if already registered: reconcile() re-arms on every foreground,
        // and re-registering an open one-shot window is the torn-down-window
        // failure this codebase goes out of its way to avoid. The release
        // time is derived from the session's start, so an existing
        // registration is already correct.
        guard !center.activities.contains(Self.releaseActivity) else { return }

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                   from: Date()),
            intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                 from: date),
            repeats: false
        )
        // Can still fail (a re-arm with under 15 minutes remaining, or the
        // activity budget). reconcile() is the backstop: an overdue timed
        // session is ended on the next foreground regardless.
        try? center.startMonitoring(Self.releaseActivity, during: schedule)
    }

    func cancelScheduledRelease() {
        center.stopMonitoring([Self.releaseActivity])
    }

    // MARK: - Recurring windows

    func stopWindows(named names: [String]) {
        guard !names.isEmpty else { return }
        // A closure, not `.init`: DeviceActivityName has both init(_:) and
        // init(rawValue:), and the unapplied reference is ambiguous.
        center.stopMonitoring(names.map { DeviceActivityName($0) })
    }

    func startWindows(_ windows: [ScheduledWindow]) -> [String] {
        // Skipping already-registered names makes a retry after a partial
        // failure safe: the survivors are left alone rather than torn down
        // and re-registered mid-window.
        let registered = Set(center.activities.map(\.rawValue))
        var failed: [String] = []

        for window in windows where !registered.contains(window.name) {
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: window.startHour,
                                              minute: window.startMinute,
                                              weekday: window.weekday),
                intervalEnd: DateComponents(hour: window.endHour,
                                            minute: window.endMinute,
                                            weekday: window.endWeekday),
                repeats: true
            )
            do {
                try center.startMonitoring(DeviceActivityName(window.name), during: schedule)
            } catch {
                // Most likely the monitored-activity budget. Reported back so
                // the engine refuses to record this sync and the UI can say so
                // — a schedule that looks configured and silently never fires
                // is the exact failure class ModeSchedule.isValid exists to
                // prevent.
                failed.append(window.name)
            }
        }
        return failed
    }
}
