import XCTest
@testable import DadCore

/// The decisions here are about dates and about what a household is told, so
/// the tests pin both: the day boundaries a review date is read against, and
/// the difference between "we talked and kept it" and "nobody has looked at
/// this".
final class ModeAgreementTests: XCTestCase {

    /// Pinned to UTC so a machine in another time zone doesn't shift day
    /// boundaries under the tests. One test below deliberately uses a second
    /// zone, to prove the calendar is genuinely consulted.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    /// Mid-morning, so a "today" comparison has hours on either side of it and
    /// an accidental instant comparison shows up.
    private lazy var now: Date = date(2026, 9, 3, hour: 9)

    private func mode(_ name: String) -> DadMode {
        DadMode(name: name, symbol: "circle")
    }

    private func agreement(for mode: DadMode,
                           reason: String = "Homework goes better without the group chat.",
                           by parties: ModeAgreement.Parties = .both,
                           agreedAt: Date? = nil,
                           renegotiateOn: Date? = nil,
                           history: [ModeAgreement.Renegotiation] = []) -> ModeAgreement {
        ModeAgreement(modeID: mode.id,
                      reason: reason,
                      agreedAt: agreedAt ?? date(2026, 6, 1),
                      agreedBy: parties,
                      renegotiateOn: renegotiateOn,
                      history: history)
    }

    private func household(_ modes: [DadMode],
                           _ agreements: [ModeAgreement]) -> HouseholdAgreements {
        HouseholdAgreements(modes: modes, agreements: agreements, now: now, calendar: calendar)
    }

    // MARK: - Overdue boundaries
    //
    // A review due today is due today all day. Comparing raw instants instead
    // would make it overdue from one minute past whatever time it was set,
    // which is not how a household would describe it.

    func testDueTodayIsNotOverdueAndReadsAsZeroDays() {
        // Due at midnight this morning — already in the past as an instant, but
        // today as a day, which is what counts.
        let a = agreement(for: mode("Sleep"), renegotiateOn: date(2026, 9, 3, hour: 0))
        XCTAssertEqual(a.daysUntilRenegotiation(now: now, calendar: calendar), 0)
        XCTAssertFalse(a.isOverdue(now: now, calendar: calendar))
    }

    func testDueLaterTodayIsStillZeroDays() {
        let a = agreement(for: mode("Sleep"), renegotiateOn: date(2026, 9, 3, hour: 23, minute: 59))
        XCTAssertEqual(a.daysUntilRenegotiation(now: now, calendar: calendar), 0)
        XCTAssertFalse(a.isOverdue(now: now, calendar: calendar))
    }

    func testDueYesterdayIsOverdueByOneDay() {
        // Late yesterday evening: fewer than 24 hours ago, but a day late.
        let a = agreement(for: mode("Sleep"), renegotiateOn: date(2026, 9, 2, hour: 23))
        XCTAssertEqual(a.daysUntilRenegotiation(now: now, calendar: calendar), -1)
        XCTAssertTrue(a.isOverdue(now: now, calendar: calendar))
    }

    func testDueTomorrowIsOneDayAway() {
        let a = agreement(for: mode("Sleep"), renegotiateOn: date(2026, 9, 4, hour: 1))
        XCTAssertEqual(a.daysUntilRenegotiation(now: now, calendar: calendar), 1)
        XCTAssertFalse(a.isOverdue(now: now, calendar: calendar))
    }

    func testNoReviewDateIsNotOverdueAndHasNoCountdown() {
        // Not overdue, because it was never due. That is a different problem
        // and it gets its own list.
        let a = agreement(for: mode("Sleep"), renegotiateOn: nil)
        XCTAssertNil(a.daysUntilRenegotiation(now: now, calendar: calendar))
        XCTAssertFalse(a.isOverdue(now: now, calendar: calendar))
        XCTAssertFalse(a.comesUpAgain)
    }

    func testOverdueIsReadAgainstTheHouseholdsOwnCalendar() {
        // `now` is 09:00 on 2026-09-03 in UTC and 02:00 on the same date in Los
        // Angeles. A review date of 03:00 UTC on 2026-09-03 is *today* in UTC —
        // not overdue — but 20:00 the previous evening in Los Angeles, so a day
        // late there. Same two instants, different verdicts, which is the whole
        // reason the calendar is injected rather than assumed.
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let a = agreement(for: mode("Sleep"), renegotiateOn: date(2026, 9, 3, hour: 3))
        XCTAssertFalse(a.isOverdue(now: now, calendar: calendar))
        XCTAssertTrue(a.isOverdue(now: now, calendar: la))
    }

