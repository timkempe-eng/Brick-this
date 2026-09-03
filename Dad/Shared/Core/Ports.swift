import Foundation

/// The six things `DadEngine` needs from the outside world.
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
    /// - Parameter neverBlocked: the apps and sites no Mode may ever take
    ///   away. Opaque here, like everything else about a `BlockedSelection`:
    ///   Core hands both halves over and the subtraction happens inside
    ///   `DadMode+FamilyControls`, which is the only file allowed to look at
    ///   either. Rule 3 expressed as a location rather than a convention.
    func apply(_ mode: DadMode, neverBlocked: BlockedSelection)

    /// Everything `apply` does except hiding the apps — which today means
    /// strict mode's refusal to let Dad be deleted.
    ///
    /// This is the state a rationing Mode is in while its allowance lasts: the
    /// apps are still there, but the escape hatch is still shut. Without it,
    /// "strict" would silently mean nothing for the whole of the free period,
    /// which is exactly the window someone would use to delete the app.
    func applyRestrictionsOnly(_ mode: DadMode)

    func clear()
}

/// Releasing a timed session with the app closed, and running Modes on a
/// recurring wall-clock schedule. Implemented by DeviceActivity, which is why
/// the one-shot case deals in an absolute date rather than a duration —
/// converting to a system schedule is the adapter's problem.
protocol SessionScheduling {
    func scheduleRelease(at date: Date)
    func cancelScheduledRelease()

    /// The mirror of `scheduleRelease`: bring a Mode *back* at `date`, after a
    /// break. Same one-shot mechanism, opposite direction.
    func scheduleResume(at date: Date)
    func cancelScheduledResume()

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

/// Counting how long a Mode's apps are used, so a Mode can ration rather than
/// forbid. Implemented by DeviceActivity's usage thresholds — a different
/// mechanism from `SessionScheduling`'s wall-clock windows, which is why it is
/// a port of its own rather than another method on that one.
protocol UsageWatching {

    /// Starts counting `mode`'s apps against its allowance, for today and each
    /// following day, until `stopWatching`.
    ///
    /// Returns false when the system refused — the activity budget, or an
    /// authorization that has gone away. The engine blocks outright in that
    /// case: an allowance nobody is counting is an unlimited allowance, and a
    /// Mode that says "15 min a day" while enforcing nothing is the
    /// looks-configured-does-nothing failure this codebase keeps paying to
    /// avoid.
    ///
    /// Registering a Mode that is already being watched is a no-op, so
    /// `reconcile()` may call this on every foreground.
    ///
    /// - Parameter neverBlocked: excluded from the count as well as from the
    ///   shield. Time in a banking app you protected must not spend the
    ///   allowance for the apps you were rationing.
    @discardableResult
    func startWatching(_ mode: DadMode, neverBlocked: BlockedSelection) -> Bool

    /// Stops counting for this Mode. Safe when nothing is registered.
    func stopWatching(modeID: UUID)
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
    /// Which tags are paired, and which Mode each one starts.
    ///
    /// Was a flat `[String]`. A tag that can *name* a Mode is what turns
    /// thirty cents of sticker into the thing Brick charges $59 a puck for:
    /// the kitchen tag starts Dinner, the desk tag starts Deep Work.
    var tags: TagPairing { get set }

    /// A break in progress: the Mode that will start itself again, and when.
    /// `nil` whenever nothing is waiting to come back.
    var pendingResume: PendingResume? { get set }

    /// Asks for a bounded release, and what was decided about them.
    ///
    /// Kept as a list rather than one current value because a declined ask is
    /// part of the record both people can see — a household that can only ever
    /// read the answers it liked is one where the log is worth nothing.
    var grantExchanges: [GrantExchange] { get set }

    /// Nights a scheduled Mode has been told to sit out.
    ///
    /// Stored rather than derived because "not tonight" is a decision somebody
    /// made, and nothing in the history could reconstruct it. Pruned as it is
    /// read — see `ScheduleSkipping.live`.
    var scheduleSkips: [ScheduleSkip] { get set }

    /// Who is using this phone, and what that lets them do.
    ///
    /// Stored rather than derived because it is an agreement between two
    /// people, not a fact about the device. Defaults to `.solo` — an adult
    /// Dadding themselves — which is the whole product as shipped and keeps
    /// every existing install behaving exactly as it did.
    var household: Household { get set }

    /// Apps and sites no Mode may take away, whatever it blocks.
    ///
    /// One list, not one per Mode, and that is the point: the failure it
    /// exists to prevent is forgetting. Every review of a blocker has the same
    /// story in it — someone shields a category, and discovers at the wrong
    /// moment that it contained their bank, their maps, or the call they
    /// needed to answer. A safety net you have to remember to fit each time is
    /// not one.
    var neverBlocked: BlockedSelection { get set }
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
