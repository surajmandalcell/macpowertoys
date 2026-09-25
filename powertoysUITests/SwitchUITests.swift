import XCTest

final class SwitchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSwitchOpensFromCLIRouteAndNavigatesByIconRail() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpt-switch-ui-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "switch"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launchEnvironment["AI_MANAGER_ROOT"] = root.path
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Switch"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let accounts = app.buttons["switch.page.Accounts"]
        let recovery = app.buttons["switch.page.Recovery"]
        XCTAssertTrue(accounts.exists)
        XCTAssertTrue(recovery.exists)
        XCTAssertTrue(window.staticTexts["Saved accounts"].exists)
        attach(window.screenshot(), named: "Switch Accounts")

        recovery.click()
        XCTAssertTrue(window.staticTexts["Interrupted operations"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Switch Recovery")

        accounts.click()
        XCTAssertTrue(window.staticTexts["Saved accounts"].waitForExistence(timeout: 5))
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
