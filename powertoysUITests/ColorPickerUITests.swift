import XCTest

final class ColorPickerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompactPickerKeepsProjectsAndSettingsInOneWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()

        let card = app.descendants(matching: .any)["tool.color-picker.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()
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
        settings.click()
        XCTAssertTrue(window.staticTexts["GLOBAL SHORTCUT"].waitForExistence(timeout: 2))
        XCTAssertTrue(window.staticTexts["Keyboard shortcut"].exists)

        window.buttons["Projects"].click()
        XCTAssertTrue(window.staticTexts["COLOR PROJECTS"].waitForExistence(timeout: 2))
        XCTAssertTrue(window.buttons["New Project"].exists)
    }
}