    func testReviewDateHelperSnapsToTheStartOfTheDay() {
        let due = ModeAgreement.reviewDate(30, after: now, calendar: calendar)
        XCTAssertEqual(due, date(2026, 10, 3, hour: 0))
    }

    // MARK: - A renegotiation that changed nothing
    //
    // "We talked and kept it" has to be a recordable fact. Without it the
    // review date slides past, the Mode joins the overdue list, and the
    // household is told off for a conversation it actually had.

    func testKeepingAnAgreementStillCountsAsHavingTalkedAboutIt() {
        let sleep = mode("Sleep")
        let overdue = agreement(for: sleep, renegotiateOn: date(2026, 8, 1))
        XCTAssertTrue(overdue.isOverdue(now: now, calendar: calendar))

        let kept = overdue.renegotiated(.keptAsIs,
                                        on: now,
                                        by: .both,
                                        nextReviewOn: ModeAgreement.reviewDate(30, after: now,
                                                                               calendar: calendar))

        XCTAssertEqual(kept.history.count, 1)
        XCTAssertEqual(kept.history.first?.outcome, .keptAsIs)
        XCTAssertEqual(kept.lastReviewedAt, now)
        XCTAssertFalse(kept.isOverdue(now: now, calendar: calendar))
        XCTAssertEqual(kept.daysUntilRenegotiation(now: now, calendar: calendar), 30)
        // The rule itself is untouched: the conversation changed nothing, and
        // recording it must not quietly rewrite the reason.
        XCTAssertEqual(kept.reason, overdue.reason)
        XCTAssertEqual(kept.standingInIsolation, .agreed)
    }

    func testKeptAsIsAndChangedAreDistinguishableAfterTheFact() {
        // Both advance the clock; only one claims the rule moved. A design that
        // collapsed them would make "we kept it" unsayable.
        let sleep = mode("Sleep")
        let base = agreement(for: sleep, renegotiateOn: date(2026, 8, 1))

        let kept = base.renegotiated(.keptAsIs, on: now, by: .both, nextReviewOn: nil)
        let changed = base.renegotiated(.changed, on: now, by: .both,
                                        reason: "Later on weekends now.",
                                        nextReviewOn: nil)

        XCTAssertEqual(kept.history.first?.outcome, .keptAsIs)
        XCTAssertEqual(changed.history.first?.outcome, .changed)
        XCTAssertEqual(kept.lastReviewedAt, changed.lastReviewedAt)
        XCTAssertEqual(kept.reason, base.reason)
        XCTAssertEqual(changed.reason, "Later on weekends now.")
    }

    func testANilNextReviewClearsTheDateRatherThanKeepingTheOldOne() {
        // Keeping the old date would make the agreement permanently overdue
        // *because* it was reviewed — the exact inversion this method exists to
        // prevent. Clearing it moves the Mode to "no date set" instead.
        let a = agreement(for: mode("Sleep"), renegotiateOn: date(2026, 8, 1))
        let after = a.renegotiated(.keptAsIs, on: now, by: .both, nextReviewOn: nil)

        XCTAssertFalse(after.comesUpAgain)
        XCTAssertFalse(after.isOverdue(now: now, calendar: calendar))
        XCTAssertNil(after.daysUntilRenegotiation(now: now, calendar: calendar))
    }

    func testABlankReasonAtRenegotiationLeavesTheWordingStanding() {
        let a = agreement(for: mode("Sleep"))
        let after = a.renegotiated(.keptAsIs, on: now, by: .both,
                                   reason: "   \n ", nextReviewOn: nil)
        XCTAssertEqual(after.reason, a.reason)
    }

    func testLastReviewedIsNeverOlderThanTheAgreementItself() {
        // History stored out of order, or carrying a record whose date failed to
        // decode, must not make a review look older than the day it was written.
        let ancient = ModeAgreement.Renegotiation(date: Date(timeIntervalSince1970: 0),
                                                  outcome: .changed,
                                                  agreedBy: .both)
        let a = agreement(for: mode("Sleep"),
                          agreedAt: date(2026, 6, 1),
                          history: [ancient])
        XCTAssertEqual(a.lastReviewedAt, date(2026, 6, 1))
    }

    // MARK: - An imposed rule reads as imposed

    func testAnImposedRuleIsVisiblyImposedEvenWithAGoodReason() {
        let sleep = mode("Sleep")
        let imposed = agreement(for: sleep,
                                reason: "Because school starts at eight.",
                                by: .onePerson)
        XCTAssertTrue(imposed.isImposed)

        let h = household([sleep], [imposed])
        XCTAssertEqual(h.imposedCount, 1)
        XCTAssertEqual(h.agreedCount, 0)
        XCTAssertEqual(h.entries.first?.standing, .imposed)
    }

