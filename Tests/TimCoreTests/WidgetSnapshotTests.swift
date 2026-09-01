import XCTest
@testable import TimCore

/// What the Lock Screen says. The widget extension is layout only, so this is
/// where the mapping and the copy are pinned.
final class WidgetSnapshotTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_756_000_000) // 2025-08-24 02:26 UTC

    private func session(startedAt: Date, mode: String = "Deep Work") -> TimSession {
        TimSession(modeID: UUID(), modeName: mode, startedAt: startedAt)
    }

    private func stats(_ sessions: [TimSession]) -> TimStats {
        TimStats(sessions: sessions, now: now, calendar: calendar)
    }

    // MARK: - State mapping

    func testAnActiveSessionShowsTheModeAndItsStart() {
        let started = now.addingTimeInterval(-3600)
        let snapshot = WidgetSnapshot.make(session: session(startedAt: started), stats: stats([]))

        XCTAssertEqual(snapshot, .timmed(modeName: "Deep Work", since: started))
        XCTAssertTrue(snapshot.isTimmed)
    }

    func testTheStartInstantIsCarriedRawRatherThanFormatted() {
        // The widget feeds this to a self-updating timer view. A pre-formatted
        // duration would freeze at whatever second the snapshot was built.
        let started = now.addingTimeInterval(-90 * 60)
        guard case .timmed(_, let since) = WidgetSnapshot.make(
            session: session(startedAt: started), stats: stats([])) else {
            return XCTFail("expected .timmed")
        }
        XCTAssertEqual(since, started)
    }

    func testNoSessionShowsTheStreak() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        var finished = session(startedAt: yesterday)
        finished.endedAt = yesterday.addingTimeInterval(3600)

        let snapshot = WidgetSnapshot.make(session: nil, stats: stats([finished]))
        XCTAssertEqual(snapshot, .free(streakDays: 1))
        XCTAssertFalse(snapshot.isTimmed)
    }

    // MARK: - Copy

    func testTimmedCopy() {
        let snapshot = WidgetSnapshot.timmed(modeName: "Sleep", since: now)
        XCTAssertEqual(snapshot.headline, "Timmed")
        XCTAssertEqual(snapshot.detail, "Sleep")
        XCTAssertEqual(snapshot.inlineText, "Timmed · Sleep")
    }

    func testStreakCopyAgreesWithItsNumber() {
        XCTAssertEqual(WidgetSnapshot.free(streakDays: 1).detail, "1 day in a row")
        XCTAssertEqual(WidgetSnapshot.free(streakDays: 4).detail, "4 days in a row")
        XCTAssertEqual(WidgetSnapshot.free(streakDays: 1).inlineText, "1 day Tim streak")
    }

    func testWithNoStreakTheWidgetInvitesRatherThanShowingAZero() {
        // "0 days in a row" is a scold, and a widget has no room to explain.
        let snapshot = WidgetSnapshot.free(streakDays: 0)
        XCTAssertEqual(snapshot.detail, "Tim my phone")
        XCTAssertFalse(snapshot.detail.contains("0"))
        XCTAssertEqual(snapshot.inlineText, "Tim")
    }

    func testTheVerbIsNeverLowercasedOnTheLockScreen() {
        let all: [WidgetSnapshot] = [
            .timmed(modeName: "Deep Work", since: now),
            .free(streakDays: 0),
            .free(streakDays: 3),
        ]
        for snapshot in all {
            for line in [snapshot.headline, snapshot.detail, snapshot.inlineText] {
                XCTAssertFalse(line.lowercased().contains("tim") && !line.contains("Tim"),
                               "lowercase verb in: \(line)")
            }
        }
    }

    // MARK: - Refresh policy

    func testWhileTimmedThereIsNothingToRefreshFor() {
        // The elapsed time draws itself, and the session ending is announced
        // through WidgetRefreshing. A timeline reload would be pure battery.
        let snapshot = WidgetSnapshot.timmed(modeName: "Deep Work", since: now)
        XCTAssertNil(snapshot.nextRefresh(after: now, calendar: calendar))
    }

    func testWhileFreeTheWidgetWakesAtMidnight() {
        // Nothing announces a streak lapsing; it just stops being true.
        let next = WidgetSnapshot.free(streakDays: 3).nextRefresh(after: now, calendar: calendar)
        XCTAssertNotNil(next)
        let parts = calendar.dateComponents([.hour, .minute, .second], from: next!)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertGreaterThan(next!, now)
        XCTAssertLessThan(next!.timeIntervalSince(now), 24 * 3600)
    }
}

