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
            let card = app.descendants(matching: .any)["tool.\(id).card"]
            XCTAssertTrue(
                card.waitForExistence(timeout: 2),
                "Missing tool card: \(id)"
            )
        }
    }

    @MainActor
    func testRulerLaunchStaysInOverlayMode() throws {
        let app = launchApp()
        let card = app.descendants(matching: .any)["tool.ruler.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()

        let launch = app.buttons["tool.ruler.launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        launch.click()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertFalse(app.windows["Ruler"].waitForExistence(timeout: 1))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        return app
    }
}
