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

        let overlay = app.descendants(matching: .any)["ruler.horizontal.overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        overlay.click()
        app.typeKey("q", modifierFlags: .command)
        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertFalse(overlay.waitForExistence(timeout: 1))
    }

    @MainActor
    func testAwakeHasFixedSizeAndTitlebarDisplayToggle() throws {
        let app = launchApp()
        let card = app.descendants(matching: .any)["tool.awake.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()

        let launch = app.buttons["tool.awake.launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 2))
        launch.click()

        let window = app.windows["Awake"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let initialFrame = window.frame
        let lowerRight = window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        lowerRight.press(
            forDuration: 0.1,
            thenDragTo: lowerRight.withOffset(CGVector(dx: 100, dy: 100))
        )
        XCTAssertEqual(window.frame, initialFrame)

        let toggle = window.switches["Keep Display On"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertTrue(toggle.isEnabled)
        let initialValue = String(describing: toggle.value)
        toggle.click()
        XCTAssertNotEqual(String(describing: toggle.value), initialValue)
        toggle.click()
        XCTAssertEqual(String(describing: toggle.value), initialValue)
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
