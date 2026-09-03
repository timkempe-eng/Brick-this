import Foundation

/// A small ledger: the young person earns, the grown-up settles up.
///
/// Pocket money, a lift into town, a later curfew on Saturday, choosing what
/// is for dinner. Dad records what was earned and what was claimed. It does
/// not move money, hold a balance on anyone's behalf, or promise that a thing
/// was handed over — a person does that, in a kitchen, and then taps
/// `settling(claim:at:)`.
///
/// # The forbidden currency
///
/// **A reward is never denominated in screen time, and this file is built so
/// that making one would be a visible change rather than a quiet one.**
///
/// The reason is the strongest finding in the research behind this backlog: a
/// whole category of apps — ScreenCoach, Chore Champ, EarnIt — lets chores buy
/// minutes, and it backfires. Screens become the thing worth working for,
/// every other activity starts to feel like an obstacle in front of the
/// reward, and cooperation turns into negotiation. `AutonomyLadder` states the
/// same rule for autonomy and calls minutes "the one currency Dad must not
/// mint". The rule is identical here and the exposure is worse, because this
/// ledger is the one place in the app where something is explicitly *bought*.
///
/// Four structural defences, and what a reviewer would see if someone undid
/// each of them:
///
/// 1. **The unit is a day, not a duration.** `Days` wraps an `Int` count of
///    calendar days on which a session was finished by hand. It is minted by
///    the session history and by nothing else. There is no initialiser from a
///    `Double`, no `TimeInterval` anywhere in this file, and no conversion in
///    either direction.
/// 2. **`Days` cannot be multiplied or divided.** It has `+`, a saturating
///    `-`, and `<`, all of them `Days`-to-`Days`. That is the complete set. A
///    day count becomes a number of minutes by being multiplied by 1440 or by
///    growing a property that returns seconds, so both of those operations are
///    simply absent from the type. Adding either is adding an operator or a
///    member to `Days` — three lines in a diff, in a file whose header says
///    not to.
/// 3. **The test suite reads this source.** `testTheLedgerSourceNamesNoUnitOfTime`
///    strips the comments out of this file and fails if the code that is left
///    contains `TimeInterval`, `Double`, `Float`, `*`, `/`, `autoUnDadAfter`
///    or `ModeAllowance`. So the second defence cannot be undone by a
///    reviewer's inattention: the build goes red. That test is the reason the
///    arithmetic below is written the long way round in one or two places.
/// 4. **Nothing here can release a phone.** A `Redemption` is a `UUID`, a
///    name, a price and two dates. It reaches no `DadMode`, no
///    `BlockedSelection` and no port, so there is no path from claiming a
///    reward to a shield coming down — not even an indirect one, because the
///    type the shield would need is not referenced in this file at all.
///
/// # Why this ranks ninth, and what keeps it there
///
/// The backlog puts earned autonomy second and this ninth, with the
/// instruction that if only one ships it should be the ladder. A concrete
/// reward is a bridge to an abstract one for a younger person; it must not
/// become the point. So:
///
/// * Nothing in this file produces an autonomy level, a rung, or a capability.
///   Days cannot be spent on any of the things the ladder grants, because this
///   type cannot name them.
/// * This ledger never writes to the session history. Spending days does not
///   delete, mark or reinterpret a single session, so a young person cannot
///   spend their way down a rung, and a grown-up cannot price a reward high
///   enough to stall the climb.
/// * The same day is therefore counted by both. That is deliberate and it is
///   not double-spending, because the two are not one budget. Splitting a
///   fixed pot between "a lift into town" and "setting my own Sleep window"
///   would force a choice between them every week, and for a twelve-year-old
///   the lift wins every time — which is exactly the failure this feature is
///   supposed to avoid.
///
/// # Everything derived, nothing stored twice
///
/// The balance is computed from the history and the redemption list, the way
/// `AutonomyLadder` computes a rung and `DadStats` computes a streak. A stored
/// balance is a number that can drift from the days that earned it, can be
/// edited by anyone who can reach the file, and has to be migrated. Only the
/// grown-up's decisions are stored: which rewards exist, and which claims were
/// made and settled.
struct RewardLedger {

