import XCTest

/// Walks the screens.
///
/// A Simulator never grants Family Controls authorization, so the app would
/// otherwise sit on onboarding forever and six hundred lines of SwiftUI would
/// first execute on somebody's phone. A DEBUG-only launch argument steps past
/// that gate; everything below it is the real app, the real store and the real
/// engine.
///
/// What this cannot show: that any of it blocks an app. Screen Time no-ops
/// here. It shows the screens build, navigate and survive being left and
/// returned to — which is exactly the class of bug that compiles cleanly.
private extension XCUIElement {
    /// `waitForExistence` for a value rather than existence.
    func waitForValue(_ expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if value as? String == expected { return true }
            usleep(200_000)
        }
        return value as? String == expected
    }
}

final class ScreenTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-TimBypassOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["Tim my phone"].waitForExistence(timeout: 30),
                      "The home screen never appeared.")
    }

    func testTheModesScreenOpensAndListsTheStarters() {
        app.buttons["Modes"].firstMatch.tap()

        // The starter Modes are what a fresh install shows, so this also
        // proves the store read back through the new schema envelope.
        XCTAssertTrue(app.staticTexts["Deep Work"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sleep"].exists)
    }

    func testAModeEditorOpensAndCloses() {
        app.buttons["Modes"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Deep Work"].waitForExistence(timeout: 10))

        app.staticTexts["Deep Work"].tap()
        // Both are editor-only, so their presence means the sheet built —
        // including the schedule section and its weekday picker.
        XCTAssertTrue(app.switches["Run on a schedule"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Cancel"].exists)

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Deep Work"].waitForExistence(timeout: 10))
    }

    func testTurningOnAScheduleChangesWhatTheModePromises() {
        app.buttons["Modes"].firstMatch.tap()
        app.staticTexts["Deep Work"].firstMatch.tap()
        let toggle = app.switches["Run on a schedule"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0", "the starter Mode has no schedule")

        toggle.tap()

        // Two assertions, because they fail for different reasons and the
        // difference is the whole diagnosis: the first says the binding
        // created a schedule, the second says the view noticed.
        XCTAssertTrue(toggle.waitForValue("1", timeout: 10),
                      "The toggle did not turn on — the optional-schedule binding didn't take.")

        // `matching`, not `containing`: containing filters by DESCENDANTS, so
        // on a static text it matches nothing and the assertion silently tests
        // the existence of any label at all.
        let promise = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Tims itself")).firstMatch
        XCTAssertTrue(promise.waitForExistence(timeout: 10),
                      "The toggle turned on but the footer never promised the phone would Tim itself.")
    }

    func testSettingsOpens() {
        app.buttons["Settings"].firstMatch.tap()
        // The pairing action, not the section header: a header's element type
        // is a SwiftUI implementation detail, and the button is the thing a
        // user actually needs to find.
        XCTAssertTrue(app.buttons["Pair a Tim tag"].waitForExistence(timeout: 10))
    }

    func testStatsOpensWithNoHistory() {
        // The empty state is the one a fresh install always hits, and the one
        // most likely to divide by zero.
        app.buttons["Stats"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 10))
    }

    func testTheAppSurvivesTheWholeTour() {
        for label in ["Modes", "Settings", "Stats"] {
            app.buttons[label].firstMatch.tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10),
                          "\(label) did not present.")
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["Tim my phone"].waitForExistence(timeout: 10),
                          "Did not get back from \(label).")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }
}
