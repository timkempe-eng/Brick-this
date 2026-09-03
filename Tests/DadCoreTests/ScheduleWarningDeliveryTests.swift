import XCTest
@testable import DadCore

/// The half of the ten-minute warning that was missing: delivering it.
///
/// `ScheduleSkipTests` covers *when* a warning is owed. This covers the seam —
/// that the engine hands the answer to the system at every moment the answer
/// can change, and takes it back at every moment it stops being true.
///
/// The failure this guards is one-sided and worth naming. A warning that never
/// arrives costs somebody a sentence they were typing. A warning that arrives
/// for a night that was skipped, or while the phone is already Dadded, is the
/// app saying something untrue — and a product whose whole argument is that it
/// tells you the truth about your own phone cannot afford that one.
final class ScheduleWarningDeliveryTests: XCTestCase {

    /// A Mode that runs tonight, on a phone that is doing nothing.
    private func scheduled(_ h: Harness) -> DadMode {
        h.addMode(schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                         endHour: 23, endMinute: 0,
                                         weekdays: Set(1...7)))
    }

    func testTheWarningIsHandedOverAsSoonAsThereIsOneToHandOver() {
        let h = Harness()
        let mode = scheduled(h)

        h.engine.reconcile()

        XCTAssertEqual(h.notifier.pending?.fireAt, h.engine.nextScheduleWarning?.fireAt)
        XCTAssertTrue(h.notifier.pending?.body.contains(mode.name) ?? false,
                      "the copy names the Mode about to land: \(h.notifier.pending?.body ?? "nothing")")
    }

    func testNothingIsPendingWhileThePhoneIsAlreadyDadded() {
        // The window being warned about will not open — `beginScheduledSession`
        // refuses to stomp a session somebody started by hand — so warning
        // about it would be a notice for something that is not going to happen.
        let h = Harness()
        let mode = scheduled(h)
        h.engine.reconcile()
        XCTAssertNotNil(h.notifier.pending)

        h.engine.dad(with: mode)

        XCTAssertNil(h.notifier.pending)
    }

    func testEndingASessionPutsTheWarningBack() {
        let h = Harness()
        let mode = scheduled(h)
        h.engine.reconcile()
        h.engine.dad(with: mode)
        XCTAssertNil(h.notifier.pending)

        h.engine.unDad(.tapped)

        XCTAssertNotNil(h.notifier.pending, "the next window can run again, so it can be warned about")
    }

    func testSkippingTonightTakesTonightsWarningBack() {
        // The specific lie: "Sleep in ten minutes" for a Sleep that was told to
        // sit tonight out. A cancel that does not happen here is a
        // notification nothing else will ever remove.
        let h = Harness()
        let mode = scheduled(h)
        h.engine.reconcile()
        let tonight = h.notifier.pending

        h.engine.skipNextNight(modeID: mode.id)

        XCTAssertNotEqual(h.notifier.pending, tonight)
        XCTAssertNotEqual(h.notifier.pending?.fireAt, tonight?.fireAt,
                          "the answer moved to the next night that will actually run")
    }

    func testAModeThatWouldNotRunIsNotWarnedAbout() {
        // The same guard `beginScheduledSession` applies, so the warning and
        // the start can never disagree: a Mode that blocks nothing is never
        // registered, and promising it would be the looks-configured-does-
        // nothing failure in notification form.
        let h = Harness()
        h.addMode(apps: 0, schedule: ModeSchedule(startHour: 22, startMinute: 0,
                                                  endHour: 23, endMinute: 0,
                                                  weekdays: Set(1...7)))
        h.engine.reconcile()

        XCTAssertNil(h.notifier.pending)
    }

    func testAForegroundCorrectsTheWarningEvenWhenTheSyncFailed() {
        // `syncSchedules` only hands the warning over on success, which is
        // right — but a foreground that could not register everything is
        // exactly when a stale warning would be left standing for a Mode the
        // system refused. So `reconcile` tells the system too, outside the
        // sync, before any of its own early returns.
        let h = Harness()
        let mode = scheduled(h)
        h.scheduler.failingNames = Set(
            ScheduleWindows.windows(for: [RecurringSchedule(modeID: mode.id,
                                                            schedule: mode.schedule!)]).map(\.name))

        XCTAssertFalse(h.engine.syncSchedules())
        let afterAFailedSync = h.notifier.calls

        h.engine.reconcile()

        XCTAssertGreaterThan(h.notifier.calls, afterAFailedSync,
                             "a foreground must state the answer, not assume the sync did")
        XCTAssertNil(h.notifier.pending, "and the answer is that nothing is going to run")
    }

    // MARK: - What the system is asked to hold

    func testTheIdentifierIsStableForTheSameWindow() {
        // So re-registering an unchanged warning replaces it rather than
        // stacking a second one. `ScheduleWarning.next(among:)` breaks ties on
        // the Mode id precisely so this holds.
        let h = Harness()
        scheduled(h)

        h.engine.reconcile()
        let first = h.notifier.pending?.id
        h.clock.advance(60)
        h.engine.reconcile()

        XCTAssertEqual(h.notifier.pending?.id, first)
    }

    func testTheCopyReadsTheWindowTheWarningCarries() {
        // Written from `windowStart` rather than recomputed, which is why the
        // warning carries it: a body assembled from a second computation is a
        // body that can name a different time from the one being scheduled.
        let h = Harness()
        scheduled(h)
        h.engine.reconcile()

        guard let warning = h.engine.nextScheduleWarning else { return XCTFail("no warning") }
        let expected = PendingWarning(warning, modeName: "Deep Work")

        XCTAssertEqual(h.notifier.pending?.body, expected.body)
        XCTAssertTrue(expected.body.contains("10 minutes"),
                      "the lead time is in the copy: \(expected.body)")
    }

    func testTheWarningNamesTheAppRatherThanShoutingTheMode() {
        // The title is the app, the body is the sentence. A notification
        // titled "Sleep" on a lock screen is a word with no context.
        let h = Harness()
        scheduled(h)
        h.engine.reconcile()

        XCTAssertEqual(h.notifier.pending?.title, Vocab.appName)
    }
}
