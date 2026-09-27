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
        XCTAssertEqual(window.frame.width, 900, accuracy: 3)
        XCTAssertEqual(window.frame.height, 620, accuracy: 3)
        XCTAssertTrue(window.buttons["mac-tweaks.about"].exists)
        XCTAssertTrue(window.staticTexts["Dock"].exists)

        let revealDelay = element(in: window, identifier: "mac-tweaks.setting.autohide-delay")
        XCTAssertTrue(revealDelay.waitForExistence(timeout: 10))
        XCTAssertTrue(revealDelay.isHittable, "The first setting must be visible immediately")
        attach(window.screenshot(), named: "Mac Tweaks Reference Dock")

        let dockPreview = element(in: window, identifier: "mac-tweaks.preview.dockReveal")
        XCTAssertTrue(dockPreview.waitForExistence(timeout: 5))
        dockPreview.hover()
        Thread.sleep(forTimeInterval: 0.2)
        let earlyMotion = dockPreview.screenshot().image.tiffRepresentation
        Thread.sleep(forTimeInterval: 1)
        let laterMotion = dockPreview.screenshot().image.tiffRepresentation
        XCTAssertNotEqual(earlyMotion, laterMotion, "The Dock preview must keep moving while hovered")
        attach(window.screenshot(), named: "Mac Tweaks Dock Motion")

        let finder = window.buttons["mac-tweaks.category.Finder"]
        XCTAssertTrue(finder.exists)
        XCTAssertLessThanOrEqual(finder.frame.height, 36)
        finder.click()
        XCTAssertTrue(element(in: window, identifier: "mac-tweaks.setting.AppleShowAllFiles").waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Mac Tweaks Reference Finder")

        window.buttons["mac-tweaks.category.Input"].click()
        XCTAssertTrue(element(in: window, identifier: "mac-tweaks.mic-lock.enabled").waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Input priority"].exists)
        XCTAssertTrue(window.buttons["mac-tweaks.mic-lock.refresh"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Reference Input")

        let search = window.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let searchSurface = window.descendants(matching: .any)["mac-tweaks.search"]
        XCTAssertTrue(searchSurface.waitForExistence(timeout: 5))
        searchSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).click()
        search.typeText("screnshot format")
        XCTAssertTrue(element(in: window, identifier: "mac-tweaks.setting.type").waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Screenshot format"].exists)
        attach(window.screenshot(), named: "Mac Tweaks Ranked Search")

        search.click()
        app.typeKey("a", modifierFlags: .command)
        search.typeText("repeat accents")
        let defaultChoice = element(in: window, identifier: "mac-tweaks.choice.ApplePressAndHoldEnabled.-1")
        let onChoice = element(in: window, identifier: "mac-tweaks.choice.ApplePressAndHoldEnabled.0")
        XCTAssertTrue(defaultChoice.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(defaultChoice.frame.width, onChoice.frame.width * 2)
        attach(window.screenshot(), named: "Mac Tweaks Segmented Control")

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
              let color = bitmap.colorAt(x: bitmap.pixelsWide / 4,
                                         y: bitmap.pixelsHigh / 20)?.usingColorSpace(.deviceRGB) else {
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
