import XCTest
@testable import DadCore

/// The ladder is a set of promises to a teenager, so the tests are mostly
/// about the promises rather than the arithmetic: a rung is never skipped, a
/// rung is never silently lost, a bad night costs nothing, and every number
/// the screen shows is available before the rung is reached.
final class AutonomyLadderTests: XCTestCase {

    /// Pinned to UTC. Every quantity here is a count of days, so a runner in
    /// another time zone would otherwise shift the boundaries under the tests.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_756_000_000) // 2025-08-24 02:26 UTC

    private func startOfDay(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
    }

    /// A finished session starting at midday, `daysAgo` days before `now`.
    private func session(daysAgo: Int,
                         minutes: Double = 60,
                         emergency: Bool = false) -> DadSession {
        let start = startOfDay(daysAgo).addingTimeInterval(12 * 3600)
        return DadSession(modeID: UUID(),
                          modeName: "Deep Work",
                          startedAt: start,
                          endedAt: start.addingTimeInterval(minutes * 60),
                          endedByEmergency: emergency)
    }

    /// One session on each of the given day offsets.
    private func days(_ offsets: [Int], emergency: Bool = false) -> [DadSession] {
        offsets.map { session(daysAgo: $0, emergency: emergency) }
    }

    /// `count` consecutive days, the most recent of them `endingDaysAgo` days
    /// back. `run(15, endingDaysAgo: 0)` is a fortnight-and-a-day up to today.
    private func run(_ count: Int, endingDaysAgo: Int = 0) -> [DadSession] {
        days(Array(endingDaysAgo..<(endingDaysAgo + count)))
    }

    private func ladder(_ sessions: [DadSession], at moment: Date? = nil) -> AutonomyLadder {
        AutonomyLadder(sessions: sessions, now: moment ?? now, calendar: calendar)
    }

    // MARK: - The bottom of the ladder

    func testAnEmptyHistoryStartsAtTheBottomRungAndDividesNothingByZero() {
        let l = ladder([])
        XCTAssertEqual(l.level, 0)
        XCTAssertEqual(l.rung, .gettingStarted)
        XCTAssertEqual(l.cleanDayCount, 0)
        XCTAssertEqual(l.longestCleanStreak, 0)
        XCTAssertEqual(l.currentCleanStreak, 0)
        XCTAssertNil(l.daysSinceLastSession)
        XCTAssertEqual(l.demotionWarning, .none)
        XCTAssertEqual(l.progress(toward: .gettingStarted).fraction, 1)
    }

    func testTheBottomRungIsNotAnEmptyStateAndAlreadyUnlocksSomething() {
        // "Looks configured and does nothing" is the failure mode; level 0
        // still says what you can do, and it is more than nothing.
        XCTAssertFalse(AutonomyLadder.Rung.gettingStarted.unlocks.isEmpty)
    }

    func testYouCannotLapseFromAHabitYouNeverStarted() {
        // No sessions at all, months into the history: nothing to withhold and
        // nothing to warn about.
        let l = ladder([])
        XCTAssertEqual(l.withheldRungs, 0)
        XCTAssertFalse(l.isWithheld)
        XCTAssertEqual(l.demotionWarning, .none)
    }

    // MARK: - What each rung costs

    func testTheFirstRungNeedsFiveCleanDaysAndAThreeDayRun() {
        XCTAssertEqual(AutonomyLadder.Rung.trusted.requirement,
                       AutonomyLadder.Requirement(cleanDays: 5, cleanStreak: 3))

        let almost = ladder(run(4))
        XCTAssertEqual(almost.level, 0)
        XCTAssertEqual(almost.progressToNextRung?.cleanDaysRemaining, 1)
        XCTAssertEqual(almost.progressToNextRung?.cleanStreakRemaining, 0)

        XCTAssertEqual(ladder(run(5)).rung, .trusted)
    }

    func testEveryRungHasItsOwnPriceAndTheyOnlyGoUp() {
        let requirements = AutonomyLadder.Rung.allCases.map(\.requirement)
        for (lower, higher) in zip(requirements, requirements.dropFirst()) {
            XCTAssertLessThan(lower.cleanDays, higher.cleanDays)
            XCTAssertLessThan(lower.cleanStreak, higher.cleanStreak)
        }
    }

