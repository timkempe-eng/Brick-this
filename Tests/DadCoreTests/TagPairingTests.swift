import XCTest
@testable import DadCore

/// A tag is a thirty-cent sticker on a fridge. Nobody debugs a sticker, so
/// every decision it depends on is pinned here: what an unpaired world means,
/// what a stranger's tag does, what happens to a tag whose Mode was deleted,
/// and — the expensive half — that the flat list of UIDs already on people's
/// phones survives the shape change.
final class TagPairingTests: XCTestCase {

    private let dinner = UUID()
    private let deepWork = UUID()

    private func json(_ string: String) -> Data { string.data(using: .utf8)! }

    private func object(_ string: String) -> Any {
        try! JSONSerialization.jsonObject(with: json(string), options: [.fragmentsAllowed])
    }

    /// What `SchemaCoding.read` will do once the step below is on the ladder:
    /// unwrap, migrate the payload, decode.
    private func readThroughTheLadder(_ stored: String) -> TagPairing? {
        let payload = object(stored)
        let migrated = TagPairing.Migration.flatUIDListToNamedPairs(payload)
        guard let body = try? JSONSerialization.data(withJSONObject: migrated,
                                                     options: [.fragmentsAllowed]) else { return nil }
        return try? JSONDecoder().decode(TagPairing.self, from: body)
    }

    // MARK: - Nothing paired yet

    func testAnEmptyPairingMeansAnyTagWorks() {
        // Not "no tag works". A fresh install cannot pair a tag without a tap,
        // so refusing the first tap makes the product unstartable.
        let pairing = TagPairing()
        XCTAssertTrue(pairing.isEmpty)
        XCTAssertEqual(pairing.count, 0)
        XCTAssertTrue(pairing.isPaired("ANYTHING"))
        XCTAssertEqual(pairing.resolve("ANYTHING", knownModeIDs: []), .anyMode)
    }

    func testForgettingEveryTagReturnsToAnyTagWorks() {
        var pairing = TagPairing(uids: ["A", "B"])
        pairing.forgetAll()
        XCTAssertTrue(pairing.isPaired("A STRANGER'S TAG"))
    }

    func testTheLastTagUnpairedAlsoReturnsToAnyTagWorks() {
        // Same state by a different route, and the more likely one: you unpair
        // the sticker you lost and the app must not lock you out of the phone
        // you are holding.
        var pairing = TagPairing(uids: ["A"])
        pairing.unpair("A")
        XCTAssertTrue(pairing.isEmpty)
        XCTAssertTrue(pairing.isPaired("B"))
    }

    // MARK: - Pairing

    func testOnceSomethingIsPairedAStrangersTagIsRefused() {
        let pairing = TagPairing(uids: ["MINE"])
        XCTAssertTrue(pairing.isPaired("MINE"))
        XCTAssertFalse(pairing.isPaired("THEIRS"))
        XCTAssertEqual(pairing.resolve("THEIRS", knownModeIDs: [dinner]), .unknownTag)
    }

    func testPairingTheSameTagTwiceDoesNotAddASecondRow() {
        // Re-tapping a tag you own is how you find out its UID, so this is a
        // normal thing to do rather than a mistake.
        var pairing = TagPairing()
        pairing.pair("ABC")
        pairing.pair("ABC")
        XCTAssertEqual(pairing.uids, ["ABC"])
    }

    func testRePointingATagKeepsItsPlaceInTheList() {
        var pairing = TagPairing(uids: ["KITCHEN", "DESK", "BEDSIDE"])
        pairing.pair("DESK", to: deepWork)
        XCTAssertEqual(pairing.uids, ["KITCHEN", "DESK", "BEDSIDE"])
        XCTAssertEqual(pairing.modeID(for: "DESK"), deepWork)
    }

