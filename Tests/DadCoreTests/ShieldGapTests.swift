import XCTest
@testable import DadCore

/// What Dad is allowed to say about a stretch it could not see.
///
/// Two things are pinned here that are decisions rather than implementation:
/// the threshold below which nothing is said at all, and the wording. The
/// wording matters more — a gap is evidence of a gap and never proof of
/// intent, so the last test in this file sweeps every string the file can
/// produce and fails if any of them assigns a motive to a person.
final class ShieldGapTests: XCTestCase {

    // MARK: - Fixtures

    /// UTC everywhere except the daylight-saving test, which says so.
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private let london: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int,
                    _ hour: Int, _ minute: Int = 0,
                    in calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Wednesday 2025-08-20, 09:00 UTC. Every test that needs "now" uses it.
    private var now: Date { at(2025, 8, 20, 9) }

    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 3600

    private func window(_ name: String = "Sleep",
                        from start: Date, to end: Date) -> ScheduledOccurrence {
        ScheduledOccurrence(modeName: name, interval: DateInterval(start: start, end: end))
    }

    private func mode(_ name: String = "Sleep",
                      startHour: Int, startMinute: Int = 0,
                      endHour: Int, endMinute: Int = 0,
                      weekdays: Set<Int> = ModeSchedule.everyDay,
                      enabled: Bool = true,
                      blocking: Bool = true) -> DadMode {
        DadMode(name: name,
                symbol: "moon",
                blocked: blocking ? BlockedSelection(payload: Data([1]), appCount: 3)
                                  : BlockedSelection(),
                schedule: ModeSchedule(isEnabled: enabled,
                                       startHour: startHour, startMinute: startMinute,
                                       endHour: endHour, endMinute: endMinute,
                                       weekdays: weekdays))
    }

    // MARK: - Authorization: the one observation that says the shield was absent

    func testAWorkingSetupSaysNothingAtAll() {
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .approved,
            activeSessionStartedAt: now.addingTimeInterval(-3 * hour),
            lastConfirmedAt: now.addingTimeInterval(-3 * hour),
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
        XCTAssertTrue(report.isSilent)
        XCTAssertNil(report.headline)
        XCTAssertNil(report.setupNote)
    }

    // MARK: - Where the week ends

    func testTheHorizonCutsOnTheWindowsStartAndTheEdgeIsExact() {
        // now is Wednesday 2025-08-20 09:00; the horizon is 2025-08-13 09:00.
        // A window starting at 10:00 on the horizon day is inside it by an
        // hour; one starting at 08:00 that same day is outside by one. Both
        // are the same distance from "a week ago" in ordinary speech, and the
        // edge has to fall somewhere.
        //
        // This also pins what was an unreachable extra day of search. Its
        // comment said an overnight window beginning just outside the horizon
        // could still end inside it — which `start >= horizon` forbids — and a
        // mutation removing the day survived the whole suite.
        let inside = ShieldGap.occurrences(
            of: [mode(startHour: 10, endHour: 11)], now: now, calendar: utc)
        let outside = ShieldGap.occurrences(
            of: [mode(startHour: 8, endHour: 9)], now: now, calendar: utc)

        XCTAssertEqual(inside.map(\.interval.start).min(), at(2025, 8, 13, 10),
                       "the oldest window found starts on the horizon day, after the horizon")
        XCTAssertEqual(outside.map(\.interval.start).min(), at(2025, 8, 14, 8),
                       "an 08:00 window on the horizon day began before it, so the run starts a day later")
    }

    func testAConfirmationFromTheFutureDoesNotCrashTheReport() {
        // The guard on the left edge is a crash guard, not tidiness, and a
        // mutation removing it survived the whole suite — so it had no test
        // under it at all.
        //
        // `DateInterval(start:end:)` traps when the end precedes the start.
        // `lastConfirmedAt` can be after `now` for reasons that happen to real
        // phones: a restored backup carrying a stamp from the future, or a
        // clock corrected backwards while a session was running — the same
        // events the report's own caveat lists as indistinguishable from a
        // gap. The honest answer is no gap, not a crash on the Stats screen.
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: now.addingTimeInterval(-3 * hour),
            lastConfirmedAt: now.addingTimeInterval(hour),
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
        XCTAssertNotNil(report.setupNote, "the setup problem is still worth saying")
    }

