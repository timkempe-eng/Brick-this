import XCTest
@testable import TimCore

final class LenientDecodingTests: XCTestCase {

    private struct Row: Codable, Equatable {
        let id: Int
        let name: String
    }

    func testACleanArrayDecodesWhole() {
        let data = try! JSONEncoder().encode([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        XCTAssertEqual(LenientDecoding.array(Row.self, from: data),
                       [Row(id: 1, name: "a"), Row(id: 2, name: "b")])
    }

    func testOneBadRowDoesNotCostTheRest() {
        // The middle row is missing a required field — the case a schema change
        // produces, and the one that would otherwise wipe a user's history.
        let json = """
        [{"id":1,"name":"a"},{"id":2},{"id":3,"name":"c"}]
        """.data(using: .utf8)!

        let rows = LenientDecoding.array(Row.self, from: json)
        XCTAssertEqual(rows, [Row(id: 1, name: "a"), Row(id: 3, name: "c")])
    }

    func testAnEmptyArrayIsNotTheSameAsNothingStored() {
        XCTAssertEqual(LenientDecoding.array(Row.self, from: "[]".data(using: .utf8)!), [])
        XCTAssertNil(LenientDecoding.array(Row.self, from: "{}".data(using: .utf8)!))
        XCTAssertNil(LenientDecoding.array(Row.self, from: Data()))
    }

    func testEveryRowBadYieldsEmptyRatherThanNil() {
        let json = #"[{"nope":1},{"nope":2}]"#.data(using: .utf8)!
        XCTAssertEqual(LenientDecoding.array(Row.self, from: json), [])
    }

    /// The real payload this exists for.
    func testAHistoryWithOneUnreadableSessionKeepsTheOthers() throws {
        let good = TimSession(modeID: UUID(), modeName: "Deep Work",
                              startedAt: Date(timeIntervalSince1970: 1_756_000_000),
                              endedAt: Date(timeIntervalSince1970: 1_756_003_600))
        var array = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([good, good])) as! [[String: Any]]
        array[0].removeValue(forKey: "startedAt")
        let data = try JSONSerialization.data(withJSONObject: array)

        let recovered = LenientDecoding.array(TimSession.self, from: data)
        XCTAssertEqual(recovered?.count, 1, "one corrupt session must not erase the history")
    }
}
