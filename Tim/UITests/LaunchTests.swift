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
        let onboarding = app.buttons["Allow Screen Time access"]
        let home = app.buttons["Tim my phone"]
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
        XCTAssertTrue(app.buttons["Allow Screen Time access"].waitForExistence(timeout: 30)
                      || app.buttons["Tim my phone"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()

        XCTAssertTrue(app.buttons["Allow Screen Time access"].waitForExistence(timeout: 30)
                      || app.buttons["Tim my phone"].waitForExistence(timeout: 5),
                      "The app rendered on a fresh install but not on a relaunch.")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
