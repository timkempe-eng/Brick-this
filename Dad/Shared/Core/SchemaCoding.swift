import Foundation

/// Versioned storage.
///
/// Everything is persisted as JSON under a fixed key and read back with a
/// forgiving decode, which means a change to a stored shape silently resets
/// whatever it touched — your Modes, or every streak you have built. That was
/// an accepted limitation while nothing was installed anywhere. Introducing the
/// envelope costs nothing before the first install and is impossible to
/// retrofit cleanly afterwards, so it happens now.
///
/// The stored form is `{"schema": N, "value": <the value>}`.
enum SchemaCoding {

    /// Bump when a stored shape changes, and add the migration below.
    static let current = 1

    private enum Key {
        static let schema = "schema"
        static let value = "value"
    }

    // MARK: - Reading

    enum Read<T>: Equatable where T: Equatable {
        /// Read and, if it was written by an older build, migrated.
        case value(T)
        /// Nothing stored. Use the default; safe to write over.
        case missing
        /// Stored but unreadable even leniently. Use the default; safe to
        /// write over, because whatever is there cannot be recovered anyway.
        case unreadable
        /// Written by a LATER build than this one. Use the default, but do
        /// **not** write over it: a downgrade — a TestFlight rollback, an old
        /// build on a second device — must not destroy newer data it merely
        /// fails to understand.
        case tooNew(schema: Int)
    }

    static func read<T: Decodable & Equatable>(_ type: T.Type, from data: Data?) -> Read<T> {
        guard let data, !data.isEmpty else { return .missing }

        let object = try? JSONSerialization.jsonObject(with: data)

        // An envelope, or a value written before envelopes existed.
        let schema: Int
        let payload: Any?
        if let dict = object as? [String: Any], let stored = dict[Key.schema] as? Int {
            schema = stored
            payload = dict[Key.value]
        } else {
            schema = 0
            payload = object
        }

        if schema > current { return .tooNew(schema: schema) }

        guard let payload, let migrated = migrate(payload, from: schema) else {
            return .unreadable
        }
        guard let body = try? JSONSerialization.data(withJSONObject: migrated,
                                                     options: [.fragmentsAllowed]),
              let value = try? JSONDecoder().decode(T.self, from: body) else {
            return .unreadable
        }
        return .value(value)
    }

    /// The same, for arrays, keeping the element-by-element leniency that stops
    /// one bad record costing a whole history.
    static func readArray<T: Decodable>(_ type: T.Type, from data: Data?) -> Read<[T]> {
        guard let data, !data.isEmpty else { return .missing }

        let object = try? JSONSerialization.jsonObject(with: data)
        let schema: Int
        let payload: Any?
        if let dict = object as? [String: Any], let stored = dict[Key.schema] as? Int {
            schema = stored
            payload = dict[Key.value]
        } else {
            schema = 0
            payload = object
        }

        if schema > current { return .tooNew(schema: schema) }

        guard let payload, let migrated = migrate(payload, from: schema),
              let body = try? JSONSerialization.data(withJSONObject: migrated),
              let values = LenientDecoding.array(T.self, from: body) else {
            return .unreadable
        }
        return .value(values)
    }

    // MARK: - Writing

    static func encode<T: Encodable>(_ value: T) -> Data? {
        guard let body = try? JSONEncoder().encode(value),
              let payload = try? JSONSerialization.jsonObject(with: body,
                                                              options: [.fragmentsAllowed])
        else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: [Key.schema: current, Key.value: payload],
            options: [.fragmentsAllowed])
    }

    // MARK: - Migration

    /// Brings a stored payload forward to `current`, or `nil` if it can't be.
    ///
    /// Each step is written against the JSON rather than the Swift types, so a
    /// migration keeps working after the type it migrates *from* has been
    /// deleted from the codebase.
    private static func migrate(_ payload: Any, from schema: Int) -> Any? {
        var value = payload
        var version = schema

        while version < current {
            switch version {
            case 0:
                // 0 → 1: values used to be stored bare, with no envelope. The
                // payload shape is unchanged; only the wrapper is new, and the
                // caller has already unwrapped it.
                version = 1
            default:
                // A gap in the ladder is a programming error, not user data
                // being wrong. Refuse rather than hand back a half-migrated
                // value that would then be written back as if it were current.
                return nil
            }
        }
        return value
    }
}
