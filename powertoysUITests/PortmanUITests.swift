import XCTest

final class PortmanUITests: XCTestCase {
    @MainActor
    func testNormalLaunchOpensMenuBarPanelAndNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "portman"]
        app.launch()
        defer { app.terminate() }

        let forward = app.buttons["portman.page.Forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: 20), "Portman did not open from the CLI route")
        attach(app.screenshot(), named: "Portman Servers")

        forward.click()
        XCTAssertTrue(app.staticTexts["SSH port forwarding"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["SSH host or alias"].exists)
        attach(app.screenshot(), named: "Portman Forward")

        app.buttons["portman.page.Alerts"].click()
        XCTAssertTrue(app.staticTexts["No active alerts"].waitForExistence(timeout: 5)
                      || app.buttons["Inspect"].exists)
        attach(app.screenshot(), named: "Portman Alerts")

        app.buttons["portman.settings"].click()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        attach(app.screenshot(), named: "Portman Settings")

        app.buttons["portman.page.Servers"].click()
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
