import XCTest
@testable import DadCore

/// The ledger's decisions, not its plumbing.
///
/// Three clusters get most of the attention, because each is a decision
/// somebody could reverse without noticing they had:
///
/// * **The forbidden currency.** Two of these tests read the source of
///   `RewardLedger.swift` and fail on the vocabulary of screen time. A comment
///   saying "never denominate a reward in minutes" is a comment; a red build
///   is a constraint. `preflight.py` already grep-checks Core for iOS imports
///   for the same reason.
/// * **Which days earn.** A schedule that opens and closes a window while the
///   phone sits on a table must earn nothing. `AutonomyLadder` got this wrong
///   and sixty-one untouched nights climbed the whole ladder.
/// * **Where the balance can go.** It cannot go below zero, a claim cannot
///   overdraw it, and a claim already honoured cannot be reversed.
final class RewardLedgerTests: XCTestCase {

    /// Pinned to UTC so a machine in another time zone doesn't shift day
    /// boundaries under the tests.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_756_000_000) // 2025-08-24 01:46 UTC

    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
    }

    /// A finished session on the day `daysAgo`.
    ///
    /// Placed in the small hours, and `minuteOfDay` rather than an hour, so
    /// that several sessions can share a day and all of them still land before
    /// `now` — which is itself just before two in the morning. A session dated
    /// after `now` is excluded by the ledger on purpose, and it would be an
    /// unwelcome surprise inside a test that is about something else.
    private func session(daysAgo: Int,
                         minuteOfDay: Double = 10,
                         minutes: Double = 5,
                         emergency: Bool = false,
                         bySchedule: Bool? = nil) -> DadSession {
        let start = day(daysAgo).addingTimeInterval(minuteOfDay * 60)
        return DadSession(modeID: UUID(),
                          modeName: "Sleep",
                          startedAt: start,
                          endedAt: start.addingTimeInterval(minutes * 60),
                          endedByEmergency: emergency,
                          startedBySchedule: bySchedule)
    }

    /// A ledger over `earningDays` distinct qualifying days, so a test that is
    /// about prices does not have to spell out a history.
    private func ledger(earningDays: Int = 0,
                        rewards: [RewardLedger.Reward] = [],
                        redemptions: [RewardLedger.Redemption] = [],
                        sessions: [DadSession]? = nil,
                        at moment: Date? = nil) -> RewardLedger {
        RewardLedger(rewards: rewards,
                     redemptions: redemptions,
                     sessions: sessions ?? (0..<earningDays).map { session(daysAgo: $0) },
                     now: moment ?? now,
                     calendar: calendar)
    }

    private func reward(_ name: String, _ price: Int, retired: Bool? = nil) -> RewardLedger.Reward {
        RewardLedger.Reward(name: name, price: RewardLedger.Days(price), isRetired: retired)
    }

    private func days(_ n: Int) -> RewardLedger.Days { RewardLedger.Days(n) }

    // MARK: - The unit

    func testADayCountIsNeverNegative() {
        // Not a debt. A negative count is a bug, a corrupt file or somebody
        // editing JSON, and zero is the only safe reading of all three.
        XCTAssertEqual(days(-4), days(0))
        XCTAssertEqual(days(-4).count, 0)
    }

    func testSubtractionSaturatesRatherThanGoingNegative() {
        // The structural answer to "what if the balance would go negative":
        // the type has no value for it.
        XCTAssertEqual(days(2) - days(5), days(0))
        XCTAssertEqual(days(5) - days(2), days(3))
        XCTAssertEqual(days(2) + days(3), days(5))
    }

    func testDaysAreOrderedByCount() {
        XCTAssertTrue(days(1) < days(2))
        XCTAssertFalse(days(2) < days(2))
        XCTAssertTrue(days(0).isZero)
    }

    func testDaysReadAndWriteAsABareNumber() throws {
        // Stored JSON should read `"price": 5`, not `{"count": 5}` — the
        // wrapper is a compile-time defence, not a storage format anybody has
        // to migrate around.
        let encoded = try JSONEncoder().encode(reward("Cinema", 5))
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(text.contains("\"price\":5"), text)

        let round = try JSONDecoder().decode(RewardLedger.Reward.self, from: encoded)
        XCTAssertEqual(round.price, days(5))
    }

    func testANegativeStoredPriceDecodesAsZeroRatherThanMintingDays() throws {
        let json = Data(#"{"id":"\#(UUID().uuidString)","name":"Edited","price":-5}"#.utf8)
        let decoded = try JSONDecoder().decode(RewardLedger.Reward.self, from: json)
        XCTAssertEqual(decoded.price, days(0))
    }

    func testDayCountsDescribeThemselvesInWholeDays() {
        XCTAssertEqual(days(1).description, "1 day")
        XCTAssertEqual(days(3).description, "3 days")
        XCTAssertEqual(days(0).description, "0 days")
    }

    // MARK: - Which days earn

    func testAnEmptyLedgerIsAllZeroAndOffersNothing() {
        let l = ledger()
        XCTAssertEqual(l.earned, days(0))
        XCTAssertEqual(l.spent, days(0))
        XCTAssertEqual(l.balance, days(0))
        XCTAssertFalse(l.isOverdrawn)
        XCTAssertTrue(l.available.isEmpty)
        XCTAssertNil(l.nearestOutOfReach)
        XCTAssertNil(l.daysUntilNearestOutOfReach)
    }

    func testADayEarnsOnceHoweverManySessionsAreInIt() {
        // Three sessions, one day, one day earned. Otherwise the unit is not a
        // day at all and the price of a reward means nothing.
        let l = ledger(sessions: [session(daysAgo: 0, minuteOfDay: 10),
                                  session(daysAgo: 0, minuteOfDay: 30),
                                  session(daysAgo: 0, minuteOfDay: 50)])
        XCTAssertEqual(l.earned, days(1))
    }

    func testEachSeparateDayEarns() {
        XCTAssertEqual(ledger(earningDays: 4).earned, days(4))
    }

    func testASessionEndedOnTheEmergencyButtonEarnsNothing() {
        let l = ledger(sessions: [session(daysAgo: 0, emergency: true)])
        XCTAssertEqual(l.earned, days(0))
    }

    func testADayWithBothABailAndAFinishAtTheTagStillEarns() {
        // The day contains the evidence. Counting the bail against it would
        // let one override cancel a day already earned that morning.
        let l = ledger(sessions: [session(daysAgo: 0, minuteOfDay: 10, emergency: true),
                                  session(daysAgo: 0, minuteOfDay: 30)])
        XCTAssertEqual(l.earned, days(1))
    }

    func testASessionAScheduleOpenedAndClosedEarnsNothing() {
        // The ladder's most expensive defect, and it costs more here: a nightly
        // Sleep window would mint a day a night with nobody choosing anything,
        // and at the end of it somebody has to actually provide a reward.
        let l = ledger(sessions: [session(daysAgo: 0, bySchedule: true),
                                  session(daysAgo: 1, bySchedule: true),
                                  session(daysAgo: 2, bySchedule: true)])
        XCTAssertEqual(l.earned, days(0))
        XCTAssertFalse(session(daysAgo: 0, bySchedule: true).wasEndedByAPerson)
    }

    func testASessionStartedByHandEarnsAndOneWithNoMarkerDoesToo() {
        // `startedBySchedule` is Optional and nil on every session recorded
        // before schedules existed. Those were all started at the tag, so nil
        // has to read as "by hand" or the ledger silently loses old days.
        XCTAssertTrue(session(daysAgo: 0, bySchedule: nil).wasEndedByAPerson)
        XCTAssertTrue(session(daysAgo: 0, bySchedule: false).wasEndedByAPerson)
        let l = ledger(sessions: [session(daysAgo: 0, bySchedule: nil),
                                  session(daysAgo: 1, bySchedule: false)])
        XCTAssertEqual(l.earned, days(2))
    }

    func testAScheduledSessionEndedOnTheButtonStillEarnsNothing() {
        // Somebody was there, but they bailed. Both conditions are required.
        let l = ledger(sessions: [session(daysAgo: 0, emergency: true, bySchedule: true)])
        XCTAssertEqual(l.earned, days(0))
    }

    func testAnUnfinishedSessionEarnsNothingUntilItEnds() {
        // No outcome yet. Counting it would let a day appear mid-session and
        // vanish when the session ended on the button — after a reward had been
        // claimed with it.
        let running = DadSession(modeID: UUID(), modeName: "Deep Work",
                                 startedAt: now.addingTimeInterval(-600), endedAt: nil)
        XCTAssertEqual(ledger(sessions: [running]).earned, days(0))
    }

    func testASessionDatedInTheFutureEarnsNothing() {
        // A clock that moved backwards, or a restored backup. On the ladder the
        // worst case is a rung arriving early; here it buys something a person
        // then has to hand over.
        let ahead = session(daysAgo: -3)
        XCTAssertEqual(ledger(sessions: [ahead]).earned, days(0))
        XCTAssertEqual(ledger(sessions: [ahead], at: now.addingTimeInterval(5 * 86_400)).earned,
                       days(1))
    }

    func testASessionRunningPastMidnightCountsTowardTheDayItStarted() {
        let start = day(1).addingTimeInterval(22 * 3600)
        let overnight = DadSession(modeID: UUID(), modeName: "Sleep",
                                   startedAt: start,
                                   endedAt: start.addingTimeInterval(3 * 3600))
        // Yesterday evening plus this morning is two sessions but one earning
        // day if they were the same evening — here they are distinct days only
        // because a second session genuinely started today.
        let l = ledger(sessions: [overnight, session(daysAgo: 1)])
        XCTAssertEqual(l.earned, days(1))
    }

    func testEarnedDaysDoNotDecayAfterALongGap() {
        // A rung can be withheld after a fortnight away, because a rung
        // describes the present. A day that happened is not revisable.
        let l = ledger(sessions: [session(daysAgo: 200), session(daysAgo: 201)])
        XCTAssertEqual(l.earned, days(2))
    }

    // MARK: - The balance

    func testBalanceIsEarnedMinusEverythingClaimed() {
        let cinema = reward("Cinema", 4)
        let l = ledger(earningDays: 10, rewards: [cinema],
                       redemptions: [claim(cinema), claim(cinema)])
        XCTAssertEqual(l.earned, days(10))
        XCTAssertEqual(l.spent, days(8))
        XCTAssertEqual(l.balance, days(2))
    }

    func testAClaimStillWaitingToBeSettledSpendsJustTheSame() {
        // Claiming spends, not settling. If the balance only fell when a
        // grown-up confirmed, five claims could be made against the same five
        // days and somebody would have to say no to four of them afterwards.
        let lift = reward("Lift into town", 3)
        let pending = claim(lift)
        let honoured = claim(lift, settledAt: now)
        XCTAssertEqual(ledger(earningDays: 6, redemptions: [pending]).balance, days(3))
        XCTAssertEqual(ledger(earningDays: 6, redemptions: [honoured]).balance, days(3))
    }

    func testTheBalanceStopsAtZeroWhenTheHistoryShrinksUnderAClaim() {
        // The stored history is finite: a household that Dads several times a
        // day will eventually lose its oldest days off the end. Nothing is
        // clawed back — the lift was given — and the shortfall is reported
        // positively rather than as a negative balance.
        let l = ledger(earningDays: 1, redemptions: [claim(reward("Cinema", 4))])
        XCTAssertEqual(l.balance, days(0))
        XCTAssertEqual(l.spentBeyondEarned, days(3))
        XCTAssertTrue(l.isOverdrawn)
    }

    func testACoveredLedgerIsNotOverdrawn() {
        let l = ledger(earningDays: 4, redemptions: [claim(reward("Cinema", 4))])
        XCTAssertEqual(l.balance, days(0))
        XCTAssertEqual(l.spentBeyondEarned, days(0))
        XCTAssertFalse(l.isOverdrawn)
    }

    // MARK: - What can I have

    func testAvailableIsCheapestFirstWithTiesBrokenByName() {
        // Stable ordering, so the list does not rearrange itself between two
        // renders of the same data.
        let l = ledger(rewards: [reward("Zoo", 6), reward("Cinema", 2),
                                 reward("Books", 2), reward("Curfew", 4)])
        XCTAssertEqual(l.available.map(\.name), ["Books", "Cinema", "Curfew", "Zoo"])
    }

    func testARetiredRewardIsNoLongerOffered() {
        let l = ledger(rewards: [reward("Cinema", 2), reward("Old deal", 1, retired: true)])
        XCTAssertEqual(l.available.map(\.name), ["Cinema"])
    }

    func testAffordableAndOutOfReachPartitionWhatIsOnOffer() {
        let l = ledger(earningDays: 3,
                       rewards: [reward("Books", 1), reward("Cinema", 3), reward("Zoo", 8)])
        XCTAssertEqual(l.affordable.map(\.name), ["Books", "Cinema"])
        XCTAssertEqual(l.outOfReach.map(\.name), ["Zoo"])
    }

    func testARewardCostingExactlyTheBalanceIsAffordable() {
        // The boundary somebody will get wrong with a `<`.
        let cinema = reward("Cinema", 3)
        XCTAssertTrue(ledger(earningDays: 3, rewards: [cinema]).canAfford(cinema))
        XCTAssertFalse(ledger(earningDays: 2, rewards: [cinema]).canAfford(cinema))
    }

    func testTheNearestThingOutOfReachIsTheCheapestOneAndSaysHowFar() {
        let l = ledger(earningDays: 2,
                       rewards: [reward("Books", 1), reward("Zoo", 8), reward("Cinema", 5)])
        XCTAssertEqual(l.nearestOutOfReach?.name, "Cinema")
        XCTAssertEqual(l.daysUntilNearestOutOfReach, days(3))
    }

    func testShortfallIsZeroForSomethingAlreadyAffordable() {
        let l = ledger(earningDays: 9, rewards: [reward("Books", 1)])
        XCTAssertEqual(l.shortfall(for: reward("Books", 1)), days(0))
        XCTAssertNil(l.nearestOutOfReach)
        XCTAssertNil(l.daysUntilNearestOutOfReach)
    }

    func testARetiredRewardIsNeitherAffordableNorOutOfReach() {
        let l = ledger(earningDays: 1, rewards: [reward("Old deal", 9, retired: true)])
        XCTAssertTrue(l.affordable.isEmpty)
        XCTAssertTrue(l.outOfReach.isEmpty)
        XCTAssertNil(l.nearestOutOfReach)
    }

    // MARK: - Claiming

    func testClaimingRecordsTheNamePriceAndTimeAndLeavesItUnsettled() throws {
        let cinema = reward("Cinema", 3)
        let l = ledger(earningDays: 5, rewards: [cinema])
        let after = try XCTUnwrap(l.claiming(cinema))
        XCTAssertEqual(after.count, 1)
        let claim = try XCTUnwrap(after.first)
        XCTAssertEqual(claim.rewardID, cinema.id)
        XCTAssertEqual(claim.rewardName, "Cinema")
        XCTAssertEqual(claim.price, days(3))
        XCTAssertEqual(claim.claimedAt, now)
        XCTAssertFalse(claim.isSettled)
    }

    func testClaimingRefusesWhatTheBalanceDoesNotCover() {
        // Refused outright rather than part-paid: a claim that leaves a debt
        // behind is the credit model this ledger does not have.
        let zoo = reward("Zoo", 8)
        XCTAssertNil(ledger(earningDays: 7, rewards: [zoo]).claiming(zoo))
    }

    func testClaimingARetiredRewardIsRefusedEvenWithDaysToSpare() {
        let old = reward("Old deal", 1, retired: true)
        XCTAssertNil(ledger(earningDays: 30, rewards: [old]).claiming(old))
    }

    func testTheSameRewardCanBeClaimedTwiceWhenTheBalanceCoversBoth() throws {
        // Two lifts into town is two claims. A rule against it would be Dad
        // having an opinion about a household's arrangements.
        let lift = reward("Lift into town", 3)
        let once = try XCTUnwrap(ledger(earningDays: 6, rewards: [lift]).claiming(lift))
        let twice = ledger(earningDays: 6, rewards: [lift], redemptions: once).claiming(lift)
        XCTAssertEqual(twice?.count, 2)
    }

    func testASecondClaimIsRefusedWhenOnlyOneIsCovered() throws {
        let lift = reward("Lift into town", 3)
        let once = try XCTUnwrap(ledger(earningDays: 5, rewards: [lift]).claiming(lift))
        XCTAssertNil(ledger(earningDays: 5, rewards: [lift], redemptions: once).claiming(lift))
    }

    func testAClaimKeepsThePriceItWasMadeAtWhenTheRewardIsRepriced() throws {
        // Re-pricing must not reach backwards. Otherwise a grown-up editing a
        // number would overdraw a balance that was correct when it was spent,
        // and days would disappear with nothing to point at.
        let lift = reward("Lift into town", 3)
        let claimed = try XCTUnwrap(ledger(earningDays: 5, rewards: [lift]).claiming(lift))

        var dearer = lift
        dearer.price = days(5)
        let l = ledger(earningDays: 5, rewards: [dearer], redemptions: claimed)
        XCTAssertEqual(l.spent, days(3))
        XCTAssertEqual(l.balance, days(2))
    }

    func testAClaimKeepsTheNameSoADeletedRewardStillReads() throws {
        let cinema = reward("Cinema", 2)
        let claimed = try XCTUnwrap(ledger(earningDays: 5, rewards: [cinema]).claiming(cinema))
        // The grown-up removes the reward entirely.
        let l = ledger(earningDays: 5, rewards: [], redemptions: claimed)
        XCTAssertEqual(l.pending.first?.rewardName, "Cinema")
        XCTAssertEqual(l.spent, days(2))
    }

    // MARK: - Settling and withdrawing

    func testSettlingStampsOnlyTheClaimNamed() throws {
        let a = claim(reward("Cinema", 2))
        let b = claim(reward("Zoo", 3))
        let l = ledger(earningDays: 9, redemptions: [a, b])
        let after = try XCTUnwrap(l.settling(claim: a.id, at: now))
        XCTAssertEqual(after.first(where: { $0.id == a.id })?.settledAt, now)
        XCTAssertNil(after.first(where: { $0.id == b.id })?.settledAt)
    }

    func testSettlingTheSameClaimTwiceIsRefused() {
        // Two hand-overs recorded for one lift. What a household actually did
        // for each other is the only thing here that cannot be recomputed.
        let a = claim(reward("Cinema", 2), settledAt: now)
        XCTAssertNil(ledger(earningDays: 9, redemptions: [a]).settling(claim: a.id, at: now))
    }

    func testSettlingAClaimThatIsNotThereIsRefused() {
        XCTAssertNil(ledger(earningDays: 9).settling(claim: UUID(), at: now))
    }

    func testWithdrawingAPendingClaimGivesTheDaysBack() throws {
        let a = claim(reward("Cinema", 2))
        let l = ledger(earningDays: 5, redemptions: [a])
        XCTAssertEqual(l.balance, days(3))
        let after = try XCTUnwrap(l.withdrawing(claim: a.id))
        XCTAssertTrue(after.isEmpty)
        XCTAssertEqual(ledger(earningDays: 5, redemptions: after).balance, days(5))
    }

    func testWithdrawingASettledClaimIsRefused() {
        // The lift was given. No state in an app makes that not so — and a
        // deletable settled claim would make the balance editable by whoever
        // is holding the phone.
        let a = claim(reward("Cinema", 2), settledAt: now)
        XCTAssertNil(ledger(earningDays: 5, redemptions: [a]).withdrawing(claim: a.id))
    }

    func testWithdrawingAClaimThatIsNotThereIsRefused() {
        XCTAssertNil(ledger(earningDays: 5).withdrawing(claim: UUID()))
    }

    func testPendingIsOldestFirstAndSettledIsMostRecentFirst() {
        let old = claim(reward("Books", 1), at: day(9))
        let recent = claim(reward("Cinema", 1), at: day(2))
        let doneOld = claim(reward("Zoo", 1), at: day(8), settledAt: day(7))
        let doneNew = claim(reward("Curfew", 1), at: day(3), settledAt: day(3))
        let l = ledger(earningDays: 20, redemptions: [recent, doneOld, old, doneNew])
        XCTAssertEqual(l.pending.map(\.rewardName), ["Books", "Cinema"])
        XCTAssertEqual(l.settled.map(\.rewardName), ["Curfew", "Zoo"])
    }

    // MARK: - Stored shapes
    //
    // Everything is persisted as JSON and read back through `LenientDecoding`,
    // which drops any element that fails to decode. That makes an added
    // non-Optional key a data-loss bug rather than a compile error, so both
    // halves of the rule get a test.

    func testARewardStoredBeforeRetirementExistedStillDecodes() {
        let json = Data(#"[{"id":"\#(UUID().uuidString)","name":"Cinema","price":4}]"#.utf8)
        let decoded = LenientDecoding.array(RewardLedger.Reward.self, from: json)
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertNil(decoded?.first?.isRetired)
        XCTAssertEqual(decoded?.first?.canBeClaimed, true)
    }

    func testAClaimStoredWithNoSettlementStillDecodes() {
        let json = Data("""
        [{"id":"\(UUID().uuidString)","rewardID":"\(UUID().uuidString)",\
        "rewardName":"Cinema","price":4,"claimedAt":0}]
        """.utf8)
        let decoded = LenientDecoding.array(RewardLedger.Redemption.self, from: json)
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.first?.isSettled, false)
    }

    func testARewardMissingARequiredKeyIsDroppedEntirely() {
        // The reason `isRetired` is Optional. A non-Optional key added later
        // makes every previously stored reward look like this one.
        let json = Data(#"[{"id":"\#(UUID().uuidString)","name":"Cinema"}]"#.utf8)
        XCTAssertEqual(LenientDecoding.array(RewardLedger.Reward.self, from: json)?.count, 0)
    }

    // MARK: - The forbidden currency, enforced against the source
    //
    // These two read `RewardLedger.swift` and assert things about the code in
    // it. That is unusual for a unit test and deliberate: the rule they defend
    // is one a well-meaning change would break silently, and there is no value
    // to assert about a type that does not have a member. A comment cannot
    // fail a build; this can.

    /// Comments stripped, so the prose above may discuss minutes freely while
    /// the code may not mention them at all.
    private func ledgerSourceCode() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DadCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let source = root.appendingPathComponent("Dad/Shared/Core/RewardLedger.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "RewardLedger.swift not found at \(source.path) — this guard is not running")
        let text = try String(contentsOf: source, encoding: .utf8)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[line.startIndex..<comment.lowerBound]
            }
            .joined(separator: "\n")
    }

    func testTheLedgerSourceNamesNoUnitOfTime() throws {
        // A reward denominated in screen time is the one thing this feature
        // must not become, and every route there passes through this list:
        // a duration type, a fractional number to scale one with, the
        // arithmetic that turns days into minutes, or the two members of
        // `DadMode` that a duration could be poured into.
        let code = try ledgerSourceCode()
        for forbidden in ["TimeInterval", "Double", "Float", "Decimal",
                          "*", "/", "autoUnDadAfter", "ModeAllowance"] {
            XCTAssertFalse(code.contains(forbidden),
                           "RewardLedger.swift's code contains '\(forbidden)'. A reward is "
                           + "priced in days somebody spent, never in minutes of screen time, "
                           + "and this type has no arithmetic that could convert between them. "
                           + "Read the header before removing this assertion.")
        }
    }

    func testTheLedgerCannotReachAnythingThatGrantsOrReleases() throws {
        // Two rules at once. Nothing here may release a phone, and nothing here
        // may stand in for `AutonomyLadder` — the backlog ranks this feature
        // ninth precisely so that a concrete reward stays a bridge to earned
        // autonomy rather than a substitute for it.
        let code = try ledgerSourceCode()
        for forbidden in ["AutonomyLadder", "Rung", "autonomyLevel", "RolePermissions",
                          "DadMode", "BlockedSelection", "ShieldControlling", "DadEngine"] {
            XCTAssertFalse(code.contains(forbidden),
                           "RewardLedger.swift's code names '\(forbidden)'. Days buy real-world "
                           + "things a person hands over; they must not buy a capability, and "
                           + "claiming a reward must not be able to move the shield.")
        }
    }

    // MARK: - Helpers

    private func claim(_ reward: RewardLedger.Reward,
                       at claimedAt: Date? = nil,
                       settledAt: Date? = nil) -> RewardLedger.Redemption {
        RewardLedger.Redemption(rewardID: reward.id,
                                rewardName: reward.name,
                                price: reward.price,
                                claimedAt: claimedAt ?? now,
                                settledAt: settledAt)
    }
}
