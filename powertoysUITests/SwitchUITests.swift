import XCTest

final class SwitchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLauncherOpensSwitch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpt-switch-launcher-ui-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "main"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launchEnvironment["AI_MANAGER_ROOT"] = root.path
        app.launch()
        defer { app.terminate() }

        let card = app.descendants(matching: .any)["tool.switch.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        attach(app.screenshot(), named: "Launcher All Tools")
        card.click()

        let launch = app.buttons["tool.switch.launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        attach(app.screenshot(), named: "Switch Launcher Detail")
        app.activate()
        let launchReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: launch)
        XCTAssertEqual(XCTWaiter.wait(for: [launchReady], timeout: 5), .completed)
        launch.click()

        let window = app.windows["Switch"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        attach(window.screenshot(), named: "Switch Opened From Launcher")
    }

    @MainActor
    func testSwitchOpensFromCLIRouteAndNavigatesSharedSidebar() throws {
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
        let backup = app.buttons["switch.page.Backup"]
        let settings = app.buttons["switch.page.Settings"]
        XCTAssertTrue(backup.exists)
        XCTAssertTrue(settings.exists)
        XCTAssertTrue(window.staticTexts["Add your first account"].waitForExistence(timeout: 5))
        let add = app.descendants(matching: .any).matching(identifier: "switch.add").firstMatch
        XCTAssertTrue(add.exists)
        add.click()
        XCTAssertTrue(app.buttons["switch.provider.claude-code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue"].exists)
        attach(window.screenshot(), named: "Switch Add Account")
        app.buttons["Close"].click()
        XCTAssertTrue(app.buttons["switch.about"].exists)
        XCTAssertTrue(window.staticTexts["Add your first account"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Switch Accounts")

        backup.click()
        XCTAssertTrue(window.staticTexts["No interrupted operations"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Switch Backup")
        app.buttons["View accounts"].click()
        XCTAssertTrue(window.staticTexts["Add your first account"].waitForExistence(timeout: 5))

        settings.click()
        XCTAssertTrue(window.staticTexts["Data locations"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Appearance"].exists)
        attach(window.screenshot(), named: "Switch Settings")

        app.buttons["switch.about"].click()
        XCTAssertFalse(app.buttons["tool.switch.launch"].exists)
        XCTAssertTrue(window.staticTexts["About"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Switch About")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