    func testScatteredDaysDoNotBuyARungWithoutARun() {
        // Five clean days, none of them next to another. The total is there;
        // the habit is not, and the streak criterion is what notices.
        let l = ladder(days([0, 4, 8, 12, 16]))
        XCTAssertEqual(l.cleanDayCount, 5)
        XCTAssertEqual(l.longestCleanStreak, 1)
        XCTAssertEqual(l.level, 0)
        XCTAssertEqual(l.progressToNextRung?.cleanDaysRemaining, 0)
        XCTAssertEqual(l.progressToNextRung?.cleanStreakRemaining, 2)
    }

    func testARunWithoutTheTotalDoesNotBuyTheRungEither() {
        // The mirror image: a four-day burst clears no rung, because one good
        // week is not the thing being rewarded.
        let l = ladder(run(4))
        XCTAssertEqual(l.longestCleanStreak, 4)
        XCTAssertEqual(l.level, 0)
    }

    func testTheLadderIsClimbedOneRungAtATime() {
        // Consecutive clean days, one more each time. The level must never
        // jump two rungs, or someone crosses a threshold and is handed a
        // capability they were never shown the price of.
        var previous = 0
        for count in 0...61 {
            let level = ladder(run(count)).level
            XCTAssertGreaterThanOrEqual(level, previous, "\(count) days lowered the level")
            XCTAssertLessThanOrEqual(level - previous, 1, "\(count) days skipped a rung")
            previous = level
        }
        XCTAssertEqual(previous, 4, "61 clean days should reach the top rung")
    }

    // MARK: - The ratchet

    func testAddingHistoryCanNeverLowerTheEarnedRung() {
        // The structural claim: earning reads only counts and high-water
        // marks, so no session anyone adds — including a bail — can take a
        // rung away. Walked chronologically over a deliberately messy history.
        var history: [DadSession] = []
        var previous = 0
        for daysAgo in stride(from: 89, through: 0, by: -1) {
            // Every fifth day bailed, and a nine-day hole in the middle.
            if (40...48).contains(daysAgo) { continue }
            history.append(session(daysAgo: daysAgo, emergency: daysAgo % 5 == 0))
            let earned = ladder(history).earnedRung.rawValue
            XCTAssertGreaterThanOrEqual(earned, previous,
                                        "adding the session \(daysAgo) days ago lowered the earned rung")
            previous = earned
        }
        XCTAssertGreaterThan(previous, 0)
    }

    func testEarningNeverLooksAtTheClock() {
        // Same history, read a year later. Time alone must not promote or
        // demote anyone — only a lapse can, and that is `withheldRungs`.
        let history = run(20, endingDaysAgo: 5)
        let later = now.addingTimeInterval(365 * 24 * 3600)
        XCTAssertEqual(ladder(history).earnedRung, ladder(history, at: later).earnedRung)
    }

    func testTheRequirementReadsTheLongestRunEverNotTheCurrentOne() {
        // Fifteen days in a row a fortnight ago, then one session yesterday.
        // The current streak is 1. Gating on it would take Self-scheduling
        // away for the crime of missing a Tuesday, which is the exact silent
        // drop this type exists to prevent.
        let l = ladder(run(15, endingDaysAgo: 10) + days([1]))
        XCTAssertEqual(l.currentCleanStreak, 1)
        XCTAssertEqual(l.longestCleanStreak, 15)
        XCTAssertEqual(l.rung, .selfScheduling)
        XCTAssertEqual(l.demotionWarning, .none)
    }

    // MARK: - A bad night costs nothing

    func testAnEmergencyBailNeverCostsARung() {
        let earned = ladder(run(16, endingDaysAgo: 1))
        XCTAssertEqual(earned.rung, .selfScheduling)

        let bailedToday = ladder(run(16, endingDaysAgo: 1) + days([0], emergency: true))
        XCTAssertEqual(bailedToday.rung, .selfScheduling)
        XCTAssertEqual(bailedToday.withheldRungs, 0)
        XCTAssertEqual(bailedToday.demotionWarning, .none)
    }

    func testABailIsStillEngagementAndStopsTheLapseClock() {
        // Thirteen days of nothing, then a session that ended on the emergency
        // button. It earns nothing, but it does mean you weren't away, and the
        // fortnight starts again rather than running out tomorrow.
        let bailed = ladder(run(15, endingDaysAgo: 13) + days([0], emergency: true))
        XCTAssertEqual(bailed.daysSinceLastSession, 0)
        XCTAssertEqual(bailed.withheldRungs, 0)
        XCTAssertEqual(bailed.demotionWarning, .none)

        // Without it, the same history is one day from costing a rung, and a
        // day later it has.
        XCTAssertEqual(ladder(run(15, endingDaysAgo: 13)).demotionWarning,
                       .approaching(rung: .selfScheduling, inDays: 1))
        XCTAssertEqual(ladder(run(15, endingDaysAgo: 14)).withheldRungs, 1)
    }

