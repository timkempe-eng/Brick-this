import Foundation
@testable import DadCore

/// In-memory `DadPersisting`. Starts genuinely empty — no starter modes — so
/// each test states the world it needs.
final class FakeStore: DadPersisting {
    var modes: [DadMode] = []
    var activeSession: DadSession?
    var history: [DadSession] = []
    var tags = TagPairing()
    var neverBlocked = BlockedSelection()
    var lastShieldConfirmedAt: Date?
    var memberID: MemberID?
    var ledger = HouseholdLedger()
    var household = Household.solo
    var scheduleSkips: [ScheduleSkip] = []
    var grantExchanges: [GrantExchange] = []
    var pendingResume: PendingResume?
    var emergencyUses: [Date] = []
    var hasOnboarded = false
    var syncedSchedules: [RecurringSchedule] = []
    var hasDataFromANewerBuild = false
}

/// Records what the engine asked of the shield, and in what order.
final class SpyShield: ShieldControlling {
    enum Call: Equatable { case apply(UUID), restrictionsOnly(UUID), clear }
    private(set) var calls: [Call] = []

    /// What the engine said was off limits on the last `apply`. The shield is
    /// where the never-block list has to arrive; a test that only checks the
    /// store would pass while the adapter never heard about it.
    private(set) var lastNeverBlocked: BlockedSelection?

    /// Which Mode's apps are currently hidden, as far as the shield has been
    /// told. Deliberately `nil` for `restrictionsOnly`: while an allowance
    /// lasts the apps are still there, and a test asserting "the shield is up"
    /// must not pass for a Mode that is merely rationing.
    var appliedMode: UUID? {
        switch calls.last {
        case .apply(let id):        return id
        case .restrictionsOnly:     return nil
        case .clear, .none:         return nil
        }
    }

    /// Which Mode is rationing right now — the apps are visible, but strict
    /// still holds.
    var rationingMode: UUID? {
        if case .restrictionsOnly(let id) = calls.last { return id }
        return nil
    }

    func apply(_ mode: DadMode, neverBlocked: BlockedSelection) {
        calls.append(.apply(mode.id))
        lastNeverBlocked = neverBlocked
    }
    func applyRestrictionsOnly(_ mode: DadMode) { calls.append(.restrictionsOnly(mode.id)) }
    func clear() { calls.append(.clear) }

    /// Approved by default: every test that is not about the gap report is
    /// about a phone whose Screen Time access is in place, and making them all
    /// say so would bury the ones that mean it.
    var authorization: ShieldAuthorization = .approved
}

/// Records what the engine asked of the usage counter.
final class SpyUsageWatcher: UsageWatching {
    enum Call: Equatable { case start(UUID, minutes: Int), stop(UUID) }
    private(set) var calls: [Call] = []

    /// Mode ids the watcher should refuse to register, standing in for the
    /// system's activity budget being full.
    var refusing: Set<UUID> = []

    /// What the system would currently be counting.
    private(set) var watching: Set<UUID> = []

    private(set) var lastNeverBlocked: BlockedSelection?

    func startWatching(_ mode: DadMode, neverBlocked: BlockedSelection) -> Bool {
        calls.append(.start(mode.id, minutes: mode.editableAllowance.minutesPerDay))
        lastNeverBlocked = neverBlocked
        guard !refusing.contains(mode.id) else { return false }
        watching.insert(mode.id)
        return true
    }

    func stopWatching(modeID: UUID) {
        calls.append(.stop(modeID))
        watching.remove(modeID)
    }
}

final class SpyScheduler: SessionScheduling {
    private(set) var scheduled: [Date] = []
    private(set) var cancelCount = 0

    /// The break's one-shot window, kept apart from the release's so a test
    /// can tell "come back at 5" from "let me go at 5".
    private(set) var resumes: [Date] = []
    private(set) var resumeCancelCount = 0

    /// Every window ever started/stopped, in order — so tests can assert not
    /// just the end state but that an unchanged window was never touched.
    private(set) var started: [ScheduledWindow] = []
    private(set) var stopped: [String] = []

    /// Names the spy should report as failing to register.
    var failingNames: Set<String> = []

    /// What the system would currently be watching.
    var registered: Set<String> {
        var names = Set<String>()
        for w in started where !failingNames.contains(w.name) { names.insert(w.name) }
        for n in stopped { names.remove(n) }
        return names
    }

    func scheduleRelease(at date: Date) { scheduled.append(date) }
    func cancelScheduledRelease() { cancelCount += 1 }
    func scheduleResume(at date: Date) { resumes.append(date) }
    func cancelScheduledResume() { resumeCancelCount += 1 }
    func stopWindows(named names: [String]) { stopped += names }
    func startWindows(_ windows: [ScheduledWindow]) -> [String] {
        started += windows
        return windows.map(\.name).filter(failingNames.contains)
    }
}

final class SpyWidget: WidgetRefreshing {
    private(set) var reloadCount = 0
    func reload() { reloadCount += 1 }
}

final class TestClock: Clock {
    var now: Date
    init(_ now: Date) { self.now = now }

    func advance(_ interval: TimeInterval) { now = now.addingTimeInterval(interval) }
    func advance(days: Int) { advance(TimeInterval(days) * 24 * 60 * 60) }
}

/// A world under test, with everything reachable.
struct Harness {
    let store = FakeStore()
    let shield = SpyShield()
    let scheduler = SpyScheduler()
    let widget = SpyWidget()
    let usage = SpyUsageWatcher()
    let clock: TestClock
    let engine: DadEngine

    /// - Parameter calendar: pinned to UTC by default so the allowance's day
    ///   boundary is the same wherever this suite runs. A test that cares about
    ///   a specific zone passes its own.
    init(now: Date = Date(timeIntervalSince1970: 1_756_000_000),
         calendar: Calendar = .utc) {
        let clock = TestClock(now)
        self.clock = clock
        self.engine = DadEngine(store: store, shield: shield, scheduler: scheduler,
                                clock: clock, widget: widget, usage: usage,
                                calendar: calendar)
    }

    @discardableResult
    func addMode(name: String = "Deep Work",
                 apps: Int = 3,
                 strict: Bool = false,
                 autoRelease: TimeInterval? = nil,
                 schedule: ModeSchedule? = nil,
                 allowance: ModeAllowance? = nil,
                 breakLength: TimeInterval? = nil) -> DadMode {
        let mode = DadMode(name: name,
                           symbol: "circle",
                           blocked: BlockedSelection(payload: Data([1]), appCount: apps),
                           isStrict: strict,
                           autoUnDadAfter: autoRelease,
                           resumeAfter: breakLength,
                           schedule: schedule,
                           allowance: allowance)
        store.modes.append(mode)
        return mode
    }

    /// Replaces a Mode in the store the way the editor would, so a test can
    /// change one mid-session and see what reaches the shield.
    func save(_ mode: DadMode) { engine.upsert(mode) }

    /// A Mode that exists but blocks nothing — the "not set up yet" state.
    @discardableResult
    func addEmptyMode(name: String = "Empty") -> DadMode {
        let mode = DadMode(name: name, symbol: "circle")
        store.modes.append(mode)
        return mode
    }
}


extension Calendar {
    /// A calendar whose days start at 00:00 UTC, so "the same day" means the
    /// same thing on every machine that runs this suite.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
