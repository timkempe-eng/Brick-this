import Foundation

/// The engine's family layer: why each Mode is here, what the days buy, and
/// the streak the household shares.

/// Split out of `DadEngine` rather than left in it, and the test for whether a
/// split is worth making is not the line count — it is whether anything has to
/// become `internal` to survive it.
///
/// Nothing did. These three groups share exactly one private helper,
/// `isGrownUpPresent`, and it moved with them; everything else they touch is
/// the engine's own ports and clock, which were never `private`. The rest of
/// `DadEngine` was left alone for the same reason in reverse: twelve private
/// helpers are shared across what its own boundaries would be, and Swift's
/// `private` is file-scoped, so splitting *there* would weaken encapsulation
/// on the one type that owns every state transition — to make a file shorter.
extension DadEngine {

    // MARK: - Why each Mode is here

    /// Every Mode and the agreement behind it.
    var householdAgreements: HouseholdAgreements {
        HouseholdAgreements(modes: store.modes,
                            agreements: store.agreements,
                            now: clock.now,
                            calendar: calendar)
    }

    func agreement(for modeID: UUID) -> ModeAgreement? {
        store.agreements.first { $0.modeID == modeID }
    }

    /// Write down why a Mode exists.
    ///
    /// `agreedBy` is **derived, never passed**, and that is the design rather
    /// than a convenience. The app cannot be told that two people agreed
    /// something; it can only observe that a grown-up was here, which on a
    /// young person's phone means the tag they hold was tapped. A parameter
    /// would let a screen assert "agreed together" about a conversation that
    /// did not happen, and the record is worth nothing the moment it can say
    /// that.
    ///
    /// A phone that is its owner's records `.onePerson`, because one person is
    /// who wrote it. That is true rather than a demotion, and the board that
    /// reads it is only shown on a young person's phone.
    @discardableResult
    func agree(modeID: UUID,
               reason: String,
               comingUpAgainIn days: Int? = nil,
               byTagUID tagUID: String? = nil) -> ModeAgreement? {
        guard store.modes.contains(where: { $0.id == modeID }) else { return nil }

        let together = store.household.role == .youngPerson && isGrownUpPresent(tagUID: tagUID)
        let existing = agreement(for: modeID)
        let agreement = ModeAgreement(
            modeID: modeID,
            reason: reason,
            agreedAt: clock.now,
            agreedBy: together ? .both : .onePerson,
            renegotiateOn: days.flatMap { ModeAgreement.reviewDate($0, after: clock.now, calendar: calendar) },
            // Kept across a rewrite. The record of a rule having been talked
            // about is the thing that makes the next conversation possible,
            // and rewriting the reason is not a reason to lose it.
            history: existing?.history ?? [])

        store.agreements = store.agreements.filter { $0.modeID != modeID } + [agreement]
        return agreement
    }

    /// Record that a Mode was talked about, whether or not anything changed.
    ///
    /// The unchanged case is recorded on purpose: "we talked and kept it" is a
    /// conversation, and a log that only remembers the times somebody won is
    /// not a log of a household.
    @discardableResult
    func renegotiate(modeID: UUID,
                     outcome: ModeAgreement.Outcome,
                     reason: String? = nil,
                     comingUpAgainIn days: Int? = nil,
                     byTagUID tagUID: String? = nil) -> ModeAgreement? {
        guard let existing = agreement(for: modeID) else { return nil }
        let together = store.household.role == .youngPerson && isGrownUpPresent(tagUID: tagUID)
        let updated = existing.renegotiated(outcome,
                                            on: clock.now,
                                            by: together ? .both : .onePerson,
                                            reason: reason ?? existing.reason,
                                            nextReviewOn: days.flatMap {
                                                ModeAgreement.reviewDate($0, after: clock.now,
                                                                         calendar: calendar)
                                            })
        store.agreements = store.agreements.filter { $0.modeID != modeID } + [updated]
        return updated
    }

    /// Drop the agreement for a Mode that no longer exists.
    ///
    /// Called where Modes are deleted rather than swept periodically:
    /// `HouseholdAgreements` is driven by the Modes and already ignores an
    /// orphan, so this is housekeeping and not correctness — which is why it
    /// is safe for it to be best-effort.
    func forgetAgreement(modeID: UUID) {
        store.agreements = store.agreements.filter { $0.modeID != modeID }
    }

    // MARK: - Rewards

    /// What is on offer, what has been claimed, and what the history has
    /// earned.
    ///
    /// Derived on every read rather than stored, exactly as `stats` is: a
    /// stored balance is a number somebody could edit, and this one decides
    /// what a young person is owed.
    var rewardLedger: RewardLedger {
        RewardLedger(rewards: store.rewards,
                     redemptions: store.redemptions,
                     sessions: store.history,
                     now: clock.now,
                     calendar: calendar)
    }

    /// Whether a grown-up is demonstrably here.
    ///
    /// The same answer the grant flow gives, and for the same reason: on a
    /// young person's phone the proof is a tap of the paired tag, which the
    /// grown-up is holding. No account, no server, no PIN anybody here has to
    /// get right. On a phone that is its owner's, the question does not
    /// arise — they are the grown-up.
    private func isGrownUpPresent(tagUID: String?) -> Bool {
        guard store.household.role == .youngPerson else { return true }
        guard let tagUID else { return false }
        return isPaired(tagUID: tagUID)
    }

