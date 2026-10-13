import XCTest
@testable import DadCore

/// A tag naming more than one Mode.
///
/// One Mode and the tap starts it — no question. Several and the tap asks,
/// offering the tag's Modes and nothing else: the Work tag set to Deep Work or
/// Meetings should not offer Sleep.
final class TagManyModesTests: XCTestCase {

    // MARK: - Tapping

    func testATagNamingSeveralAsksBetweenThoseAndOnlyThose() {
        let h = Harness()
        let deepWork = h.addMode(name: "Deep Work")
        h.addMode(name: "Sleep")
        let meetings = h.addMode(name: "Meetings")
        h.engine.pair(tagUID: "WORK", to: [meetings.id, deepWork.id])

        XCTAssertEqual(h.engine.handleTap(tagUID: "WORK"),
                       .needsModeChoice(among: [meetings, deepWork]),
                       "in the tag's order, and Sleep is not offered")
        XCTAssertNil(h.store.activeSession, "and nothing started while asking")
    }

    func testTheAnswerStartsTheModeChosen() {
        let h = Harness()
        let deepWork = h.addMode(name: "Deep Work")
        let meetings = h.addMode(name: "Meetings")
        h.engine.pair(tagUID: "WORK", to: [deepWork.id, meetings.id])

        guard case .dadded(let started, _) =
                h.engine.handleTap(tagUID: "WORK", preferredMode: meetings) else {
            return XCTFail("expected the chosen Mode to start")
        }
        XCTAssertEqual(started.id, meetings.id)
    }

    func testATagNamingOneStartsItWithoutAsking() {
        // The point of the request: one Mode means no question, however many
        // other Modes the phone has.
        let h = Harness()
        let deepWork = h.addMode(name: "Deep Work")
        h.addMode(name: "Sleep")
        h.addMode(name: "Dinner")
        h.engine.pair(tagUID: "WORK", to: [deepWork.id])

        guard case .dadded(let started, _) = h.engine.handleTap(tagUID: "WORK") else {
            return XCTFail("one Mode should start without a choice")
        }
        XCTAssertEqual(started.id, deepWork.id)
    }

    func testDeletingAllButOneLeavesATagThatStartsTheOneLeft() {
        let h = Harness()
        let deepWork = h.addMode(name: "Deep Work")
        let meetings = h.addMode(name: "Meetings")
        h.addMode(name: "Sleep")
        h.engine.pair(tagUID: "WORK", to: [deepWork.id, meetings.id])
        h.engine.deleteMode(id: meetings.id)

        guard case .dadded(let started, _) = h.engine.handleTap(tagUID: "WORK") else {
            return XCTFail("the one left should start")
        }
        XCTAssertEqual(started.id, deepWork.id)
    }

    func testEmptyingAllButOneLeavesATagThatStartsTheOneLeft() {
        // "Which: Deep Work, or a Mode that takes nothing?" is not a question.
        let h = Harness()
        let deepWork = h.addMode(name: "Deep Work")
        let meetings = h.addMode(name: "Meetings", apps: 0)
        h.addMode(name: "Sleep")
        h.engine.pair(tagUID: "WORK", to: [deepWork.id, meetings.id])

        guard case .dadded(let started, _) = h.engine.handleTap(tagUID: "WORK") else {
            return XCTFail("the one that blocks anything should start")
        }
        XCTAssertEqual(started.id, deepWork.id)
    }

    func testDeletingEveryOneFallsBackToTheAppsChoice() {
        // The same promise a one-Mode tag makes: a sticker never goes dead.
        let h = Harness()
        let deepWork = h.addMode(name: "Deep Work")
        let meetings = h.addMode(name: "Meetings")
        let only = h.addMode(name: "Sleep")
        h.engine.pair(tagUID: "WORK", to: [deepWork.id, meetings.id])
        h.engine.deleteMode(id: deepWork.id)
        h.engine.deleteMode(id: meetings.id)

        XCTAssertEqual(h.store.tags.danglingUIDs(knownModeIDs: [only.id]), ["WORK"])
        guard case .dadded(let started, _) = h.engine.handleTap(tagUID: "WORK") else {
            return XCTFail("the tag must still work")
        }
        XCTAssertEqual(started.id, only.id)
    }