    func testABailStopsTheClockButDoesNotRebuildARungAlreadySetAside() {
        // Rebuilding is counted in clean days, deliberately. Coming back and
        // bailing means the lapse is over and nothing further will be set
        // aside, but the rung that already went is still waiting on the habit.
        let l = ladder(run(15, endingDaysAgo: 14) + days([0], emergency: true))
        XCTAssertEqual(l.daysSinceLastSession, 0)
        XCTAssertEqual(l.withheldRungs, 1)
        XCTAssertEqual(l.cleanDaysUntilARungIsRestored, 3)
    }

    func testADayWithBothACleanFinishAndABailStillCountsAsClean() {
        var history = run(4, endingDaysAgo: 1)
        history += days([0])                      // clean
        history += days([0], emergency: true)     // and a bail the same day
        let l = ladder(history)
        XCTAssertEqual(l.cleanDayCount, 5)
        XCTAssertEqual(l.rung, .trusted)
    }

    func testAnInFlightSessionIsIgnoredUntilItEnds() {
        // No outcome yet, so it can't be counted clean; counting it would let
        // a rung appear mid-session and disappear when it ended badly.
        let running = DadSession(modeID: UUID(), modeName: "Sleep",
                                 startedAt: startOfDay(0), endedAt: nil)
        let l = ladder(run(4, endingDaysAgo: 1) + [running])
        XCTAssertEqual(l.cleanDayCount, 4)
        XCTAssertEqual(l.level, 0)
    }

    // MARK: - Day boundaries

    func testASessionCrossingMidnightCreditsTheDayItStarted() {
        // 23:30 yesterday to 00:30 today, exactly as `DadStats` counts it.
        let start = startOfDay(1).addingTimeInterval(23.5 * 3600)
        let overnight = DadSession(modeID: UUID(), modeName: "Sleep",
                                   startedAt: start,
                                   endedAt: start.addingTimeInterval(3600))
        let l = ladder(run(4, endingDaysAgo: 2) + [overnight])
        XCTAssertEqual(l.cleanDayCount, 5, "credited to yesterday, not today")
        XCTAssertEqual(l.longestCleanStreak, 5)
        XCTAssertEqual(l.rung, .trusted)
    }

    func testDayBoundariesFollowTheInjectedCalendarAndNotUTC() {
        // Two sessions ninety minutes apart across a UTC midnight. In UTC that
        // is two clean days; two time zones west it is one evening. Which is
        // right depends entirely on where the household is, which is why the
        // calendar is injected rather than assumed.
        let late = startOfDay(2).addingTimeInterval(23.5 * 3600)
        let justAfter = startOfDay(1).addingTimeInterval(0.5 * 3600)
        let pair = [late, justAfter].map {
            DadSession(modeID: UUID(), modeName: "Dinner",
                       startedAt: $0, endedAt: $0.addingTimeInterval(1800))
        }

        var west = Calendar(identifier: .gregorian)
        west.timeZone = TimeZone(secondsFromGMT: -2 * 3600)!

        XCTAssertEqual(AutonomyLadder(sessions: pair, now: now, calendar: calendar).cleanDayCount, 2)
        XCTAssertEqual(AutonomyLadder(sessions: pair, now: now, calendar: west).cleanDayCount, 1)
    }

    func testAFutureDatedSessionDoesNotReadAsANegativeLapse() {
        // A restored backup or a clock that moved backwards. Clamped, because
        // a negative lapse would otherwise divide into a negative number of
        // withheld rungs and hand out autonomy.
        let l = ladder(run(20, endingDaysAgo: 0) + days([-3]))
        XCTAssertEqual(l.daysSinceLastSession, 0)
        XCTAssertEqual(l.withheldRungs, 0)
    }

    // MARK: - Demotion: slow, warned, and reversible

