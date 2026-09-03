import XCTest
@testable import DadCore

/// The parts of a weekly review that go quietly wrong are the same ones that
/// have bitten this repo before — week starts, midnight, a percentage against
/// a baseline that isn't there — so those get the most attention here.
///
/// Everything is pinned: a UTC calendar with an explicit `firstWeekday`, and a
/// fixed `now`. A review whose week boundary depends on the machine running
/// the suite is a review whose tests pass in London and fail in Auckland.
final class WeeklyReviewTests: XCTestCase {

    /// UTC, week starting Monday. `firstWeekday` is set explicitly rather than
    /// left at the Gregorian default (Sunday), because the whole point of
    /// injecting the calendar is that this is a decision, not an accident.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    /// Sunday 2025-08-24, 02:26 UTC — the *last* day of a Monday-start week,
    /// so unless a test says otherwise every day of "this week" has already
    /// happened and `hasHappened` cannot mask a bug.
    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: now)!.start
    }

    // MARK: - Builders

    /// An instant `dayOffset` days into the week `weeksAgo` weeks back.
    private func start(weeksAgo: Int = 0, day dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: weekStart)!
        let day = calendar.date(byAdding: .day, value: dayOffset, to: base)!
        return calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private func session(_ startedAt: Date,
                         minutes: Double = 60,
                         modeID: UUID = deepWork,
                         modeName: String = "Deep Work",
                         emergency: Bool = false) -> DadSession {
        DadSession(modeID: modeID,
                   modeName: modeName,
                   startedAt: startedAt,
                   endedAt: startedAt.addingTimeInterval(minutes * 60),
                   endedByEmergency: emergency)
    }

    private static let deepWork = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
    private static let sleep    = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
    private static let dinner   = UUID(uuidString: "00000000-0000-0000-0000-0000000000D3")!

    private func review(_ sessions: [DadSession], at moment: Date? = nil) -> WeeklyReview {
        WeeklyReview(sessions: sessions, now: moment ?? now, calendar: calendar)
    }

    /// 20:00 on the Tuesday of this week — two days elapsed, five still to come.
    private var midweek: Date { start(day: 1, hour: 20) }

    // MARK: - Enough to say anything

    func testAnEmptyHistoryAdmitsItHasNothingToSayInsteadOfDrawingAChart() {
        let r = review([])
        XCTAssertEqual(r.adequacy, .nothingYet)
        XCTAssertFalse(r.adequacy.isEnoughToSaySomething)
        XCTAssertEqual(r.totalThisWeek, 0)
        XCTAssertEqual(r.sessionCountThisWeek, 0)
        XCTAssertTrue(r.timeByMode.isEmpty)
        XCTAssertNil(r.busiestPartOfDay)
        XCTAssertEqual(r.dayContrast, .notEnoughDays(activeDays: 0))
        XCTAssertEqual(r.comparison, .noBaseline(thisWeek: 0))
        XCTAssertNil(r.comparison.fraction)
        XCTAssertEqual(r.daysTheAllowanceRanOutCount, 0)
        XCTAssertEqual(r.headline, "No Dad sessions this week.")
    }

    func testEvenAnEmptyWeekStillHasSevenDayRowsSoTheChartKeepsItsShape() {
        let r = review([])
        XCTAssertEqual(r.days.count, 7)
        XCTAssertEqual(r.days.map(\.total), Array(repeating: 0, count: 7))
        XCTAssertEqual(r.timeOfDay.count, 4)
    }

    func testOneDayOfDataIsNotEnoughToSaySomething() {
        let r = review([session(start(day: 2, hour: 9), minutes: 30),
                        session(start(day: 2, hour: 19), minutes: 45)])
        XCTAssertEqual(r.adequacy, .oneDayOnly(sessions: 2))
        XCTAssertFalse(r.adequacy.isEnoughToSaySomething)
        XCTAssertEqual(r.dayContrast, .notEnoughDays(activeDays: 1),
                       "one day cannot be both the busiest and the quietest")
    }

    func testTwoDaysWithSomethingOnThemIsEnoughToSaySomething() {
        let r = review([session(start(day: 0, hour: 9)),
                        session(start(day: 3, hour: 9))])
        XCTAssertEqual(r.adequacy, .enough(days: 2, sessions: 2))
        XCTAssertTrue(r.adequacy.isEnoughToSaySomething)
    }

    func testAnInFlightSessionIsLeftOutSoTheWeekDoesNotCreepWhileYouLookAtIt() {
        let running = DadSession(modeID: Self.deepWork, modeName: "Deep Work",
                                 startedAt: start(day: 6, hour: 1), endedAt: nil)
        let r = review([session(start(day: 0, hour: 9), minutes: 30), running])
        XCTAssertEqual(r.sessionCountThisWeek, 1)
        XCTAssertEqual(r.totalThisWeek, 30 * 60)
    }

    // MARK: - Per Mode

    func testTimeByModeIsRankedWithTheBiggestFirst() {
        let r = review([session(start(day: 0, hour: 9), minutes: 30, modeID: Self.dinner, modeName: "Dinner"),
                        session(start(day: 1, hour: 22), minutes: 480, modeID: Self.sleep, modeName: "Sleep"),
                        session(start(day: 2, hour: 9), minutes: 90)])
        XCTAssertEqual(r.timeByMode.map(\.modeName), ["Sleep", "Deep Work", "Dinner"])
        XCTAssertEqual(r.timeByMode.first?.total, 480 * 60)
    }

    func testTimeByModeSumsARepeatedModeIntoOneRow() {
        let r = review([session(start(day: 0, hour: 9), minutes: 30),
                        session(start(day: 0, hour: 14), minutes: 45),
                        session(start(day: 2, hour: 9), minutes: 15)])
        XCTAssertEqual(r.timeByMode.count, 1)
        XCTAssertEqual(r.timeByMode[0].total, 90 * 60)
        XCTAssertEqual(r.timeByMode[0].sessionCount, 3)
    }

    func testARenamedModeStaysOneRowUnderItsNewestName() {
        // Same id, renamed mid-week. Grouping by name would split this into
        // two bars for what the user sees as one Mode.
        let r = review([session(start(day: 0, hour: 9), minutes: 30, modeName: "Deep Work"),
                        session(start(day: 4, hour: 9), minutes: 30, modeName: "Homework")])
        XCTAssertEqual(r.timeByMode.count, 1)
        XCTAssertEqual(r.timeByMode[0].modeName, "Homework")
        XCTAssertEqual(r.timeByMode[0].total, 60 * 60)
    }

    func testModesTiedOnTimeAreOrderedByNameSoTheListNeverWobbles() {
        let zebra = session(start(day: 0, hour: 9), minutes: 60, modeID: Self.sleep, modeName: "Zebra")
        let apple = session(start(day: 1, hour: 9), minutes: 60, modeID: Self.dinner, modeName: "Apple")

        XCTAssertEqual(review([zebra, apple]).timeByMode.map(\.modeName), ["Apple", "Zebra"])
        XCTAssertEqual(review([apple, zebra]).timeByMode.map(\.modeName), ["Apple", "Zebra"],
                       "the order must not depend on the order sessions arrive in")
    }

    // MARK: - Which days

    func testDaysRunOldestFirstFromTheWeekStartAndKeepTheGaps() {
        let r = review([session(start(day: 0, hour: 9), minutes: 20),
                        session(start(day: 3, hour: 9), minutes: 40)])
        XCTAssertEqual(r.days.count, 7)
        XCTAssertEqual(r.days[0].date, weekStart)
        XCTAssertEqual(r.days.map(\.date), r.days.map(\.date).sorted(), "oldest first")
        XCTAssertEqual(r.days[0].total, 20 * 60)
        XCTAssertEqual(r.days[1].total, 0)
        XCTAssertEqual(r.days[2].total, 0)
        XCTAssertEqual(r.days[3].total, 40 * 60)
        XCTAssertEqual(r.days[0].weekday, 2, "week starts Monday in this calendar")
    }

    func testTheDaysStillToComeAreMarkedSoNoOneReadsAPatternIntoThem() {
        let r = review([session(start(day: 0, hour: 9))], at: midweek)
        XCTAssertEqual(r.days.map(\.hasHappened), [true, true, false, false, false, false, false])
        XCTAssertEqual(r.daysSoFar.count, 2)
    }

    func testASessionCrossingMidnightCountsTowardTheDayItStarted() {
        // 23:40 Saturday to 00:40 Sunday. Saturday's, out loud and here.
        let r = review([session(start(day: 5, hour: 23, minute: 40), minutes: 60)])
        XCTAssertEqual(r.days[5].total, 3600)
        XCTAssertEqual(r.days[6].total, 0)
        XCTAssertEqual(r.activeDayCount, 1)
    }

    func testAMinuteLongSessionStillMakesTheDayCountAsActive() {
        // Active days are counted by session, not by duration — the phone was
        // Dadded that day even if it did not stay that way for long.
        let r = review([session(start(day: 0, hour: 9), minutes: 1),
                        session(start(day: 1, hour: 9), minutes: 1)])
        XCTAssertEqual(r.activeDayCount, 2)
        XCTAssertTrue(r.adequacy.isEnoughToSaySomething)
    }

    // MARK: - Week boundaries

    func testASessionStartingExactlyOnTheWeekBoundaryLandsInTheNewWeekOnly() {
        let r = review([session(weekStart, minutes: 60)])
        XCTAssertEqual(r.totalThisWeek, 3600)
        XCTAssertEqual(r.comparison, .noBaseline(thisWeek: 3600),
                       "counting it in both weeks would make it its own baseline")
    }

    func testASessionOneSecondBeforeTheBoundaryBelongsToLastWeek() {
        let r = review([session(weekStart.addingTimeInterval(-1), minutes: 60)])
        XCTAssertEqual(r.totalThisWeek, 0)
        XCTAssertEqual(r.comparison.lastWeek, 3600)
    }

    func testASessionThatRunsIntoTheNewWeekStaysInTheWeekItStarted() {
        // Sunday 23:00 of last week, released 01:00 on Monday of this one.
        let r = review([session(start(weeksAgo: 1, day: 6, hour: 23), minutes: 120)])
        XCTAssertEqual(r.totalThisWeek, 0, "credited to the week it began in")
        XCTAssertEqual(r.comparison.lastWeek, 2 * 3600)
    }

    func testTheWeekStartsWhereTheInjectedCalendarSaysItDoes() {
        // `now` is a Sunday. With a Monday-start week it is the last day of
        // the week and the preceding Wednesday is in it; with a Sunday-start
        // week it is the *first* day, and that Wednesday belongs to last week.
        var sundayStart = calendar
        sundayStart.firstWeekday = 1

        let wednesday = session(start(day: 2, hour: 12), minutes: 60)
        XCTAssertEqual(review([wednesday]).totalThisWeek, 3600)
        XCTAssertEqual(WeeklyReview(sessions: [wednesday], now: now, calendar: sundayStart).totalThisWeek, 0)
    }

    // MARK: - Which times of day

    func testTheHourBucketsMeetWithoutOverlappingOrLeavingAGap() {
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 4), .night)
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 5), .morning)
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 11), .morning)
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 12), .afternoon)
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 16), .afternoon)
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 17), .evening)
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 21), .evening)
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 22), .night)
        XCTAssertEqual(WeeklyReview.PartOfDay.containing(hour: 0), .night, "night wraps midnight")
    }

    func testASessionIsFiledWholeUnderTheHourItStartedRatherThanSplit() {
        // 21:00 to 00:00 — three hours of evening, not two plus one of night.
        let r = review([session(start(day: 1, hour: 21), minutes: 180)])
        let byPart = Dictionary(uniqueKeysWithValues: r.timeOfDay.map { ($0.part, $0.total) })
        XCTAssertEqual(byPart[.evening], 3 * 3600)
        XCTAssertEqual(byPart[.night], 0)
        XCTAssertEqual(r.busiestPartOfDay, .evening)
    }

    func testTheFourPartsOfTheDayAreAlwaysPresentAndInClockOrder() {
        let r = review([session(start(day: 1, hour: 2), minutes: 30)])
        XCTAssertEqual(r.timeOfDay.map(\.part), [.morning, .afternoon, .evening, .night])
        XCTAssertEqual(r.timeOfDay.last?.total, 30 * 60, "02:00 is night")
        XCTAssertEqual(r.timeOfDay.map(\.sessionCount), [0, 0, 0, 1])
    }

    func testAPartOfDayTieResolvesToTheEarlierPartSoTheAnswerIsStable() {
        let r = review([session(start(day: 0, hour: 9), minutes: 60),
                        session(start(day: 1, hour: 19), minutes: 60)])
        XCTAssertEqual(r.busiestPartOfDay, .morning)
    }

    func testEachPartOfTheDayCarriesItsOwnLabel() {
        XCTAssertEqual(WeeklyReview.PartOfDay.allCases.map(\.label),
                       ["Morning", "Afternoon", "Evening", "Night"])
    }

    // MARK: - Busiest and quietest day

    func testTheQuietestDayCanBeADayWithNothingOnItAtAll() {
        // Monday and Tuesday only. The interesting fact is the empty Wednesday,
        // and dropping empty days would hide exactly that.
        let r = review([session(start(day: 0, hour: 9), minutes: 90),
                        session(start(day: 1, hour: 9), minutes: 30)])
        guard case .contrast(let busiest, let quietest) = r.dayContrast else {
            return XCTFail("expected a contrast, got \(r.dayContrast)")
        }
        XCTAssertEqual(busiest.date, weekStart)
        XCTAssertEqual(busiest.total, 90 * 60)
        XCTAssertEqual(quietest.total, 0)
        XCTAssertEqual(quietest.date, calendar.date(byAdding: .day, value: 2, to: weekStart)!,
                       "the earliest empty day, so the answer does not wobble")
    }

    func testDaysThatAreAllEqualAreReportedAsLevelRatherThanRankedAgainstEachOther() {
        // Two days elapsed, both identical: naming one of them the busiest
        // would invent a difference out of a tie.
        let r = review([session(start(day: 0, hour: 9), minutes: 30),
                        session(start(day: 1, hour: 9), minutes: 30)],
                       at: midweek)
        XCTAssertEqual(r.dayContrast, .level(each: 30 * 60))
    }

    func testTiedBusiestDaysResolveToTheEarlierOne() {
        let r = review([session(start(day: 1, hour: 9), minutes: 60),
                        session(start(day: 4, hour: 9), minutes: 60)])
        guard case .contrast(let busiest, _) = r.dayContrast else {
            return XCTFail("expected a contrast, got \(r.dayContrast)")
        }
        XCTAssertEqual(busiest.date, calendar.date(byAdding: .day, value: 1, to: weekStart)!)
    }

    // MARK: - Against last week

    func testAnEmptyPreviousWeekIsReportedAsNoBaselineWithNoPercentage() {
        // The decision this whole enum exists for: no "+100%", no "∞", no
        // "new". Two absolute numbers and nothing to divide by.
        let r = review([session(start(day: 0, hour: 9), minutes: 120)])
        XCTAssertEqual(r.comparison, .noBaseline(thisWeek: 120 * 60))
        XCTAssertNil(r.comparison.fraction)
        XCTAssertEqual(r.comparison.lastWeek, 0)
        XCTAssertEqual(r.comparison.delta, 120 * 60)
    }

    func testATinyPreviousWeekIsAlsoRefusedAsAPercentageBaseline() {
        // Two minutes last week against ninety this week is "+4,400%" — true
        // and useless. The absolute difference says the same thing honestly.
        let r = review([session(start(weeksAgo: 1, day: 3, hour: 9), minutes: 2),
                        session(start(day: 0, hour: 9), minutes: 90)])
        XCTAssertEqual(r.comparison, .baselineTooSmall(thisWeek: 90 * 60, lastWeek: 2 * 60))
        XCTAssertNil(r.comparison.fraction)
        XCTAssertEqual(r.comparison.delta, 88 * 60)
    }

    func testAPreviousWeekExactlyAtTheThresholdIsBigEnoughToDivideBy() {
        let r = review([session(start(weeksAgo: 1, day: 3, hour: 9), minutes: 15),
                        session(start(day: 0, hour: 9), minutes: 30)])
        XCTAssertEqual(r.comparison, .measured(thisWeek: 30 * 60, lastWeek: 15 * 60))
        XCTAssertEqual(r.comparison.fraction!, 1.0, accuracy: 0.0001)
    }

    func testARealBaselineGetsARealProportion() {
        let r = review([session(start(weeksAgo: 1, day: 2, hour: 9), minutes: 60),
                        session(start(day: 2, hour: 9), minutes: 90)])
        XCTAssertEqual(r.comparison.fraction!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(r.comparison.delta, 30 * 60)
    }

    func testALighterWeekIsReportedAsANegativeChangeAndNothingElse() {
        let r = review([session(start(weeksAgo: 1, day: 2, hour: 9), minutes: 120),
                        session(start(day: 2, hour: 9), minutes: 60)])
        XCTAssertEqual(r.comparison.fraction!, -0.5, accuracy: 0.0001)
        XCTAssertEqual(r.comparison.delta, -60 * 60)
    }

    func testTheWeekBeforeLastIsNotPartOfTheBaseline() {
        let r = review([session(start(weeksAgo: 2, day: 2, hour: 9), minutes: 600),
                        session(start(day: 2, hour: 9), minutes: 60)])
        XCTAssertEqual(r.comparison, .noBaseline(thisWeek: 60 * 60))
    }

    // MARK: - How sessions ended

    func testEndingAtTheTagAndEndingWithAnOverrideAreCountedSeparately() {
        let r = review([session(start(day: 0, hour: 9)),
                        session(start(day: 1, hour: 9), emergency: true),
                        session(start(day: 2, hour: 9)),
                        session(start(day: 3, hour: 9))])
        XCTAssertEqual(r.endedAtTheTag, 3)
        XCTAssertEqual(r.endedWithAnOverride, 1)
    }

    func testEndingsFromLastWeekAreNotCountedInThisWeek() {
        let r = review([session(start(weeksAgo: 1, day: 0, hour: 9), emergency: true),
                        session(start(day: 0, hour: 9))])
        XCTAssertEqual(r.endedAtTheTag, 1)
        XCTAssertEqual(r.endedWithAnOverride, 0)
    }

    // MARK: - Running out of overrides

    /// `EmergencyAllowance.perWindow` overrides in a row, days 0 upward.
    private func overrideRun(weeksAgo: Int = 0, count: Int, fromDay: Int = 0) -> [DadSession] {
        (0..<count).map {
            session(start(weeksAgo: weeksAgo, day: fromDay + $0, hour: 12),
                    minutes: 30, emergency: true)
        }
    }

    func testTheDayTheLastOverrideIsSpentIsTheDayTheAllowanceRanOut() {
        let r = review(overrideRun(count: EmergencyAllowance.perWindow))
        let fifthDay = calendar.date(byAdding: .day, value: 4, to: weekStart)!
        XCTAssertEqual(r.daysTheAllowanceRanOut, [fifthDay])
        XCTAssertEqual(r.daysTheAllowanceRanOutCount, 1)
    }

    func testAnAllowanceWithOneOverrideLeftHasNotRunOut() {
        let r = review(overrideRun(count: EmergencyAllowance.perWindow - 1))
        XCTAssertEqual(r.daysTheAllowanceRanOutCount, 0)
    }

    func testRunningOutIsCreditedToTheDayTheSessionStartedNotTheDayItBroke() {
        // The fifth override starts at 23:50 and is spent at 00:20. The day
        // that ran out is the day the household was in at the time.
        var run = overrideRun(count: EmergencyAllowance.perWindow - 1)
        run.append(session(start(day: 4, hour: 23, minute: 50), minutes: 30, emergency: true))

        let fifthDay = calendar.date(byAdding: .day, value: 4, to: weekStart)!
        XCTAssertEqual(review(run).daysTheAllowanceRanOut, [fifthDay])
    }

    func testOverridesFromLastWeekStillCountTowardRunningOutThisWeek() {
        // The allowance window is thirty days — longer than the review it
        // appears in — so the fourth override last week is what makes the
        // first one this week the last straw.
        var run = overrideRun(weeksAgo: 1, count: EmergencyAllowance.perWindow - 1)
        run.append(session(start(day: 2, hour: 12), minutes: 30, emergency: true))

        let wednesday = calendar.date(byAdding: .day, value: 2, to: weekStart)!
        XCTAssertEqual(review(run).daysTheAllowanceRanOut, [wednesday])
    }

    func testRunningOutLastWeekIsNotReportedAsRunningOutThisWeek() {
        let r = review(overrideRun(weeksAgo: 1, count: EmergencyAllowance.perWindow))
        XCTAssertEqual(r.daysTheAllowanceRanOutCount, 0)
    }

    func testOverridesThatHaveAgedOutOfTheWindowDoNotCountTowardRunningOut() {
        // Two overrides forty days ago have expired; three this week leaves
        // two in hand, so nothing ran out.
        let old = (0..<2).map {
            session(now.addingTimeInterval(-TimeInterval(40 * 24 * 3600 + $0 * 3600)),
                    minutes: 30, emergency: true)
        }
        let r = review(old + overrideRun(count: 3))
        XCTAssertEqual(r.daysTheAllowanceRanOutCount, 0)
    }

    func testASessionEndedAtTheTagNeverSpendsTheAllowance() {
        let r = review((0..<EmergencyAllowance.perWindow).map {
            session(start(day: $0, hour: 12), minutes: 30, emergency: false)
        })
        XCTAssertEqual(r.daysTheAllowanceRanOutCount, 0)
    }

    // MARK: - Tone

    func testTheHeadlineStatesTheWeekWithoutGradingIt() {
        let r = review([session(start(day: 0, hour: 9), minutes: 60),
                        session(start(day: 2, hour: 9), minutes: 30),
                        session(start(day: 2, hour: 14), minutes: 15)])
        XCTAssertEqual(r.headline, "1h 45m Dadded over 3 sessions on 2 days.")
    }

    func testTheHeadlineIsSingularWhenThereIsOneOfSomething() {
        let r = review([session(start(day: 0, hour: 9), minutes: 60)])
        XCTAssertEqual(r.headline, "1h 0m Dadded over 1 session on 1 day.")
    }

    /// The tone requirement, made mechanical. A future edit that reaches for
    /// "only", "great" or a streak reminder turns this red — which is the
    /// point, because that is the register a teenager stops reading.
    func testTheCopyCarriesNoPraiseNoScoldingAndNoComparisonWithAnyoneElse() {
        let copy = [
            review([]).headline,
            review([session(start(day: 0, hour: 9), minutes: 5)]).headline,
            review([session(start(day: 0, hour: 9)), session(start(day: 3, hour: 9))]).headline,
        ] + WeeklyReview.PartOfDay.allCases.map(\.label)

        let banned = ["only", "just ", "great", "well done", "nice", "keep it up",
                      "better", "worse", "best", "worst", "should", "failed",
                      "fail", "missed", "streak", "than", "everyone", "average",
                      "family", "compared"]
        for line in copy {
            for word in banned {
                XCTAssertFalse(line.lowercased().contains(word),
                               "evaluative or comparative copy '\(word)' in: \(line)")
            }
        }
    }

    /// The verb is the product; a lowercase one in the review reads as a typo.
    func testTheVerbKeepsItsCapitalInTheHeadline() {
        let headline = review([session(start(day: 0, hour: 9))]).headline
        XCTAssertTrue(headline.contains("Dadded"))
        XCTAssertFalse(headline.contains("dadded"))
    }
}
