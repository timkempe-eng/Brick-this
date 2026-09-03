import XCTest
@testable import DadCore

/// Who may do what to the reward ledger.
///
/// `RewardLedgerTests` covers the arithmetic and the rules of the ledger
/// itself. This covers the part the engine adds: three of the five acts belong
/// to a grown-up, and on a young person's phone the proof that one is here is
/// the same proof the grant flow already uses — a tap of the paired tag they
/// are holding. No account, no server, no PIN.
///
/// The asymmetry is deliberate and is what the first two tests pin. Claiming
/// needs nobody's permission, because the balance *is* the permission and it
/// was earned. Settling does, because settling is somebody promising a lift
/// actually happened.
final class RewardWiringTests: XCTestCase {

    private let lift = RewardLedger.Reward(name: "A lift into town", price: RewardLedger.Days(2))

    /// A young person's phone with a paired tag and `days` earned.
    private func youngPerson(earning days: Int = 5) -> Harness {
        let h = Harness()
        h.store.household = Household(role: .youngPerson, autonomyLevel: 0)
        h.engine.pair(tagUID: "PARENT")
        let mode = h.addMode()
        h.clock.advance(days: -days)
        for _ in 0..<days {
            h.engine.dad(with: mode)
            h.clock.advance(60 * 60)
            h.engine.unDad(.tapped)
            h.clock.advance(23 * 60 * 60)
        }
        return h
    }

    // MARK: - Whose act is whose

    func testAnOfferNeedsAGrownUpInTheRoom() {
        let h = youngPerson()

        XCTAssertFalse(h.engine.offer(lift), "nobody proved they may offer anything")
        XCTAssertFalse(h.engine.offer(lift, byTagUID: "SOMEONEELSE"))
        XCTAssertTrue(h.store.rewards.isEmpty)

        XCTAssertTrue(h.engine.offer(lift, byTagUID: "PARENT"))
        XCTAssertEqual(h.store.rewards.count, 1)
    }

    func testClaimingNeedsNobody() {
        // The balance is the permission, and it was earned. Requiring a
        // grown-up to be present for the claim as well would make the whole
        // ledger a second thing to ask for.
        let h = youngPerson(earning: 5)
        h.engine.offer(lift, byTagUID: "PARENT")

        XCTAssertTrue(h.engine.claim(h.store.rewards[0]))
        XCTAssertEqual(h.engine.rewardLedger.pending.count, 1)
        XCTAssertEqual(h.engine.rewardLedger.balance, RewardLedger.Days(3))
    }

    func testSettlingNeedsAGrownUpInTheRoom() {
        // Settling says a thing happened in the world. It is also the one act
        // that cannot be undone, so it is the one that most needs the person
        // who did it to be here.
        let h = youngPerson()
        h.engine.offer(lift, byTagUID: "PARENT")
        h.engine.claim(h.store.rewards[0])
        let claim = h.engine.rewardLedger.pending[0]

        XCTAssertFalse(h.engine.settle(claim: claim.id))
        XCTAssertTrue(h.engine.rewardLedger.settled.isEmpty)

        XCTAssertTrue(h.engine.settle(claim: claim.id, byTagUID: "PARENT"))
        XCTAssertEqual(h.engine.rewardLedger.settled.count, 1)
    }

    func testAYoungPersonMayTakeTheirOwnClaimBack() {
        // Their own unsettled claim, so it costs nobody anything and needs
        // nobody. A settled one is permanent; the ledger refuses that itself.
        let h = youngPerson()
        h.engine.offer(lift, byTagUID: "PARENT")
        h.engine.claim(h.store.rewards[0])
        let claim = h.engine.rewardLedger.pending[0]

        XCTAssertTrue(h.engine.withdraw(claim: claim.id))
        XCTAssertEqual(h.engine.rewardLedger.balance, RewardLedger.Days(5), "the days come back")

        h.engine.claim(h.store.rewards[0])
        let second = h.engine.rewardLedger.pending[0]
        h.engine.settle(claim: second.id, byTagUID: "PARENT")
        XCTAssertFalse(h.engine.withdraw(claim: second.id), "the lift was given; that stands")
    }

