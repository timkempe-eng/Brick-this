import Foundation

/// `DadPersisting` over the App Group `UserDefaults`, so the app, both shield
/// extensions and the DeviceActivity monitor all read the same truth.
///
/// The extensions run in their own processes under tight memory limits, so
/// this stays deliberately small: plain `Codable` values, no database, no
/// cross-process observers.
final class UserDefaultsStore: DadPersisting {

    static let appGroupID = "group.app.dad.shared"
    static let shared = UserDefaultsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        guard let suite = defaults ?? UserDefaults(suiteName: Self.appGroupID) else {
            // A missing App Group is a build-configuration mistake, not a
            // runtime condition worth limping through: the shield would
            // silently disagree with the app about whether we're Dadded.
            fatalError("App Group \(Self.appGroupID) is not configured for this target.")
        }
        self.defaults = suite
    }

    private enum Key {
        static let modes = "modes"
        static let activeSession = "activeSession"
        static let history = "history"
        static let pairedTagUIDs = "pairedTagUIDs"
        static let emergencyUses = "emergencyUses"
        static let hasOnboarded = "hasOnboarded"
        static let syncedSchedules = "syncedSchedules"
    }

    var modes: [DadMode] {
        // Lenient: a Mode made unreadable by a schema change shouldn't take the
        // user's other Modes with it. Only a completely absent or non-array
        // value falls back to the starters.
        get { decodeArray(DadMode.self, Key.modes) ?? DadMode.starterModes }
        set { encode(newValue, Key.modes) }
    }

    var activeSession: DadSession? {
        get { decode(DadSession.self, Key.activeSession) }
        set { encode(newValue, Key.activeSession) }
    }

    var history: [DadSession] {
        // Lenient for the same reason, and it matters most here: this is every
        // streak the user has built.
        get { decodeArray(DadSession.self, Key.history) ?? [] }
        set { encode(newValue, Key.history) }
    }

    var pairedTagUIDs: [String] {
        get { decodeArray(String.self, Key.pairedTagUIDs) ?? [] }
        set { encode(newValue, Key.pairedTagUIDs) }
    }

    var emergencyUses: [Date] {
        get { decode([Date].self, Key.emergencyUses) ?? [] }
        set { encode(newValue, Key.emergencyUses) }
    }

    var syncedSchedules: [RecurringSchedule] {
        get { decode([RecurringSchedule].self, Key.syncedSchedules) ?? [] }
        set { encode(newValue, Key.syncedSchedules) }
    }

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    // MARK: - Storage

    /// Set by any read that finds a later schema than this build understands.
    private(set) var hasDataFromANewerBuild = false

    /// Arrays skip unreadable elements rather than discarding the whole array,
    /// so one bad record cannot cost a whole history.
    private func decodeArray<T: Decodable & Equatable>(_ type: T.Type, _ key: String) -> [T]? {
        switch SchemaCoding.readArray(T.self, from: defaults.data(forKey: key)) {
        case .value(let values):  return values
        case .missing, .unreadable: return nil
        case .tooNew(let schema):
            noteNewerBuild(key: key, schema: schema)
            return nil
        }
    }

    private func decode<T: Decodable & Equatable>(_ type: T.Type, _ key: String) -> T? {
        switch SchemaCoding.read(T.self, from: defaults.data(forKey: key)) {
        case .value(let value):   return value
        case .missing, .unreadable: return nil
        case .tooNew(let schema):
            noteNewerBuild(key: key, schema: schema)
            return nil
        }
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value else { return defaults.removeObject(forKey: key) }
        defaults.set(SchemaCoding.encode(value), forKey: key)
    }

    /// Deliberately does not block the write that will follow.
    ///
    /// Refusing to save would leave the app looking broken with no way out.
    /// Telling the user plainly, and letting them decide whether to go on, is
    /// the better trade for data they can still recover by updating.
    private func noteNewerBuild(key: String, schema: Int) {
        hasDataFromANewerBuild = true
    }
}