/// Three different things open Tim by URL and they mean different things.
final class IncomingLinkTests: XCTestCase {

    private func action(_ string: String) -> IncomingLink.Action? {
        IncomingLink.action(for: URL(string: string)!)
    }

    func testTheVocabulary() {
        XCTAssertEqual(action("https://tim.example.com/tap"), .toggle)
        XCTAssertEqual(action("https://tim.example.com/tim"), .tim)
        XCTAssertEqual(action("https://tim.example.com/untim"), .unTim)
        XCTAssertEqual(action("tim://open"), .open)
    }

    func testTheWidgetLinkOnlyOpens() {
        // The regression this exists for: the widget URL used to fall through
        // to the toggle default, so glancing at the Lock Screen and tapping
        // through would have released a live session.
        XCTAssertEqual(IncomingLink.action(for: IncomingLink.widgetURL), .open)
    }

    func testAnUnrecognisedLinkDoesNothing() {
        XCTAssertNil(action("https://tim.example.com/"))
        XCTAssertNil(action("https://tim.example.com/something"))
        XCTAssertNil(action("tim://wat"))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(action("tim://OPEN"), .open)
        XCTAssertEqual(action("https://tim.example.com/Tap"), .toggle)
    }
}

/// Every process that can end a session must clear the Lock Screen.
final class WidgetRefreshTests: XCTestCase {

    func testStartingASessionRefreshesTheWidget() {
        let h = Harness()
        h.addMode()
        h.engine.handleTap()
        XCTAssertEqual(h.widget.reloadCount, 1)
    }

    func testEndingASessionRefreshesTheWidget() {
        let h = Harness()
        h.addMode()
        h.engine.handleTap()
        let afterStart = h.widget.reloadCount

        h.engine.handleTap()
        XCTAssertEqual(h.widget.reloadCount, afterStart + 1)
    }

    func testAnEmergencyReleaseRefreshesTheWidget() {
        // This one runs in the shield extension's process, not the app's.
        let h = Harness()
        h.addMode()
        h.engine.handleTap()
        let afterStart = h.widget.reloadCount

        XCTAssertTrue(h.engine.emergencyUnTim())
        XCTAssertEqual(h.widget.reloadCount, afterStart + 1)
    }

    func testAScheduledReleaseRefreshesTheWidget() {
        // And this one in the DeviceActivity monitor's.
        let h = Harness()
        let mode = h.addMode(schedule: ModeSchedule(
            startHour: 22, startMinute: 0, endHour: 7, endMinute: 0,
            weekdays: ModeSchedule.everyDay))
        h.engine.beginScheduledSession(modeID: mode.id)
        let afterStart = h.widget.reloadCount

        h.engine.endScheduledSession(modeID: mode.id)
        XCTAssertEqual(h.widget.reloadCount, afterStart + 1)
    }

    func testAFailedEmergencyReleaseDoesNotRefresh() {
        // Nothing changed, so the Lock Screen has nothing new to say.
        let h = Harness()
        h.addMode()
        h.store.emergencyUses = (0..<EmergencyAllowance.perWindow).map { _ in h.clock.now }
        h.engine.handleTap()
        let afterStart = h.widget.reloadCount

        XCTAssertFalse(h.engine.emergencyUnTim())
        XCTAssertEqual(h.widget.reloadCount, afterStart)
    }
}
