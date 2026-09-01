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
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))

        // Off, the footer says the Mode only runs when you tap.
        XCTAssertTrue(footer(containing: "only runs when you tap").waitForExistence(timeout: 10),
                      "A starter Mode should begin with no schedule.")

        toggle.tap()

        // On, it promises the phone will Tim itself.
        //
        // Asserting the footer rather than the switch's own `value`: two runs
        // were spent on a value assertion that never turned true, using a
        // hand-rolled poll rather than the sanctioned wait. Whether XCUITest
        // reports a SwiftUI Toggle's value promptly is not something this test
        // should depend on — the words the user reads are, and they come from
        // the same binding either way.
        XCTAssertTrue(footer(containing: "Tims itself").waitForExistence(timeout: 15),
                      "Enabling the schedule did not change what the Mode promises.")
    }

    /// `matching`, not `containing`: containing filters by DESCENDANTS, so on a
    /// static text it matches nothing and the assertion silently passes on the
    /// existence of any label at all.
    private func footer(containing text: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
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
