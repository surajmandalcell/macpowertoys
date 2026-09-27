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

        tray.click()
        let monitor = app.menuBars.statusItems["SystemMonitorMenuBarItem"]
        XCTAssertTrue(monitor.waitForExistence(timeout: 10), app.menuBars.debugDescription)
        monitor.click()
        app.buttons["system-monitor.tray.home"].click()
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

        app.buttons["system-monitor.tray.sensors"].click()
        XCTAssertTrue(app.staticTexts["Enable fan control"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Fan Auto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Fan Cool"].exists)
        XCTAssertTrue(app.buttons["Fan Max"].exists)
    }

    @MainActor
    func testMonitorTabsCardsAndSavedSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launchEnvironment["MACPOWERTOYS_UI_TEST_MONITOR_MENU"] = "separate"
        app.launchEnvironment["MACPOWERTOYS_UI_TEST_REMOTE_PROFILES"] = "1"
        app.launch()
        defer { app.terminate() }

        app.activate()
        let tray = app.menuBars.statusItems.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "MenuBarIcon", "MacPowerToys"
        )).firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout: 10), app.menuBars.debugDescription)
        tray.click()
        XCTAssertFalse(app.buttons["tray.tab.system-monitor"].exists)
        tray.click()
        let monitor = app.menuBars.statusItems["SystemMonitorMenuBarItem"]
        XCTAssertTrue(monitor.waitForExistence(timeout: 10), app.menuBars.debugDescription)
        monitor.click()

        let home = app.buttons["system-monitor.tray.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.click()
        XCTAssertTrue(app.staticTexts["Build Mac"].waitForExistence(timeout: 5))
        let tabsCapture = XCTAttachment(screenshot: app.screenshot())
        tabsCapture.name = "Dedicated Task Manager popup"
        tabsCapture.lifetime = .keepAlways
        add(tabsCapture)
        app.buttons["system-monitor.tray.cpu"].click()
        XCTAssertTrue(app.staticTexts["Load · 1 minute"].waitForExistence(timeout: 5))

        home.click()
        app.buttons["system-monitor.tray.summary.cpu"].click()
        XCTAssertTrue(app.staticTexts["Load · 1 minute"].waitForExistence(timeout: 5))

        monitor.click()
        monitor.click()
        XCTAssertTrue(app.staticTexts["Load · 1 minute"].waitForExistence(timeout: 5))

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Task Manager CPU after reopening tray"
        capture.lifetime = .keepAlways
        add(capture)

        app.buttons["system-monitor.menu.open-app"].click()
        let taskManager = app.windows["Task Manager"]
        XCTAssertTrue(taskManager.waitForExistence(timeout: 10), app.windows.debugDescription)
        XCTAssertEqual(taskManager.frame.width, 1_080, accuracy: 2)
        XCTAssertEqual(taskManager.frame.height, 660, accuracy: 2)

        let sidebarTitle = app.staticTexts["task-manager.sidebar.title"]
        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebarTitle.frame.midY, taskManager.frame.minY + 20, accuracy: 2)
        let closeButton = taskManager.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "close"
        )).firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), taskManager.debugDescription)
        XCTAssertEqual(closeButton.frame.midY, sidebarTitle.frame.midY, accuracy: 2)

        app.buttons["task-manager.sidebar.remote-stats"].click()
        let configure = app.buttons["system-monitor.remote.configure.ui-build-mac"]
        let connect = app.buttons["system-monitor.remote.connect.ui-build-mac"]
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertEqual(configure.frame.height, connect.frame.height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 34)
        XCTAssertEqual(connect.frame.minX - configure.frame.maxX, 8, accuracy: 2)
        XCTAssertGreaterThanOrEqual(taskManager.frame.maxX - connect.frame.maxX, 28)
        XCTAssertLessThanOrEqual(taskManager.frame.maxX - connect.frame.maxX, 40)

        let remoteCapture = XCTAttachment(screenshot: app.screenshot())
        remoteCapture.name = "Task Manager balanced Remote Stats actions"
        remoteCapture.lifetime = .keepAlways
        add(remoteCapture)

        app.buttons["task-manager.sidebar.processes"].click()
        let processRows = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "task-manager.process.row."
        ))
        let firstProcess = processRows.firstMatch
        XCTAssertTrue(firstProcess.waitForExistence(timeout: 15), app.debugDescription)
        firstProcess.hover()

        let hoverCapture = XCTAttachment(screenshot: app.screenshot())
        hoverCapture.name = "Task Manager process identity cell hover"
        hoverCapture.lifetime = .keepAlways
        add(hoverCapture)

        firstProcess.click()
        XCTAssertTrue(app.staticTexts["Process Information"].waitForExistence(timeout: 5))

        let sheetCapture = XCTAttachment(screenshot: app.screenshot())
        sheetCapture.name = "Task Manager themed process information"
        sheetCapture.lifetime = .keepAlways
        add(sheetCapture)

        let moreMenu = app.descendants(matching: .any)["task-manager.process.more"]
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(moreMenu.label, "More")
        moreMenu.click()
        XCTAssertTrue(app.menuItems["Force Quit"].waitForExistence(timeout: 5))
        let menuCapture = XCTAttachment(screenshot: app.screenshot())
        menuCapture.name = "Task Manager dark process action menu"
        menuCapture.lifetime = .keepAlways
        add(menuCapture)
        app.typeKey(.escape, modifierFlags: [])
    }
}