    func testOutsideAnyTagStillBringsThePhoneBackIn() {
        let h = Harness()
        let deepWork = h.addMode(name: "Deep Work")
        let meetings = h.addMode(name: "Meetings")
        h.engine.pair(tagUID: "WORK", to: [deepWork.id, meetings.id])
        h.engine.dad(with: deepWork)

        guard case .unDadded = h.engine.handleTap(tagUID: "WORK") else {
            return XCTFail("a several-Mode tag releases like any other")
        }
    }

    // MARK: - The list

    func testResolutionNarrowsToTheModesThatStillExist() {
        let a = UUID(), b = UUID(), c = UUID()
        var pairing = TagPairing()
        pairing.pair("T", to: [a, b, c])

        XCTAssertEqual(pairing.resolve("T", knownModeIDs: [a, b, c]), .oneOf([a, b, c]))
        XCTAssertEqual(pairing.resolve("T", knownModeIDs: [c, a]), .oneOf([a, c]))
        XCTAssertEqual(pairing.resolve("T", knownModeIDs: [b]), .mode(b))
        XCTAssertEqual(pairing.resolve("T", knownModeIDs: []), .anyMode)
        XCTAssertEqual(pairing.danglingUIDs(knownModeIDs: [b]), [],
                       "a tag with one Mode left has not fallen back")
    }

    func testTheSameModeTwiceIsOneMode() {
        let a = UUID(), b = UUID()
        var pairing = TagPairing()
        pairing.pair("T", to: [a, b, a])
        XCTAssertEqual(pairing.modeIDs(for: "T"), [a, b])

        pairing.pair("T", to: [a, a])
        XCTAssertEqual(pairing.resolve("T", knownModeIDs: [a, b]), .mode(a),
                       "a list of one Mode twice starts it rather than asking")
    }

    func testClearingTheListMakesATagAToggleAgain() {
        let a = UUID(), b = UUID()
        var pairing = TagPairing()
        pairing.pair("T", to: [a, b])
        pairing.pair("T", to: [UUID]())
        XCTAssertEqual(pairing.modeIDs(for: "T"), [])
        XCTAssertEqual(pairing.resolve("T", knownModeIDs: [a, b]), .anyMode)
    }

    // MARK: - Said out loud

    func testWhatATagStartsReadsAsAList() {
        XCTAssertNil(Vocab.tagStarts([]))
        XCTAssertEqual(Vocab.tagStarts(["Deep Work"]), "Deep Work")
        XCTAssertEqual(Vocab.tagStarts(["Deep Work", "Meetings"]), "Deep Work or Meetings")
        XCTAssertEqual(Vocab.tagStarts(["Deep Work", "Meetings", "Focus"]),
                       "Deep Work, Meetings or Focus")
    }

    // MARK: - On disk

    func testAOneModeTagIsStoredExactlyAsBefore() throws {
        // So the row is the one every earlier build wrote and reads.
        let a = UUID()
        var pairing = TagPairing()
        pairing.pair("T", to: [a])
        let rows = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pairing)) as? [[String: Any]]
        XCTAssertEqual(rows?.first?["modeID"] as? String, a.uuidString)
        XCTAssertNil(rows?.first?["moreModeIDs"], "no second key for a single Mode")
    }

    func testAnOlderBuildReadsASeveralModeTagAsItsFirst() throws {
        // What a build from before this change decodes a row into: the UID and
        // one optional Mode. It must land on a Mode the tag was set to start.
        struct OlderPair: Decodable { let uid: String; let modeID: UUID? }
        let a = UUID(), b = UUID()
        var pairing = TagPairing()
        pairing.pair("T", to: [a, b])

        let older = try JSONDecoder().decode([OlderPair].self, from: JSONEncoder().encode(pairing))
        XCTAssertEqual(older.first?.modeID, a)
    }

    func testSeveralModesSurviveARoundTrip() throws {
        let a = UUID(), b = UUID(), c = UUID()
        var pairing = TagPairing()
        pairing.pair("T", to: [a, b, c])
        pairing.rename("T", to: "Work")
        let back = try JSONDecoder().decode(TagPairing.self, from: JSONEncoder().encode(pairing))
        XCTAssertEqual(back, pairing)
        XCTAssertEqual(back.modeIDs(for: "T"), [a, b, c])
    }
}