    func testAnImposedRuleWithNoReasonStaysImposedRatherThanBecomingUnexplained() {
        // A blank reason demotes an agreed Mode but must never rescue an
        // imposed one. Folding it into "unexplained" would hide the imposition
        // among Modes nobody has got round to yet, which is the silent
        // equivalence this whole feature exists to stop.
        let sleep = mode("Sleep")
        let h = household([sleep], [agreement(for: sleep, reason: "", by: .onePerson)])
        XCTAssertEqual(h.entries.first?.standing, .imposed)
        XCTAssertEqual(h.unexplainedCount, 0)
    }

    func testAgreedRequiresBothPeopleAndSomethingWrittenDown() {
        let a = mode("A"), b = mode("B"), c = mode("C"), d = mode("D")
        let h = household([a, b, c, d], [
            agreement(for: a, reason: "So dinner is dinner.", by: .both),
            agreement(for: b, reason: "   ", by: .both),
            agreement(for: c, reason: "So dinner is dinner.", by: .onePerson),
        ])
        XCTAssertEqual(h.entries.map(\.standing),
                       [.agreed, .unexplained, .imposed, .unexplained])
    }

    func testAnImposedRuleBecomesAgreedOnceBothPeopleSitDownOverIt() {
        // Restrictions are supposed to shrink as trust grows, so the record has
        // to be able to move in that direction. If it could not, every rule set
        // in the first week would read as imposed forever.
        let sleep = mode("Sleep")
        let imposed = agreement(for: sleep, by: .onePerson)
        let now2 = now
        let agreed = imposed.renegotiated(.keptAsIs, on: now2, by: .both, nextReviewOn: nil)

        XCTAssertFalse(agreed.isImposed)
        XCTAssertEqual(household([sleep], [agreed]).agreedCount, 1)
        XCTAssertEqual(agreed.history.first?.agreedBy, .both)
    }

    // MARK: - The household summary

    func testTheEmptyHouseholdSaysNothingAtAll() {
        let h = household([], [])
        XCTAssertEqual(h.total, 0)
        XCTAssertEqual(h.agreedCount, 0)
        XCTAssertEqual(h.imposedCount, 0)
        XCTAssertEqual(h.unexplainedCount, 0)
        XCTAssertTrue(h.entries.isEmpty)
        XCTAssertTrue(h.overdue.isEmpty)
        XCTAssertTrue(h.neverRevisited.isEmpty)
        XCTAssertTrue(h.unexplained.isEmpty)
        XCTAssertTrue(h.imposed.isEmpty)
        // True, but it means "nothing to raise", not "well done".
        XCTAssertTrue(h.nothingToRaise)
        XCTAssertEqual(AgreementCopy.overdueHeadline(count: 0), "")
    }

    func testAModeWithNoAgreementIsUnexplainedAndNotOverdue() {
        let sleep = mode("Sleep")
        let h = household([sleep], [])
        let entry = h.entries[0]
        XCTAssertEqual(entry.standing, .unexplained)
        XCTAssertNil(entry.agreement)
        XCTAssertNil(entry.daysUntilRenegotiation)
        XCTAssertFalse(entry.isOverdue)
        // Not "never comes up again" either: there is no agreement to revisit.
        // Listing it there would put it in front of the household twice.
        XCTAssertFalse(entry.neverComesUpAgain)
        XCTAssertEqual(h.neverRevisited.count, 0)
        XCTAssertEqual(h.unexplained.count, 1)
    }

    func testTheThreeStandingsPartitionEveryMode() {
        let a = mode("A"), b = mode("B"), c = mode("C")
        let h = household([a, b, c], [
            agreement(for: a, by: .both),
            agreement(for: b, by: .onePerson),
        ])
        XCTAssertEqual(h.total, 3)
        XCTAssertEqual(h.agreedCount + h.imposedCount + h.unexplainedCount, h.total)
        XCTAssertEqual(h.agreedCount, 1)
        XCTAssertEqual(h.imposedCount, 1)
        XCTAssertEqual(h.unexplainedCount, 1)
    }

    func testOverdueListsTheLongestIgnoredFirst() {
        let a = mode("A"), b = mode("B"), c = mode("C")
        let h = household([a, b, c], [
            agreement(for: a, renegotiateOn: date(2026, 9, 1)),   // 2 days late
            agreement(for: b, renegotiateOn: date(2026, 6, 1)),   // months late
            agreement(for: c, renegotiateOn: date(2026, 12, 1)),  // not yet due
        ])
        XCTAssertEqual(h.overdue.map(\.modeName), ["B", "A"])
        XCTAssertEqual(AgreementCopy.overdueHeadline(count: h.overdue.count),
                       "2 modes are due to be talked about")
    }

