import AppKit
import XCTest

final class MacTweaksUITests: XCTestCase {
    @MainActor func testReferenceLayoutNavigationAndRankedSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "mac-tweaks"]
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Mac Tweaks"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        XCTAssertEqual(window.frame.width, 1_120, accuracy: 3)
        XCTAssertEqual(window.frame.height, 826, accuracy: 3)
        XCTAssertTrue(window.staticTexts["Mac Tweaks"].exists)
        XCTAssertTrue(window.staticTexts["Dock"].exists)

        let revealDelay = element(in: window, identifier: "mac-tweaks.setting.autohide-delay")
        XCTAssertTrue(revealDelay.waitForExistence(timeout: 10))
        XCTAssertTrue(revealDelay.isHittable, "The first setting must be visible immediately")
        attach(window.screenshot(), named: "Mac Tweaks Reference Dock")

        let finder = window.buttons["mac-tweaks.category.Finder"]
        XCTAssertTrue(finder.exists)
        XCTAssertLessThanOrEqual(finder.frame.height, 36)
        finder.click()
        XCTAssertTrue(element(in: window, identifier: "mac-tweaks.setting.AppleShowAllFiles").waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Mac Tweaks Reference Finder")

        window.buttons["mac-tweaks.category.Input"].click()
        XCTAssertTrue(element(in: window, identifier: "mac-tweaks.mic-lock.enabled").waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Input priority"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Reference Input")

        let search = window.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("screnshot format")
        XCTAssertTrue(element(in: window, identifier: "mac-tweaks.setting.type").waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Screenshot format"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Ranked Search")

        search.click()
        app.typeKey("a", modifierFlags: .command)
        search.typeText("search ")
        XCTAssertTrue(window.staticTexts["No matching settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["Clear search"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Empty Search")
    }

    @MainActor func testWindowUsesDarkReferenceAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-appTheme", "Light",
                               "--open", "mac-tweaks"]
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Mac Tweaks"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        let screenshot = window.screenshot()
        assertDarkBackground(screenshot)
        attach(screenshot, named: "Mac Tweaks Fixed Dark Appearance")
    }

    private func element(in window: XCUIElement, identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertDarkBackground(_ screenshot: XCUIScreenshot) {
        guard let data = screenshot.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let color = bitmap.colorAt(x: bitmap.pixelsWide * 9 / 10,
                                         y: bitmap.pixelsHigh * 4 / 5)?.usingColorSpace(.deviceRGB) else {
            XCTFail("Could not inspect the Mac Tweaks screenshot appearance")
            return
        }
        XCTAssertLessThan(color.brightnessComponent, 0.25, "The reference window must stay dark")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
