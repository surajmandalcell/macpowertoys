import XCTest
@testable import powertoys

@MainActor
final class RulerManagerTests: XCTestCase {
    func testCreatePairBuildsGroupedHorizontalAndVerticalRulers() throws {
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

        let horizontal = try XCTUnwrap(manager.rulers.first { $0.orientation == .horizontal })
        let vertical = try XCTUnwrap(manager.rulers.first { $0.orientation == .vertical })
        XCTAssertEqual(horizontal.height, RulerGeometry.thickness)
        XCTAssertEqual(vertical.width, RulerGeometry.thickness)
        XCTAssertEqual(horizontal.frame.minX - vertical.frame.maxX, RulerGeometry.groupGap, accuracy: 0.001)
        XCTAssertEqual(vertical.frame.maxY, horizontal.frame.maxY, accuracy: 0.001)
        XCTAssertFalse(vertical.frame.intersects(horizontal.frame))
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.displayID == horizontal.screenID })
        XCTAssertEqual(horizontal.width, screen.visibleFrame.width * 0.3, accuracy: 0.001)
        XCTAssertEqual(vertical.height, screen.visibleFrame.height * 0.3, accuracy: 0.001)
        XCTAssertEqual(horizontal.screenID, vertical.screenID)
    }

    func testRulerSizeCanBeSetFromControls() throws {
        let manager = RulerManager.shared
        manager.removeAll()
        defer { manager.removeAll() }

        manager.create(.joined)
        let ruler = try XCTUnwrap(manager.rulers.first)
        manager.setSize(ruler.id, width: 320, height: 240)

        let resized = try XCTUnwrap(manager.rulers.first)
        XCTAssertEqual(resized.width, 320)
        XCTAssertEqual(resized.height, 240)
    }

    func testQuitCommandOnlyTargetsRulerWindows() {
        XCTAssertTrue(RulerManager.isRulerWindowIdentifier("ruler"))
        XCTAssertTrue(RulerManager.isRulerWindowIdentifier("ruler.00000000-0000-0000-0000-000000000000"))
        XCTAssertFalse(RulerManager.isRulerWindowIdentifier("main"))
        XCTAssertFalse(RulerManager.isRulerWindowIdentifier("rulership"))
        XCTAssertFalse(RulerManager.isRulerWindowIdentifier(nil))
    }

    func testClosingAndReopeningRestoresRulersWithoutDuplicates() {
        let manager = RulerManager.shared
        manager.removeAll()
        defer { manager.removeAll() }

        manager.openTool()
        let originalIDs = manager.rulers.map(\.id)
        manager.closeTool()
        manager.openTool()

        XCTAssertEqual(manager.rulers.map(\.id), originalIDs)
        XCTAssertTrue(manager.rulers.allSatisfy(\.isVisible))
    }

    func testGroupedPairStaysAFullSizedNonOverlappingL() throws {
        let manager = RulerManager.shared
        manager.removeAll()
        defer { manager.removeAll() }

        manager.createPair()
        let vertical = try XCTUnwrap(manager.rulers.first { $0.orientation == .vertical })
        manager.setSize(vertical.id, height: RulerGeometry.thickness)
        manager.normalizeGroupedPairs(minimumDefaultLengths: true)

        let horizontal = try XCTUnwrap(manager.rulers.first { $0.orientation == .horizontal })
        let resizedVertical = try XCTUnwrap(manager.rulers.first { $0.orientation == .vertical })
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.displayID == horizontal.screenID })
        XCTAssertEqual(resizedVertical.height, screen.visibleFrame.height * 0.3, accuracy: 0.001)
        XCTAssertEqual(horizontal.frame.minX - resizedVertical.frame.maxX, RulerGeometry.groupGap, accuracy: 0.001)
        XCTAssertEqual(resizedVertical.frame.maxY, horizontal.frame.maxY, accuracy: 0.001)
        XCTAssertFalse(resizedVertical.frame.intersects(horizontal.frame))
    }

    func testCommandWClosesAGroupedPairWithoutQuittingTheApp() {
        let manager = RulerManager.shared
        manager.removeAll()
        defer { manager.removeAll() }

        manager.createPair()
        let id = manager.rulers[0].id
        manager.closeWindow(identifier: "ruler.\(id.uuidString)")

        XCTAssertEqual(manager.rulers.count, 2)
        XCTAssertTrue(manager.rulers.allSatisfy { !$0.isVisible })
    }
}
