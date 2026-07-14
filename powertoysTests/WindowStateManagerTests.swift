import XCTest
@testable import powertoys

final class WindowStateManagerTests: XCTestCase {
    func testWindowInstancesShareStableStorageIdentifiers() {
        for identifier in [
            "main", "cc-history", "rclone", "logs", "ruler", "awake",
            "color-picker", "text-extractor"
        ] {
            XCTAssertEqual(
                WindowStateManager.storageIdentifier(for: "\(identifier)-AppWindow-2"),
                identifier
            )
        }

        XCTAssertNil(WindowStateManager.storageIdentifier(for: "unknown-AppWindow-1"))
    }
}