    func testATagCanBeRePointedBackToToggling() {
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)
        pairing.pair("KITCHEN", to: nil)
        XCTAssertNil(pairing.modeID(for: "KITCHEN"))
        XCTAssertEqual(pairing.resolve("KITCHEN", knownModeIDs: [dinner]), .anyMode)
    }

    func testUnpairingOneTagLeavesTheOthers() {
        var pairing = TagPairing(uids: ["A", "B", "C"])
        pairing.unpair("B")
        XCTAssertEqual(pairing.uids, ["A", "C"])
        XCTAssertFalse(pairing.isPaired("B"))
    }

    func testPairingOrderIsPreserved() {
        var pairing = TagPairing()
        pairing.pair("FIRST")
        pairing.pair("SECOND")
        XCTAssertEqual(pairing.uids, ["FIRST", "SECOND"])
    }

    func testUIDsAreMatchedExactly() {
        // The adapter decides the format; normalising here would silently stop
        // matching the UIDs already on disk.
        let pairing = TagPairing(uids: ["04a2"])
        XCTAssertTrue(pairing.isPaired("04a2"))
        XCTAssertFalse(pairing.isPaired("04A2"))
    }

    func testDuplicateRowsAreCollapsedFirstOneWinning() {
        // Not reachable through `pair`, but stored JSON can say anything, and
        // "the first one, probably" is not an answer.
        let pairing = TagPairing([
            .init(uid: "KITCHEN", modeID: dinner),
            .init(uid: "KITCHEN", modeID: deepWork),
        ])
        XCTAssertEqual(pairing.count, 1)
        XCTAssertEqual(pairing.modeID(for: "KITCHEN"), dinner)
    }

    func testCountIsWhatSettingsOffersToForget() {
        var pairing = TagPairing(uids: ["A", "B"])
        pairing.pair("C", to: dinner)
        XCTAssertEqual(pairing.count, 3)
    }

    // MARK: - What a tap means

    func testATagThatNamesAModeStartsThatMode() {
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)
        pairing.pair("DESK", to: deepWork)

        XCTAssertEqual(pairing.resolve("KITCHEN", knownModeIDs: [dinner, deepWork]), .mode(dinner))
        XCTAssertEqual(pairing.resolve("DESK", knownModeIDs: [dinner, deepWork]), .mode(deepWork))
    }

    func testAnUnnamedTagStillJustToggles() {
        // The behaviour of every tag before this file existed, and the one
        // that must not change.
        var pairing = TagPairing()
        pairing.pair("KITCHEN")
        XCTAssertEqual(pairing.resolve("KITCHEN", knownModeIDs: [dinner]), .anyMode)
    }

    func testAnUnknownTagIsNotTheSameAnswerAsAnUnnamedOne() {
        // Collapsing these two into "no Mode id" is how a stranger's tag ends
        // up Dadding your phone.
        var pairing = TagPairing()
        pairing.pair("MINE")
        XCTAssertEqual(pairing.resolve("MINE", knownModeIDs: []), .anyMode)
        XCTAssertEqual(pairing.resolve("THEIRS", knownModeIDs: []), .unknownTag)
    }

    // MARK: - A Mode deleted while the sticker stays on the fridge

    func testATagNamingADeletedModeFallsBackToTogglingRatherThanDying() {
        // The decision. A sticker that silently does nothing is the failure
        // this codebase exists to avoid, and it would show up weeks after the
        // delete that caused it. Dadding for a surprising Mode is loud and one
        // tap from undone.
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)
        XCTAssertEqual(pairing.resolve("KITCHEN", knownModeIDs: [deepWork]), .anyMode)
    }

    func testTheDeadPointerIsKeptRatherThanRepaired() {
        // Modes decode leniently, so a Mode can vanish for a launch and come
        // back. Repairing the pairing on sight would forget what the kitchen
        // tag meant over a Mode that was never actually deleted.
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)
        XCTAssertEqual(pairing.resolve("KITCHEN", knownModeIDs: []), .anyMode)
        XCTAssertEqual(pairing.modeID(for: "KITCHEN"), dinner, "still remembers Dinner")
        XCTAssertEqual(pairing.resolve("KITCHEN", knownModeIDs: [dinner]), .mode(dinner))
    }

    func testDanglingTagsAreNameableSoTheFallbackIsNotASecret() {
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)
        pairing.pair("DESK", to: deepWork)
        pairing.pair("SPARE")

        XCTAssertEqual(pairing.danglingUIDs(knownModeIDs: [deepWork]), ["KITCHEN"])
        XCTAssertEqual(pairing.danglingUIDs(knownModeIDs: [dinner, deepWork]), [],
                       "nothing to report when every Mode is still there")
    }

    func testAnUnnamedTagIsNeverDangling() {
        // It points at nothing on purpose. Listing it would invite the user to
        // "fix" a tag that works.
        let pairing = TagPairing(uids: ["SPARE"])
        XCTAssertEqual(pairing.danglingUIDs(knownModeIDs: []), [])
    }

    func testDanglingTagsComeBackInPairingOrder() {
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)
        pairing.pair("DESK", to: deepWork)
        XCTAssertEqual(pairing.danglingUIDs(knownModeIDs: []), ["KITCHEN", "DESK"])
    }

    // MARK: - Storage

    func testAPairingSurvivesTheRoundTrip() {
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)
        pairing.pair("SPARE")
        XCTAssertEqual(SchemaCoding.read(TagPairing.self, from: SchemaCoding.encode(pairing)),
                       .value(pairing))
    }

    func testAnEmptyPairingSurvivesTheRoundTripAsEmpty() {
        // And not as "missing", which would be indistinguishable from a fresh
        // install — the same value, but arrived at deliberately.
        let pairing = TagPairing()
        XCTAssertEqual(SchemaCoding.read(TagPairing.self, from: SchemaCoding.encode(pairing)),
                       .value(pairing))
    }

    func testItIsStoredAsABareArrayOfPairs() {
        // Pinned because the migration writes this shape by hand, in JSON. If
        // the encoded form ever grows a wrapper object or renames `uid`, the
        // migration is producing something nothing can decode and this is the
        // test that says so.
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)
        pairing.pair("SPARE")

        let data = SchemaCoding.encode(pairing)!
        let envelope = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rows = envelope["value"] as! [[String: Any]]

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["uid"] as? String, "KITCHEN")
        XCTAssertEqual(rows[0]["modeID"] as? String, dinner.uuidString)
        XCTAssertEqual(rows[1]["uid"] as? String, "SPARE")
        XCTAssertNil(rows[1]["modeID"], "an unnamed tag omits the key rather than storing null")
    }

    func testOneCorruptRowCostsOneStickerRatherThanTheKeyring() {
        let mixed = json(#"[{"uid":"KITCHEN"},{"modeID":"not even a uid"},{"uid":"DESK"}]"#)
        let pairing = try? JSONDecoder().decode(TagPairing.self, from: mixed)
        XCTAssertEqual(pairing?.uids, ["KITCHEN", "DESK"])
    }

    func testARowNamingAnUnparseableModeIsDroppedRatherThanSilentlyUnnamed() {
        // Dropping it makes the tag unpaired, which is visible in the count.
        // Keeping it as a toggle would look configured and do something else.
        let bad = json(#"[{"uid":"KITCHEN","modeID":"xyz"}]"#)
        XCTAssertEqual((try? JSONDecoder().decode(TagPairing.self, from: bad))?.count, 0)
    }

    func testSomethingThatIsNotAnArrayAtAllIsUnreadableRatherThanEmpty() {
        // `SchemaCoding` needs the throw to tell corrupt from empty.
        XCTAssertEqual(SchemaCoding.read(TagPairing.self, from: json(#"{"schema":1,"value":{"a":1}}"#)),
                       .unreadable)
        XCTAssertEqual(SchemaCoding.read(TagPairing.self, from: json("not json at all")),
                       .unreadable)
    }

    // MARK: - Migration: the flat list already on people's phones

    func testAFlatListOfUIDsBecomesTagsThatToggle() {
        let migrated = readThroughTheLadder(#"["04A2","0B11"]"#)
        XCTAssertEqual(migrated?.uids, ["04A2", "0B11"])
        XCTAssertNil(migrated?.modeID(for: "04A2"), "an upgraded tag keeps doing what it did")
        XCTAssertEqual(migrated?.resolve("04A2", knownModeIDs: [dinner]), .anyMode)
    }

    func testAnEmptyFlatListStaysEmptyAndStillMeansAnyTagWorks() {
        let migrated = readThroughTheLadder("[]")
        XCTAssertEqual(migrated, TagPairing())
        XCTAssertTrue(migrated!.isPaired("ANYTHING"))
    }

    func testAValueAlreadyInTheNewShapeIsNotMigratedTwice() {
        // The one that would break every sticker in the house at once: a
        // second pass over pairs would take the *description* of each
        // dictionary for a UID.
        var pairing = TagPairing()
        pairing.pair("KITCHEN", to: dinner)

        let stored = try! JSONSerialization.jsonObject(
            with: JSONEncoder().encode(pairing), options: [.fragmentsAllowed])
        let once = TagPairing.Migration.flatUIDListToNamedPairs(stored)
        let twice = TagPairing.Migration.flatUIDListToNamedPairs(once)

        let body = try! JSONSerialization.data(withJSONObject: twice, options: [.fragmentsAllowed])
        XCTAssertEqual(try? JSONDecoder().decode(TagPairing.self, from: body), pairing)
    }

    func testMigrationIsIdempotentAcrossRepeatedRuns() {
        // A ladder that gains a step later re-runs everything below it.
        let legacy = object(#"["04A2"]"#)
        var value = TagPairing.Migration.flatUIDListToNamedPairs(legacy)
        for _ in 0..<5 { value = TagPairing.Migration.flatUIDListToNamedPairs(value) }

        let body = try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        XCTAssertEqual(try? JSONDecoder().decode(TagPairing.self, from: body),
                       TagPairing(uids: ["04A2"]))
    }

    func testJunkIsHandedBackUnchangedRatherThanCrashingOrBeingSalvaged() {
        // Never `nil`: in the ladder that means "unreadable", and unreadable
        // means the caller falls back to its default — for Modes, the user's
        // Modes replaced by the starters.
        let junk: [Any] = [
            object(#"["04A2",7]"#),          // half strings
            object(#"[[1,2],[3]]"#),         // arrays of arrays
            object(#"{"schema":"nope"}"#),   // an object
            object("42"),                    // a bare number
            object(#""a bare string""#),
            object("true"),
        ]
        func serialised(_ value: Any) -> Data {
            try! JSONSerialization.data(withJSONObject: value,
                                        options: [.fragmentsAllowed, .sortedKeys])
        }
        for payload in junk {
            let out = TagPairing.Migration.flatUIDListToNamedPairs(payload)
            XCTAssertEqual(serialised(out), serialised(payload),
                           "unrecognised payloads are passed through untouched")
        }
    }

    // MARK: - Migration: every other key the ladder runs over

    func testAStoredModeIsNotTouchedByTheTagStep() {
        // The ladder does not know which key it is reading. A step that
        // rewrote every payload would rewrite the user's Modes.
        let mode = DadMode(name: "Dinner", symbol: "fork.knife",
                           blocked: BlockedSelection(payload: Data([1, 2]), appCount: 3))
        let stored = try! JSONSerialization.jsonObject(
            with: JSONEncoder().encode([mode]), options: [.fragmentsAllowed])

        let out = TagPairing.Migration.flatUIDListToNamedPairs(stored)
        let body = try! JSONSerialization.data(withJSONObject: out)
        XCTAssertEqual(try? JSONDecoder().decode([DadMode].self, from: body), [mode])
    }

    func testAHistoryOfSessionsIsNotTouchedByTheTagStep() {
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let sessions = [DadSession(modeID: dinner, modeName: "Dinner",
                                   startedAt: start, endedAt: start.addingTimeInterval(600))]
        let stored = try! JSONSerialization.jsonObject(
            with: JSONEncoder().encode(sessions), options: [.fragmentsAllowed])

        let out = TagPairing.Migration.flatUIDListToNamedPairs(stored)
        let body = try! JSONSerialization.data(withJSONObject: out)
        XCTAssertEqual(try? JSONDecoder().decode([DadSession].self, from: body), sessions)
    }

    func testTheEmergencyUseLogIsNotTouchedByTheTagStep() {
        // An array, like the tag list, but of numbers — which is exactly what
        // makes recognising the tag list by shape safe today.
        let uses = [Date(timeIntervalSince1970: 1_756_000_000)]
        let stored = try! JSONSerialization.jsonObject(
            with: JSONEncoder().encode(uses), options: [.fragmentsAllowed])

        let out = TagPairing.Migration.flatUIDListToNamedPairs(stored)
        let body = try! JSONSerialization.data(withJSONObject: out)
        XCTAssertEqual(try? JSONDecoder().decode([Date].self, from: body), uses)
    }

    // MARK: - The step's place on the ladder

    func testTheStepDeclaresTheVersionsItSpans() {
        // The integrator wires `case 1: value = …; version = 2` into
        // `SchemaCoding.migrate` and bumps `current` to 2. These constants are
        // what that hook must agree with. Deliberately not asserted against
        // `SchemaCoding.current` on the nose — a later shape change bumps it
        // again, and a test that has to be edited to let the ladder grow is a
        // test that gets edited without being read.
        XCTAssertEqual(TagPairing.Migration.namedPairs, TagPairing.Migration.flatUIDList + 1)
        XCTAssertGreaterThanOrEqual(SchemaCoding.current, TagPairing.Migration.flatUIDList,
                                    "this step migrates a version the ladder has reached")
    }
}
