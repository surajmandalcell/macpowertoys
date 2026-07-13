import XCTest
@testable import powertoys

final class ToolRegistryTests: XCTestCase {
    func testRegistryContainsEveryShippedToolWindow() {
        XCTAssertEqual(
            Set(ToolRegistry.allTools.map(\.id)),
            Set(["cc-history", "rclone", "logs", "ruler", "awake", "color-picker", "text-extractor"])
        )
    }

    func testToolIdentifiersAreUnique() {
        let identifiers = ToolRegistry.allTools.map(\.id)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
    }
}
