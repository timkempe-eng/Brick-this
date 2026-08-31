import Foundation

/// Decoding that loses as little as possible.
///
/// Everything is persisted as JSON in `UserDefaults` and read back with
/// `try?`, so a single unreadable record — a field added in a later version, a
/// half-written write — would otherwise throw away the entire array. For the
/// session history that means losing every streak the user has built, which is
/// a bad trade for one bad row.
enum LenientDecoding {

    /// Decodes an array element by element, skipping any that fail.
    ///
    /// Returns `nil` only when the data isn't a JSON array at all, so callers
    /// can still tell "nothing stored" from "stored but empty".
    static func array<T: Decodable>(_ type: T.Type,
                                    from data: Data,
                                    decoder: JSONDecoder = JSONDecoder()) -> [T]? {
        guard let wrapped = try? decoder.decode([Failable<T>].self, from: data) else { return nil }
        return wrapped.compactMap(\.value)
    }

    /// Decodes as `T`, or `nil` if that element is unreadable — never throws
    /// out of the surrounding array.
    private struct Failable<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = try? container.decode(T.self)
        }
    }
}
