import Foundation
import DeviceActivity

/// `SessionScheduling` over DeviceActivity.
///
/// The system wakes `DeviceActivityMonitorExtension` at the end of the
/// interval, which is what makes "Tim me for an hour" survive a force-quit, a
/// reboot, or the app being jetsammed.
struct DeviceActivityScheduler: SessionScheduling {

    static let activityName = DeviceActivityName("tim.autoUnTim")

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func scheduleRelease(at date: Date) {
        // DeviceActivitySchedule is expressed in date components rather than
        // instants. Hour and minute is the granularity it works in; the engine
        // has already applied the 15-minute floor.
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute], from: Date()),
            intervalEnd: calendar.dateComponents([.hour, .minute], from: date),
            repeats: false
        )
        try? DeviceActivityCenter().startMonitoring(Self.activityName, during: schedule)
    }

    func cancelScheduledRelease() {
        DeviceActivityCenter().stopMonitoring([Self.activityName])
    }
}