    // MARK: - The unit

    /// A whole number of days, and the only currency in this file.
    ///
    /// **Why a day, rather than points, or pounds, or minutes.**
    ///
    /// *Not minutes*, for the reason above.
    ///
    /// *Not points.* A point is whatever the app says it is, which means the
    /// app is minting it, which means the exchange rate between a point and a
    /// day of actually doing the thing is a number somebody tuned. Tune it
    /// upward and the ledger inflates; tune it downward and yesterday's
    /// promises quietly get more expensive. A day cannot be tuned. It either
    /// happened or it did not, and the session history is the record.
    ///
    /// *Not money.* The moment a price reads "£5", Dad is claiming to hold a
    /// balance that it does not hold, and it has acquired everything that
    /// follows from that claim: a dispute when the fiver never arrives, a
    /// question about what happens when the household stops paying, and a
    /// reasonable expectation that the app can transfer, refund and reconcile.
    /// Dad is not a payments product and cannot become one by accident. A
    /// grown-up who wants a reward to be five pounds writes "£5 pocket money"
    /// in the *name* — a string Dad never interprets — and prices it in days.
    ///
    /// *A day*, then, because it is a real event the household can both point
    /// at, it is already the unit `AutonomyLadder` counts in, so a rung and a
    /// reward are quoted against the same evidence and cannot drift into two
    /// separate economies, and — the part that matters most here — it is
    /// indivisible. There is no half day. A unit with no fractions is a unit
    /// that resists being scaled into anything finer, which is the direction
    /// minutes lie in.
    struct Days: Hashable, Comparable, Codable, CustomStringConvertible {

        /// Always zero or more. A negative day count is not a debt; it is a
        /// bug, a corrupt file or somebody editing JSON, and in all three
        /// cases the only safe reading is zero. See `init(_:)`.
        let count: Int

        /// Clamps at zero rather than trapping, so that no arithmetic anywhere
        /// in this file can produce a negative quantity even by mistake.
        init(_ count: Int) {
            self.count = max(0, count)
        }

        /// Encoded as a bare number, so stored JSON reads `"price": 5`.
        /// Decoding goes through `init(_:)`, which means a file that has been
        /// hand-edited to `-5` reads as zero instead of minting five days for
        /// whoever edited it.
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.init(try container.decode(Int.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(count)
        }

        static let zero = Days(0)

        var isZero: Bool { count == 0 }

        static func < (lhs: Days, rhs: Days) -> Bool { lhs.count < rhs.count }

        static func + (lhs: Days, rhs: Days) -> Days { Days(lhs.count + rhs.count) }

        /// Saturating: `Days(2) - Days(5)` is zero, not minus three.
        ///
        /// This is the answer to "what happens when a balance would go
        /// negative", made structural. A negative balance is not merely
        /// refused, it is unrepresentable — the type has no value for it. What
        /// would have been the negative part is reported separately and
        /// positively, by `shortfall(for:)` when you are asking for something
        /// and by `spentBeyondEarned` when the history has shrunk underneath a
        /// claim that was already honoured.
        ///
        /// The alternative was letting the balance go negative and calling it
        /// debt. That was rejected on tone: a screen that tells a young person
        /// they are four days in arrears to their own family is the guilt
        /// register this product does not use, and it invites a household to
        /// treat cooperation as something that can be owed.
        static func - (lhs: Days, rhs: Days) -> Days { Days(lhs.count - rhs.count) }

        /// Deliberately no `*`, no `/`, no `Double`, no seconds. See the
        /// header. If you are here because you need one of them, the thing you
        /// are building is not a reward.

        var description: String { count == 1 ? "1 day" : "\(count) days" }
    }

    // MARK: - What the grown-up defines

