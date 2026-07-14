import XCTest
@testable import powertoys

@MainActor
final class RulerManagerTests: XCTestCase {
    func testCreatePairBuildsGroupedHorizontalAndVerticalRulers() {
        let manager = RulerManager.shared
        manager.removeAll()
        defer { manager.removeAll() }

        manager.createPair()

        XCTAssertEqual(manager.rulers.count, 2)
        XCTAssertEqual(
            manager.rulers.map(\.orientation.rawValue).sorted(),
            [RulerOrientation.horizontal.rawValue, RulerOrientation.vertical.rawValue]
        )
        let groupID = manager.rulers.first?.groupID
        XCTAssertNotNil(groupID)
        XCTAssertTrue(manager.rulers.allSatisfy { $0.groupID == groupID })
        XCTAssertTrue(manager.rulers.allSatisfy(\.isVisible))
    }
}
