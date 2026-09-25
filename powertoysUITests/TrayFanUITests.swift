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
        let tray = app.menuBars.statusItems["MenuBarIcon"]
        XCTAssertTrue(tray.waitForExistence(timeout: 10))
        tray.click()
        app.buttons["System Monitor"].click()
        app.buttons["system-monitor.tray.home"].click()
        XCTAssertFalse(app.buttons["fan-control.setup"].exists)
        app.buttons["system-monitor.tray.sensors"].click()

        let setup = app.buttons["fan-control.setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 20))
        setup.click()

        XCTAssertTrue(app.staticTexts["Enable fan control"].waitForExistence(timeout: 5))
        let setupNote = app.staticTexts["MacPowerToys includes fan control. macOS may ask you to allow its background item once; there is no package or Terminal command to install."]
        XCTAssertTrue(setupNote.exists)
        XCTAssertGreaterThan(setupNote.frame.height, 20)
        XCTAssertTrue(app.buttons["Enable Fan Control"].exists)
        XCTAssertTrue(app.buttons["Check Again"].exists)

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Fan setup popover"
        capture.lifetime = .keepAlways
        add(capture)

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(app.staticTexts["Enable fan control"].exists)
    }

    @MainActor
    func testMonitorTabsCardsAndSavedSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }

        app.activate()
        let tray = app.menuBars.statusItems["MenuBarIcon"]
        XCTAssertTrue(tray.waitForExistence(timeout: 10))
        tray.click()
        app.buttons["System Monitor"].click()

        let home = app.buttons["system-monitor.tray.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.click()
        app.buttons["system-monitor.tray.cpu"].click()
        XCTAssertTrue(app.staticTexts["Usage across all cores"].waitForExistence(timeout: 5))

        home.click()
        app.buttons["system-monitor.tray.summary.cpu"].click()
        XCTAssertTrue(app.staticTexts["Usage across all cores"].waitForExistence(timeout: 5))

        tray.click()
        tray.click()
        XCTAssertTrue(app.staticTexts["Usage across all cores"].waitForExistence(timeout: 5))

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Monitor CPU after reopening tray"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
