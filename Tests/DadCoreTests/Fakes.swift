import Foundation
@testable import DadCore

/// In-memory `DadPersisting`. Starts genuinely empty — no starter modes — so
/// each test states the world it needs.
final class FakeStore: DadPersisting {
    var modes: [DadMode] = []
    var activeSession: DadSession?
    var history: [DadSession] = []
    var pairedTagUIDs: [String] = []
    var emergencyUses: [Date] = []
    var hasOnboarded = false
    var syncedSchedules: [RecurringSchedule] = []
    var hasDataFromANewerBuild = false
}

/// Records what the engine asked of the shield, and in what order.
final class SpyShield: ShieldControlling {
    enum Call: Equatable { case apply(UUID), clear }
    private(set) var calls: [Call] = []

    /// What the shield is showing right now, as far as it's been told.
    var appliedMode: UUID? {
        switch calls.last {
        case .apply(let id): return id
        case .clear, .none:  return nil
        }
    }

    func apply(_ mode: DadMode) { calls.append(.apply(mode.id)) }
    func clear() { calls.append(.clear) }
}

final class SpyScheduler: SessionScheduling {
    private(set) var scheduled: [Date] = []
    private(set) var cancelCount = 0

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
    let clock: TestClock
    let engine: DadEngine

    init(now: Date = Date(timeIntervalSince1970: 1_756_000_000)) {
        let clock = TestClock(now)
        self.clock = clock
        self.engine = DadEngine(store: store, shield: shield, scheduler: scheduler,
                                clock: clock, widget: widget)
    }

    @discardableResult
    func addMode(name: String = "Deep Work",
                 apps: Int = 3,
                 strict: Bool = false,
                 autoRelease: TimeInterval? = nil,
                 schedule: ModeSchedule? = nil) -> DadMode {
        let mode = DadMode(name: name,
                           symbol: "circle",
                           blocked: BlockedSelection(payload: Data([1]), appCount: apps),
                           isStrict: strict,
                           autoUnDadAfter: autoRelease,
                           schedule: schedule)
        store.modes.append(mode)
        return mode
    }

    /// A Mode that exists but blocks nothing — the "not set up yet" state.
    @discardableResult
    func addEmptyMode(name: String = "Empty") -> DadMode {
        let mode = DadMode(name: name, symbol: "circle")
        store.modes.append(mode)
        return mode
    }
}