    func testAnAgreementWithNoDateIsListedAsNeverRevisitedRatherThanOverdue() {
        let sleep = mode("Sleep")
        let h = household([sleep], [agreement(for: sleep, renegotiateOn: nil)])
        XCTAssertTrue(h.overdue.isEmpty)
        XCTAssertEqual(h.neverRevisited.map(\.modeName), ["Sleep"])
        XCTAssertFalse(h.nothingToRaise)
    }

    func testAnAgreementForADeletedModeIsNotCounted() {
        // Otherwise a household with three Modes is shown four agreements, and
        // the arithmetic under it stops adding up.
        let sleep = mode("Sleep")
        let ghost = agreement(for: mode("Deleted"), by: .both)
        let h = household([sleep], [agreement(for: sleep, by: .both), ghost])
        XCTAssertEqual(h.total, 1)
        XCTAssertEqual(h.agreedCount, 1)
    }

    func testTwoAgreementsForOneModeResolveToTheOneReviewedMostRecently() {
        // A side table can end up with two rows after a merge or a racy write.
        // Picking by array order would flip the summary between launches for
        // reasons nobody can see.
        let sleep = mode("Sleep")
        let stale = agreement(for: sleep, reason: "Old wording.", by: .onePerson,
                              agreedAt: date(2026, 1, 1))
        let fresh = agreement(for: sleep, reason: "New wording.", by: .both,
                              agreedAt: date(2026, 7, 1))

        for pair in [[stale, fresh], [fresh, stale]] {
            let h = household([sleep], pair)
            XCTAssertEqual(h.entries.first?.agreement?.reason, "New wording.")
            XCTAssertEqual(h.agreedCount, 1)
        }
    }

    func testEntriesFollowTheOrderTheModesAreIn() {
        let a = mode("Deep Work"), b = mode("Dinner"), c = mode("Sleep")
        XCTAssertEqual(household([a, b, c], []).entries.map(\.modeName),
                       ["Deep Work", "Dinner", "Sleep"])
    }

    // MARK: - Storage
    //
    // The failure being guarded against is silent: a record that throws while
    // decoding is skipped by `LenientDecoding`, so a missing key deletes the
    // agreement and nothing anywhere reports it.