    /// A reward, as written down by the grown-up.
    ///
    /// `name` is free text and Dad never parses it. That is the seam where a
    /// household's real-world arrangements live — "a lift to football", "£5",
    /// "you pick Friday's dinner" — and keeping it uninterpreted is what stops
    /// this type growing categories, amounts and currencies.
    struct Reward: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var name: String
        var price: Days

        /// Retired rewards can no longer be claimed but stay readable, so a
        /// grown-up can withdraw an offer without deleting the record of the
        /// times it was already honoured.
        ///
        /// Optional, not `Bool`, and this is the rule rather than a
        /// preference: Swift's synthesised decoder throws when a
        /// non-optional key is missing, and `LenientDecoding` responds to a
        /// throw by dropping the element. A plain `Bool` added here would
        /// therefore delete every reward written by the build before it — not
        /// fail loudly, *delete* — on the morning the household updates. The
        /// same reasoning is on `DadMode.schedule` and
        /// `DadSession.startedBySchedule`.
        var isRetired: Bool?

        var canBeClaimed: Bool { isRetired != true }
    }

    /// A claim: a reward asked for, and later handed over.
    ///
    /// Two moments, because in a household they are two moments. The young
    /// person claims; the grown-up settles up when the lift actually happens.
    /// A claim that is never settled stays visible as an open promise, which
    /// is the honest thing for the app to show and the one place it can
    /// usefully nag nobody but the grown-up.
    struct Redemption: Codable, Identifiable, Hashable {
        var id: UUID = UUID()

        /// Which reward this was, for the app to link back to.
        var rewardID: UUID

        /// The name as it read when the claim was made.
        ///
        /// Denormalised on purpose, exactly as `DadSession` stores `modeName`
        /// alongside `modeID`: a grown-up who deletes a reward must not erase
        /// the history of it being given, and a renamed reward must not
        /// rewrite what last month's claim said.
        var rewardName: String

        /// The price at the moment of claiming.
        ///
        /// Stored rather than looked up, so that re-pricing a reward cannot
        /// reach backwards. If the price of a lift goes from three days to
        /// five, last week's lift still cost three — otherwise a grown-up
        /// editing a number would silently overdraw a balance that was
        /// correct when it was spent, and the young person would watch days
        /// disappear with nothing to point at.
        var price: Days

        var claimedAt: Date

        /// When the grown-up handed it over. `nil` means claimed and still
        /// outstanding. Optional for the state it represents, and Optional for
        /// the decoding reason on `Reward.isRetired` as well.
        var settledAt: Date?

        var isSettled: Bool { settledAt != nil }
    }

    // MARK: - Construction

    let rewards: [Reward]
    let redemptions: [Redemption]
    let sessions: [DadSession]
    let calendar: Calendar
    let now: Date

