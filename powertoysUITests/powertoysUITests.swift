//
//  powertoysUITests.swift
//  powertoysUITests
//

import XCTest

final class powertoysUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAllShippedToolsAreDiscoverable() throws {
        let app = launchApp()
        XCTAssertTrue(app.windows["MacPowerToys"].waitForExistence(timeout: 5))

        for id in ["cc-history", "rclone", "logs", "ruler", "awake", "color-picker", "text-extractor"] {
            XCTAssertTrue(
                app.buttons["tool.\(id).open"].waitForExistence(timeout: 2),
                "Missing tool button: \(id)"
            )
        }
    }

    @MainActor
    func testRulerOpensInItsOwnWindow() throws {
        let app = launchApp()
        let button = app.buttons["tool.ruler.open"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(app.windows["Ruler"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }
}
