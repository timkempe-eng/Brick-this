import DeviceActivity

/// Starts and ends sessions, and rations Modes, with the app closed.
///
/// The system wakes this extension at the edges of every window we registered
/// — the one-shot release for a timed session, both ends of each scheduled
/// Mode's window, and the day inside which a rationing Mode's usage is counted
/// — plus once more when a usage threshold is reached.
///
/// It is woken with nothing but the activity's name, so what the window is
/// *for* is parsed back out of it. That decision lives in
/// `ScheduleActivityNaming.activity(named:)`, in Core, where it is tested: a
/// misparse here is a window that fires into a process nobody can watch and is
/// silently ignored.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        switch ScheduleActivityNaming.activity(named: activity.rawValue) {
        case .scheduledWindow(let modeID):
            DadEngine.live.beginScheduledSession(modeID: modeID)

        case .allowanceDay(let modeID):
            // Midnight: a new day's allowance. `renewAllowance` refuses if the
            // day has not actually turned, which is what makes it safe to be
            // called on registration too — the system delivers the start of a
            // window that is already open.
            DadEngine.live.renewAllowance(modeID: modeID)

        case .release, .unrecognised:
            break
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        switch ScheduleActivityNaming.activity(named: activity.rawValue) {
        case .release:
            DadEngine.live.unDad(byEmergency: false)

        case .scheduledWindow(let modeID):
            DadEngine.live.endScheduledSession(modeID: modeID)

        case .allowanceDay:
            // 23:59. The day repeats, and the new one starts a minute later —
            // ending the session here would turn "fifteen minutes a day" into
            // "until midnight".
            break

        case .unrecognised:
            break
        }
    }

    /// The Mode's apps have now been used for as long as today's allowance
    /// permits. This is the moment a rationed Mode becomes a blocked one.
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        guard event.rawValue == ScheduleActivityNaming.allowanceSpent,
              case .allowanceDay(let modeID) =
                ScheduleActivityNaming.activity(named: activity.rawValue)
        else { return }

        DadEngine.live.spendAllowance(modeID: modeID)
    }
}
