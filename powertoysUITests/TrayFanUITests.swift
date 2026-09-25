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

        let setup = app.buttons["fan-control.setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 20))
        setup.click()

        XCTAssertTrue(app.staticTexts["Enable fan control"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1  Install smctl"].exists)
        XCTAssertTrue(app.staticTexts["2  Approve its helper"].exists)
        let installNote = app.staticTexts["Install with Homebrew, or use the guide for other methods."]
        let approvalNote = app.staticTexts["Run this in Terminal. macOS will ask for administrator approval."]
        XCTAssertTrue(installNote.exists)
        XCTAssertTrue(approvalNote.exists)
        XCTAssertGreaterThan(installNote.frame.height, 20)
        XCTAssertGreaterThan(approvalNote.frame.height, 20)
        XCTAssertTrue(app.buttons["Copy smctl installation command"].exists)
        XCTAssertTrue(app.buttons["Copy helper installation command"].exists)
        XCTAssertTrue(app.buttons["Check again"].exists)

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Fan setup popover"
        capture.lifetime = .keepAlways
        add(capture)

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(app.staticTexts["Enable fan control"].exists)
    }
}
