import DeviceActivity

/// Releases a timed session even if the app is never opened again.
///
/// The system wakes this extension at the end of the scheduled interval,
/// which is what makes "Tim me for an hour" survive a force-quit, a reboot,
/// or the app being jetsammed.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == DeviceActivityScheduler.activityName else { return }
        TimEngine.live.unTim(byEmergency: false)
    }
}
