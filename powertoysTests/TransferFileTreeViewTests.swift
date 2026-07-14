import XCTest
@testable import powertoys

@MainActor
final class TransferFileTreeViewTests: XCTestCase {
    func testTreePathsIncludeFilesAndTheirAncestors() {
        XCTAssertEqual(
            TransferFileTreeView.treePaths(for: ["photos/2026/july.jpg", "notes.txt"]),
            ["photos", "photos/2026", "photos/2026/july.jpg", "notes.txt"]
        )
    }
}
