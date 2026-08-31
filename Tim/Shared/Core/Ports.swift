import Foundation

/// The four things `TimEngine` needs from the outside world.
///
/// Each one hides a framework or a global that would otherwise make the engine
/// untestable and Mac-only. The iOS adapters live in `Tim/Shared/Adapters`;
/// the fakes used by the tests live in the test target. See
/// `docs/adr/001-ports-and-adapters.md`.

/// Time, so tests can say when "now" is.
protocol Clock {
    var now: Date { get }
}

/// Taking apps away and giving them back. Implemented by ManagedSettings.
protocol ShieldControlling {
    func apply(_ mode: TimMode)
    func clear()
}

/// Releasing a timed session with the app closed, and running Modes on a
/// recurring wall-clock schedule. Implemented by DeviceActivity, which is why
/// the one-shot case deals in an absolute date rather than a duration —
/// converting to a system schedule is the adapter's problem.
protocol SessionScheduling {
    func scheduleRelease(at date: Date)
    func cancelScheduledRelease()

    /// Replaces the full set of recurring schedules. Declarative rather than
    /// add/remove, so the system's registered set can't drift from ours.
    func setRecurringSchedules(_ schedules: [RecurringSchedule])
}

struct RecurringSchedule: Equatable, Hashable {
    let modeID: UUID
    let schedule: ModeSchedule
}

/// Everything that has to survive a process death and be visible to the
/// extensions. Implemented by the App Group `UserDefaults`.
///
/// Class-bound because the engine mutates it in place and the shield extension
/// must observe the same instance's writes.
protocol TimPersisting: AnyObject {
    var modes: [TimMode] { get set }
    var activeSession: TimSession? { get set }
    var history: [TimSession] { get set }
    var pairedTagUIDs: [String] { get set }
    var emergencyUses: [Date] { get set }
    var hasOnboarded: Bool { get set }
}
