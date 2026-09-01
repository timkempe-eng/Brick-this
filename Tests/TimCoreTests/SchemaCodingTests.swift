import XCTest
@testable import TimCore

/// Storage is the one place where a mistake is not recoverable by rebuilding —
/// it costs the user their Modes or their streaks.
final class SchemaCodingTests: XCTestCase {

    private struct Row: Codable, Equatable {
        var id: Int
        var name: String
    }

    private func json(_ string: String) -> Data { string.data(using: .utf8)! }

    // MARK: - Round trip

    func testAValueSurvivesEncodingAndReading() {
        let row = Row(id: 1, name: "Deep Work")
        let data = SchemaCoding.encode(row)
        XCTAssertEqual(SchemaCoding.read(Row.self, from: data), .value(row))
    }

    func testWhatIsWrittenCarriesTheSchemaVersion() {
        let data = SchemaCoding.encode(Row(id: 1, name: "a"))!
        let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["schema"] as? Int, SchemaCoding.current)
        XCTAssertNotNil(object["value"])
    }

    func testNothingStoredIsDistinctFromStoredButBroken() {
        // The caller treats these the same today, but conflating them makes it
        // impossible to ever tell a fresh install from a corrupted one.
        XCTAssertEqual(SchemaCoding.read(Row.self, from: nil), .missing)
        XCTAssertEqual(SchemaCoding.read(Row.self, from: Data()), .missing)
        XCTAssertEqual(SchemaCoding.read(Row.self, from: json("not json")), .unreadable)
        XCTAssertEqual(SchemaCoding.read(Row.self, from: json(#"{"schema":1,"value":{"id":1}}"#)),
                       .unreadable)
    }

    // MARK: - Older data

    func testAValueWrittenBeforeEnvelopesExistedStillReads() {
        // Every install that predates this change has bare values on disk.
        // Failing to read them would reset exactly the data this is meant to
        // protect.
        let legacy = json(#"{"id":7,"name":"Sleep"}"#)
        XCTAssertEqual(SchemaCoding.read(Row.self, from: legacy),
                       .value(Row(id: 7, name: "Sleep")))
    }

    func testALegacyArrayStillReads() {
        let legacy = json(#"[{"id":1,"name":"a"},{"id":2,"name":"b"}]"#)
        XCTAssertEqual(SchemaCoding.readArray(Row.self, from: legacy),
                       .value([Row(id: 1, name: "a"), Row(id: 2, name: "b")]))
    }

    // MARK: - Newer data

    func testDataFromALaterBuildIsReportedRatherThanReset() {
        // A TestFlight rollback, or an older build on a second device. The
        // value is unreadable here, but it is not corrupt — and overwriting it
        // would destroy data the newer build understands perfectly.
        let future = json(#"{"schema":999,"value":{"anything":true}}"#)
        XCTAssertEqual(SchemaCoding.read(Row.self, from: future), .tooNew(schema: 999))
        XCTAssertEqual(SchemaCoding.readArray(Row.self, from: future), .tooNew(schema: 999))
    }

    func testTooNewIsDecidedBeforeTheValueIsEvenLookedAt() {
        // A later schema's payload may be a shape this build cannot parse at
        // all. That must still report tooNew, not unreadable, or the caller
        // would treat it as safe to overwrite.
        let future = json(#"{"schema":2,"value":"a bare string"}"#)
        XCTAssertEqual(SchemaCoding.read(Row.self, from: future), .tooNew(schema: 2))
    }

    func testAMalformedSchemaIsRefusedRatherThanAssumedCurrent() {
        // Not too-new, not a version we ever wrote. Treating it as current
        // would hand back a payload of unknown shape as if it were valid.
        XCTAssertEqual(SchemaCoding.read(Row.self, from: json(#"{"schema":-1,"value":{"id":1,"name":"a"}}"#)),
                       .unreadable)
        XCTAssertEqual(SchemaCoding.readArray(Row.self, from: json(#"{"schema":-3,"value":[]}"#)),
                       .unreadable)
    }

    // MARK: - Leniency is preserved

    func testOneBadRowStillDoesNotCostTheRest() {
        let mixed = json(#"{"schema":1,"value":[{"id":1,"name":"a"},{"id":2},{"id":3,"name":"c"}]}"#)
        XCTAssertEqual(SchemaCoding.readArray(Row.self, from: mixed),
                       .value([Row(id: 1, name: "a"), Row(id: 3, name: "c")]))
    }

    // MARK: - The real payloads

    func testAModeSurvivesTheRoundTrip() {
        let mode = TimMode(name: "Deep Work", symbol: "brain",
                           blocked: BlockedSelection(payload: Data([1, 2]), appCount: 4),
                           isStrict: true, autoUnTimAfter: 3600)
        XCTAssertEqual(SchemaCoding.read(TimMode.self, from: SchemaCoding.encode(mode)),
                       .value(mode))
    }

    func testAHistoryOfSessionsSurvivesTheRoundTrip() {
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let sessions = (0..<3).map { i in
            TimSession(modeID: UUID(), modeName: "Mode \(i)",
                       startedAt: start, endedAt: start.addingTimeInterval(600))
        }
        guard case .value(let restored) =
                SchemaCoding.readArray(TimSession.self, from: SchemaCoding.encode(sessions)) else {
            return XCTFail("history did not survive")
        }
        XCTAssertEqual(restored, sessions)
    }
}
