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
            "main", "cc-history", "rclone", "logs", "awake",
            "color-picker", "text-extractor", "input-devices", "system-care", "power-stats"
        ] {
            XCTAssertEqual(
                WindowStateManager.storageIdentifier(for: "\(identifier)-AppWindow-2"),
                identifier
            )
        }

        XCTAssertNil(WindowStateManager.storageIdentifier(for: "unknown-AppWindow-1"))
    }

    func testRestoredWorkspaceFrameIsClampedToItsRememberedMonitor() {
        let screen = NSRect(x: -1440, y: 0, width: 1440, height: 900)
        let restored = WindowStateManager.clamped(
            NSRect(x: -1600, y: -80, width: 1700, height: 1000),
            to: screen
        )

        XCTAssertEqual(restored, screen)
    }
}
