import XCTest

final class PortmanUITests: XCTestCase {
    @MainActor
    func testNormalLaunchOpensMenuBarPanelAndNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "portman"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }

        let forward = app.buttons["portman.page.Forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: 20), "Portman did not open from the CLI route")
        let servers = app.buttons["portman.page.Servers"]
        let alerts = app.buttons["portman.page.Alerts"]
        XCTAssertEqual(servers.frame.width, forward.frame.width, accuracy: 1)
        XCTAssertEqual(alerts.frame.width, forward.frame.width, accuracy: 1)
        XCTAssertTrue(app.staticTexts["0 KB"].isHittable)
        XCTAssertTrue(app.staticTexts["No servers listening"].isHittable)
        XCTAssertTrue(app.staticTexts["Local development ports 3000–9999 will appear here."].isHittable,
                      "The empty-state explanation is clipped below the menu-bar panel")
        attach(app.screenshot(), named: "Portman Servers")

        forward.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["SSH port forwarding"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["SSH alias or username at IP address"].exists)
        attach(app.screenshot(), named: "Portman Forward")

        let host = app.textFields["SSH alias or username at IP address"]
        host.click()
        host.typeText("alice@127.0.0.1")
        app.buttons["Enter SSH password"].click()
        XCTAssertTrue(app.secureTextFields["Password"].waitForExistence(timeout: 5),
                      "A direct SSH host did not offer password authentication")
        attach(app.screenshot(), named: "Portman SSH Password")
        app.secureTextFields["Password"].click()
        app.secureTextFields["Password"].typeText("test-password")
        app.buttons["Continue"].click()
        XCTAssertTrue(app.staticTexts["SSH port forwarding"].waitForExistence(timeout: 5),
                      "Submitting the password dismissed the Portman panel")
        XCTAssertTrue(app.staticTexts["Authentication failed. Enter the password again."].waitForExistence(timeout: 10),
                      "A rejected SSH password did not offer a retry")
        app.buttons["Cancel"].click()
        XCTAssertFalse(app.secureTextFields["Password"].exists,
                       "Cancel kept the SSH password prompt open")
        let remotePort = app.textFields["Remote port to add"]
        remotePort.click()
        remotePort.typeText("3000\n")
        XCTAssertTrue(app.buttons["Forward 1 selected"].waitForExistence(timeout: 5),
                      "Return did not add the manual remote port")

        alerts.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["No active alerts"].waitForExistence(timeout: 5)
                      || app.buttons["Inspect"].exists)
        attach(app.screenshot(), named: "Portman Alerts")

        forward.click()
        XCTAssertTrue(app.buttons["Forward 0 selected"].waitForExistence(timeout: 5),
                      "Leaving Forward kept a pending port selection")

        app.buttons["portman.settings"].click()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        attach(app.screenshot(), named: "Portman Settings")

        servers.click()
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
