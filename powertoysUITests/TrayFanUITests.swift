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
        app.launchEnvironment["MACPOWERTOYS_UI_TEST_MONITOR_MENU"] = "1"
        app.launch()
        defer { app.terminate() }

        app.activate()
        let tray = app.menuBars.statusItems.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "MenuBarIcon", "MacPowerToys"
        )).firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout: 10), app.menuBars.debugDescription)
        tray.click()
        app.buttons["tray.tab.home"].click()
        XCTAssertFalse(app.buttons["tray.tab.system-monitor"].exists)
        XCTAssertFalse(app.buttons["Fan Auto"].exists)

        let homeCapture = XCTAttachment(screenshot: app.screenshot())
        homeCapture.name = "Main menu without System Monitor"
        homeCapture.lifetime = .keepAlways
        add(homeCapture)

        let monitor = app.menuBars.statusItems.matching(identifier: "SystemMonitorMenuBarItem").firstMatch
        XCTAssertTrue(monitor.waitForExistence(timeout: 10))
        monitor.click()
        app.buttons["system-monitor.tray.home"].click()
        XCTAssertFalse(app.buttons["fan-control.setup"].exists)
        XCTAssertFalse(app.buttons["Fan Auto"].exists)
        app.buttons["system-monitor.tray.sensors"].click()

        XCTAssertTrue(app.buttons["Fan Auto"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Fan Cool"].exists)
        XCTAssertTrue(app.buttons["Fan Max"].exists)

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

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(app.staticTexts["Enable fan control"].exists)
    }

    @MainActor
    func testMonitorTabsCardsAndSavedSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launchEnvironment["MACPOWERTOYS_UI_TEST_MONITOR_MENU"] = "separate"
        app.launch()
        defer { app.terminate() }

        app.activate()
        let tray = app.menuBars.statusItems.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "MenuBarIcon", "MacPowerToys"
        )).firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout: 10), app.menuBars.debugDescription)
        tray.click()
        XCTAssertFalse(app.buttons["tray.tab.system-monitor"].exists)
        let monitor = app.menuBars.statusItems.matching(identifier: "SystemMonitorMenuBarItem").firstMatch
        XCTAssertTrue(monitor.waitForExistence(timeout: 10))
        monitor.click()

        let home = app.buttons["system-monitor.tray.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        let tabsCapture = XCTAttachment(screenshot: app.screenshot())
        tabsCapture.name = "Dedicated Monitor popup with labeled tabs"
        tabsCapture.lifetime = .keepAlways
        add(tabsCapture)
        home.click()
        app.buttons["system-monitor.tray.cpu"].click()
        XCTAssertTrue(app.staticTexts["Usage across all cores"].waitForExistence(timeout: 5))

        home.click()
        app.buttons["system-monitor.tray.summary.cpu"].click()
        XCTAssertTrue(app.staticTexts["Usage across all cores"].waitForExistence(timeout: 5))

        monitor.click()
        monitor.click()
        XCTAssertTrue(app.staticTexts["Usage across all cores"].waitForExistence(timeout: 5))

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Monitor CPU after reopening tray"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
