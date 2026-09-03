import XCTest
@testable import DadCore

/// The shared streak, and the tag it rides on.
///
/// Two properties are worth more than the arithmetic and are tested as
/// properties rather than as examples: the wire format can never carry prose,
/// whatever anybody adds to the type later; and a stale number is never
/// reported as a live one.
final class HouseholdLedgerTests: XCTestCase {

    /// Pinned. A day boundary is the unit this whole file is about, so leaving
    /// it to the runner's zone would make every failure a timezone question.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let parent = MemberID("a1b2c3d4")!
    private let child = MemberID("e5f6a7b8")!
    private let third = MemberID("00112233")!

    private func day(_ compact: String) -> ScheduleOccurrence {
        guard let day = ScheduleOccurrence(compact: compact) else {
            fatalError("bad test date \(compact)")
        }
        return day
    }

    private func standing(_ member: MemberID, _ compact: String, _ streak: Int) -> MemberStanding {
        MemberStanding(member: member, lastActive: day(compact), streak: streak)
    }

    // MARK: - Who a phone is

    func testAMemberIDIsEightHexCharactersAndNothingElse() {
        // The width is what lets six of them fit on the cheapest tag anyone
        // buys, and the character set is what makes a garbled read a decode
        // failure rather than a seventh member who never goes away.
        XCTAssertNotNil(MemberID("a1b2c3d4"))
        XCTAssertNil(MemberID("a1b2c3d"), "too short")
        XCTAssertNil(MemberID("a1b2c3d4e"), "too long")
        XCTAssertNil(MemberID("A1B2C3D4"), "upper case is a different eight bytes")
        XCTAssertNil(MemberID("hello123"), "not hex")
        XCTAssertNil(MemberID(""))
    }

    func testAFreshIDIsUsable() {
        let fresh = MemberID.fresh()
        XCTAssertNotNil(MemberID(fresh.value), "a generated id must survive its own validator")
        XCTAssertNotEqual(MemberID.fresh().value, MemberID.fresh().value)
    }

    // MARK: - The wire format