    /// Put a reward on offer. A grown-up's act.
    @discardableResult
    func offer(_ reward: RewardLedger.Reward, byTagUID tagUID: String? = nil) -> Bool {
        guard isGrownUpPresent(tagUID: tagUID) else { return false }
        var rewards = store.rewards.filter { $0.id != reward.id }
        rewards.append(reward)
        store.rewards = rewards
        return true
    }

    /// Take an offer back without erasing the times it was honoured.
    @discardableResult
    func retire(rewardID: UUID, byTagUID tagUID: String? = nil) -> Bool {
        guard isGrownUpPresent(tagUID: tagUID) else { return false }
        guard let index = store.rewards.firstIndex(where: { $0.id == rewardID }) else { return false }
        var rewards = store.rewards
        rewards[index].isRetired = true
        store.rewards = rewards
        return true
    }

    /// Claim a reward. The young person's act, and it needs nobody's
    /// permission — the balance is the permission, and it was earned.
    @discardableResult
    func claim(_ reward: RewardLedger.Reward) -> Bool {
        guard let updated = rewardLedger.claiming(reward) else { return false }
        store.redemptions = Array(updated.suffix(Self.grantHistoryLimit))
        return true
    }

    /// Take an unsettled claim back, returning its days.
    @discardableResult
    func withdraw(claim id: UUID) -> Bool {
        guard let updated = rewardLedger.withdrawing(claim: id) else { return false }
        store.redemptions = updated
        return true
    }

    /// The lift actually happened. A grown-up's act, and the only one that is
    /// permanent: no state in an app can make a thing that happened not have.
    @discardableResult
    func settle(claim id: UUID, byTagUID tagUID: String? = nil) -> Bool {
        guard isGrownUpPresent(tagUID: tagUID) else { return false }
        guard let updated = rewardLedger.settling(claim: id, at: clock.now) else { return false }
        store.redemptions = updated
        return true
    }

    // MARK: - The household's streak, carried on the tag

    /// This phone's id, minted on first use.
    ///
    /// Lazy rather than created at install, so a household that never uses the
    /// shared streak never has an id at all — and so reading the store is not
    /// something that writes to it. Once minted it is never replaced: a new id
    /// reads as a new person and would reset the household to zero.
    func memberID() -> MemberID {
        if let existing = store.memberID { return existing }
        let fresh = MemberID.fresh()
        store.memberID = fresh
        return fresh
    }

    /// What this phone would tell the tag about itself.
    ///
    /// Derived from the session history every time rather than stored, for the
    /// reason `DadStats` is: a stored streak is a second number that can
    /// disagree with the first, and the one it would disagree with is the one
    /// on the screen next to it.
    ///
    /// `nil` before there is anything to report. A member with no sessions is
    /// not a member with a streak of zero — writing them to the tag would end
    /// the household's run on the day somebody installed the app.
    var myStanding: MemberStanding? {
        let stats = self.stats
        guard let lastActive = store.history.map(\.startedAt).max() else { return nil }
        return MemberStanding(member: memberID(),
                              lastActive: ScheduleOccurrence(startingAt: lastActive,
                                                             calendar: calendar),
                              streak: stats.currentStreak)
    }

    /// The ledger as it should be written back: what the tag said, updated
    /// with what this phone knows about itself.
    ///
    /// `setting` rather than `merged` for our own entry — this phone is the
    /// authority on its own streak even when its news is worse. See
    /// `HouseholdLedger.setting(_:)`.
    var ledgerToWrite: HouseholdLedger {
        store.ledger.afterExchange(with: nil, own: myStanding)
    }

    /// The payload for the tag, or `nil` when there is nothing worth writing.
    ///
    /// Nothing worth writing is the one-member case: a tag carrying only this
    /// phone tells the next reader nothing they did not already know, and
    /// writing it spends a write cycle and a second of somebody holding a
    /// phone against a sticker.
    func tagPayload() -> String? {
        let ledger = ledgerToWrite
        guard ledger.standings.count > 1 || !store.ledger.standings.isEmpty else {
            // Still write the first time, so the *other* phone has something
            // to merge with. Only a repeat write of a solo ledger is skipped.
            return ledger.standings.isEmpty ? nil : ledger.encoded()
        }
        return ledger.encoded()
    }

    /// Take in what a tag was carrying.
    ///
    /// Returns whether anything changed, so a caller can decide whether the
    /// write-back is worth the second it costs. A payload this build cannot
    /// read changes nothing and is reported as such — never half-applied,
    /// because the write-back would then overwrite the other phone's real
    /// data with our guess at it.
    @discardableResult
    func absorb(tagPayload payload: String) -> Bool {
        guard HouseholdLedger.decoded(payload) != nil else { return false }
        let merged = store.ledger.afterExchange(with: payload, own: nil)
        guard merged != store.ledger else { return false }
        store.ledger = merged
        widget.reload()
        return true
    }

    /// The number both people see, or `nil` when there is no household to
    /// speak of.
    ///
    /// Computed against `ledgerToWrite` rather than the stored ledger, so this
    /// phone's own contribution is current even when the tag has not been
    /// touched today. The other members are as stale as the last exchange, and
    /// `HouseholdStreak.asOf` is what says so.
    var householdStreak: HouseholdStreak? {
        ledgerToWrite.streak(asOf: ScheduleOccurrence(startingAt: clock.now, calendar: calendar),
                             calendar: calendar)
    }
}
