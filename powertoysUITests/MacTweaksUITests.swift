import XCTest

final class MacTweaksUITests: XCTestCase {
    @MainActor func testGroupedSidebarCardsAndSearchInNormalApp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "mac-tweaks"]
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Mac Tweaks"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        XCTAssertTrue(window.buttons["mac-tweaks.card.mic-lock"].waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["EVERYDAY"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Input")

        window.buttons["mac-tweaks.category.Finder"].click()
        XCTAssertTrue(window.buttons["mac-tweaks.card.finder.hidden-files"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Mac Tweaks Finder")

        window.buttons["mac-tweaks.card.finder.hidden-files"].click()
        XCTAssertTrue(window.buttons["mac-tweaks.back"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Mac Tweaks Setting")
        window.buttons["mac-tweaks.back"].click()

        let search = window.textFields["Search tweaks"]
        search.click()
        search.typeText("screnshot format")
        XCTAssertTrue(window.buttons["mac-tweaks.card.screenshots.format"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Mac Tweaks Search")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