    func testThirteenDaysAwayCostsNothing() {
        // One bad fortnight-minus-a-day is not a demotion. The grace period is
        // the whole point: a level that goes overnight is one nobody plays for.
        let l = ladder(run(30, endingDaysAgo: 13))
        XCTAssertEqual(l.earnedRung, .selfGoverning)
        XCTAssertEqual(l.rung, .selfGoverning)
        XCTAssertEqual(l.withheldRungs, 0)
    }

    func testItWarnsBeforeARungGoesRatherThanAfter() {
        for (daysAway, warningDays) in [(11, 3), (12, 2), (13, 1)] {
            let l = ladder(run(30, endingDaysAgo: daysAway))
            XCTAssertEqual(l.demotionWarning,
                           .approaching(rung: .selfGoverning, inDays: warningDays),
                           "\(daysAway) days away should warn \(warningDays) days out")
        }
        // Four days out is too early to nag.
        XCTAssertEqual(ladder(run(30, endingDaysAgo: 10)).demotionWarning, .none)
    }

    func testAFortnightAwayCostsExactlyOneRung() {
        let l = ladder(run(30, endingDaysAgo: 14))
        XCTAssertEqual(l.earnedRung, .selfGoverning)
        XCTAssertEqual(l.rung, .selfScheduling)
        XCTAssertEqual(l.withheldRungs, 1)
        XCTAssertTrue(l.isWithheld)
        XCTAssertEqual(l.demotionWarning, .withheld(rung: .selfGoverning, cleanDays: 3))
    }

    func testAMonthAwayCostsTwoRungsAndNotEverything() {
        // Sustained regression costs more than one lapse, but the ladder still
        // comes down a rung at a time rather than resetting to zero.
        let l = ladder(run(30, endingDaysAgo: 28))
        XCTAssertEqual(l.earnedRung, .selfGoverning)
        XCTAssertEqual(l.withheldRungs, 2)
        XCTAssertEqual(l.rung, .trusted)
    }

    func testALapseNeverTakesYouBelowTheBottomRung() {
        let l = ladder(run(5, endingDaysAgo: 90))
        XCTAssertEqual(l.earnedRung, .trusted)
        XCTAssertEqual(l.withheldRungs, 1, "capped at what was earned, not at 90/14")
        XCTAssertEqual(l.level, 0)
        XCTAssertEqual(l.demotionWarning, .withheld(rung: .trusted, cleanDays: 3))
    }

    func testComingBackForOneDayDoesNotHandTheRungStraightBack() {
        // The lapse is over — the clock has stopped — but a single tap is not
        // the rebuild. Two more clean days to go, and the app can say so.
        let l = ladder(run(15, endingDaysAgo: 20) + days([0]))
        XCTAssertEqual(l.earnedRung, .selfScheduling)
        XCTAssertEqual(l.daysSinceLastSession, 0)
        XCTAssertEqual(l.withheldRungs, 1)
        XCTAssertEqual(l.rung, .trusted)
        XCTAssertEqual(l.cleanDaysUntilARungIsRestored, 2)
    }

    func testThreeCleanDaysBackRestoreTheRung() {
        let l = ladder(run(15, endingDaysAgo: 20) + days([2, 1, 0]))
        XCTAssertEqual(l.withheldRungs, 0)
        XCTAssertEqual(l.rung, .selfScheduling)
        XCTAssertNil(l.cleanDaysUntilARungIsRestored)
        XCTAssertEqual(l.demotionWarning, .none)
    }

    func testDuringALapseTheRestorationCountIsTheFullRebuildNotAPartialOne() {
        // Still away. Reporting "1 clean day to go" here would tick downward
        // while the situation was getting worse.
        let l = ladder(run(30, endingDaysAgo: 16))
        XCTAssertEqual(l.cleanDaysUntilARungIsRestored, AutonomyLadder.restoreDays)
    }

    func testTwoOrdinaryLapsesDoNotCompoundIntoADeeperHole() {
        // Lapsed, rebuilt fully, lapsed again. The user is in one hole, not
        // two; summing the two counts would produce a demotion nobody could
        // account for from the screen.
        let l = ladder(run(30, endingDaysAgo: 60) + run(6, endingDaysAgo: 20))
        XCTAssertEqual(l.earnedRung, .selfGoverning)
        XCTAssertEqual(l.withheldRungs, 1, "20 days away is one lapse, not one plus the old one")
    }

