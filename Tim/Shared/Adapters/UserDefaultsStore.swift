import Foundation

/// `TimPersisting` over the App Group `UserDefaults`, so the app, both shield
/// extensions and the DeviceActivity monitor all read the same truth.
///
/// The extensions run in their own processes under tight memory limits, so
/// this stays deliberately small: plain `Codable` values, no database, no
/// cross-process observers.
final class UserDefaultsStore: TimPersisting {

    static let appGroupID = "group.app.tim.shared"
    static let shared = UserDefaultsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        guard let suite = defaults ?? UserDefaults(suiteName: Self.appGroupID) else {
            // A missing App Group is a build-configuration mistake, not a
            // runtime condition worth limping through: the shield would
            // silently disagree with the app about whether we're Timmed.
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
    }

    var modes: [TimMode] {
        get { decode([TimMode].self, Key.modes) ?? TimMode.starterModes }
        set { encode(newValue, Key.modes) }
    }

    var activeSession: TimSession? {
        get { decode(TimSession.self, Key.activeSession) }
        set { encode(newValue, Key.activeSession) }
    }

    var history: [TimSession] {
        get { decode([TimSession].self, Key.history) ?? [] }
        set { encode(newValue, Key.history) }
    }

    var pairedTagUIDs: [String] {
        get { defaults.stringArray(forKey: Key.pairedTagUIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.pairedTagUIDs) }
    }

    var emergencyUses: [Date] {
        get { decode([Date].self, Key.emergencyUses) ?? [] }
        set { encode(newValue, Key.emergencyUses) }
    }

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
