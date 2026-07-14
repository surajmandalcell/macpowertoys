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
        XCTAssertTrue(app.windows["Logs"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testOpeningToolCanCloseMainWindow() throws {
        let app = launchApp(additionalArguments: [
            "-app.closeMainWindowAfterOpeningTool", "YES"
        ])
        openLogs(in: app)

        XCTAssertFalse(app.windows["MacPowerToys"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.windows["Logs"].waitForExistence(timeout: 2))
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
