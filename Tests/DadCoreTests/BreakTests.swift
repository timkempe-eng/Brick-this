import XCTest
@testable import DadCore

/// Release on a leash: a Mode that starts itself again after a break.
///
/// The behaviour is opt-in per Mode and off by default, so the first thing
/// these tests pin down is that a Mode without one is unchanged. After that,
/// the decisions worth defending:
///
/// - only a release *by hand* starts a break; an emergency override never
///   does, or someone who could not reach the tag would be re-blocked with no
///   way out;
/// - tapping during a break calls it off, because that is the outcome the tag
///   is the only route to;
/// - a break whose end is never delivered is resumed at the next foreground,
///   the same backstop a lost timed release already has.
final class BreakTests: XCTestCase {

    private let fifteen: TimeInterval = 15 * 60

    // MARK: - Off by default

    func testAModeWithoutABreakIsUnchanged() {
        let h = Harness()
        let mode = h.addMode()
        h.engine.dad(with: mode)
        h.engine.handleTap()

        XCTAssertNil(h.store.pendingResume)
        XCTAssertTrue(h.scheduler.resumes.isEmpty)
        XCTAssertFalse(mode.takesBreaks)
    }

    func testAModeThatBlocksNothingTakesNoBreaks() {
        var mode = DadMode(name: "Empty", symbol: "circle")
        mode.resumeAfter = 15 * 60
        XCTAssertFalse(mode.takesBreaks)
    }

    func testAZeroLengthBreakIsNoBreak() {
        let h = Harness()
        let mode = h.addMode(breakLength: 0)
        XCTAssertFalse(mode.takesBreaks)
        h.engine.dad(with: mode)
        h.engine.handleTap()
        XCTAssertNil(h.store.pendingResume)
    }

    // MARK: - Starting one

    func testTappingOutStartsTheBreak() {
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)

        h.engine.handleTap()

