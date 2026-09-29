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

    func testProjectionCachesFilteringStatusAndTreeAncestors() {
        let folder = entry("folder", isDir: true)
        let uploaded = entry("folder/a.txt", size: 1_000)
        let pending = entry("z.txt", size: 2_000)
        let ignored = entry("draft.tmp", size: 3_000)

        let projection = TransferFileTreeView.makeProjection(
            roots: [folder, pending, ignored],
            children: [folder.path: [uploaded]],
            expanded: [folder.path],
            allEntries: [uploaded, pending, ignored],
            destinationEntries: [uploaded.path: uploaded],
            patterns: ["*.tmp"],
            hideIgnored: true,
            search: ""
        )

        XCTAssertEqual(projection.treeRows.map(\.id), ["folder", "folder/a.txt", "z.txt"])
        XCTAssertEqual(projection.pendingRows.map(\.id), ["z.txt"])
        XCTAssertEqual(projection.uploadedRows.map(\.id), ["folder", "folder/a.txt"])
        XCTAssertEqual(projection.pendingRows.first?.size, "2.0 KB")
    }

    private func entry(_ path: String, size: Int64 = 0, isDir: Bool = false) -> RemoteEntry {
        RemoteEntry(
            path: path,
            name: String(path.split(separator: "/").last ?? ""),
            size: size,
            modTime: nil,
            isDir: isDir,
            mimeType: isDir ? "inode/directory" : "text/plain"
        )
    }
}
