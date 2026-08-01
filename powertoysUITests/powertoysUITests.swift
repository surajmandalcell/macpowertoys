//
//  powertoysUITests.swift
//  powertoysUITests
//

import XCTest

final class powertoysUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAllShippedToolsAreDiscoverable() throws {
        let app = launchApp()
        XCTAssertTrue(app.windows["MacPowerToys"].waitForExistence(timeout: 5))

        for id in ["cc-history", "rclone", "logs", "ruler", "awake", "color-picker", "text-extractor"] {
            let card = app.descendants(matching: .any)["tool.\(id).card"]
            XCTAssertTrue(
                card.waitForExistence(timeout: 2),
                "Missing tool card: \(id)"
            )
        }
    }

    @MainActor
    func testRulerLaunchUsesUpstreamWindowAndBothWings() throws {
        let app = launchRuler()
        let rulerWindow = app.dialogs["ruler-window"]
        let horizontalRuler = app.otherElements["horizontal-ruler-view"]
        let verticalRuler = app.otherElements["vertical-ruler-view"]

        XCTAssertTrue(waitForVisibleFrame(rulerWindow))
        XCTAssertTrue(waitForVisibleFrame(horizontalRuler))
        XCTAssertTrue(waitForVisibleFrame(verticalRuler))
        XCTAssertEqual(app.dialogs.matching(identifier: "ruler-window").count, 1)
        XCTAssertFalse(app.windows["ruler"].exists, "The removed SwiftUI Ruler scene must stay absent")
        XCTAssertEqual(horizontalRuler.frame.height, 40, accuracy: 1)
        XCTAssertEqual(verticalRuler.frame.width, 40, accuracy: 1)
        for title in ["Ruler", "Unit", "Options"] {
            XCTAssertTrue(
                app.menuBars.menuBarItems[title].waitForExistence(timeout: 2),
                "Missing FreeRuler menu: \(title)"
            )
        }
    }

    @MainActor
    func testRulerWingAndUnitHotkeys() throws {
        let app = launchRuler()
        let horizontalRuler = app.otherElements["horizontal-ruler-view"]
        let verticalRuler = app.otherElements["vertical-ruler-view"]

        horizontalRuler.click()
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(horizontalRuler))
        XCTAssertTrue(verticalRuler.exists)
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(waitForVisibleFrame(horizontalRuler))

        verticalRuler.click()
        app.typeKey("v", modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(verticalRuler))
        XCTAssertTrue(horizontalRuler.exists)
        app.typeKey("v", modifierFlags: [])
        XCTAssertTrue(waitForVisibleFrame(verticalRuler))

        horizontalRuler.click()
        XCTAssertEqual(horizontalRuler.value as? String, "px")
        app.typeKey("u", modifierFlags: [])
        XCTAssertTrue(waitForValue("mm", on: horizontalRuler))
        app.typeKey("u", modifierFlags: [])
        XCTAssertTrue(waitForValue("in", on: horizontalRuler))
        app.typeKey("u", modifierFlags: [])
        XCTAssertTrue(waitForValue("px", on: horizontalRuler))
    }

    @MainActor
    func testRulerSettingsAndDefaultsShortcuts() throws {
        let app = launchRuler()
        app.otherElements["horizontal-ruler-view"].click()
        app.typeKey(",", modifierFlags: .command)

        let rulerSettings = app.windows["ruler-settings-window"]
        XCTAssertTrue(waitForVisibleFrame(rulerSettings))
        XCTAssertFalse(app.windows["preferences-window"].exists)
        XCTAssertTrue(app.colorWells["ruler-settings-color-well"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.sliders["ruler-settings-foreground-opacity-slider"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.sliders["ruler-settings-background-opacity-slider"].waitForExistence(timeout: 2))

        app.typeKey(",", modifierFlags: [.option, .command])
        let rulerDefaults = app.windows["preferences-window"]
        XCTAssertTrue(waitForVisibleFrame(rulerDefaults))
        XCTAssertTrue(app.colorWells["ruler-color-well"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.sliders["ruler-foreground-opacity-slider"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.sliders["ruler-background-opacity-slider"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testRulerCreatesCyclesAndGroupsMultipleWindows() throws {
        let app = launchRuler()
        let rulerWindows = app.dialogs.matching(identifier: "ruler-window")
        let initialFrame = rulerWindows.element(boundBy: 0).frame

        app.otherElements["horizontal-ruler-view"].click()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(waitForCount(2, in: rulerWindows))
        let createdFrames = rulerWindows.allElementsBoundByIndex.map(\.frame)
        let newFrame = try XCTUnwrap(createdFrames.first { !framesMatch($0, initialFrame) })

        app.typeKey("g", modifierFlags: [])
        XCTAssertTrue(app.otherElements["hotkey-bezel"].waitForExistence(timeout: 2))
        XCTAssertEqual(rulerWindows.count, 2)

        app.typeKey("`", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForCount(1, in: rulerWindows))
        XCTAssertTrue(
            framesMatch(rulerWindows.element(boundBy: 0).frame, newFrame),
            "⌘` must cycle to the first ruler before ⌘W closes it"
        )
    }

    @MainActor
    func testRulerCloseWithCommandWLeavesMacPowerToysRunning() throws {
        let app = launchRuler()
        let rulerWindow = app.dialogs["ruler-window"]

        rulerWindow.click()
        app.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(waitForDisappearance(rulerWindow))
        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertTrue(app.windows["MacPowerToys"].exists)
    }

    @MainActor
    func testAwakeHasFixedSizeAndTitlebarDisplayToggle() throws {
        let app = launchApp()
        let card = app.descendants(matching: .any)["tool.awake.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()

        let launch = app.buttons["tool.awake.launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 2))
        launch.click()

        let window = app.windows["Awake"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let initialFrame = window.frame
        let lowerRight = window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        lowerRight.press(
            forDuration: 0.1,
            thenDragTo: lowerRight.withOffset(CGVector(dx: 100, dy: 100))
        )
        XCTAssertEqual(window.frame, initialFrame)

        let toggle = window.switches["Keep Display On"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertTrue(toggle.isEnabled)
        let initialValue = String(describing: toggle.value)
        toggle.click()
        XCTAssertNotEqual(String(describing: toggle.value), initialValue)
        toggle.click()
        XCTAssertEqual(String(describing: toggle.value), initialValue)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func launchRuler() -> XCUIApplication {
        let app = launchApp()
        let card = app.descendants(matching: .any)["tool.ruler.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()

        let launch = app.buttons["tool.ruler.launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        launch.click()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.dialogs["ruler-window"].waitForExistence(timeout: 5))
        return app
    }

    private func waitForVisibleFrame(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        waitUntil(timeout: timeout) { element.exists && !element.frame.isEmpty }
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 2) -> Bool {
        waitUntil(timeout: timeout) { !element.exists }
    }

    private func waitForValue(
        _ value: String,
        on element: XCUIElement,
        timeout: TimeInterval = 2
    ) -> Bool {
        waitUntil(timeout: timeout) { element.value as? String == value }
    }

    private func waitForCount(
        _ count: Int,
        in query: XCUIElementQuery,
        timeout: TimeInterval = 3
    ) -> Bool {
        waitUntil(timeout: timeout) { query.count == count }
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return condition()
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, accuracy: CGFloat = 1) -> Bool {
        abs(lhs.minX - rhs.minX) <= accuracy
            && abs(lhs.minY - rhs.minY) <= accuracy
            && abs(lhs.width - rhs.width) <= accuracy
            && abs(lhs.height - rhs.height) <= accuracy
    }
}