        XCTAssertNil(h.store.activeSession, "the apps come back now")
        XCTAssertEqual(h.store.pendingResume?.modeID, mode.id)
        XCTAssertEqual(h.store.pendingResume?.at, h.clock.now.addingTimeInterval(fifteen))
        XCTAssertEqual(h.scheduler.resumes, [h.clock.now.addingTimeInterval(fifteen)])
    }

    func testABreakShorterThanTheSystemWillWatchIsRoundedUp() {
        // DeviceActivity refuses an interval under 15 minutes, so a 5-minute
        // break would simply never fire. Rounding up is visible; silently not
        // coming back is not.
        let h = Harness()
        let mode = h.addMode(breakLength: 5 * 60)
        h.engine.dad(with: mode)
        h.engine.handleTap()

        XCTAssertEqual(h.store.pendingResume?.at,
                       h.clock.now.addingTimeInterval(DadEngine.minimumScheduledRelease))
    }

    func testTheBreakCarriesTheModeNameSoItCanBeNamedWithTheAppClosed() {
        let h = Harness()
        let mode = h.addMode(name: "Deep Work", breakLength: fifteen)
        h.engine.dad(with: mode)
        h.engine.handleTap()

        XCTAssertEqual(h.store.pendingResume?.modeName, "Deep Work")
    }

    // MARK: - Which endings start one

    func testAnEmergencyOverrideNeverStartsABreak() {
        // An override is for when the tag is genuinely out of reach. Coming
        // back in fifteen minutes would leave someone blocked with no way out
        // — the one situation the override exists to prevent.
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)

        XCTAssertTrue(h.engine.emergencyUnDad())

        XCTAssertNil(h.store.pendingResume)
        XCTAssertTrue(h.scheduler.resumes.isEmpty)
    }

    func testATimedReleaseDoesNotStartABreak() {
        // "Dad me for an hour" already said when this Mode should stop.
        // Starting a break would make it a loop.
        let h = Harness()
        let mode = h.addMode(autoRelease: 60 * 60, breakLength: fifteen)
        h.engine.dad(with: mode)

        h.clock.advance(60 * 60)
        h.engine.reconcile()

        XCTAssertNil(h.store.activeSession)
        XCTAssertNil(h.store.pendingResume)
    }

    func testAScheduleBoundaryDoesNotStartABreak() {
        let h = Harness()
        let mode = h.addMode(schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                                    endHour: 7, endMinute: 0,
                                                    weekdays: ModeSchedule.everyDay),
                             breakLength: fifteen)
        h.engine.beginScheduledSession(modeID: mode.id)
        h.engine.endScheduledSession(modeID: mode.id)

        XCTAssertNil(h.store.pendingResume, "the schedule decides when this Mode runs")
    }

    func testAModeDeletedUnderARunningSessionDoesNotStartABreak() {
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)
        h.engine.deleteMode(id: mode.id)

        h.engine.reconcile()

        XCTAssertNil(h.store.activeSession)
        XCTAssertNil(h.store.pendingResume)
    }

    // MARK: - Ending one

    func testTheBreakEndsAndTheModeComesBack() {
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)
        h.engine.handleTap()
        XCTAssertNil(h.shield.appliedMode)

        h.clock.advance(fifteen)
        h.engine.resumeFromBreak()

        XCTAssertEqual(h.store.activeSession?.modeID, mode.id)
        XCTAssertEqual(h.shield.appliedMode, mode.id)
        XCTAssertNil(h.store.pendingResume, "it is not pending any more")
    }

    func testTappingDuringABreakCallsItOff() {
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)
        h.engine.handleTap()

        XCTAssertEqual(h.engine.handleTap(), .breakCancelled(mode: mode))

        XCTAssertNil(h.store.pendingResume)
        XCTAssertNil(h.store.activeSession, "cancelling a break does not Dad you")
        XCTAssertEqual(h.scheduler.resumeCancelCount, 1)
    }

    func testAfterCancellingABreakATapDadsAgainAsNormal() {
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)
        h.engine.handleTap()           // out, break running
        h.engine.handleTap()           // break called off

        let result = h.engine.handleTap()

        guard case .dadded = result else { return XCTFail("expected .dadded, got \(result)") }
        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testStartingASessionDuringABreakSupersedesIt() {
        let h = Harness()
        let mode = h.addMode(name: "Deep Work", breakLength: fifteen)
        let other = h.addMode(name: "Sleep")
        h.engine.dad(with: mode)
        h.engine.handleTap()

        h.engine.dad(with: other)

        XCTAssertNil(h.store.pendingResume)
        XCTAssertEqual(h.shield.appliedMode, other.id)
    }

    func testResumingIntoASessionSomebodyElseStartedLeavesItAlone() {
        let h = Harness()
        let mode = h.addMode(name: "Deep Work", breakLength: fifteen)
        let other = h.addMode(name: "Sleep")
        h.engine.dad(with: mode)
        h.engine.handleTap()
        // The break survives being re-armed by hand only because we set it
        // back deliberately: a session is running, so the resume must no-op.
        h.store.pendingResume = PendingResume(modeID: mode.id, modeName: mode.name,
                                              at: h.clock.now)
        h.engine.dad(with: other)
        h.store.pendingResume = PendingResume(modeID: mode.id, modeName: mode.name,
                                              at: h.clock.now)

        h.engine.resumeFromBreak()

        XCTAssertEqual(h.store.activeSession?.modeID, other.id, "theirs wins")
        XCTAssertNil(h.store.pendingResume)
    }

    func testAModeDeletedDuringABreakDropsTheBreak() {
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)
        h.engine.handleTap()

        h.engine.deleteMode(id: mode.id)
        h.clock.advance(fifteen)
        h.engine.resumeFromBreak()

        XCTAssertNil(h.store.activeSession)
        XCTAssertNil(h.store.pendingResume, "a resume that can never happen must not linger")
    }

    // MARK: - The backstop

    func testAnOverdueBreakResumesAtTheNextForeground() {
        // The registration can be lost with the process, exactly as a timed
        // release can, and the consequence has the same shape: a Mode that
        // promised to come back and silently didn't.
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)
        h.engine.handleTap()

        h.clock.advance(60 * 60)
        h.engine.reconcile()

        XCTAssertEqual(h.store.activeSession?.modeID, mode.id)
        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testABreakStillRunningIsReArmedRatherThanResumed() {
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        h.engine.dad(with: mode)
        h.engine.handleTap()
        let due = h.store.pendingResume!.at

        h.clock.advance(60)
        h.engine.reconcile()

        XCTAssertNil(h.store.activeSession, "the break is not over")
        XCTAssertEqual(h.scheduler.resumes, [due, due], "re-armed with the same instant")
    }

    func testTheSummaryMentionsTheBreak() {
        let h = Harness()
        let mode = h.addMode(breakLength: fifteen)
        XCTAssertTrue(mode.summary.contains("15m breaks"), mode.summary)
    }
}

