import XCTest
import CoreLocation

/// End-to-end tests against disposable loopback Firebase emulators.
/// - Note: The runner seeds the documented emulator-only player and course first.
/// - Example: Run after starting the Firebase Emulator Suite and seeding UI fixtures.
final class RadventureUITests: XCTestCase {
    /// Stop immediately after a failed user-visible assertion.
    /// - Throws: XCTest setup errors.
    /// - Example: Called by XCTest before each scenario.
    override func setUpWithError() throws { continueAfterFailure = false }

    /// A checkout with no cloud configuration must still launch with useful instructions.
    /// - Returns: Nothing.
    /// - Example: Run with XCTest.
    func testMissingConfigurationShowsSetupScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["--unconfigured"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Connect your backend"].waitForExistence(timeout: 10))
        app.terminate()
    }

    /// Verify login, team creation, scoring, live results, history, and session persistence.
    /// - Returns: Nothing.
    /// - Example: Run against seeded local Firebase emulators with simulated GPS.
    func testCompleteTeamActivity() {
        let previousLocation = XCUIDevice.shared.location
        defer { XCUIDevice.shared.location = previousLocation }
        let teamName = "UI Team \(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        app.launchArguments = ["--emulator"]
        app.launch()
        if app.tabBars.buttons["Profile"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["Profile"].tap()
            app.buttons["Sign out"].swipeUp()
            app.buttons["Sign out"].tap()
        }
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10))
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("ui-player@compass.example.test")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("Emulator-only-Compass-123!")
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 20))
        if app.buttons["Not Now"].waitForExistence(timeout: 5) { app.buttons["Not Now"].tap() }
        if app.buttons["End activity"].waitForExistence(timeout: 3) {
            tapWhenReady(app.buttons["End activity"])
            tapWhenReady(app.alerts.buttons["Leave"])
        }
        XCTAssertTrue(app.buttons["Create team"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Create team"].tap()
        XCTAssertTrue(app.buttons["Practice course (sample)"].waitForExistence(timeout: 10))
        let course = app.buttons["Practice course (sample)"]
        XCTAssertTrue(course.wait(for: \.isHittable, toEqual: true, timeout: 10), app.debugDescription)
        course.tap()
        XCTAssertTrue(app.textFields["Team name"].waitForExistence(timeout: 10), app.debugDescription)
        app.textFields["Team name"].tap()
        app.textFields["Team name"].typeText(teamName)
        app.alerts.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Start activity"].waitForExistence(timeout: 15))
        app.buttons["Start activity"].tap()
        XCTAssertTrue(app.buttons["Choose checkpoint"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Choose checkpoint"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Activity timer"].label.isEmpty)
        tapWhenReady(app.buttons["Choose checkpoint"])
        tapWhenReady(app.buttons["North checkpoint (sample)"])
        setCheckpointLocation(latitude: 41, longitude: 29)
        tapWhenReady(app.alerts.buttons["North"])
        XCTAssertTrue(app.alerts.buttons["OK"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.alerts.staticTexts["Correct answer. Your team's score is updated."].exists, app.alerts.debugDescription)
        app.alerts.buttons["OK"].tap()
        tapWhenReady(app.buttons["Choose checkpoint"])
        tapWhenReady(app.buttons["East checkpoint (sample)"])
        tapWhenReady(app.textFields["Your answer"])
        app.textFields["Your answer"].typeText("4")
        setCheckpointLocation(latitude: 41.0002, longitude: 29.0002)
        app.alerts.buttons["Submit answer"].tap()
        XCTAssertTrue(app.alerts.buttons["OK"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.alerts.staticTexts["Correct answer. Your team's score is updated."].exists, app.alerts.debugDescription)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["Activity status"].label.contains("200 points"))
        app.tabBars.buttons["Leaderboard"].tap()
        XCTAssertTrue(app.tables.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", teamName)).firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.tables.staticTexts["Practice course (sample) · \(teamName)"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Create team"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Activity status"].label.contains("200 points"))
    }

    private func tapWhenReady(_ element: XCUIElement) {
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: 10))
        element.tap()
    }

    private func setCheckpointLocation(latitude: Double, longitude: Double) {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date()
        ))
    }
}