    func testTheWithheldRungIsTheOneAboveWhereYouAreStanding() {
        let l = ladder(run(30, endingDaysAgo: 14))
        XCTAssertEqual(l.nextRung, .selfGoverning, "the rung you lost, not one you never had")
        XCTAssertEqual(l.progressToNextRung?.isMet, true,
                       "the history did buy it — restoration is reported by demotionWarning")
    }

    // MARK: - Legibility

    func testProgressSaysExactlyWhatIsStillOutstanding() {
        let l = ladder(run(9))
        let next = l.progressToNextRung
        XCTAssertEqual(l.rung, .trusted)
        XCTAssertEqual(next?.rung, .selfScheduling)
        XCTAssertEqual(next?.requirement, AutonomyLadder.Requirement(cleanDays: 15, cleanStreak: 7))
        XCTAssertEqual(next?.cleanDays, 9)
        XCTAssertEqual(next?.cleanStreak, 9)
        XCTAssertEqual(next?.cleanDaysRemaining, 6)
        XCTAssertEqual(next?.cleanStreakRemaining, 0)
        XCTAssertEqual(next?.isMet, false)
    }

    func testProgressFractionTracksTheBindingConstraintNotTheAverage() {
        // Thirty clean days, never two in a row. Averaging the two ratios
        // would draw the bar past half full for someone who has not moved the
        // thing actually standing in their way.
        let scattered = days(Array(stride(from: 0, through: 87, by: 3)))
        let l = ladder(scattered)
        XCTAssertEqual(l.cleanDayCount, 30)
        XCTAssertEqual(l.longestCleanStreak, 1)
        XCTAssertEqual(l.progress(toward: .trusted).fraction, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testThereIsNothingLeftToClimbAtTheTop() {
        let l = ladder(run(61))
        XCTAssertEqual(l.rung, .keeperOfTheTag)
        XCTAssertNil(l.nextRung)
        XCTAssertNil(l.progressToNextRung)
    }

    func testLevelIsTheRungRawValueSoAnIntIsEnoughToAskThePermissionQuestion() {
        XCTAssertEqual(ladder([]).level, 0)
        XCTAssertEqual(ladder(run(5)).level, AutonomyLadder.Rung.trusted.rawValue)
        XCTAssertEqual(ladder(run(61)).level, 4)
    }

    // MARK: - The rungs themselves

    func testCapabilitiesAreCumulativeAndNeverTakenBackHigherUp() {
        var seen = (edit: false, sleep: false, create: false, tag: false)
        for rung in AutonomyLadder.Rung.allCases {
            if seen.edit   { XCTAssertTrue(rung.canEditModeApps, "\(rung) took back editing") }
            if seen.sleep  { XCTAssertTrue(rung.canSetOwnSleepWindow, "\(rung) took back the Sleep window") }
            if seen.create { XCTAssertTrue(rung.canCreateModes, "\(rung) took back Mode creation") }
            if seen.tag    { XCTAssertTrue(rung.keepsTheTag, "\(rung) took back the tag") }
            seen = (rung.canEditModeApps, rung.canSetOwnSleepWindow,
                    rung.canCreateModes, rung.keepsTheTag)
        }
        XCTAssertTrue(seen.tag, "the top rung should hold everything")
        XCTAssertFalse(AutonomyLadder.Rung.gettingStarted.canEditModeApps)
    }

    func testEachRungUnlocksSomethingItsPredecessorDidNot() {
        // A rung that grants nothing new is a state that looks configured and
        // does nothing — the thing this codebase refuses to ship.
        for rung in AutonomyLadder.Rung.allCases {
            XCTAssertFalse(rung.unlocks.isEmpty, "\(rung) unlocks nothing")
            XCTAssertFalse(rung.title.isEmpty)
        }
    }

    func testNoRungEverPaysInScreenTime() {
        // The research finding, pinned. Paying for good behaviour in minutes
        // makes screens the thing worth working for and turns cooperation into
        // negotiation. Earned minutes are the currency Dad must not mint, and
        // this is the test that fails when someone tries.
        let banned = ["minute", "screen time", "extra time", "more time", "bonus time"]
        for rung in AutonomyLadder.Rung.allCases {
            for line in rung.unlocks {
                for phrase in banned {
                    XCTAssertFalse(line.lowercased().contains(phrase),
                                   "\(rung) unlocks screen time: \(line)")
                }
            }
        }
    }

    func testTheEmergencyAllowanceWidensOnlyNearTheTopAndBuildsOnTheRealBase() {
        XCTAssertEqual(AutonomyLadder.Rung.gettingStarted.extraEmergencyOverrides, 0)
        XCTAssertEqual(AutonomyLadder.Rung.trusted.extraEmergencyOverrides, 0)
        XCTAssertEqual(AutonomyLadder.Rung.selfScheduling.extraEmergencyOverrides, 0)
        XCTAssertEqual(AutonomyLadder.Rung.selfGoverning.extraEmergencyOverrides, 2)

        // Reads `EmergencyAllowance` rather than restating five, so the two
        // can never disagree about what the base allowance is.
        XCTAssertEqual(AutonomyLadder.Rung.gettingStarted.emergencyAllowance,
                       EmergencyAllowance.perWindow)
        XCTAssertEqual(AutonomyLadder.Rung.keeperOfTheTag.emergencyAllowance,
                       EmergencyAllowance.perWindow + 3)
    }

    func testALevelThisBuildCannotUnderstandFailsClosedInBothFiles() {
        // This used to clamp upward — a level from a newer build read as the
        // top rung this build knows — which is the generous-looking answer and
        // was wrong. `RolePermissions` normalises the same number *downward*,
        // so the two disagreed: the app displayed "Keeper of the Dad tag"
        // while granting no capability at all. One normalisation now, failing
        // closed, and the store's existing newer-build banner is what explains
        // it to the person holding the phone.
        XCTAssertEqual(AutonomyLadder.Rung(autonomyLevel: 99), .gettingStarted)
        XCTAssertEqual(AutonomyLadder.Rung(autonomyLevel: -4), .gettingStarted)
        XCTAssertEqual(AutonomyLadder.Rung(autonomyLevel: 2), .selfScheduling)
        XCTAssertEqual(AutonomyLadder.Rung(autonomyLevel: 99).rawValue,
                       RolePermissions.normalisedLevel(99))
    }

    /// The bug that made all of this necessary, as a test.
    func testTheLadderAndThePermissionTableAgreeOnHowManyRungsThereAre() {
        // They did not, and nothing said so. The ladder ran 0…4 and the
        // permission table capped at 3, so a young person who reached the top
        // — the whole point of the product, "the tag lives in your room" —
        // hit a level `RolePermissions` treated as unreadable and collapsed to
        // *zero* capabilities. The reward path was the one thing that broke,
        // and it broke silently, in the direction nobody tests.
        XCTAssertEqual(AutonomyLadder.Rung.allCases.count - 1,
                       RolePermissions.maxAutonomyLevel)
    }

    func testEveryRungTheLadderCanProduceBuysSomethingTheOneBelowDidNot() {
        // The promise the ladder makes, checked end to end rather than rung by
        // rung: climbing must never be lateral and must never go backwards.
        var previous = Set<HouseholdCapability>()
        for rung in AutonomyLadder.Rung.allCases {
            let allowed = Set(HouseholdCapability.allCases.filter {
                RolePermissions.for(role: .youngPerson, autonomyLevel: rung.rawValue).may($0)
            })
            XCTAssertTrue(previous.isSubset(of: allowed),
                          "\(rung.title) took something away")
            if rung != .gettingStarted {
                XCTAssertGreaterThan(allowed.count, previous.count,
                                     "\(rung.title) unlocks nothing")
            }
            previous = allowed
        }
    }

    func testTheTopRungIsWhereTheTagIs() {
        // The ladder's last rung is titled for a permission, and this is the
        // assertion that keeps the title honest.
        XCTAssertEqual(RolePermissions.minimumAutonomyLevel(for: .unpairTag),
                       AutonomyLadder.Rung.keeperOfTheTag.rawValue)
    }

    func testRungsCompareInLadderOrder() {
        XCTAssertLessThan(AutonomyLadder.Rung.gettingStarted, AutonomyLadder.Rung.trusted)
        XCTAssertLessThan(AutonomyLadder.Rung.selfScheduling, AutonomyLadder.Rung.keeperOfTheTag)
        XCTAssertEqual(AutonomyLadder.Rung.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
    }

    func testTheCopyUsesTheVerbAsDeclared() {
        // Vocabulary rule: the verb is never lowercased. These strings go
        // straight onto the ladder screen.
        for rung in AutonomyLadder.Rung.allCases {
            for line in rung.unlocks + [rung.title] {
                XCTAssertFalse(line.contains("dad"), "lowercase verb in: \(line)")
            }
        }
    }
}
