import XCTest

final class DiskExplorerUITests: XCTestCase {
    @MainActor func testScanControlsAndResultTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "disk-explorer"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Disk Explorer"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        XCTAssertTrue(window.descendants(matching: .any)["diskExplorer.scan"].waitForExistence(timeout: 5))
        let contents = window.buttons["diskExplorer.contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.click()
        XCTAssertTrue(window.textFields["Search Contents"].waitForExistence(timeout: 5))
        contents.click()
        XCTAssertFalse(window.textFields["Search Contents"].exists)

        let tabs = window.descendants(matching: .any)["diskExplorer.resultTabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.descendants(matching: .any)["Largest Files"].click()
        XCTAssertTrue(window.textFields["Filter largest files"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Disk Explorer Largest Files")
        tabs.descendants(matching: .any)["Visualization"].click()
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Disk Explorer Visualization")

        let statistics = window.buttons["diskExplorer.statistics"]
        XCTAssertTrue(statistics.waitForExistence(timeout: 5))
        statistics.click()
        XCTAssertTrue(app.staticTexts["Measured So Far"].waitForExistence(timeout: 5)
                      || app.staticTexts["Scan Statistics"].exists)
        attach(app.screenshot(), named: "Disk Explorer Scan Statistics")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
