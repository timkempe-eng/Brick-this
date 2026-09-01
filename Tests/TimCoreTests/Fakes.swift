import Foundation
@testable import TimCore

/// In-memory `TimPersisting`. Starts genuinely empty — no starter modes — so
/// each test states the world it needs.
final class FakeStore: TimPersisting {
    var modes: [TimMode] = []
    var activeSession: TimSession?
    var history: [TimSession] = []
    var pairedTagUIDs: [String] = []
    var emergencyUses: [Date] = []
    var hasOnboarded = false
    var syncedSchedules: [RecurringSchedule] = []
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

    func apply(_ mode: TimMode) { calls.append(.apply(mode.id)) }
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
    let clock: TestClock
    let engine: TimEngine

    init(now: Date = Date(timeIntervalSince1970: 1_756_000_000)) {
        let clock = TestClock(now)
        self.clock = clock
        self.engine = TimEngine(store: store, shield: shield, scheduler: scheduler, clock: clock)
    }

    @discardableResult
    func addMode(name: String = "Deep Work",
                 apps: Int = 3,
                 strict: Bool = false,
                 autoRelease: TimeInterval? = nil,
                 schedule: ModeSchedule? = nil) -> TimMode {
        let mode = TimMode(name: name,
                           symbol: "circle",
                           blocked: BlockedSelection(payload: Data([1]), appCount: apps),
                           isStrict: strict,
                           autoUnTimAfter: autoRelease,
                           schedule: schedule)
        store.modes.append(mode)
        return mode
    }

    /// A Mode that exists but blocks nothing — the "not set up yet" state.
    @discardableResult
    func addEmptyMode(name: String = "Empty") -> TimMode {
        let mode = TimMode(name: name, symbol: "circle")
        store.modes.append(mode)
        return mode
    }
}
