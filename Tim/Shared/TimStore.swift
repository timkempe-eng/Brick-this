import Foundation
import FamilyControls

/// Shared state, persisted in the App Group so that the app, the shield
/// extensions and the DeviceActivity monitor all read the same truth.
///
/// The extensions run in their own processes with tight memory limits, so
/// this stays deliberately small: plain `Codable` values in `UserDefaults`,
/// no database, no observers across process boundaries.
final class TimStore {
    static let appGroupID = "group.app.tim.shared"

    static let shared = TimStore()

    private let defaults: UserDefaults

    private init() {
        guard let suite = UserDefaults(suiteName: Self.appGroupID) else {
            // A missing App Group is a build-configuration mistake, not a
            // runtime condition worth limping through: the shield would
            // silently disagree with the app about whether we are Timmed.
            fatalError("App Group \(Self.appGroupID) is not configured for this target.")
        }
        defaults = suite
    }

    private enum Key {
        static let modes = "modes"
        static let activeSession = "activeSession"
        static let history = "history"
        static let pairedTagUIDs = "pairedTagUIDs"
        static let emergencyUses = "emergencyUses"
        static let hasOnboarded = "hasOnboarded"
    }

    // MARK: - Modes

    var modes: [TimMode] {
        get { decode([TimMode].self, Key.modes) ?? TimMode.starterModes }
        set { encode(newValue, Key.modes) }
    }

    func mode(id: UUID) -> TimMode? { modes.first { $0.id == id } }

    func upsert(_ mode: TimMode) {
        var all = modes
        if let i = all.firstIndex(where: { $0.id == mode.id }) { all[i] = mode } else { all.append(mode) }
        modes = all
    }

    func deleteMode(id: UUID) {
        modes = modes.filter { $0.id != id }
    }

    // MARK: - Active session

    var activeSession: TimSession? {
        get { decode(TimSession.self, Key.activeSession) }
        set { encode(newValue, Key.activeSession) }
    }

    var isTimmed: Bool { activeSession != nil }

    var history: [TimSession] {
        get { decode([TimSession].self, Key.history) ?? [] }
        set { encode(newValue, Key.history) }
    }

    func archive(_ session: TimSession) {
        // Keep the tail bounded — the extensions read this file too.
        history = Array((history + [session]).suffix(500))
    }

    // MARK: - Paired tags
    //
    // Stored as hex UID strings. More than one tag can be paired so you can
    // keep one on the desk and one by the front door.

    var pairedTagUIDs: [String] {
        get { defaults.stringArray(forKey: Key.pairedTagUIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.pairedTagUIDs) }
    }

    func pair(tagUID: String) {
        guard !pairedTagUIDs.contains(tagUID) else { return }
        pairedTagUIDs.append(tagUID)
    }

    func isPaired(tagUID: String) -> Bool {
        // An empty pairing list means "any tag works", which is what you want
        // before the user has paired anything.
        pairedTagUIDs.isEmpty || pairedTagUIDs.contains(tagUID)
    }

    // MARK: - Emergency overrides
    //
    // Five per rolling 30 days, matching the escape hatch Brick ships. The
    // point is not to make it impossible, just expensive enough to think about.

    static let emergencyAllowance = 5
    private static let emergencyWindow: TimeInterval = 30 * 24 * 60 * 60

    private var emergencyUses: [Date] {
        get { decode([Date].self, Key.emergencyUses) ?? [] }
        set { encode(newValue, Key.emergencyUses) }
    }

    var emergencyUnTimsRemaining: Int {
        let cutoff = Date().addingTimeInterval(-Self.emergencyWindow)
        let recent = emergencyUses.filter { $0 > cutoff }
        return max(0, Self.emergencyAllowance - recent.count)
    }

    /// Spends one override. Returns false — and changes nothing — when the
    /// allowance is gone.
    func consumeEmergencyUnTim() -> Bool {
        guard emergencyUnTimsRemaining > 0 else { return false }
        let cutoff = Date().addingTimeInterval(-Self.emergencyWindow)
        emergencyUses = emergencyUses.filter { $0 > cutoff } + [Date()]
        return true
    }

    // MARK: - Onboarding

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    // MARK: - Codable plumbing

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value else { return defaults.removeObject(forKey: key) }
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