    func testAnAgreementSurvivesARoundTrip() throws {
        let sleep = mode("Sleep")
        let original = agreement(for: sleep,
                                 renegotiateOn: date(2026, 12, 1),
                                 history: [.init(date: date(2026, 7, 1),
                                                 outcome: .keptAsIs,
                                                 agreedBy: .both,
                                                 reason: "Same as before.")])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ModeAgreement.self, from: data), original)
    }

    func testARecordCarryingOnlyAModeIDStillDecodes() throws {
        // This is the shape a record written by an older build has once a field
        // is added. It must decode to something usable rather than vanish.
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: [["modeID": id.uuidString]])
        let decoded = LenientDecoding.array(ModeAgreement.self, from: data)

        XCTAssertEqual(decoded?.count, 1)
        let a = try XCTUnwrap(decoded?.first)
        XCTAssertEqual(a.modeID, id)
        XCTAssertEqual(a.reason, "")
        XCTAssertFalse(a.hasReason)
        XCTAssertTrue(a.history.isEmpty)
        XCTAssertNil(a.renegotiateOn)
    }

    func testAnUnrecordedOrUnknownPartyReadsAsImposedRatherThanAgreed() throws {
        // A decode gap is not evidence of a conversation. Defaulting the other
        // way would let a storage change quietly promote every imposed rule to
        // an agreed one — the one direction this must never move on its own.
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            ["modeID": id.uuidString],
            ["modeID": UUID().uuidString, "agreedBy": "theWholeFamily"],
        ])
        let decoded = try XCTUnwrap(LenientDecoding.array(ModeAgreement.self, from: data))
        XCTAssertEqual(decoded.count, 2)
        XCTAssertTrue(decoded.allSatisfy(\.isImposed))
    }

    func testOneUnreadableAgreementDoesNotCostTheRest() throws {
        let sleep = mode("Sleep")
        let good = agreement(for: sleep, by: .both)
        let encoded = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(good))
        // No `modeID`: this one describes nothing and is correctly dropped.
        let data = try JSONSerialization.data(withJSONObject: [["reason": "orphan"], encoded])

        let decoded = try XCTUnwrap(LenientDecoding.array(ModeAgreement.self, from: data))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.modeID, sleep.id)
    }

    func testAConversationWithAnUnreadableOutcomeDoesNotDeleteTheAgreement() throws {
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: [[
            "modeID": id.uuidString,
            "history": [["outcome": "postponed"]],
        ]])
        let decoded = try XCTUnwrap(LenientDecoding.array(ModeAgreement.self, from: data))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.history.count, 1)
        // The same conservative default applies inside a conversation: a stored
        // renegotiation that does not say who was there must not read as one
        // both people attended. A mutation of this line survived until it was
        // asserted here — the outer default was covered, the inner one was not.
        XCTAssertEqual(decoded.first?.history.first?.agreedBy, .onePerson)
        // An unrecognised outcome reads as `changed`, which claims less than
        // pretending the rule was deliberately kept.
        XCTAssertEqual(decoded.first?.history.first?.outcome, .changed)
    }

    // MARK: - Copy
    //
    // Kept in Core for the reason `WidgetSnapshot` is: where the phrasing is
    // the decision, the phrasing is testable. Every line is a fact with no
    // verdict attached — no praise, no scolding, nobody named.

    func testDueLineStatesTheFactAndNothingElse() {
        XCTAssertEqual(AgreementCopy.dueLine(daysUntil: nil),
                       "No date set to talk about this again")
        XCTAssertEqual(AgreementCopy.dueLine(daysUntil: 0), "Comes up today")
        XCTAssertEqual(AgreementCopy.dueLine(daysUntil: 1), "Comes up tomorrow")
        XCTAssertEqual(AgreementCopy.dueLine(daysUntil: 12), "Comes up in 12 days")
        XCTAssertEqual(AgreementCopy.dueLine(daysUntil: -1), "Was due yesterday")
        XCTAssertEqual(AgreementCopy.dueLine(daysUntil: -9), "Was due 9 days ago")
    }

    func testOverdueHeadlineIsPluralCorrectAndSilentWhenThereIsNothingToSay() {
        XCTAssertEqual(AgreementCopy.overdueHeadline(count: 0), "")
        XCTAssertEqual(AgreementCopy.overdueHeadline(count: 1), "1 mode is due to be talked about")
        XCTAssertEqual(AgreementCopy.overdueHeadline(count: 3), "3 modes are due to be talked about")
    }

    func testStandingAndOutcomeLabelsNameTheStateWithoutJudgingIt() {
        XCTAssertEqual(AgreementCopy.standingLabel(.agreed), "Agreed together")
        XCTAssertEqual(AgreementCopy.standingLabel(.imposed), "Set by one person")
        XCTAssertEqual(AgreementCopy.standingLabel(.unexplained), "No reason written down")
        XCTAssertEqual(AgreementCopy.partiesLabel(.both), "Agreed together")
        XCTAssertEqual(AgreementCopy.partiesLabel(.onePerson), "Set by one person")
        // "No change" would read as a wasted conversation; the conversation is
        // the point of the feature.
        XCTAssertEqual(AgreementCopy.outcomeLabel(.keptAsIs), "Talked it over, kept it")
        XCTAssertEqual(AgreementCopy.outcomeLabel(.changed), "Talked it over, changed it")
    }

    func testNoCopyInThisFeatureNamesOrRanksAPerson() {
        // The one output this feature must never produce is a comparison
        // between two people. It cannot, because nobody is identified anywhere
        // in the model — `Parties` counts heads and stops there. This test is
        // the guard that notices if a role ever gets smuggled in.
        let everyString = [
            AgreementCopy.reasonPrompt,
            AgreementCopy.reasonHint,
            AgreementCopy.standingLabel(.agreed),
            AgreementCopy.standingLabel(.imposed),
            AgreementCopy.standingLabel(.unexplained),
            AgreementCopy.outcomeLabel(.keptAsIs),
            AgreementCopy.outcomeLabel(.changed),
            AgreementCopy.dueLine(daysUntil: nil),
            AgreementCopy.dueLine(daysUntil: -9),
            AgreementCopy.overdueHeadline(count: 3),
        ]
        for line in everyString {
            for word in ["parent", "teen", "child", "kid", "mum", "mom", "your son",
                         "your daughter", "better than", "score", "points", "minutes"] {
                XCTAssertFalse(line.lowercased().contains(word),
                               "\"\(line)\" names or ranks a person, or pays in minutes")
            }
        }
    }
}

/// Convenience for asserting a single agreement's standing without building a
/// household around it. Lives in the tests because the app always has the Modes
/// to hand and should go through `HouseholdAgreements`.
private extension ModeAgreement {
    var standingInIsolation: ModeStanding { HouseholdAgreements.standing(for: self) }
}
