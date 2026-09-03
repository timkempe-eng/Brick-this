import XCTest
@testable import DadCore

/// The seam between two phones and the tag between them.
///
/// `HouseholdLedgerTests` covers the arithmetic against hand-built values.
/// These are the tests that would have caught the fan-out's characteristic
/// defect: two sides that are each right alone and disagree where they meet.
/// So they run **two whole engines**, with their own stores and their own
/// histories, and pass strings between them exactly as a tag would.
final class SharedStreakTests: XCTestCase {

    /// Gives `h` a session on each of the last `days` days, ending today.
    private func dadDaily(_ h: Harness, days: Int) {
        let mode = h.addMode()
        h.clock.advance(days: -days + 1)
        for _ in 0..<days {
            h.engine.dad(with: mode)
            h.clock.advance(60 * 60)
            h.engine.unDad(.tapped)
            h.clock.advance(23 * 60 * 60)
        }
        // Back to the moment the last session ended, so "today" is the last
        // day anything happened rather than the day after.
        h.clock.advance(-60 * 60)
    }

    // MARK: - What one phone knows

    func testAPhoneWithNoHistoryReportsNothing() {
        // Not a streak of zero. A member with no sessions written to the tag
        // would end the household's run on the day somebody installed the app.
        let h = Harness()
        XCTAssertNil(h.engine.myStanding)
        XCTAssertNil(h.engine.tagPayload())
        XCTAssertNil(h.engine.householdStreak)
    }

    func testAPhoneReportsItsOwnStreak() {
        let h = Harness()
        dadDaily(h, days: 4)

        XCTAssertEqual(h.engine.myStanding?.streak, 4)
        XCTAssertEqual(h.engine.myStanding?.member, h.engine.memberID())
    }

    func testThePhonesIdentityIsMintedOnceAndKept() {
        // A new id reads as a new person and resets the household to zero, so
        // this is the one value in the store that must never be regenerated.
        let h = Harness()
        let first = h.engine.memberID()
        XCTAssertEqual(h.engine.memberID(), first)
        XCTAssertEqual(h.store.memberID, first)
    }

    func testAskingWhoWeAreDoesNotInventAHousehold() {
        let h = Harness()
        dadDaily(h, days: 3)
        XCTAssertNil(h.engine.householdStreak,
                     "one phone's streak wearing a different hat is not a shared one")
    }

    func testThePayloadSaysWhatWeHaveRatherThanWhetherItIsNews() {
        // Whether a write is worth making needs the tag's current contents,
        // which only the NFC session has — so `tagPayload` answers the
        // narrower question and `TagScanner` makes the call by comparing.
        //
        // There used to be a guard here trying to skip a repeat solo write.
        // Both its branches returned the same value; a mutation replacing the
        // condition with `false` survived the whole suite, and its comment
        // described behaviour that had never existed.
        let h = Harness()
        dadDaily(h, days: 3)

        let first = h.engine.tagPayload()
        XCTAssertNotNil(first, "a solo phone still writes, or nobody can ever find it")

        // Store it back, which is exactly what a write-back does. The answer
        // does not change, and that is the point: it is not a diff.
        h.engine.absorb(tagPayload: first!)
        XCTAssertEqual(h.engine.tagPayload(), first)
    }

    // MARK: - Two phones and a tag

    /// The exchange, end to end: two engines that have never heard of each
    /// other agree on a number after passing one string each way.
    func testTwoPhonesAgreeAfterOneExchange() {
        let parent = Harness()
        let child = Harness()
        dadDaily(parent, days: 9)
        dadDaily(child, days: 4)

        // The parent taps the tag: nothing on it yet, so they leave their own
        // standing behind.
        guard let written = parent.engine.tagPayload() else {
            return XCTFail("the first phone must leave something to merge with")
        }

        // The child taps the same tag, reads it, and writes back both.
        XCTAssertTrue(child.engine.absorb(tagPayload: written))
        guard let returned = child.engine.tagPayload() else {
            return XCTFail("the second phone must write the household back")
        }

        // The parent taps again and picks the child up.
        XCTAssertTrue(parent.engine.absorb(tagPayload: returned))

        XCTAssertEqual(parent.engine.householdStreak?.days, 4,
                       "the shorter run is the household's")
        XCTAssertEqual(parent.engine.householdStreak?.days,
                       child.engine.householdStreak?.days,
                       "and the two phones must not disagree about it")
        XCTAssertEqual(parent.engine.householdStreak?.members, 2)
    }

