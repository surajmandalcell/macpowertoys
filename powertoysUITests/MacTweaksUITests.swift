import XCTest

final class MacTweaksUITests: XCTestCase {
    @MainActor func testInlineControlsAndSearchInNormalApp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "mac-tweaks"]
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Mac Tweaks"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        let micToggle = window.descendants(matching: .any)
            .matching(identifier: "mac-tweaks.mic-lock.enabled").firstMatch
        XCTAssertTrue(window.buttons["mac-tweaks.card.mic-lock"].waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["EVERYDAY"].exists)
        XCTAssertFalse(micToggle.exists)
        attach(window.screenshot(), named: "Mac Tweaks Collapsed")

        window.buttons["mac-tweaks.card.mic-lock"].click()
        XCTAssertTrue(micToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["mac-tweaks.card.mic-lock"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Mic Lock Expanded")
        window.buttons["mac-tweaks.card.mic-lock"].click()
        XCTAssertFalse(micToggle.exists)

        window.buttons["mac-tweaks.category.Finder"].click()
        XCTAssertTrue(window.buttons["mac-tweaks.card.finder.hidden-files"].waitForExistence(timeout: 5))
        XCTAssertFalse(window.buttons["mac-tweaks.card.finder.open-animation"].exists)

        window.buttons["mac-tweaks.card.finder.hidden-files"].click()
        XCTAssertTrue(window.buttons["mac-tweaks.apply.finder.hidden-files"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["mac-tweaks.card.finder.hidden-files"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Finder Expanded")
        window.buttons["mac-tweaks.card.finder.quit"].click()
        XCTAssertFalse(window.buttons["mac-tweaks.apply.finder.hidden-files"].exists)
        XCTAssertTrue(window.buttons["mac-tweaks.apply.finder.quit"].waitForExistence(timeout: 5))

        window.buttons["mac-tweaks.category.Dock"].click()
        let firstDockCard = window.buttons["mac-tweaks.card.dock.reveal-delay"]
        XCTAssertTrue(firstDockCard.waitForExistence(timeout: 5))
        firstDockCard.click()
        window.scrollViews.element(boundBy: 1).swipeUp()
        XCTAssertTrue(firstDockCard.isHittable, "The first result should remain visible while later cards scroll")
        attach(window.screenshot(), named: "Mac Tweaks Pinned First Result")

        let power = window.buttons["mac-tweaks.category.Power and hardware"]
        XCTAssertTrue(power.exists)
        XCTAssertLessThanOrEqual(power.frame.height, 30, "A short category label should fit one sidebar row")
        power.click()
        XCTAssertTrue(window.buttons["mac-tweaks.card.helper.keep-awake"].waitForExistence(timeout: 5))
        XCTAssertFalse(window.buttons["mac-tweaks.card.hardware.auto-start"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Power Collapsed")

        let search = window.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("screnshot format")
        XCTAssertTrue(window.buttons["mac-tweaks.card.screenshots.format"].waitForExistence(timeout: 5))
        window.buttons["mac-tweaks.card.screenshots.format"].click()
        XCTAssertTrue(window.buttons["mac-tweaks.apply.screenshots.format"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Mac Tweaks Search Expanded")

        window.buttons["Clear search"].firstMatch.click()
        search.click()
        search.typeText("search ")
        XCTAssertTrue(window.staticTexts["No matches for “search”"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Mac Tweaks Empty Search")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