    /// - Parameter calendar: injected for the same reason `DadStats` and
    ///   `AutonomyLadder` inject it. Everything earned here is a count of
    ///   *days*, and which instant belongs to which day is a property of the
    ///   household's time zone rather than of this code. Tests pin UTC so a
    ///   runner in another zone cannot move a boundary underneath them; the
    ///   app passes `.current`, which is what the household's days actually
    ///   are.
    init(rewards: [Reward] = [],
         redemptions: [Redemption] = [],
         sessions: [DadSession] = [],
         now: Date = Date(),
         calendar: Calendar = .current) {
        self.rewards = rewards
        self.redemptions = redemptions
        // Two filters, both of them decisions.
        //
        // Unfinished sessions are excluded, as in `DadStats` and
        // `AutonomyLadder`: an in-flight session has no outcome yet, so
        // counting it would let a day appear in the balance mid-session and
        // vanish again when it ended on the emergency button — after a reward
        // had already been claimed with it.
        //
        // Sessions dated after `now` are excluded too. A clock that moved
        // backwards or a restored backup can put them there, and unlike the
        // ladder — where the worst case is a rung arriving early — here they
        // would buy something a person then has to hand over.
        self.sessions = sessions.filter { $0.endedAt != nil && $0.startedAt <= now }
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Earning

    /// Days that count.
    ///
    /// A session counts toward the day it *started*, exactly as in `DadStats`:
    /// an evening that runs past midnight credits the evening you began,
    /// because that is how anybody would describe it out loud.
    ///
    /// One qualifying session makes the day, even if another session the same
    /// day ended on the emergency button. The day contains the evidence, and
    /// counting the bad one against it would mean a single override could
    /// cancel a reward that had already been earned that morning.
    /// The same set of days the ladder spends on rungs, by construction
    /// rather than by both files agreeing to say the same thing. The `&&
    /// !endedByEmergency` that used to be here could not change the answer —
    /// an override already reads as nobody having ended it — and a redundant
    /// clause in a copied rule is the one that survives when the original
    /// changes.
    private var earningDays: Set<Date> { sessions.daysEndedByAPerson(calendar: calendar) }

    /// Every day ever earned. It does not decay.
    ///
    /// `AutonomyLadder` can withhold a rung after a fortnight away, and that is
    /// right for a rung, because a rung is a standing permission and has to
    /// describe the present. A day already earned is different: it is a thing
    /// that happened. Taking it back would mean an app removing days from a
    /// balance while nobody was using the app, which reads as theft and is the
    /// point at which a young person stops believing the number.
    var earned: Days { Days(earningDays.count) }

    /// Everything claimed, whether or not the grown-up has settled up yet.
    ///
    /// Claiming spends, not settling. If the balance only fell when a grown-up
    /// got round to confirming, then five claims could be made against the
    /// same five days and the shortfall would surface at the kitchen table,
    /// with somebody having to say no to four things already asked for. The
    /// balance has to mean "what I can ask for right now" or it means nothing.
    var spent: Days {
        redemptions.reduce(Days.zero) { $0 + $1.price }
    }

    /// What is available to spend. Never negative — see `Days.-`.
    var balance: Days { earned - spent }

    /// How far past the earned total the claims currently reach.
    ///
    /// Normally zero, because `claiming(_:)` refuses anything the balance does
    /// not cover. It can become non-zero without anybody doing wrong: the
    /// stored history is finite, so a household that Dads several times a day
    /// will eventually see the oldest days fall off the end of it, and days
    /// that fell off the end cannot be counted. `AutonomyLadder` hit the same
    /// edge and fixed it by writing an earned rung down as it was reached.
    ///
    /// The equivalent fix is not available here and should not be invented:
    /// what is stored is a list of things a household did for each other, and
    /// the ledger reporting a shortfall is preferable to the ledger
    /// un-settling a lift that was actually given. So nothing is clawed back,
    /// no claim is reversed, and the number is simply reported — positively,
    /// so no screen has to render a minus sign.
    var spentBeyondEarned: Days { spent - earned }

    var isOverdrawn: Bool { !spentBeyondEarned.isZero }

    // MARK: - What can I have

    /// Rewards still on offer, cheapest first, ties broken by name so the list
    /// does not reorder itself between two renders.
    var available: [Reward] {
        rewards.filter(\.canBeClaimed).sorted {
            $0.price == $1.price ? $0.name < $1.name : $0.price < $1.price
        }
    }

    func canAfford(_ reward: Reward) -> Bool {
        reward.price <= balance
    }

    /// How many more days this reward needs. Zero when it is already
    /// affordable, so callers can render it without a special case.
    func shortfall(for reward: Reward) -> Days {
        reward.price - balance
    }

    /// "What can I have right now."
    var affordable: [Reward] { available.filter(canAfford) }

    /// "And what can I not."
    var outOfReach: [Reward] { available.filter { !canAfford($0) } }

    /// The nearest thing that is out of reach.
    ///
    /// Worth having as its own answer rather than leaving the caller to take
    /// the first element of `outOfReach`: legibility is a design requirement
    /// here for the same reason it is on the ladder — a reward you cannot
    /// predict is not an incentive, it is a surprise. The app can say "two
    /// more days and the cinema is in reach" without doing any arithmetic of
    /// its own, and therefore without a second implementation of it to drift.
    var nearestOutOfReach: Reward? { outOfReach.first }

    /// Days remaining until `nearestOutOfReach` is affordable, or `nil` when
    /// everything on offer is already within reach.
    var daysUntilNearestOutOfReach: Days? {
        nearestOutOfReach.map(shortfall(for:))
    }

    // MARK: - Claims

    /// Claims not yet settled, oldest first — the grown-up's to-do list.
    var pending: [Redemption] {
        redemptions.filter { !$0.isSettled }.sorted { $0.claimedAt < $1.claimedAt }
    }

    /// Claims that were handed over, most recent first.
    var settled: [Redemption] {
        redemptions.filter(\.isSettled).sorted { $0.claimedAt > $1.claimedAt }
    }

    // MARK: - Settling up
    //
    // All three of these are pure: they return the new list of redemptions, or
    // `nil` when the thing being asked for is refused. That is the shape
    // `EmergencyAllowance.consume(uses:now:)` uses, and it is what keeps every
    // rule below reachable from `swift test` rather than living in whichever
    // screen happens to call it.

    /// Claim a reward. `nil` when it cannot be claimed.
    ///
    /// Refused in two cases, and the caller cannot tell them apart on purpose —
    /// both are simply "not now", and a screen that explains at length why a
    /// thing is unavailable is a screen that argues with somebody.
    ///
    /// * The balance does not cover the price. Under-covering is refused
    ///   outright rather than part-paid: a claim that leaves a debt behind is
    ///   the credit model rejected on `Days.-`.
    /// * The reward has been retired.
    ///
    /// Claiming the same reward twice is allowed as long as the balance covers
    /// both. Two lifts into town is two claims, and inventing a rule against
    /// it would be Dad having an opinion about a household's arrangements.
    func claiming(_ reward: Reward) -> [Redemption]? {
        guard reward.canBeClaimed else { return nil }
        guard canAfford(reward) else { return nil }
        let claim = Redemption(rewardID: reward.id,
                               rewardName: reward.name,
                               price: reward.price,
                               claimedAt: now,
                               settledAt: nil)
        return redemptions + [claim]
    }

    /// Record that the grown-up handed the reward over.
    ///
    /// `nil` when there is no such claim, or when it has already been settled.
    /// Refusing the second settle matters: settling twice would show two
    /// hand-overs in the history for one lift, and the history of what a
    /// household actually did for each other is the only thing in this file
    /// that cannot be recomputed from anything else.
    func settling(claim id: UUID, at date: Date) -> [Redemption]? {
        guard let index = redemptions.firstIndex(where: { $0.id == id }) else { return nil }
        guard !redemptions[index].isSettled else { return nil }
        var updated = redemptions
        updated[index].settledAt = date
        return updated
    }

    /// Withdraw a claim that has not been settled, returning its days to the
    /// balance.
    ///
    /// `nil` when there is no such claim, or when it has already been settled.
    /// A settled claim is permanent because the thing happened: the lift was
    /// given, and no state in an app can make that not so. Allowing it to be
    /// deleted would also make the balance editable by whoever is holding the
    /// phone, which is the whole ledger.
    func withdrawing(claim id: UUID) -> [Redemption]? {
        guard let claim = redemptions.first(where: { $0.id == id }) else { return nil }
        guard !claim.isSettled else { return nil }
        return redemptions.filter { $0.id != id }
    }
}
// `DadSession.wasEndedByAPerson` used to be defined here, as an inference
// from `endedByEmergency` and `startedBySchedule`, because this file was
// written before `DadSession` recorded how a session ended. It does now, so
// the inference is gone and the field is read instead — which the compiler
// insisted on, by name collision, exactly as intended.


