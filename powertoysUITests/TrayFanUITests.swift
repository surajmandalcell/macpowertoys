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
        XCTAssertTrue(app.buttons["Auto"].waitForExistence(timeout: 10))

        let homeCapture = XCTAttachment(screenshot: app.screenshot())
        homeCapture.name = "Main menu without System Monitor"
        homeCapture.lifetime = .keepAlways
        add(homeCapture)

        tray.click()
        let monitor = app.menuBars.statusItems["SystemMonitorMenuBarItem"]
        XCTAssertTrue(monitor.waitForExistence(timeout: 10), app.menuBars.debugDescription)
        monitor.click()
        app.buttons["system-monitor.tray.home"].click()
        XCTAssertTrue(app.buttons["Auto"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Cool"].exists)
        XCTAssertTrue(app.buttons["Max"].exists)

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
        XCTAssertTrue(app.buttons["Auto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cool"].exists)
        XCTAssertTrue(app.buttons["Max"].exists)
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
        let cpuLoad = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@", "Load · 1 minute"
        )).firstMatch
        app.buttons["system-monitor.tray.cpu"].click()
        XCTAssertTrue(cpuLoad.waitForExistence(timeout: 5))

        home.click()
        app.buttons["system-monitor.tray.summary.cpu"].click()
        XCTAssertTrue(cpuLoad.waitForExistence(timeout: 5))

        monitor.click()
        XCTAssertTrue(cpuLoad.waitForNonExistence(timeout: 5), app.debugDescription)
        monitor.click()
        XCTAssertTrue(cpuLoad.waitForExistence(timeout: 5), app.debugDescription)

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Task Manager CPU after reopening tray"
        capture.lifetime = .keepAlways
        add(capture)

        app.buttons["system-monitor.menu.open-app"].click()
        let taskManager = app.windows["Task Manager"]
        XCTAssertTrue(taskManager.waitForExistence(timeout: 10), app.windows.debugDescription)

        let overviewScreenshot = taskManager.screenshot()
        let windowCapture = XCTAttachment(screenshot: overviewScreenshot)
        windowCapture.name = "Task Manager fixed Overview window"
        windowCapture.lifetime = .keepAlways
        add(windowCapture)

        assertTaskManagerSidebarPaintsThroughBottom(overviewScreenshot)

        XCTAssertEqual(taskManager.frame.width, 1_080, accuracy: 2)
        XCTAssertEqual(taskManager.frame.height, 660, accuracy: 2)

        let sidebarTitle = taskManager.descendants(matching: .any)["task-manager.sidebar.title"]
        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 5), taskManager.debugDescription)
        XCTAssertEqual(sidebarTitle.frame.midY, taskManager.frame.minY + 27, accuracy: 2)
        XCTAssertLessThanOrEqual(sidebarTitle.frame.maxX, taskManager.frame.minX + 200)

        let overview = app.buttons["task-manager.sidebar.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertEqual(overview.frame.minX, taskManager.frame.minX + 10, accuracy: 2)
        XCTAssertEqual(overview.frame.maxX, taskManager.frame.minX + 190, accuracy: 2)

        app.buttons["task-manager.sidebar.cpu"].click()
        XCTAssertTrue(app.staticTexts["Core activity"].waitForExistence(timeout: 5))
        let cpuCapture = XCTAttachment(screenshot: taskManager.screenshot())
        cpuCapture.name = "Task Manager grouped CPU core activity"
        cpuCapture.lifetime = .keepAlways
        add(cpuCapture)

        app.buttons["task-manager.sidebar.remote-stats"].click()
        let configure = app.buttons["system-monitor.remote.configure.ui-build-mac"]
        let connect = app.buttons["system-monitor.remote.connect.ui-build-mac"]
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertEqual(configure.frame.height, 24, accuracy: 1)
        XCTAssertEqual(connect.frame.height, 24, accuracy: 1)
        XCTAssertGreaterThan(connect.frame.width, connect.frame.height)
        XCTAssertEqual(taskManager.buttons.matching(identifier: "system-monitor.remote.connect.ui-build-mac").count, 1)
        XCTAssertEqual(connect.frame.midY, configure.frame.midY, accuracy: 1)
        XCTAssertEqual(taskManager.frame.maxX - connect.frame.maxX, 32, accuracy: 2)

        let remoteCapture = XCTAttachment(screenshot: taskManager.screenshot())
        remoteCapture.name = "Task Manager remote host and configuration actions"
        remoteCapture.lifetime = .keepAlways
        add(remoteCapture)

        app.buttons["task-manager.sidebar.processes"].click()
        let search = app.searchFields.matching(NSPredicate(
            format: "identifier == %@ OR label == %@",
            "task-manager.process.search",
            "Search name, path, or PID"
        )).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        let searchFrame = search.frame
        let searchIdleCapture = XCTAttachment(screenshot: taskManager.screenshot())
        searchIdleCapture.name = "Task Manager search idle baseline"
        searchIdleCapture.lifetime = .keepAlways
        add(searchIdleCapture)
        search.click()
        XCTAssertEqual(search.frame, searchFrame)
        let searchFocusedCapture = XCTAttachment(screenshot: taskManager.screenshot())
        searchFocusedCapture.name = "Task Manager search focused baseline"
        searchFocusedCapture.lifetime = .keepAlways
        add(searchFocusedCapture)
        let nativeTable = taskManager.tables.firstMatch
        XCTAssertTrue(nativeTable.waitForExistence(timeout: 15), app.debugDescription)
        let firstProcess = nativeTable.descendants(matching: .tableRow).firstMatch
        XCTAssertTrue(firstProcess.waitForExistence(timeout: 15), app.debugDescription)
        firstProcess.hover()

        let hoverCapture = XCTAttachment(screenshot: app.screenshot())
        hoverCapture.name = "Task Manager process identity cell hover"
        hoverCapture.lifetime = .keepAlways
        add(hoverCapture)

        firstProcess.click()
        XCTAssertFalse(app.staticTexts["Process Information"].exists, "A single click selects without inspecting")
        XCTAssertTrue(firstProcess.isSelected)
        nativeTable.typeKey(.downArrow, modifierFlags: [])
        XCTAssertFalse(firstProcess.isSelected, "Arrow keys move native selection")
        nativeTable.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Process Information"].waitForExistence(timeout: 5))

        let sheetCapture = XCTAttachment(screenshot: app.screenshot())
        sheetCapture.name = "Task Manager themed process information"
        sheetCapture.lifetime = .keepAlways
        add(sheetCapture)

        let moreMenu = app.descendants(matching: .any)["task-manager.process.more"]
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(moreMenu.label, "More")
        moreMenu.click()
        XCTAssertTrue(app.buttons["Force Quit"].waitForExistence(timeout: 5))
        let menuCapture = XCTAttachment(screenshot: app.screenshot())
        menuCapture.name = "Task Manager dark process action menu"
        menuCapture.lifetime = .keepAlways
        add(menuCapture)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func assertTaskManagerSidebarPaintsThroughBottom(_ screenshot: XCUIScreenshot) {
        guard let data = screenshot.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else {
            XCTFail("Could not inspect the Task Manager screenshot")
            return
        }
        let scaleX = CGFloat(bitmap.pixelsWide) / screenshot.image.size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / screenshot.image.size.height
        let innerX = Int(40 * scaleX)
        let edgeX = Int(198 * scaleX)
        let bodyX = Int(204 * scaleX)
        let lowerY = Int(40 * scaleY)
        let middleY = bitmap.pixelsHigh / 2
        guard let inner = bitmap.colorAt(x: innerX, y: middleY)?.usingColorSpace(.sRGB),
              let edgeMiddle = bitmap.colorAt(x: edgeX, y: middleY)?.usingColorSpace(.sRGB),
              let edgeLower = bitmap.colorAt(x: edgeX, y: lowerY)?.usingColorSpace(.sRGB),
              let body = bitmap.colorAt(x: bodyX, y: middleY)?.usingColorSpace(.sRGB) else {
            XCTFail("Could not sample the Task Manager sidebar")
            return
        }
        for edge in [edgeMiddle, edgeLower] {
            XCTAssertEqual(edge.redComponent, inner.redComponent, accuracy: 0.01)
            XCTAssertEqual(edge.greenComponent, inner.greenComponent, accuracy: 0.01)
            XCTAssertEqual(edge.blueComponent, inner.blueComponent, accuracy: 0.01)
        }
        XCTAssertGreaterThan(abs(body.redComponent - inner.redComponent), 0.01)
    }
}
