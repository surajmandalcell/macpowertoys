import XCTest

final class MainAppBehaviorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpeningToolKeepsMainWindowOpenByDefault() throws {
        let app = launchApp()
        openLogs(in: app)

        XCTAssertTrue(app.windows["MacPowerToys"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.windows["Event Viewer"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testOpeningToolCanCloseMainWindow() throws {
        let app = launchApp(additionalArguments: [
            "-app.closeMainWindowAfterOpeningTool", "YES"
        ])
        openLogs(in: app)

        XCTAssertFalse(app.windows["MacPowerToys"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.windows["Event Viewer"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testToolCardsAndDetailsExposeSharedSettingsAndEnablement() throws {
        let app = launchApp()
        let quickToggle = app.descendants(matching: .any)["tool.logs.quick-toggle"]
        XCTAssertTrue(quickToggle.waitForExistence(timeout: 5))

        app.descendants(matching: .any)["tool.logs.card"].click()

        XCTAssertTrue(app.descendants(matching: .any)["tool.logs.enabled"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tool.logs.page"].exists)
        XCTAssertTrue(app.staticTexts["Font size"].exists)
    }

    @MainActor
    func testToolPageHeroFollowsEnablementAndEndsWithTheManual() throws {
        let app = launchApp(additionalArguments: ["-powertoys.disabledTools", "()"])
        let card = app.descendants(matching: .any)["tool.rclone.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()

        let window = app.windows["MacPowerToys"]
        let launch = app.buttons["tool.rclone.launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        XCTAssertEqual(launch.label, "Open RSync UI")

        window.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(window.staticTexts["How to use"].waitForExistence(timeout: 2))
        XCTAssertTrue(window.staticTexts["Connect Cloud Storage"].exists)
        window.scrollViews.firstMatch.swipeDown()

        let enabled = window.descendants(matching: .any)["tool.rclone.enabled"]
        enabled.click()
        XCTAssertFalse(launch.isEnabled)
        enabled.click()
        XCTAssertTrue(launch.isEnabled)
    }

    @MainActor
    private func openLogs(in app: XCUIApplication) {
        let card = app.descendants(matching: .any)["tool.logs.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()

        let launch = app.buttons["tool.logs.launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        launch.click()
    }

    @MainActor
    private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"] + additionalArguments
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        return app
    }
}
