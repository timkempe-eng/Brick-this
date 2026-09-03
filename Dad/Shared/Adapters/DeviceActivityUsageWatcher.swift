import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// `UsageWatching` over DeviceActivity's usage thresholds — the mechanism that
/// lets a Mode ration rather than forbid.
///
/// A different thing entirely from `DeviceActivityScheduler`, which registers
/// wall-clock windows. Here the *window* is only a container: it is the whole
/// day, and what matters is the **event** inside it, which the system fires
/// once the Mode's apps have been used for as long as the allowance permits.
/// That is why it is a separate port and a separate adapter rather than
/// another method on the scheduler.
///
/// Deliberately thin, like its sibling. Whether a Mode rations, whether
/// today's allowance is spent, and what the shield should therefore be doing
/// are all decided in Core (`ShieldPolicy`), where they are tested. This file
/// maps that onto the system types and nothing else.
struct DeviceActivityUsageWatcher: UsageWatching {

    private let center = DeviceActivityCenter()

    /// The day the allowance is counted within.
    ///
    /// Midnight to 23:59 rather than an interval anchored to the session, and
    /// that is the product decision: an allowance is *per day*, so it has to
    /// renew on the day boundary the user recognises. The system's own
    /// component-based schedule uses the device's calendar, which is the same
    /// midnight `ShieldPolicy` measures against.
    private static let day = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0, minute: 0),
        intervalEnd: DateComponents(hour: 23, minute: 59),
        repeats: true
    )

    func startWatching(_ mode: DadMode) -> Bool {
        let name = DeviceActivityName(ScheduleActivityNaming.allowanceName(modeID: mode.id))

        // Already counting: leave it alone and report success. `reconcile()`
        // calls this on every foreground, and re-registering an open window
        // would restart the day's count — which is both wrong and the exact
        // torn-down-window failure this codebase goes out of its way to avoid.
        guard !center.activities.contains(name) else { return true }

        let selection = mode.selection
        let minutes = mode.editableAllowance.minutesPerDay

        // No `includesPastActivity`: it is iOS 17.4+ and the deployment target
        // is 17.0, and the behaviour without it is the one we want anyway —
        // the count starts when the session does, so tapping the tag at 4pm
        // grants the allowance from 4pm rather than handing over what is left
        // of a budget already spent before Dad was involved.
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: minutes)
        )

        do {
            try center.startMonitoring(
                name,
                during: Self.day,
                events: [DeviceActivityEvent.Name(ScheduleActivityNaming.allowanceSpent): event]
            )
            return true
        } catch {
            // Most likely the monitored-activity budget, which scheduled Modes
            // also draw on. Reported rather than swallowed: the engine blocks
            // outright instead, because an allowance nobody counts is an
            // unlimited allowance and the user would never find out.
            return false
        }
    }

    func stopWatching(modeID: UUID) {
        center.stopMonitoring([DeviceActivityName(ScheduleActivityNaming.allowanceName(modeID: modeID))])
    }
}
