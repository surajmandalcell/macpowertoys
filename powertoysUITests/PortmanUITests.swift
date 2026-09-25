import XCTest

final class PortmanUITests: XCTestCase {
    @MainActor
    func testFourServerRowsMatchMemoryBarAndShowFooter() throws {
        var listeners: [Process] = []
        defer {
            for listener in listeners where listener.isRunning { listener.terminate() }
            listeners.forEach { $0.waitUntilExit() }
        }
        for port in [7411, 7412, 7413, 7414] {
            let listener = Process()
            listener.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            listener.arguments = ["-l", String(port)]
            try listener.run()
            listeners.append(listener)
        }
        Thread.sleep(forTimeInterval: 0.25)

        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "portman"]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["portman.local.7414"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let bar = app.descendants(matching: .any)["portman.memoryBreakdown"]
        XCTAssertTrue(bar.exists)
        XCTAssertEqual(row.frame.minX, bar.frame.minX, accuracy: 1)
        XCTAssertEqual(row.frame.width, bar.frame.width, accuracy: 1)
        let sort = app.descendants(matching: .any)["portman.sort"]
        XCTAssertTrue(sort.isHittable, "Sort by is clipped below the four-server panel")
        attach(app.screenshot(), named: "Portman four servers and footer")
    }

    @MainActor
    func testServerHoverReplacesMetricsWithActions() throws {
        let listener = Process()
        listener.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        listener.arguments = ["-l", "7265"]
        try listener.run()
        defer {
            if listener.isRunning { listener.terminate() }
            listener.waitUntilExit()
        }
        Thread.sleep(forTimeInterval: 0.25)

        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "portman"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["portman.local.7265"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Portman did not discover the test listener")
        attach(app.screenshot(), named: "Portman server at rest")
        let sort = app.descendants(matching: .any)["portman.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5), "Server sorting is missing from the footer")
        sort.click()
        let memory = app.menuItems["Memory"]
        XCTAssertTrue(memory.waitForExistence(timeout: 5))
        memory.click()
        attach(app.screenshot(), named: "Portman sorted by memory")

        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).hover()
        let link = app.buttons["portman.link.7265"]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Row hover did not show the link action")
        XCTAssertTrue(app.buttons["portman.stop.7265"].exists)
        attach(app.screenshot(), named: "Portman server hover")

        link.hover()
        attach(app.screenshot(), named: "Portman link hover")

        sort.click()
        app.menuItems["Port"].click()
    }

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
        let settings = app.buttons["portman.page.Settings"]
        XCTAssertEqual(servers.frame.width, forward.frame.width, accuracy: 1)
        XCTAssertEqual(settings.frame.width, forward.frame.width, accuracy: 1)
        XCTAssertTrue(app.buttons["portman.refresh"].exists)
        if app.staticTexts["No servers listening"].exists {
            XCTAssertTrue(app.staticTexts["0 KB"].isHittable)
            XCTAssertTrue(app.staticTexts["Local development ports 3000–9999 will appear here."].isHittable,
                          "The empty-state explanation is clipped below the menu-bar panel")
        } else {
            XCTAssertTrue(app.descendants(matching: .any)["portman.sort"].isHittable)
        }
        attach(app.screenshot(), named: "Portman Servers")

        forward.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["SSH port forwarding"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["SSH alias or username at IP address"].exists)
        attach(app.screenshot(), named: "Portman Forward")

        let host = app.textFields["SSH alias or username at IP address"]
        host.click()
        host.typeText("alice@127.0.0.1")
        XCTAssertFalse(app.buttons["Enter SSH password"].exists,
                       "Forward offered a password before SSH requested one")
        XCTAssertFalse(app.secureTextFields["Password"].exists,
                       "Entering a host opened a premature password prompt")
        let remotePort = app.textFields["Remote port to add"]
        remotePort.click()
        remotePort.typeText("3000\n")
        XCTAssertTrue(app.buttons["Forward 1 selected"].waitForExistence(timeout: 5),
                      "Return did not add the manual remote port")

        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        attach(app.screenshot(), named: "Portman Settings")
        let search = app.searchFields["portman.settings.search"]
        search.click()
        search.typeText("scan")
        XCTAssertGreaterThan(search.frame.width, 300, "Settings search did not fill the content width")
        XCTAssertTrue(app.staticTexts["Scan ports"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Keyboard shortcut"].exists)
        attach(app.screenshot(), named: "Portman Settings search")
        let interval = app.descendants(matching: .any)["portman.settings.interval"]
        guard interval.isHittable else {
            XCTFail("The scan interval selector is not clickable.\n\(app.debugDescription)")
            return
        }
        interval.click()
        app.menuItems["5 seconds"].click()
        XCTAssertEqual(interval.value as? String, "5 seconds",
                      "Choosing a scan interval did not update the setting")
        interval.click()
        app.menuItems["2 seconds"].click()
        search.click()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        search.typeText("mode")
        let cleanup = app.descendants(matching: .any)["portman.settings.cleanupMode"]
        guard cleanup.isHittable else {
            XCTFail("The cleanup mode selector is not clickable.\n\(app.debugDescription)")
            return
        }
        cleanup.click()
        app.menuItems["Off"].click()
        XCTAssertEqual(cleanup.value as? String, "Off",
                      "Choosing a cleanup mode did not update the setting")
        cleanup.click()
        app.menuItems["Ask"].click()

        forward.click()
        XCTAssertTrue(app.buttons["Forward 0 selected"].waitForExistence(timeout: 5),
                      "Leaving Forward kept a pending port selection")

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