    // MARK: - A phone that is its owner's

    func testAnAdultOnTheirOwnPhoneNeedsNoTag() {
        // The question does not arise: they are the grown-up, and they are the
        // one holding the tag. Requiring a tap here would be ceremony for its
        // own sake.
        let h = Harness()
        XCTAssertEqual(h.store.household.role, .grownUp, "the default this rests on")

        XCTAssertTrue(h.engine.offer(lift))
        XCTAssertTrue(h.engine.retire(rewardID: h.store.rewards[0].id))
    }

    // MARK: - The days themselves

    func testTheDaysComeFromTheHistoryAndNowhereElse() {
        // No stored balance. A stored one is a number somebody could edit, and
        // this one decides what a young person is owed.
        let h = youngPerson(earning: 4)
        XCTAssertEqual(h.engine.rewardLedger.earned, RewardLedger.Days(4))

        h.store.history = []
        XCTAssertEqual(h.engine.rewardLedger.earned, RewardLedger.Days(0))
    }

    // MARK: - What must never be dropped

    func testTheClaimHistoryIsNeverTruncated() {
        // It used to be, at `grantHistoryLimit` — a constant named and
        // documented for a different list. Nothing tested the bound, a
        // mutation lowering it to three survived the whole suite, and the
        // consequence was not a lost row: `spent` is derived by summing this
        // list, so the hundred-and-first claim refunded a day nobody gave back
        // and erased a lift that had actually been given.
        //
        // Truncation is a memory strategy. It cannot also be an accounting
        // one, and this is the list where the two collide.
        let h = youngPerson(earning: 400)
        h.engine.offer(RewardLedger.Reward(name: "A biscuit", price: RewardLedger.Days(1)),
                       byTagUID: "PARENT")
        let biscuit = h.store.rewards[0]

        for _ in 0..<150 {
            XCTAssertTrue(h.engine.claim(biscuit))
            h.engine.settle(claim: h.engine.rewardLedger.pending[0].id, byTagUID: "PARENT")
        }

        XCTAssertEqual(h.store.redemptions.count, 150)
        XCTAssertEqual(h.engine.rewardLedger.spent, RewardLedger.Days(150),
                       "every claim spends, and nothing hands a day back on its own")
        XCTAssertEqual(h.engine.rewardLedger.settled.count, 150,
                       "a lift that was given stays given")
        XCTAssertEqual(h.engine.rewardLedger.balance, RewardLedger.Days(250))
    }

    func testAClaimYouCannotAffordIsRefused() {
        let h = youngPerson(earning: 1)
        let expensive = RewardLedger.Reward(name: "A weekend away", price: RewardLedger.Days(30))
        h.engine.offer(expensive, byTagUID: "PARENT")

        XCTAssertFalse(h.engine.claim(h.store.rewards[0]))
        XCTAssertEqual(h.engine.rewardLedger.shortfall(for: h.store.rewards[0]),
                       RewardLedger.Days(29))
    }

    func testARetiredRewardIsStillReadableButNoLongerOnOffer() {
        // A grown-up withdrawing an offer must not erase the record of the
        // times it was already honoured.
        let h = youngPerson()
        h.engine.offer(lift, byTagUID: "PARENT")
        h.engine.claim(h.store.rewards[0])
        h.engine.retire(rewardID: h.store.rewards[0].id, byTagUID: "PARENT")

        XCTAssertTrue(h.engine.rewardLedger.available.isEmpty)
        XCTAssertEqual(h.engine.rewardLedger.pending.count, 1, "the promise still stands")
        XCTAssertEqual(h.store.rewards.count, 1, "and the reward itself is still there to read")
    }
}
