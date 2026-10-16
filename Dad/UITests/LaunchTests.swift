import XCTest

/// Proves the app launches and renders — which compilation does not.
///
/// Screen Time and NFC both no-op in the Simulator, so this can never show
/// that a tap blocks anything. What it *can* catch is the class of failure
/// that compiles perfectly and dies on the first run: the App Group missing
/// (`UserDefaultsStore` traps deliberately), a SwiftUI body that crashes on
/// first layout, a missing Info.plist key, an extension that fails to embed.
///
/// Every one of those currently reaches a device unexamined.
final class LaunchTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTheAppLaunchesAndStaysUp() {
        let app = XCUIApplication()
        app.launch()

        // Recognisable UI means SwiftUI got through a first layout pass.
        // Which screen depends on whether the Simulator grants Screen Time
        // authorization, and either is a pass — the point is that it rendered
        // rather than crashed.
        let onboarding = app.buttons["Get started"]
        let home = app.buttons["Touch Grass"]
        let rendered = onboarding.waitForExistence(timeout: 30)
            || home.waitForExistence(timeout: 5)

        XCTAssertTrue(rendered,
                      "No recognisable screen appeared. The app launched but rendered nothing.")

        // A crash a moment after first paint is still a crash.
        XCTAssertEqual(app.state, .runningForeground,
                       "The app did not stay in the foreground after launching.")
    }

    func testLaunchingTwiceIsFine() {
        // The second launch reads back what the first wrote. A store that only
        // works on a virgin install would pass a single-launch test and fail
        // every real one.
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 30)
                      || app.buttons["Touch Grass"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()

        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 30)
                      || app.buttons["Touch Grass"].waitForExistence(timeout: 5),
                      "The app rendered on a fresh install but not on a relaunch.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testOnboardingWalksThroughToThePermission() {
        // Stops short of "Allow": the Simulator never grants Screen Time, and
        // the system prompt is not this app's UI. What is checked is that each
        // page leads to the next — a page with no way forward compiles fine.
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Get started"]
        guard start.waitForExistence(timeout: 30) else {
            // Authorization granted after all: there is no onboarding to walk.
            return XCTAssertTrue(app.buttons["Touch Grass"].exists)
        }
        start.tap()

        XCTAssertTrue(app.staticTexts["Whose phone is this?"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.buttons["Allow"].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10),
                      "Back from the permission did not return to the role question.")
    }
}
