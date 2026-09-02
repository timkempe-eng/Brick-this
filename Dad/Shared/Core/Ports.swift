import Foundation

/// The five things `DadEngine` needs from the outside world.
///
/// Each one hides a framework or a global that would otherwise make the engine
/// untestable and Mac-only. The iOS adapters live in `Dad/Shared/Adapters`;
/// the fakes used by the tests live in the test target. See
/// `docs/adr/001-ports-and-adapters.md`.

/// Time, so tests can say when "now" is.
protocol Clock {
    var now: Date { get }
}

/// Taking apps away and giving them back. Implemented by ManagedSettings.
protocol ShieldControlling {
    func apply(_ mode: DadMode)
    func clear()
}

/// Releasing a timed session with the app closed, and running Modes on a
/// recurring wall-clock schedule. Implemented by DeviceActivity, which is why
/// the one-shot case deals in an absolute date rather than a duration —
/// converting to a system schedule is the adapter's problem.
protocol SessionScheduling {
    func scheduleRelease(at date: Date)
    func cancelScheduledRelease()

    /// Stops exactly these windows, by name. Never called for a window whose
    /// schedule is unchanged — see `ScheduleWindows.diff`.
    func stopWindows(named names: [String])

    /// Registers exactly these windows. Returns the names that FAILED to
    /// register (the system caps how many activities an app may monitor), so
    /// the engine can refuse to record a sync that didn't fully happen.
    /// Skips a name that is already registered, which makes retries safe.
    @discardableResult
    func startWindows(_ windows: [ScheduledWindow]) -> [String]
}

struct RecurringSchedule: Codable, Equatable, Hashable {
    let modeID: UUID
    let schedule: ModeSchedule
}

/// Telling the Lock Screen widget its timeline is stale. Implemented by
/// WidgetKit.
///
/// A port rather than a direct call because the engine ends sessions from
/// three processes — the app, the shield's emergency button, and the
/// DeviceActivity monitor — and every one of them must refresh the widget or
/// it keeps showing "Dadded" after the phone is free.
protocol WidgetRefreshing {
    func reload()
}

/// Everything that has to survive a process death and be visible to the
/// extensions. Implemented by the App Group `UserDefaults`.
///
/// Class-bound because the engine mutates it in place and the shield extension
/// must observe the same instance's writes.
protocol DadPersisting: AnyObject {
    var modes: [DadMode] { get set }
    var activeSession: DadSession? { get set }
    var history: [DadSession] { get set }
    var pairedTagUIDs: [String] { get set }
    var emergencyUses: [Date] { get set }
    var hasOnboarded: Bool { get set }

    /// The schedule set last handed to the system. Kept so we can tell whether
    /// a re-registration is actually needed — see `DadEngine.syncSchedules`.
    var syncedSchedules: [RecurringSchedule] { get set }

    /// True when something on disk was written by a later build than this one
    /// — a TestFlight rollback, or an older build on a second device. The
    /// values read as their defaults, so without this the user would see empty
    /// Modes and a lost streak with no explanation, and the first thing they
    /// did would overwrite the data they still have.
    var hasDataFromANewerBuild: Bool { get }
}