    func testTheParentsOwnPhoneIsInTheNumber() {
        // The whole point of the feature: a parent who stops taking part stops
        // the household's streak, rather than watching the child's.
        let parent = Harness()
        let child = Harness()
        dadDaily(child, days: 6)
        // The parent has Dadded, but not for a fortnight.
        let mode = parent.addMode()
        parent.clock.advance(days: -14)
        parent.engine.dad(with: mode)
        parent.clock.advance(60 * 60)
        parent.engine.unDad(.tapped)
        parent.clock.advance(days: 14)

        child.engine.absorb(tagPayload: parent.engine.tagPayload()!)

        let streak = child.engine.householdStreak
        XCTAssertEqual(streak?.days, 0)
        XCTAssertEqual(streak?.isCurrent, false, "and it is not reported as live")
    }

    func testAThirdPhoneJoinsWithNothingConfigured() {
        let parent = Harness(), child = Harness(), sibling = Harness()
        for (h, days) in [(parent, 8), (child, 5), (sibling, 3)] {
            dadDaily(h, days: days)
        }

        var tag = parent.engine.tagPayload()!
        child.engine.absorb(tagPayload: tag)
        tag = child.engine.tagPayload()!
        sibling.engine.absorb(tagPayload: tag)
        tag = sibling.engine.tagPayload()!
        parent.engine.absorb(tagPayload: tag)

        XCTAssertEqual(parent.engine.householdStreak?.members, 3)
        XCTAssertEqual(parent.engine.householdStreak?.days, 3,
                       "the newest member's run is the shortest, so it is the household's")
    }

    func testTwoPhonesInAgreementProduceTheSameBytes() {
        // The only thing standing between this feature and a tag write on
        // every single tap is `TagScanner` asking "is what I would write
        // different from what I just read?". `setting` puts the writer at the
        // front of its own ledger — which it must, or the cap drops the phone
        // from its own tag — so without a canonical order on the wire, two
        // phones holding identical facts encode differently, the check never
        // says no, and the tag is rewritten on every alternating tap forever.
        let parent = Harness(), child = Harness()
        dadDaily(parent, days: 5)
        dadDaily(child, days: 5)

        var tag = parent.engine.tagPayload()!
        child.engine.absorb(tagPayload: tag)
        tag = child.engine.tagPayload()!
        parent.engine.absorb(tagPayload: tag)

        XCTAssertEqual(parent.engine.tagPayload(), tag,
                       "the parent has nothing new to say, and must be able to tell")
        XCTAssertEqual(child.engine.tagPayload(), parent.engine.tagPayload(),
                       "two phones that agree must write the same bytes")
    }

    // MARK: - What the tag must never do

    func testAPayloadThisBuildCannotReadChangesNothing() {
        // Never half-applied. The write-back would otherwise overwrite the
        // other phone's real data with our guess at it, on the one copy that
        // is shared.
        let h = Harness()
        dadDaily(h, days: 3)
        h.engine.absorb(tagPayload: "d1;e5f6a7b8,20260903,4")
        let before = h.store.ledger

        XCTAssertFalse(h.engine.absorb(tagPayload: "d9;whatever"))
        XCTAssertFalse(h.engine.absorb(tagPayload: "not a ledger at all"))
        XCTAssertEqual(h.store.ledger, before)
    }

    func testAnExchangeThatChangesNothingSaysSo() {
        // So a caller can skip the write, which costs a write cycle and a
        // second of somebody holding a phone against a sticker.
        let h = Harness()
        dadDaily(h, days: 3)
        let payload = "d1;e5f6a7b8,20260903,4"

        XCTAssertTrue(h.engine.absorb(tagPayload: payload))
        XCTAssertFalse(h.engine.absorb(tagPayload: payload), "the second read is news to nobody")
    }

    func testTheTagCannotHandBackAStreakYouJustBroke() {
        // The defect this seam invites: the tag holds a nine-day run from
        // last week, this phone knows the run ended, and a merge that treated
        // both as equal would restore it. `setting` exists for exactly this.
        let h = Harness()
        dadDaily(h, days: 2)
        let mine = h.engine.memberID()

        h.engine.absorb(tagPayload: "d1;\(mine.value),20260101,900")

        XCTAssertEqual(h.engine.ledgerToWrite.standing(for: mine)?.streak, 2,
                       "our own history is the authority on our own streak")
        XCTAssertEqual(h.engine.myStanding?.streak, 2)
    }

    func testWhatGoesOnTheTagIsStillOpaque() {
        // The privacy property, asserted where the payload is actually
        // produced rather than only where it is formatted. A Mode's name, an
        // app count and a session time all pass through this engine, and none
        // of them may reach a sticker anyone can read.
        let h = Harness()
        h.addMode(name: "Bedtime for the twins")
        dadDaily(h, days: 2)
        h.engine.absorb(tagPayload: "d1;e5f6a7b8,20260903,4")

        let payload = h.engine.tagPayload() ?? ""
        let permitted = Set("0123456789abcdef,;d")
        XCTAssertFalse(payload.isEmpty)
        XCTAssertTrue(payload.allSatisfy { permitted.contains($0) }, payload)
        XCTAssertFalse(payload.contains("Bedtime"))
    }
}
