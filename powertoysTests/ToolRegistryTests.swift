import XCTest
@testable import powertoys

final class ToolRegistryTests: XCTestCase {
    func testRegistryContainsEveryShippedToolWindow() {
        XCTAssertEqual(
            Set(ToolRegistry.builtInTools.map(\.id)),
            Set(["cc-history", "rclone", "logs", "ruler", "awake", "color-picker", "text-extractor", "input-devices", "system-care", "system-monitor"])
        )
    }

    func testAllToolsStartsWithBuiltIns() {
        XCTAssertEqual(
            Array(ToolRegistry.allTools.prefix(ToolRegistry.builtInTools.count)).map(\.id),
            ToolRegistry.builtInTools.map(\.id)
        )
    }

    func testToolIdentifiersAreUnique() {
        let identifiers = ToolRegistry.allTools.map(\.id)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
    }
}
