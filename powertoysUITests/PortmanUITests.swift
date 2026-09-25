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
        attach(app.screenshot(), named: "Portman Servers")

        forward.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["SSH port forwarding"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["SSH host or alias"].exists)
        attach(app.screenshot(), named: "Portman Forward")

        let host = app.textFields["SSH host or alias"]
        host.click()
        host.typeText("example-server")
        let remotePort = app.textFields["Remote port to add"]
        remotePort.click()
        remotePort.typeText("3000\n")
        XCTAssertTrue(app.buttons["Forward 1 selected"].waitForExistence(timeout: 5),
                      "Return did not add the manual remote port")

        app.buttons["portman.page.Alerts"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["No active alerts"].waitForExistence(timeout: 5)
                      || app.buttons["Inspect"].exists)
        attach(app.screenshot(), named: "Portman Alerts")

        forward.click()
        XCTAssertTrue(app.buttons["Forward 0 selected"].waitForExistence(timeout: 5),
                      "Leaving Forward kept a pending port selection")

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
