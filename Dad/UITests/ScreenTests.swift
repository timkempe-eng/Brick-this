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
        app.launchArguments = ["-DadBypassOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["Dad my phone"].waitForExistence(timeout: 30),
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

        app.staticTexts["Deep Work"].firstMatch.tap()
        // An editor-only row, so its presence means the sheet built.
        let editorOnly = app.staticTexts["Apps and sites to hide"]
        XCTAssertTrue(editorOnly.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Cancel"].exists)

        app.buttons["Cancel"].tap()

        // Assert the editor GOES AWAY, not that "Deep Work" exists — that
        // label is also the editor's own navigation title, so the old
        // assertion passed whether or not Cancel did anything. It was then
        // cited as proof that taps reach the editor and its actions run,
        // which narrowed the hunt for the editor bug in the wrong direction.
        // Nothing yet establishes that a tap on this sheet does anything.
        XCTAssertTrue(editorOnly.waitForNonExistence(timeout: 10),
                      "Cancel did not dismiss the editor, so taps may not be reaching it at all.")
    }

    /// Turning the schedule on must change what the Mode says it will do —
    /// and for a starter Mode, which blocks nothing, what it says must NOT be
    /// that your phone will Dad itself. A Mode that blocks nothing is never
    /// registered with the system scheduler, so promising it would be the
    /// looks-configured-does-nothing failure. That is a decision, not an
    /// implementation detail, which is why it is pinned here.
    ///
    /// Three CI runs were spent failing this test on the promise. The app was
    /// right to refuse to make it; the test was asserting the wrong sentence.
    func testTurningOnAScheduleChangesWhatTheModePromises() {
        app.buttons["Modes"].firstMatch.tap()
        app.staticTexts["Deep Work"].firstMatch.tap()
        let toggle = app.switches["Run on a schedule"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))

        // Off, the Mode only runs when you tap.
        XCTAssertTrue(footer(containing: "only runs when you tap").waitForExistence(timeout: 10),
                      "A starter Mode should begin with no schedule.")

        toggle.tap()

        // On, it says what is still missing rather than implying it will run.
        //
        // Asserting the words rather than the switch's own `value`: two runs
        // were spent on a value assertion that never turned true, using a
        // hand-rolled poll rather than the sanctioned wait. Whether XCUITest
        // reports a SwiftUI Toggle's value promptly is not something this test
        // should depend on. The footer comes from the same binding, and the
        // words are what the user actually acts on.
        // The failure message carries the screen with it. Asserting a string
        // and reporting only "it wasn't there" is what turned one bug into
        // five CI runs of guessing which branch had rendered.
        XCTAssertTrue(footer(containing: "blocks something").waitForExistence(timeout: 15),
                      """
                      Enabling the schedule did not change what the Mode promises.
                      Switch value: \(String(describing: toggle.value))
                      On screen: \(visibleText())
                      """)
        XCTAssertFalse(footer(containing: "itself").exists,
                       "A Mode that blocks nothing must not promise to Dad your phone.")
    }

    /// Every label currently on screen, for a failure message. A test that says
    /// what it actually saw costs one run; one that says only "not found" costs
    /// as many as it takes to guess.
    private func visibleText() -> String {
        app.staticTexts.allElementsBoundByIndex
            .prefix(40)
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    /// Does ANY control in the Mode editor accept a change?
    ///
    /// "Strict" is the simplest possible case — `Toggle(isOn: $mode.isStrict)`,
    /// a direct binding to a non-optional Bool on the editor's own `@State`.
    /// If even that will not flip, the schedule switch is not the problem and
    /// the editor's state is; if it flips, the fault is specific to the
    /// schedule row. The schedule switch failing has already been reproduced
    /// four times without ever separating those two.
    func testTheEditorAcceptsASimpleToggle() {
        app.buttons["Modes"].firstMatch.tap()
        app.staticTexts["Deep Work"].firstMatch.tap()

        let strict = app.switches["Strict"]
        XCTAssertTrue(strict.waitForExistence(timeout: 15))
        let before = String(describing: strict.value)

        strict.tap()

        XCTAssertEqual(strict.value as? String, "1",
                       """
                       A plain direct binding did not take either, so the fault \
                       is the editor's state and not the schedule row.
                       Strict before: \(before)
                       Hittable: \(strict.isHittable)
                       On screen: \(visibleText())
                       """)
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
        XCTAssertTrue(app.buttons["Pair a Dad tag"].waitForExistence(timeout: 10))
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
            XCTAssertTrue(app.buttons["Dad my phone"].waitForExistence(timeout: 10),
                          "Did not get back from \(label).")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }
}
