import DeviceActivity

/// Starts and ends sessions with the app closed.
///
/// The system wakes this extension at the edges of every window we registered:
/// the one-shot release for a timed session, and both ends of each scheduled
/// Mode's window. It is woken with nothing but the activity's name, so the
/// Mode is parsed back out of it.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let modeID = ScheduleActivityNaming.modeID(from: activity.rawValue) else { return }
        DadEngine.live.beginScheduledSession(modeID: modeID)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        if ScheduleActivityNaming.isRelease(activity.rawValue) {
            DadEngine.live.unDad(byEmergency: false)
            return
        }
        guard let modeID = ScheduleActivityNaming.modeID(from: activity.rawValue) else { return }
        DadEngine.live.endScheduledSession(modeID: modeID)
    }
}
