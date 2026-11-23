import AppKit
import XCTest

final class TrayFanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUnavailableFanOpensSetupPopover() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }

        app.activate()
        let tray = app.menuBars.statusItems.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "MenuBarIcon", "MacPowerToys"
        )).firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout: 10), app.menuBars.debugDescription)
        tray.click()
        app.buttons["tray.tab.home"].click()
        XCTAssertTrue(app.buttons["Auto"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Curve"].exists)
        XCTAssertTrue(app.buttons["Max"].exists)

        let homeCapture = XCTAttachment(screenshot: app.screenshot())
        homeCapture.name = "Main menu Home with Fan"
        homeCapture.lifetime = .keepAlways
        add(homeCapture)

        let setup = app.buttons["fan-control.setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 20))
        setup.click()

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Fan setup popover"
        capture.lifetime = .keepAlways
        add(capture)

        XCTAssertTrue(app.staticTexts["Enable fan control"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Enable Fan Control"].exists)
        XCTAssertTrue(app.buttons["Check Again"].exists)
    }
}
