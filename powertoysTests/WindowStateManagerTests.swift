import XCTest
@testable import powertoys

final class WindowStateManagerTests: XCTestCase {
    @MainActor
    func testInitialSwiftUIFrameCannotOverwriteSavedStateBeforeRestoration() {
        let key = "windowState.input-devices"
        let defaults = UserDefaults.standard
        let originalData = defaults.data(forKey: key)
        defer {
            if let originalData {
                defaults.set(originalData, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let savedState = Data("saved-state".utf8)
        defaults.set(savedState, forKey: key)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 980, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("input-devices-AppWindow-1")

        let manager = WindowStateManager.shared
        manager.saveState(for: window)

        XCTAssertEqual(defaults.data(forKey: key), savedState)

        manager.restoreState(for: window)
        manager.saveState(for: window)

        XCTAssertNotEqual(defaults.data(forKey: key), savedState)
    }

    func testWindowInstancesShareStableStorageIdentifiers() {
        for identifier in [
            "main", "rclone", "logs", "awake",
            "color-picker", "text-extractor", "input-devices", "system-care",
            "system-monitor", "nettoys", "disk-explorer", "mac-tweaks"
        ] {
            XCTAssertEqual(
                WindowStateManager.storageIdentifier(for: "\(identifier)-AppWindow-2"),
                identifier
            )
        }

        XCTAssertNil(WindowStateManager.storageIdentifier(for: "unknown-AppWindow-1"))
    }

    @MainActor
    func testSystemMonitorReadsLegacyWindowStateWhenCurrentStateIsAbsent() throws {
        let suite = "WindowStateManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyData = Data("legacy-frame".utf8)
        defaults.set(legacyData, forKey: "windowState.power-stats")

        XCTAssertEqual(
            WindowStateManager.storedStateData(for: "system-monitor", in: defaults),
            legacyData
        )

        let currentData = Data("current-frame".utf8)
        defaults.set(currentData, forKey: "windowState.system-monitor")
        XCTAssertEqual(
            WindowStateManager.storedStateData(for: "system-monitor", in: defaults),
            currentData
        )
    }

    func testRestoredWorkspaceFrameIsClampedToItsRememberedMonitor() {
        let screen = NSRect(x: -1440, y: 0, width: 1440, height: 900)
        let restored = WindowStateManager.clamped(
            NSRect(x: -1600, y: -80, width: 1700, height: 1000),
            to: screen
        )

        XCTAssertEqual(restored, screen)
    }

    func testMissingDisplayRestorationKeepsTheTitlebarOnTheGreatestOverlapScreen() {
        let negative = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: -1000, y: 500, width: 1240, height: 840)
        let restored = WindowStateManager.frameOnSurvivingScreen(
            frame, visibleFrames: [negative, primary], currentScreen: primary
        )
        XCTAssertEqual(restored, NSRect(x: -1240, y: 40, width: 1240, height: 840))
        XCTAssertEqual(restored.size, frame.size)

        XCTAssertEqual(WindowStateManager.frameOnSurvivingScreen(
            NSRect(x: 9000, y: 9000, width: 1240, height: 840),
            visibleFrames: [negative, primary], currentScreen: negative
        ), NSRect(x: -1240, y: 40, width: 1240, height: 840))
    }
}
