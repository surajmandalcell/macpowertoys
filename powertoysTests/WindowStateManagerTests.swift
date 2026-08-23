import XCTest
@testable import powertoys

final class WindowStateManagerTests: XCTestCase {
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
