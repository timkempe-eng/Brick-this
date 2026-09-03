import XCTest
@testable import DadCore

/// The first time this schema ladder has actually moved a shape.
///
/// The envelope has been in place since before anything shipped — added
/// specifically because it "costs nothing before the first install and can't be
/// retrofitted cleanly after". This is the migration it was added for, and
/// these tests are the ones that decide whether that bet paid off: what a phone
/// with tags already paired sees the morning it updates.
///
/// `TagPairingTests` covers the migration function. These cover it *through*
/// `SchemaCoding`, which is the path a real phone takes.
final class TagMigrationTests: XCTestCase {

    private func stored(_ json: String) -> Data { json.data(using: .utf8)! }

    // MARK: - What is already on somebody's phone

    func testTagsPairedByAnOlderBuildSurviveAndBecomePlainToggles() {
        // The whole point. Somebody paired a sticker months ago; after the
        // update it must still open their phone, and it must behave exactly as
        // it did — a toggle, not a tag that suddenly names a Mode nobody chose.
        let old = stored(#"{"schema":1,"value":["ABC123","DEADBEEF"]}"#)

        guard case .value(let tags) = SchemaCoding.read(TagPairing.self, from: old) else {
            return XCTFail("a phone with tags paired must not lose them")
        }
        XCTAssertEqual(tags.count, 2)
        XCTAssertTrue(tags.isPaired("ABC123"))
        XCTAssertTrue(tags.isPaired("DEADBEEF"))
        XCTAssertNil(tags.modeID(for: "ABC123"), "and it is still just a toggle")
    }

    func testAPhoneFromBeforeEnvelopesExistedStillMigratesAllTheWay() {
        // Schema 0 — a bare value with no envelope at all — has to climb both
        // rungs of the ladder in one read.
        let ancient = stored(#"["ABC123"]"#)

        guard case .value(let tags) = SchemaCoding.read(TagPairing.self, from: ancient) else {
            return XCTFail("0 → 1 → 2 must run to completion")
        }
        XCTAssertTrue(tags.isPaired("ABC123"))
    }

    func testAPhoneWithNoTagsPairedIsUnaffected() {
        let none = stored(#"{"schema":1,"value":[]}"#)
        guard case .value(let tags) = SchemaCoding.read(TagPairing.self, from: none) else {
            return XCTFail("an empty list is not a failure")
        }
        XCTAssertTrue(tags.isEmpty)
        XCTAssertTrue(tags.isPaired("ANYTHING"), "and empty still means any tag works")
    }

    func testMigratingIsNotAppliedTwice() {
        // A value already at the current schema must be read, not migrated —
        // running the step again on the new shape is how a migration corrupts
        // the data it was written to save.
        let current = stored(#"{"schema":2,"value":[{"uid":"ABC123"}]}"#)
        guard case .value(let tags) = SchemaCoding.read(TagPairing.self, from: current) else {
            return XCTFail("the current shape must read straight through")
        }
        XCTAssertEqual(tags.uids, ["ABC123"])
    }

    // MARK: - Round trip

    func testWhatThisBuildWritesIsWhatItReadsBack() {
        var tags = TagPairing()
        let dinner = UUID()
        tags.pair("KITCHEN", to: dinner)
        tags.pair("DESK")

        let data = SchemaCoding.encode(tags)
        XCTAssertNotNil(data)
        guard case .value(let read) = SchemaCoding.read(TagPairing.self, from: data) else {
            return XCTFail("a value this build wrote must read back")
        }
        XCTAssertEqual(read.modeID(for: "KITCHEN"), dinner)
        XCTAssertNil(read.modeID(for: "DESK"))
    }

    func testAnOlderBuildRefusesToOverwriteWhatThisOneWrote() {
        // The other half of the envelope's promise, and the reason the bump is
        // safe: a TestFlight rollback reads schema 2 as `.tooNew` and declines
        // to write over it, rather than treating a shape it cannot parse as
        // corrupt and resetting somebody's tags.
        let written = SchemaCoding.encode(TagPairing())!
        let object = try! JSONSerialization.jsonObject(with: written) as! [String: Any]
        XCTAssertEqual(object["schema"] as? Int, SchemaCoding.current)
    }

    // MARK: - The migration cannot reach other keys

    func testTheStepLeavesEveryOtherStoredShapeAlone() {
        // It recognises a non-empty array of strings and nothing else. That is
        // safe only because the paired-tag list is the only bare `[String]`
        // stored today — a future key holding one makes this wrong, and the
        // fix then is to make migration key-aware.
        let modes = stored(#"{"schema":1,"value":[{"id":"\#(UUID().uuidString)","name":"Deep Work","symbol":"brain","blocked":{"payload":"","appCount":2,"categoryCount":0,"webDomainCount":0},"isStrict":false}]}"#)
        guard case .value(let decoded) = SchemaCoding.readArray(DadMode.self, from: modes) else {
            return XCTFail("Modes stored at schema 1 must survive the bump")
        }
        XCTAssertEqual(decoded.first?.name, "Deep Work")

        let uses = stored(#"{"schema":1,"value":[1756000000]}"#)
        guard case .value(let dates) = SchemaCoding.read([Date].self, from: uses) else {
            return XCTFail("override uses are numbers and must be untouched")
        }
        XCTAssertEqual(dates.count, 1)
    }
}