    func testAConfirmationAtThisVeryInstantIsNotAGapOfNoLength() {
        // Confirmed exactly now, so there is no interval between the last time
        // the shield was known good and the moment we looked.
        //
        // Note that loosening the guard to `<=` still passes this: a
        // zero-length gap is below `minimumReportable` and gets filtered out
        // regardless. That is recorded on the guard itself, because a mutation
        // survives there and it is taste rather than a hole.
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: now.addingTimeInterval(-3 * hour),
            lastConfirmedAt: now,
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
    }

    func testNotBeingAbleToAskIsNotAnAnswer() {
        // `.unknown` must never be read as `.notApproved`. A slow or
        // unavailable AuthorizationCenter would otherwise manufacture a gap,
        // and here a false positive reads as an accusation.
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .unknown,
            activeSessionStartedAt: now.addingTimeInterval(-6 * hour),
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
        XCTAssertFalse(report.authorizationMissingNow)
        XCTAssertNil(report.setupNote)
    }

    func testAbsentAuthorizationDuringASessionBoundsFromTheSessionStart() {
        let started = now.addingTimeInterval(-2 * hour)
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: started,
            audience: .shared))

        XCTAssertEqual(report.gaps.count, 1)
        XCTAssertEqual(report.gaps.first?.interval, DateInterval(start: started, end: now))
        XCTAssertEqual(report.gaps.first?.evidence, .authorizationNotInPlace)
        XCTAssertEqual(report.gaps.first?.longestPossible, 2 * hour)
    }

    func testALaterConfirmationTightensTheBound() {
        // The app saw the shield in place 30 minutes ago, so it cannot have
        // been absent for the whole five-hour session. Reporting the session's
        // length here would inflate every figure the feature prints.
        let started = now.addingTimeInterval(-5 * hour)
        let confirmed = now.addingTimeInterval(-30 * minute)
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: started,
            lastConfirmedAt: confirmed,
            audience: .shared))

        XCTAssertEqual(report.gaps.first?.interval, DateInterval(start: confirmed, end: now))
        XCTAssertEqual(report.gaps.first?.longestPossible, 30 * minute)
    }

    func testAConfirmationFromBeforeTheSessionCannotWidenTheBound() {
        // A stale confirmation left over from an earlier session must not drag
        // the left edge back before the moment there was anything to hold.
        let started = now.addingTimeInterval(-1 * hour)
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: started,
            lastConfirmedAt: now.addingTimeInterval(-9 * hour),
            audience: .shared))

        XCTAssertEqual(report.gaps.first?.interval, DateInterval(start: started, end: now))
    }

    func testAbsentAuthorizationWithNoSessionIsASetupProblemAndNotAGap() {
        // Nothing was supposed to be held, so nothing was lost.
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: nil,
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
        XCTAssertTrue(report.authorizationMissingNow)
        XCTAssertNotNil(report.setupNote)
        XCTAssertFalse(report.isSilent)
    }

    func testTheSetupProblemIsRaisedEvenWhenTheGapItselfIsTooShort() {
        // Five minutes is below the floor, so nothing is said about the past —
        // but the tool is broken right now and that is worth a minute's fixing.
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: now.addingTimeInterval(-5 * minute),
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
        XCTAssertNil(report.headline)
        XCTAssertNotNil(report.setupNote)
    }

    // MARK: - The floor

    func testTheFloorIsTheShortestStretchTheSystemItselfWillMonitor() {
        // Not a tuned number: below DeviceActivity's own granularity a clock
        // correction, a reboot and a real lapse are the same observation.
        XCTAssertEqual(ShieldGap.minimumReportable, DadEngine.minimumScheduledRelease)
        XCTAssertEqual(ShieldGap.minimumReportable, 15 * 60)
    }

    func testAStretchShorterThanTheFloorIsNotMentioned() {
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: now.addingTimeInterval(-(15 * minute - 1)),
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
    }

    func testAStretchOfExactlyTheFloorIsMentioned() {
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: now.addingTimeInterval(-ShieldGap.minimumReportable),
            audience: .shared))

        XCTAssertEqual(report.gaps.count, 1)
    }

    func testRepeatedShortStretchesDoNotAddUpToSomethingWorthSaying() {
        // Twelve five-minute windows across a week. Individually meaningless,
        // and counting them would turn an old battery into a pattern claim
        // about a person. The report must stay silent.
        let short = (1...12).map { day -> ScheduledOccurrence in
            let start = now.addingTimeInterval(-Double(day) * 12 * hour)
            return window(from: start, to: start.addingTimeInterval(5 * minute))
        }
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved, occurrences: short, audience: .shared))

        XCTAssertFalse(ShieldGap.aggregatesShortGaps)
        XCTAssertTrue(report.gaps.isEmpty)
        XCTAssertTrue(report.isSilent)
    }

    // MARK: - Scheduled windows

    func testAScheduledWindowWithNothingRecordedInItIsAGap() {
        let start = at(2025, 8, 19, 22)
        let end = at(2025, 8, 20, 7)
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [window("Sleep", from: start, to: end)],
            audience: .shared))

        XCTAssertEqual(report.gaps.count, 1)
        XCTAssertEqual(report.gaps.first?.evidence,
                       .noSessionForScheduledWindow(modeName: "Sleep"))
        XCTAssertEqual(report.gaps.first?.interval, DateInterval(start: start, end: end))
    }

    func testAWindowWithASessionInsideItIsSilent() {
        let start = at(2025, 8, 19, 22)
        let end = at(2025, 8, 20, 7)
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [window(from: start, to: end)],
            daddedIntervals: [DateInterval(start: start, end: end)],
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
    }

    func testAPartlyCoveredWindowIsSilentOnPurpose() {
        // Twenty minutes of a nine-hour window. Saying "eight hours of this
        // were uncovered" is the per-minute ledger this feature refuses to
        // keep, so any overlap at all buys silence. The false negative is the
        // cheaper mistake.
        let start = at(2025, 8, 19, 22)
        let end = at(2025, 8, 20, 7)
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [window(from: start, to: end)],
            daddedIntervals: [DateInterval(start: start, end: start.addingTimeInterval(20 * minute))],
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
    }

    func testASessionEndingExactlyAsAWindowOpensDoesNotCoverIt() {
        // Touching is not overlapping. `DateInterval.intersects` disagrees,
        // which would hide a window that genuinely held nothing.
        let start = at(2025, 8, 19, 22)
        let end = at(2025, 8, 20, 7)
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [window(from: start, to: end)],
            daddedIntervals: [DateInterval(start: start.addingTimeInterval(-hour), end: start)],
            audience: .shared))

        XCTAssertEqual(report.gaps.count, 1)
    }

    func testAWindowInsideAnAuthorizationGapIsCountedOnce() {
        // The same event seen two ways. The count is the only number a reader
        // takes away, so it must not double.
        let started = at(2025, 8, 19, 20)
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: started,
            occurrences: [window(from: at(2025, 8, 19, 22), to: at(2025, 8, 20, 7))],
            audience: .shared))

        XCTAssertEqual(report.gaps.count, 1)
        XCTAssertEqual(report.gaps.first?.evidence, .authorizationNotInPlace)
    }

    func testAWindowOutsideTheAuthorizationGapIsStillItsOwnGap() {
        let report = ShieldGap.report(ShieldObservations(
            now: now,
            authorization: .notApproved,
            activeSessionStartedAt: now.addingTimeInterval(-hour),
            occurrences: [window(from: at(2025, 8, 17, 22), to: at(2025, 8, 18, 7))],
            audience: .shared))

        XCTAssertEqual(report.gaps.count, 2)
    }

    // MARK: - The lookback

    func testAStretchOlderThanAWeekIsNotRaised() {
        // Past a week it stops being "go and check Screen Time" and becomes a
        // grievance with a timestamp.
        let start = now.addingTimeInterval(-8 * 24 * hour)
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [window(from: start, to: start.addingTimeInterval(9 * hour))],
            audience: .shared))

        XCTAssertTrue(report.gaps.isEmpty)
    }

    func testAStretchJustInsideTheWeekIsRaised() {
        let start = now.addingTimeInterval(-6 * 24 * hour)
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [window(from: start, to: start.addingTimeInterval(9 * hour))],
            audience: .shared))

        XCTAssertEqual(report.gaps.count, 1)
        XCTAssertEqual(ShieldGap.lookback, 7 * 24 * 3600)
    }

    func testGapsAreNewestFirst() {
        let older = window("Sleep", from: at(2025, 8, 16, 22), to: at(2025, 8, 17, 7))
        let newer = window("Dinner", from: at(2025, 8, 19, 18), to: at(2025, 8, 19, 20))
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [older, newer],
            audience: .shared))

        XCTAssertEqual(report.gaps.map(\.interval), [newer.interval, older.interval])
    }

    // MARK: - Deriving the windows from stored Modes, with no background wake

    func testAnOvernightWindowEndsAtTheChosenWallClockTime() {
        let sleep = mode(startHour: 22, endHour: 7)
        let found = ShieldGap.occurrences(of: [sleep], now: now, calendar: utc)

        // Most recent first: last night, 22:00 to 07:00.
        XCTAssertEqual(found.first?.interval,
                       DateInterval(start: at(2025, 8, 19, 22), end: at(2025, 8, 20, 7)))
        XCTAssertEqual(found.first?.modeName, "Sleep")
    }

    func testAWindowStillOpenContributesOnlyItsElapsedPart() {
        // 08:00-12:00 with "now" at 09:00. The remaining three hours have not
        // had a chance to happen, and reporting them would be a prediction.
        let daytime = mode("Deep Work", startHour: 8, endHour: 12)
        let found = ShieldGap.occurrences(of: [daytime], now: now, calendar: utc)

        XCTAssertEqual(found.first?.interval,
                       DateInterval(start: at(2025, 8, 20, 8), end: now))
    }

    func testAModeThatBlocksNothingContributesNoWindows() {
        // It is never registered with the scheduler, so a missing session for
        // it is not evidence of anything.
        let empty = mode(startHour: 22, endHour: 7, blocking: false)
        XCTAssertTrue(ShieldGap.occurrences(of: [empty], now: now, calendar: utc).isEmpty)
    }

    func testAModeWithItsScheduleSwitchedOffContributesNoWindows() {
        let off = mode(startHour: 22, endHour: 7, enabled: false)
        XCTAssertTrue(ShieldGap.occurrences(of: [off], now: now, calendar: utc).isEmpty)
    }

    func testOnlyTheChosenWeekdaysProduceWindows() {
        // Sundays only (Calendar weekday 1). In the week before Wed 20 Aug
        // that is Sun 17 Aug, once.
        let sundays = mode(startHour: 22, endHour: 23, weekdays: [1])
        let found = ShieldGap.occurrences(of: [sundays], now: now, calendar: utc)

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.interval.start, at(2025, 8, 17, 22))
    }

    func testEveryWindowInTheLookbackIsFoundAndNoMore() {
        let sleep = mode(startHour: 22, endHour: 7)
        let found = ShieldGap.occurrences(of: [sleep], now: now, calendar: utc)

        // Seven nights: 13 Aug through 19 Aug at 22:00. The night of 12 Aug
        // starts before the horizon.
        XCTAssertEqual(found.count, 7)
        XCTAssertEqual(found.last?.interval.start, at(2025, 8, 13, 22))
        XCTAssertTrue(found.allSatisfy { $0.interval.start >= now.addingTimeInterval(-ShieldGap.lookback) })
    }

    func testADaylightSavingChangeDoesNotStretchTheBound() {
        // Europe/London, clocks forward 01:00 to 02:00 on 30 March 2025. A
        // 22:00-07:00 window that night is eight real hours, not nine. Adding
        // `schedule.duration` would have printed an hour that did not exist —
        // and every bound in this file is already an upper one.
        let springForward = at(2025, 3, 30, 12, in: london)
        let sleep = mode(startHour: 22, endHour: 7)
        let found = ShieldGap.occurrences(of: [sleep], now: springForward, calendar: london)

        XCTAssertEqual(found.first?.interval.duration, 8 * hour)
        XCTAssertEqual(sleep.schedule?.duration, 9 * hour)
    }

    // MARK: - Who the report is for

    func testTheDefaultAudienceIsTheQuietOne() {
        // Getting this field wrong makes the app look like it is accusing
        // somebody, so not thinking about it has to yield silence.
        let observations = ShieldObservations(now: now, authorization: .approved)
        XCTAssertEqual(observations.audience, .solo)
    }

    func testOneAdultDaddingThemselvesGetsNoRetrospectiveCopy() {
        let start = at(2025, 8, 19, 22)
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [window(from: start, to: at(2025, 8, 20, 7))],
            audience: .solo))

        XCTAssertNil(report.headline)
        XCTAssertNil(report.detail)
        // The values survive; only the sentence is withheld.
        XCTAssertEqual(report.gaps.count, 1)
    }

    func testOneAdultStillLearnsWhenTheToolItselfIsNotSetUp() {
        // Actionable, about the tool, and fixable in the next minute — so it
        // is the one thing a solo household is still told.
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .notApproved, audience: .solo))

        XCTAssertNotNil(report.setupNote)
        XCTAssertFalse(report.isSilent)
    }

    func testASharedHouseholdGetsACountAndTheCaveatUnderIt() {
        let start = at(2025, 8, 19, 22)
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved,
            occurrences: [window(from: start, to: at(2025, 8, 20, 7))],
            audience: .shared))

        XCTAssertEqual(report.headline, "1 unconfirmed stretch")
        XCTAssertEqual(report.detail, ShieldGapReport.caveat)
    }

    func testTheCountPluralises() {
        let a = window("Sleep", from: at(2025, 8, 19, 22), to: at(2025, 8, 20, 7))
        let b = window("Dinner", from: at(2025, 8, 18, 18), to: at(2025, 8, 18, 20))
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .approved, occurrences: [a, b], audience: .shared))

        XCTAssertEqual(report.headline, "2 unconfirmed stretches")
    }

    // MARK: - Copy

    func testTheCaveatNamesTheInnocentExplanations() {
        // Shipped with the number rather than hidden in a help screen: a
        // reader left to supply a cause supplies the worst one.
        let caveat = ShieldGapReport.caveat.lowercased()
        for innocent in ["restart", "restore", "ios update", "settings"] {
            XCTAssertTrue(caveat.contains(innocent), "caveat should mention \(innocent)")
        }
    }

    func testEveryDurationIsPhrasedAsAnUpperBound() {
        let gap = ShieldGap(interval: DateInterval(start: at(2025, 8, 19, 22),
                                                   end: at(2025, 8, 20, 0, 10)),
                            evidence: .authorizationNotInPlace)
        XCTAssertEqual(gap.boundText, "Up to 2h 10m")
    }

    func testEvidenceCopyStatesAConditionRatherThanACause() {
        let auth = ShieldGap(interval: DateInterval(start: at(2025, 8, 19, 22),
                                                    end: at(2025, 8, 20, 7)),
                             evidence: .authorizationNotInPlace)
        XCTAssertEqual(auth.evidenceText, "Screen Time access was not in place.")

        let window = ShieldGap(interval: DateInterval(start: at(2025, 8, 19, 22),
                                                      end: at(2025, 8, 20, 7)),
                               evidence: .noSessionForScheduledWindow(modeName: "Sleep"))
        XCTAssertEqual(window.evidenceText,
                       "No Sleep session is recorded for a scheduled window.")
    }

    func testTheSetupNoteUsesTheAppNameAndAsksForNothingOfAnyone() {
        let report = ShieldGap.report(ShieldObservations(
            now: now, authorization: .notApproved, audience: .shared))
        XCTAssertEqual(report.setupNote,
                       "Screen Time access is not granted. Dad cannot hold anything until it is.")
    }

    // MARK: - The sweep
    //
    // A gap is evidence of a gap, not proof of intent. A flat battery, a
    // restore, an iOS update and a deliberate revocation are the same
    // observation from in here, so no string this file produces may name an
    // actor, a motive or a fault. This is the test that keeps that true as the
    // copy changes.

    /// Every report shape the file can produce, so the sweep has the whole
    /// surface rather than a sample of it.
    private var everyReport: [ShieldGapReport] {
        let start = at(2025, 8, 19, 22)
        let end = at(2025, 8, 20, 7)
        let occurrences = [window("Sleep", from: start, to: end),
                           window("Deep Work", from: at(2025, 8, 18, 9), to: at(2025, 8, 18, 12))]

        var reports: [ShieldGapReport] = []
        for audience in [ShieldAudience.solo, .shared] {
            for authorization in [ShieldAuthorization.approved, .notApproved, .unknown] {
                for sessionStart in [nil, at(2025, 8, 19, 20)] as [Date?] {
                    for windows in [[], occurrences, [occurrences[0]]] {
                        reports.append(ShieldGap.report(ShieldObservations(
                            now: now,
                            authorization: authorization,
                            activeSessionStartedAt: sessionStart,
                            occurrences: windows,
                            audience: audience)))
                    }
                }
            }
        }
        return reports
    }

    func testTheSweepActuallyReachesEveryKindOfString() {
        // A sweep over an empty surface passes trivially. Prove it is looking
        // at headlines, details, setup notes, evidence lines and bounds.
        let all = Set(everyReport.flatMap(\.allStrings))
        XCTAssertTrue(all.contains(ShieldGapReport.caveat))
        XCTAssertTrue(all.contains("1 unconfirmed stretch"))
        XCTAssertTrue(all.contains("2 unconfirmed stretches"))
        XCTAssertTrue(all.contains("Screen Time access was not in place."))
        XCTAssertTrue(all.contains("No Sleep session is recorded for a scheduled window."))
        XCTAssertTrue(all.contains { $0.hasPrefix("Up to ") })
        XCTAssertTrue(all.contains { $0.hasPrefix("Screen Time access is not granted.") })
    }

    func testNoStringAssignsIntentOrBlame() {
        let forbidden = [
            "someone", "somebody", "anyone", "whoever",
            "turned off", "turned it off", "switched off", "shut off",
            "disabled", "removed", "deleted", "revoked", "uninstalled",
            "bypass", "circumvent", "got around", "evaded", "escaped",
            "cheat", "sneak", "lied", "dishonest", "trick",
            "ignored", "avoided", "tamper", "broke", "violat",
            "blame", "fault", "deliberate", "on purpose", "intentional",
            "excuse", "caught", "suspicious", "should have", "failed",
            "explain", "admit", "trust", "why",
        ]

        for report in everyReport {
            for string in report.allStrings {
                XCTAssertFalse(string.isEmpty)
                let lowered = string.lowercased()
                for word in forbidden {
                    XCTAssertFalse(lowered.contains(word),
                                   "\"\(string)\" contains \"\(word)\", which assigns intent or blame")
                }
            }
        }
    }

    func testNoStringAddressesAPerson() {
        // Everything here describes the device or the app. The moment a
        // sentence says "you", it is talking to a suspect.
        for report in everyReport {
            for string in report.allStrings {
                let words = string.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                for pronoun in ["you", "your", "yours", "he", "she", "they", "their"] {
                    XCTAssertFalse(words.contains(pronoun),
                                   "\"\(string)\" addresses or names a person")
                }
            }
        }
    }
}
