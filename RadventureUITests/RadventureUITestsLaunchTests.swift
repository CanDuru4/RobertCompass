//
//  RadventureUITestsLaunchTests.swift
//  RadventureUITests
//
//  Created by Can Duru on 22.06.2023.
//

import XCTest

final class RadventureUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--unconfigured"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Connect your backend"].waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