/// What the Lock Screen says during a break.
///
/// The point of the widget is answering "can I use my phone" without
/// unlocking, and a break is a third answer to it: yes, for now.
final class BreakWidgetTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func snapshot(resume: PendingResume?) -> WidgetSnapshot {
        .make(session: nil, stats: DadStats(sessions: [], now: now),
              pendingResume: resume, now: now)
    }

    func testABreakIsItsOwnState() {
        let resume = PendingResume(modeID: UUID(), modeName: "Deep Work",
                                   at: now.addingTimeInterval(900))
        XCTAssertEqual(snapshot(resume: resume),
                       .onBreak(modeName: "Deep Work", until: resume.at))
    }

    func testWithNoBreakItIsTheOrdinaryFreeState() {
        XCTAssertEqual(snapshot(resume: nil), .free(streakDays: 0))
    }

    func testABreakThatIsAlreadyDueReadsAsFree() {
        // The resume has not landed yet, but the break is over. Saying "comes
        // back at 14:35" at 14:40 is the widget lying about the past.
        let resume = PendingResume(modeID: UUID(), modeName: "Deep Work",
                                   at: now.addingTimeInterval(-60))
        XCTAssertEqual(snapshot(resume: resume), .free(streakDays: 0))
    }

    func testTheWidgetWakesWhenTheBreakEnds() {
        // The one state with a deadline rather than an event: nothing in this
        // process announces a resume, so the timeline has to ask to be rebuilt.
        let until = now.addingTimeInterval(900)
        let snapshot = WidgetSnapshot.onBreak(modeName: "Deep Work", until: until)
        XCTAssertEqual(snapshot.nextRefresh(after: now), until)
    }

    func testItSaysWhichModeIsComingBack() {
        let until = now.addingTimeInterval(900)
        let snapshot = WidgetSnapshot.onBreak(modeName: "Deep Work", until: until)
        XCTAssertTrue(snapshot.detail.contains("Deep Work"), snapshot.detail)
        XCTAssertTrue(snapshot.inlineText.contains("Deep Work"), snapshot.inlineText)
        XCTAssertFalse(snapshot.isDadded, "the apps are available during a break")
    }

    func testTheVerbIsNotLowercasedHereEither() {
        let snapshot = WidgetSnapshot.onBreak(modeName: "Deep Work",
                                              until: now.addingTimeInterval(900))
        for text in [snapshot.headline, snapshot.detail, snapshot.inlineText] {
            XCTAssertFalse(text.contains("dad"), text)
        }
    }
}

/// A break inside a scheduled window.
///
/// The interaction that is easy to get wrong and impossible to notice: tap out
/// of Sleep at 2am on a Mode that takes breaks, and the resumed session must
/// still be the schedule's, or the 07:00 boundary — which deliberately refuses
/// to end a session you started by hand — leaves the phone Dadded all day.
final class BreakInsideAScheduleTests: XCTestCase {

    private func sleepMode(_ h: Harness) -> DadMode {
        h.addMode(name: "Sleep",
                  schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                         endHour: 7, endMinute: 0,
                                         weekdays: ModeSchedule.everyDay),
                  breakLength: 15 * 60)
    }

    func testTheBreakRemembersItInterruptedAScheduledSession() {
        let h = Harness()
        let sleep = sleepMode(h)
        h.engine.beginScheduledSession(modeID: sleep.id)

        h.engine.handleTap()

        XCTAssertEqual(h.store.pendingResume?.startedBySchedule, true)
    }

    func testTheScheduleStillEndsASessionItsOwnBreakBroughtBack() {
        let h = Harness()
        let sleep = sleepMode(h)
        h.engine.beginScheduledSession(modeID: sleep.id)
        h.engine.handleTap()                 // up at 2am, tapped out

        h.clock.advance(15 * 60)
        h.engine.resumeFromBreak()
        XCTAssertEqual(h.store.activeSession?.startedBySchedule, true)

        h.engine.endScheduledSession(modeID: sleep.id)

        XCTAssertNil(h.store.activeSession, "07:00 must still release it")
    }

    func testAHandStartedSessionStaysHandStartedThroughABreak() {
        // The other direction, and the reason the flag is carried rather than
        // assumed: a schedule boundary must still not end a session you began
        // yourself with the same Mode.
        let h = Harness()
        let sleep = sleepMode(h)
        h.engine.dad(with: sleep)            // by hand, at 20:00
        h.engine.handleTap()
        h.clock.advance(15 * 60)
        h.engine.resumeFromBreak()

        XCTAssertNotEqual(h.store.activeSession?.startedBySchedule, true)
        h.engine.endScheduledSession(modeID: sleep.id)
        XCTAssertNotNil(h.store.activeSession, "yours means until you tap again")
    }
}
