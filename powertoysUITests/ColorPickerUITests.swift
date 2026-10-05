import XCTest

final class ColorPickerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompactPickerKeepsProjectsAndSettingsInOneWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-app.closeMainWindowAfterOpeningTool", "YES"
        ]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()

        let card = app.descendants(matching: .any)["tool.color-picker.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()
        let embeddedShortcut = app.staticTexts["Global shortcut"]
        let embeddedColors = app.staticTexts["Saved colors"]
        XCTAssertTrue(embeddedShortcut.waitForExistence(timeout: 2))
        XCTAssertTrue(embeddedColors.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(embeddedColors.frame.minY, embeddedShortcut.frame.maxY)
        XCTAssertEqual(embeddedShortcut.frame.minX, embeddedColors.frame.minX, accuracy: 0.5)
        let launch = app.buttons["tool.color-picker.launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 2))
        launch.click()

        let window = app.windows["Color Picker"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(window.frame.width, 430)

        let search = window.descendants(matching: .any)["color-picker.search"]
        let format = window.descendants(matching: .any)["color-picker.format"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        XCTAssertTrue(format.waitForExistence(timeout: 2))
        XCTAssertEqual(search.frame.height, format.frame.height, accuracy: 0.5)

        let settings = window.descendants(matching: .any)["color-picker.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(settings.frame.midX, window.frame.midX)
        XCTAssertLessThanOrEqual(settings.frame.maxY - window.frame.minY, 40)
        settings.click()
        let appletShortcut = window.staticTexts["Global shortcut"]
        let appletColors = window.staticTexts["Saved colors"]
        XCTAssertTrue(appletShortcut.waitForExistence(timeout: 2))
        XCTAssertTrue(appletColors.exists)
        XCTAssertGreaterThan(appletColors.frame.minY, appletShortcut.frame.maxY)
        XCTAssertEqual(appletShortcut.frame.minX, appletColors.frame.minX, accuracy: 0.5)
        XCTAssertTrue(window.staticTexts["Keyboard shortcut"].exists)
        XCTAssertEqual(window.buttons["color-picker.clear-all"].label, "Clear all")
        XCTAssertFalse(window.buttons["History"].exists)
        XCTAssertFalse(window.buttons["Projects"].exists)

        window.descendants(matching: .any)["color-picker.settings"].click()
        XCTAssertTrue(window.buttons["Projects"].waitForExistence(timeout: 2))
        window.buttons["Projects"].click()
        XCTAssertTrue(window.staticTexts["Color projects"].waitForExistence(timeout: 2))
        XCTAssertTrue(window.buttons["New Project"].exists)
    }
}