    func testAPayloadRoundTrips() {
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260903", 7),
            standing(child, "20260902", 3),
        ])
        let decoded = HouseholdLedger.decoded(ledger.encoded())
        XCTAssertEqual(decoded?.standings, ledger.standings)
    }

    /// The privacy model, made structural rather than promised.
    ///
    /// Anyone who taps this tag with any phone can read what is on it — a
    /// visitor, a stranger, a shop. So the assertion is not "we did not put a
    /// name in", which is a fact about today's fields; it is that the format
    /// has no way to carry one. Add a `String` anybody types to
    /// `MemberStanding` and this test fails before the tag ever reaches a
    /// pocket.
    func testTheTagCannotCarryProse() {
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260903", 7),
            standing(child, "20260902", 3),
            standing(third, "20260901", 41),
        ])
        // Base 36 now, so the whole lower-case alphabet is in the set — and
        // still nothing that can spell a name apart, because the *fields* are
        // fixed width and positional: eight characters of opaque id, three of
        // packed date, three of base-36 streak. There is nowhere for prose to
        // go even though its letters are permitted.
        let permitted = Set("0123456789abcdefghijklmnopqrstuvwxyz,;")
        let payload = ledger.encoded()

        XCTAssertFalse(payload.isEmpty)
        XCTAssertTrue(payload.allSatisfy { permitted.contains($0) },
                      "the wire format must be incapable of carrying a name: \(payload)")
    }

    func testATextRecordThatMerelyStartsWithDIsNotALedger() {
        // The bug this predicate exists to prevent, found by review. All three
        // NFC call sites matched on `"d"` alone, so any text record beginning
        // with that letter — "desk", "dinner", "downstairs", the sort of thing
        // somebody writes with NFC Tools — was treated as a ledger. It was
        // destroyed on the first in-app tap, and if it sat before a real
        // ledger record it was read *as* one: the decode fails, the tag is
        // ignored, and both records are then replaced by this phone's
        // un-merged view. Everyone else's standings, gone.
        XCTAssertFalse(HouseholdLedgerFormat.isOurRecord("desk"))
        XCTAssertFalse(HouseholdLedgerFormat.isOurRecord("dinner"))
        XCTAssertFalse(HouseholdLedgerFormat.isOurRecord(nil))
        XCTAssertFalse(HouseholdLedgerFormat.isOurRecord("d"))
        XCTAssertTrue(HouseholdLedgerFormat.isOurRecord("d2;a1b2c3d4,0rm,007"))
    }

    func testALaterBuildsRecordIsNotOursToReplace() {
        // Version-exact, and the same decision `decoded` makes for the same
        // reason. A record we cannot read is left on the tag rather than
        // overwritten, so a household running two builds carries two records
        // and heals when both update — instead of one build deleting data it
        // could not parse.
        XCTAssertFalse(HouseholdLedgerFormat.isOurRecord("d3;a1b2c3d4,0rm,007"))
        XCTAssertNil(HouseholdLedger.decoded("d3;a1b2c3d4,0rm,007"))
    }

    func testEverythingWeWriteIsSomethingWeWouldRecogniseBack() {
        // The predicate and the encoder are two halves of one rule, so they
        // are asserted against each other rather than each against a literal.
        let ledger = HouseholdLedger(standings: [standing(parent, "20260903", 7)])
        XCTAssertTrue(HouseholdLedgerFormat.isOurRecord(ledger.encoded()))
    }

    func testATagWrittenByALaterBuildIsLeftAlone() {
        // Strict across versions on purpose. A later build's fields cannot be
        // guessed, and half-reading them would write the guess back — losing
        // whatever the other phone actually meant, on the one copy of the data
        // that is shared.
        let future = "d3;a1b2c3d4,0rm,007"
        XCTAssertNil(HouseholdLedger.decoded(future))
        XCTAssertNil(HouseholdLedger.decoded("x2;a1b2c3d4,0rm,007"))
        XCTAssertNil(HouseholdLedger.decoded(""))
        XCTAssertNil(HouseholdLedger.decoded("nonsense"))
    }

    func testOneCorruptMemberDoesNotCostTheOthers() {
        // Lenient *within* a version, following `LenientDecoding`: a single bad
        // field on a shared physical object must not cost the whole household
        // their number.
        let payload = "d2;a1b2c3d4,0rm,007;zzzz,notadate,x;e5f6a7b8,0rl,003"
        let decoded = HouseholdLedger.decoded(payload)

        XCTAssertEqual(decoded?.standings.count, 2)
        XCTAssertEqual(decoded?.standing(for: parent)?.streak, 7)
        XCTAssertEqual(decoded?.standing(for: child)?.streak, 3)
    }

    func testTheSameMemberTwiceOnOneTagIsReadOnce() {
        // Two entries for one member is not a state any phone writes, so a tag
        // holding it has been corrupted or hand-edited. Taking the first and
        // dropping the rest is arbitrary but bounded; merging them would make
        // a member's streak grow by being written badly.
        let decoded = HouseholdLedger.decoded("d2;a1b2c3d4,0rm,007;a1b2c3d4,0rm,0p0")
        XCTAssertEqual(decoded?.standings.count, 1)
        XCTAssertEqual(decoded?.standings.first?.streak, 7)
    }

    func testAnImpossibleDateIsNotAMember() {
        XCTAssertEqual(HouseholdLedger.decoded("d2;a1b2c3d4,zzz,007")?.standings.count, 0,
                       "there is no thirteenth month")
        XCTAssertEqual(HouseholdLedger.decoded("d2;a1b2c3d4,---,007")?.standings.count, 0,
                       "there is no zeroth day")
        XCTAssertEqual(HouseholdLedger.decoded("d2;a1b2c3d4,0rm,-04")?.standings.count, 0,
                       "a negative streak is not a shorter one")
    }

    func testThePayloadFitsOnTheCheapestTag() {
        // The number that matters is not the member cap but the byte budget:
        // an NTAG213 has 144 bytes of user memory and may already hold a URL
        // record. A ledger that fails to write is worse than one carrying four
        // people instead of six.
        let crowded = HouseholdLedger(standings: (0..<12).map {
            standing(MemberID(String(format: "%08x", $0))!, "20260903", 999)
        })
        XCTAssertLessThanOrEqual(crowded.encoded().utf8.count,
                                 HouseholdLedgerFormat.conservativePayload)
    }

    func testAFullHouseholdSurvivesTheRoundTripToTheTag() {
        // The defect this exists to prevent, which a review found and no test
        // could: the cap was six and six did not fit, so `encoded()` quietly
        // dropped one. The writing phone reported six members and every
        // reading phone reported five — and the dropped member is the
        // *stalest*, which is the one whose last-active day decides whether
        // the streak is current. A reader therefore computed a longer, and
        // possibly falsely-current, streak than the writer.
        //
        // Asserted against `encoded()` rather than `trimmed()`, which is what
        // the old test did and why any cap of three or more passed it.
        // Four-digit streaks, which is what a household at the cap looks like
        // after three years. A three-digit assumption held until the day
        // somebody's streak reached a thousand and then dropped a member
        // again, on a date nobody would have connected to it.
        let full = HouseholdLedger(standings: (0..<HouseholdLedgerFormat.maximumMembers).map {
            standing(MemberID(String(format: "%08x", $0))!, "20260903", 9999)
        })

        XCTAssertLessThanOrEqual(full.encoded().utf8.count, HouseholdLedgerFormat.conservativePayload)
        XCTAssertEqual(HouseholdLedger.decoded(full.encoded())?.standings.count,
                       HouseholdLedgerFormat.maximumMembers,
                       "what the writer counts and what the reader counts must be the same number")
    }

    func testTheMemberCapIsArithmeticOnTheByteBudget() {
        // Two numbers that have to agree cannot both be written down. Spelled
        // out here because it is the one place the relationship is visible.
        XCTAssertEqual(HouseholdLedgerFormat.maximumMembers, 7,
                       "seven by default, and more when the tag says it can hold more")
        XCTAssertLessThanOrEqual(
            2 + HouseholdLedgerFormat.maximumMembers * HouseholdLedgerFormat.maximumMemberBytes,
            HouseholdLedgerFormat.conservativePayload)
    }

    func testTheWireCarriesThreeBaseThirtySixDigitsOfStreak() {
        // Spelled out, because every assertion about the clamp refers to it
        // symbolically and the whole suite therefore moves with it. A mutation
        // lowering it to 9 survived: every phone would publish a streak
        // truncated to nine days, and every other phone in the house would
        // compute a short household streak from day ten — a wrong number on a
        // screen, silently.
        //
        // The number is written down in prose in its own doc comment, which is
        // the test CLAUDE.md gives for a literal belonging in a test.
        XCTAssertEqual(HouseholdLedgerFormat.widestStreakOnTheWire, 46_655,
                       "zzz, which is a hundred and twenty-seven years")

        let long = HouseholdLedger(standings: [standing(parent, "20260903", 5_000)])
        XCTAssertEqual(HouseholdLedger.decoded(long.encoded())?.standings.first?.streak, 5_000,
                       "and anything under it is carried exactly")
    }

    func testAStreakTooWideForTheWireIsClampedRatherThanDroppingAMember() {
        // The last door on the cap arithmetic. A five-digit streak makes a
        // member's line 24 bytes, five of them 122, and `encoded()`'s
        // drop-until-it-fits loop then removes somebody — the writer counting
        // a member every reader cannot see, returning twenty-seven years in.
        //
        // Clamping is the lesser lie, and it only ever affects what the tag
        // carries about somebody else: a phone reads its own streak from its
        // own history.
        let ancient = HouseholdLedger(standings: (0..<HouseholdLedgerFormat.maximumMembers).map {
            standing(MemberID(String(format: "%08x", $0))!, "20260903", 100_000)
        })

        XCTAssertLessThanOrEqual(ancient.encoded().utf8.count,
                                 HouseholdLedgerFormat.conservativePayload)
        XCTAssertEqual(HouseholdLedger.decoded(ancient.encoded())?.standings.count,
                       HouseholdLedgerFormat.maximumMembers,
                       "nobody is dropped, however long they have been at it")
        XCTAssertEqual(HouseholdLedger.decoded(ancient.encoded())?.standings.first?.streak,
                       HouseholdLedgerFormat.widestStreakOnTheWire)
    }

    func testASixPersonHouseholdFitsOnTheCheapestTag() {
        // The reason version 2 exists. Five was never a considered number — it
        // was whatever the arithmetic yielded against a budget guessed from
        // the smallest chip on the market, and six is not an unusual family.
        //
        // Six now costs 104 bytes where it used to cost 140, so it fits an
        // NTAG213 with room for a URL record beside it, and fits the NTAG215
        // this project actually recommends many times over.
        let six = HouseholdLedger(standings: (0..<6).map {
            standing(MemberID(String(format: "%08x", $0))!, "20260903", 400)
        })

        XCTAssertLessThanOrEqual(six.encoded().utf8.count, 110)
        XCTAssertEqual(HouseholdLedger.decoded(six.encoded())?.standings.count, 6,
                       "and every one of them survives the round trip")
        XCTAssertTrue(six.encoded(within: 144).dropped.isEmpty)
    }

    func testATagThatCannotHoldEverybodySaysWhoDidNotFit() {
        // Dropping the stalest member silently is the writer-disagrees-with-
        // reader defect this format has produced twice. A household too big
        // for its tag is now told which people did not fit, so somebody can be
        // told to buy a bigger sticker rather than quietly losing a person.
        let eight = HouseholdLedger(standings: (0..<8).map {
            standing(MemberID(String(format: "%08x", $0))!, "20260903", 1)
        })

        let onATinyTag = eight.encoded(within: 60)
        XCTAssertLessThanOrEqual(onATinyTag.payload.utf8.count, 60)
        XCTAssertEqual(onATinyTag.dropped.count, 5, "three fit in sixty bytes; five did not")
        XCTAssertEqual(HouseholdLedger.decoded(onATinyTag.payload)?.standings.count, 3)

        let onARealTag = eight.encoded(within: 500)
        XCTAssertTrue(onARealTag.dropped.isEmpty, "an NTAG215 holds everybody")
        XCTAssertEqual(HouseholdLedger.decoded(onARealTag.payload)?.standings.count, 8)
    }

    func testTheParsedMemberCountIsBoundedWhateverTheTagSays() {
        // A tag is a thing anybody can write anything onto, and a 500-byte
        // chip would otherwise admit thirty members. Not a product limit —
        // sixteen is past any household — but a bound on the work one read can
        // cause.
        let crowd = (0..<40).map { "\(String(format: "%08x", $0)),0rm,001" }.joined(separator: ";")
        XCTAssertEqual(HouseholdLedger.decoded("d2;" + crowd)?.standings.count,
                       HouseholdLedgerFormat.absoluteMaximumMembers)

        // Both ends of the format, because a bound on reading is no bound at
        // all if writing is unbounded. An NTAG216 has 888 bytes, which the
        // arithmetic alone would turn into fifty-two members.
        XCTAssertEqual(HouseholdLedgerFormat.membersThatFit(inPayload: 5_000),
                       HouseholdLedgerFormat.absoluteMaximumMembers)
    }

    func testAPackedDateSurvivesEveryDayItCanExpress() {
        // The packing wastes 372 slots on 365 days so it is reversible by
        // division with no month-length table — a table would be a second copy
        // of a rule the calendar already owns. Walked rather than sampled,
        // because an off-by-one in either direction is a member landing on the
        // wrong day and losing a merge.
        for year in [2024, 2026, 2099, 2124] {
            for month in 1...12 {
                for day in 1...31 {
                    let original = ScheduleOccurrence(year: year, month: month, day: day)
                    let packed = HouseholdLedgerFormat.packed(original)
                    XCTAssertEqual(HouseholdLedgerFormat.unpacked(packed), original,
                                   "\(original) did not survive packing")
                }
            }
        }
        XCTAssertNil(HouseholdLedgerFormat.unpacked(-1))
        XCTAssertNil(HouseholdLedgerFormat.unpacked(46_655),
                     "a wide field decoded as a date four hundred million years out, "
                     + "which sorted as the freshest standing and won every merge")
    }

    func testTheDerivationBitesAtABudgetWhereItMatters() {
        // The whole point of deriving the cap rather than writing it down is
        // that the two stay in step when the budget changes. At today's 120
        // bytes the header term makes no difference — both answers are five —
        // so a mutation deleting it survived. At 115 it decides the answer,
        // and getting it wrong puts five members into a payload that holds
        // four, which is exactly the defect the derivation replaced.
        XCTAssertEqual(HouseholdLedgerFormat.membersThatFit(inPayload: 103), 5)
        XCTAssertEqual(HouseholdLedgerFormat.membersThatFit(inPayload: 121), 7)

        // The header term is two bytes, not three: `recordPrefix` is "d2;"
        // and the ";" belongs to the first member. That distinction gets a
        // paragraph in the source and had nothing under it — a mutation
        // charging the whole prefix survived, because it only bites where the
        // budget lands within a byte of a member boundary, as 119 does.
        XCTAssertEqual(HouseholdLedgerFormat.membersThatFit(inPayload: 119), 6)
        XCTAssertEqual(HouseholdLedgerFormat.membersThatFit(inPayload: 120), 6)

        XCTAssertEqual(HouseholdLedgerFormat.membersThatFit(inPayload: 1), 0,
                       "a budget too small for anybody holds nobody")
    }

    func testTheHeaderIsChargedAgainstTheBudget() {
        // The `- 2` in the derivation is the header, and a mutation removing it
        // survived: at a 120-byte budget both answers are five, so nothing
        // downstream moved. It bites exactly when the derivation is supposed
        // to earn its place — when the budget changes. At 115 the correct cap
        // is four and the mutated one is five, and five members do not fit,
        // which is the original defect walking back in.
        //
        // Asserted as the relationship rather than as a number, because a
        // number here would be the thing the derivation exists to stop.
        let header = HouseholdLedger(standings: []).encoded()
        XCTAssertEqual(header.utf8.count, 2, "the header is two bytes, and they are spent")
        XCTAssertLessThanOrEqual(
            header.utf8.count
                + HouseholdLedgerFormat.maximumMembers * HouseholdLedgerFormat.maximumMemberBytes,
            HouseholdLedgerFormat.conservativePayload)
    }

    func testTheRecordPrefixIncludesItsSeparator() {
        // "the third character, and what matters" — but nothing tested it. A
        // mutation dropping the semicolon survived, because every case in the
        // suite ("d", "desk", "dinner", "d2;…") passes either way. Without it,
        // "d1nner" is read as a ledger and destroyed: the same defect, one
        // character narrower.
        XCTAssertTrue(HouseholdLedgerFormat.recordPrefix.hasSuffix(";"))
        XCTAssertFalse(HouseholdLedgerFormat.isOurRecord("d2nner"))
        XCTAssertFalse(HouseholdLedgerFormat.isOurRecord("d2 kitchen"))
    }

    func testAHouseholdIsCappedAndKeepsTheFreshest() {
        let many = HouseholdLedger(standings: (0..<10).map {
            standing(MemberID(String(format: "%08x", $0))!, "202609\(String(format: "%02d", $0 + 1))", 1)
        })
        let kept = many.merged(with: HouseholdLedger()).trimmed()

        XCTAssertEqual(kept.standings.count, HouseholdLedgerFormat.maximumMembers)
        XCTAssertEqual(kept.standings.first?.lastActive, day("20260910"),
                       "the freshest survives; the tag is not an archive")
    }

    // MARK: - Merging

    func testTheFresherStandingWins() {
        // Only a member's own phone ever writes their standing, so between two
        // copies the later one is the true one and the other is a stale echo
        // off the tag.
        let mine = HouseholdLedger(standings: [standing(parent, "20260903", 7)])
        let tag = HouseholdLedger(standings: [standing(parent, "20260901", 5)])

        XCTAssertEqual(mine.merged(with: tag).standing(for: parent)?.streak, 7)
        XCTAssertEqual(tag.merged(with: mine).standing(for: parent)?.streak, 7,
                       "and it must not depend on which way round the merge ran")
    }

    func testAMemberYouHaveNeverHeardOfIsKept() {
        // What makes a third phone joinable with nothing configured.
        let mine = HouseholdLedger(standings: [standing(parent, "20260903", 7)])
        let tag = HouseholdLedger(standings: [standing(child, "20260902", 3)])

        let merged = mine.merged(with: tag)
        XCTAssertEqual(merged.standings.count, 2)
        XCTAssertNotNil(merged.standing(for: child))
    }

    func testYourOwnPhoneWinsEvenWhenItsNewsIsWorse() {
        // The one place the merge rule is not applied, and the reason it
        // exists: a young person whose streak just broke must not have the
        // tag's older, longer number win it back. `setting` is a phone writing
        // its own standing, where it is the authority.
        let tag = HouseholdLedger(standings: [standing(parent, "20260903", 40)])
        let broken = standing(parent, "20260903", 1)

        XCTAssertEqual(tag.setting(broken).standing(for: parent)?.streak, 1)
        XCTAssertEqual(tag.merged(with: HouseholdLedger(standings: [broken]))
                        .standing(for: parent)?.streak, 40,
                       "the merge rule alone would have handed the streak back")
    }

    // MARK: - The whole exchange, in one function

    func testTheExchangeTakesNewsInBeforeItAssertsItself() {
        // The order is the seam. `merged` first so everyone else's news is
        // taken in, `setting` second so this phone's view of itself wins
        // unconditionally. Reversed, the tag's stale copy of us beats our own
        // history whenever it carries the same day and a longer run — which is
        // exactly the day a streak breaks.
        let known = HouseholdLedger(standings: [standing(parent, "20260903", 2)])
        let tag = "d2;a1b2c3d4,0rm,014;e5f6a7b8,0rl,006"
        let result = known.afterExchange(with: tag, own: standing(parent, "20260903", 2))

        XCTAssertEqual(result.standing(for: parent)?.streak, 2, "our history is the authority on us")
        XCTAssertEqual(result.standing(for: child)?.streak, 6, "and theirs on them")
    }

    func testAnExchangeWithNothingOnTheTagIsJustOurOwnView() {
        let known = HouseholdLedger(standings: [standing(child, "20260902", 6)])
        let result = known.afterExchange(with: nil, own: standing(parent, "20260903", 2))

        XCTAssertEqual(result.standings.count, 2)
        XCTAssertEqual(result.standing(for: parent)?.streak, 2)
    }

    func testAnUnreadableTagLeavesTheExchangeWhereItWas() {
        // Never half-applied: the write-back would otherwise put our guess at
        // the other phone's data onto the one copy that is shared.
        let known = HouseholdLedger(standings: [standing(child, "20260902", 6)])
        XCTAssertEqual(known.afterExchange(with: "d7;nonsense", own: nil).standings,
                       known.standings)
    }

    func testOurOwnStandingIsNeverTheOneDroppedByTheCap() {
        // `setting` puts us at the front, and a mutation appending us instead
        // survived the suite. It should not have: `trimmed` keeps the first
        // `maximumMembers`, so in a household already at the cap the phone
        // writing the tag would drop *itself* — and then read the tag back and
        // conclude it was not a member of its own household.
        //
        // This is the one entry with a claim on the space. Everyone else's
        // standing is news from the tag; ours is the only thing on it that
        // nothing else can supply.
        let others = (0..<HouseholdLedgerFormat.maximumMembers).map {
            standing(MemberID(String(format: "1000000%d", $0))!, "20260903", 9)
        }
        let mine = standing(parent, "20260901", 2)

        let written = HouseholdLedger(standings: others).setting(mine).trimmed()

        XCTAssertEqual(written.standings.count, HouseholdLedgerFormat.maximumMembers)
        XCTAssertNotNil(written.standing(for: parent), "the writer must be on its own tag")
        XCTAssertEqual(HouseholdLedger.decoded(written.encoded())?.standing(for: parent)?.streak, 2)
    }

    func testANegativeStreakIsNotAShorterRunWhenOneIsConstructed() {
        // The clamp guards construction, not decoding: the synthesised decoder
        // does not run this initialiser. What protects the decode paths is
        // separate and already tested — the wire format rejects a negative
        // streak outright, and `HouseholdStreak` clamps whatever the
        // arithmetic produces. This pins the third door.
        XCTAssertEqual(MemberStanding(member: parent, lastActive: day("20260903"),
                                      streak: -4).streak, 0)
    }

    // MARK: - The shared number

    func testTheSharedStreakIsTheOverlap() {
        // Everyone, not anyone. A number that counts the child alone is the
        // number they already have; the point of this feature is to put the
        // parent's phone inside it.
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260903", 7),
            standing(child, "20260903", 3),
        ])
        let streak = ledger.streak(asOf: day("20260903"), calendar: calendar)

        XCTAssertEqual(streak?.days, 3, "the shorter run is the household's")
        XCTAssertEqual(streak?.members, 2)
        XCTAssertEqual(streak?.isCurrent, true)
    }

    func testAnOverlapAcrossAMonthBoundaryIsStillAnOverlap() {
        // The case a hand-rolled day subtraction gets wrong, and it happens to
        // somebody every thirty days.
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260902", 10),
            standing(child, "20260903", 3),
        ])
        // Parent: 23 Aug – 2 Sep. Child: 31 Aug – 3 Sep. Both: 1 and 2 Sep.
        XCTAssertEqual(ledger.streak(asOf: day("20260903"), calendar: calendar)?.days, 2)
    }

    func testOnePersonBeingBehindEndsTheSharedRun() {
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260820", 30),
            standing(child, "20260903", 3),
        ])
        let streak = ledger.streak(asOf: day("20260903"), calendar: calendar)

        XCTAssertEqual(streak?.days, 0)
        XCTAssertEqual(streak?.isCurrent, false)
    }

    func testAMemberWithNoStreakAtAllEndsIt() {
        // A member seen but not Dadding is not a member excluded from the
        // count. Skipping them is exactly how a "household" streak becomes one
        // person's streak with extra words on it.
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260903", 7),
            standing(child, "20260903", 0),
        ])
        XCTAssertEqual(ledger.streak(asOf: day("20260903"), calendar: calendar)?.days, 0)
    }

    func testYesterdayIsStillCurrentAndTheDayBeforeIsNot() {
        // The same forgiveness `DadStats.currentStreak` gives one phone: today
        // is not over, so a run ending yesterday has not been broken.
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260902", 7),
            standing(child, "20260902", 7),
        ])
        XCTAssertEqual(ledger.streak(asOf: day("20260903"), calendar: calendar)?.isCurrent, true)
        XCTAssertEqual(ledger.streak(asOf: day("20260903"), calendar: calendar)?.days, 7)

        XCTAssertEqual(ledger.streak(asOf: day("20260904"), calendar: calendar)?.isCurrent, false,
                       "by the day after, the run is history")
        XCTAssertEqual(ledger.streak(asOf: day("20260904"), calendar: calendar)?.days, 0,
                       "and history is not reported as a live number")
    }

    func testANegativeRunIsNotAShorterOne() {
        // The clamp lives on the value rather than at the one call site that
        // computes it, because that is where a test can reach it. An overlap
        // of nothing computes to a negative number, and a negative number that
        // reaches a screen gets formatted and shown.
        XCTAssertEqual(HouseholdStreak(days: -11, members: 2, asOf: nil, isCurrent: true).days, 0)
    }

    func testAnEmptyRunOnAFreshTagIsNotAStaleOne() {
        // "Everyone is up to date and the shared run is nought" has to be
        // sayable. Folding it into "not current" would put a go-and-tap-the-tag
        // note in front of a household whose tag is perfectly current.
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260903", 4),
            standing(child, "20260903", 0),
        ])
        let streak = ledger.streak(asOf: day("20260903"), calendar: calendar)

        XCTAssertEqual(streak?.days, 0)
        XCTAssertEqual(streak?.isCurrent, true)
    }

    func testAHouseholdOfOneHasNoSharedStreak() {
        // A shared streak with one member is that member's own streak wearing
        // a different hat, and showing it would be the product claiming a
        // thing it has not got.
        let alone = HouseholdLedger(standings: [standing(parent, "20260903", 7)])
        XCTAssertNil(alone.streak(asOf: day("20260903"), calendar: calendar))
        XCTAssertNil(HouseholdLedger().streak(asOf: day("20260903"), calendar: calendar))
    }

    func testTheNumberSaysHowFreshItIs() {
        // The failure this feature can produce is a stale number shown as a
        // live one, and it is invisible at the call site if the call site is
        // the thing that has to remember. So `asOf` travels with `days`.
        let ledger = HouseholdLedger(standings: [
            standing(parent, "20260903", 7),
            standing(child, "20260901", 7),
        ])
        XCTAssertEqual(ledger.streak(asOf: day("20260903"), calendar: calendar)?.asOf,
                       day("20260903"))
        XCTAssertNil(HouseholdLedger().lastActiveDay)
    }

    // MARK: - Days

    func testDayArithmeticCrossesMonthsAndYears() {
        XCTAssertEqual(day("20260101").dayNumber(in: calendar)! - day("20251231").dayNumber(in: calendar)!, 1)
        XCTAssertEqual(day("20240301").dayNumber(in: calendar)! - day("20240229").dayNumber(in: calendar)!, 1,
                       "2024 is a leap year")
        XCTAssertEqual(day("20260301").dayNumber(in: calendar)! - day("20260228").dayNumber(in: calendar)!, 1,
                       "2026 is not")
    }

    func testTheOverlapSurvivesADaylightSavingChange() {
        // London puts the clocks back on 25 October 2026. A day is 25 hours
        // long that week, so anything counting in seconds loses or gains one.
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!

        let ledger = HouseholdLedger(standings: [
            standing(parent, "20261027", 5),
            standing(child, "20261027", 5),
        ])
        XCTAssertEqual(ledger.streak(asOf: day("20261027"), calendar: london)?.days, 5)
    }
}
