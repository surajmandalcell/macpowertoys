import XCTest
@testable import powertoys

final class ResourceDiagnosticsTests: XCTestCase {
    func testResourceCountsRouteIsExactAndHasNoQueryControlledSurface() {
        XCTAssertTrue(DeepLinkHandler.isResourceCountsDiagnosticsURL(
            URL(string: "macpowertoys://diagnostics/resource-counts")!
        ))

        for url in [
            "powertoys://diagnostics/resource-counts",
            "macpowertoys://diagnostics/resource-counts/extra",
            "macpowertoys://diagnostics/resource-counts?path=/tmp/counts.jsonl",
            "macpowertoys://diagnostics/resource-counts#latest",
            "macpowertoys://open/resource-counts",
        ] {
            XCTAssertFalse(
                DeepLinkHandler.isResourceCountsDiagnosticsURL(URL(string: url)!),
                url
            )
        }
    }

    @MainActor
    func testCurrentSnapshotContainsOnlyTheResourceOwnerSchema() {
        let snapshot = ResourceDiagnostics.currentSnapshot(at: Date(timeIntervalSince1970: 123))

        XCTAssertEqual(snapshot.timestampMilliseconds, 123_000)
        XCTAssertFalse(snapshot.sourceCommit.isEmpty)
        XCTAssertEqual(Set(snapshot.counts.keys), [
            "app.eventMonitors",
            "app.observers",
            "app.timers",
            "awake.assertions",
            "awake.timers",
            "cloudSync.daemons",
            "cloudSync.fileWatchers",
            "cloudSync.longLivedTasks",
            "cloudSync.observers",
            "cloudSync.pollTasks",
            "cloudSync.windowOwners",
            "globalShortcuts.eventHandlers",
            "globalShortcuts.eventTaps",
            "globalShortcuts.hotKeys",
            "inputDevices.eventTaps",
            "menuBar.observers",
            "menuBar.statusItems",
            "projectHistory.fileWatchers",
            "settingsSync.observers",
            "systemMonitor.observers",
            "systemMonitor.statusItems",
            "systemMonitor.timers",
            "windowState.observers",
        ])
        XCTAssertTrue(snapshot.counts.values.allSatisfy { $0 >= 0 })
    }

    @MainActor
    func testJSONLWriterKeepsOnlyNewestBoundedSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResourceDiagnosticsTests.\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("resource-counts.jsonl")
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<7 {
            let snapshot = ResourceCountSnapshot(
                timestampMilliseconds: Int64(index),
                sourceCommit: "commit-\(index)",
                counts: ["test.owner": index]
            )
            try ResourceDiagnostics.append(snapshot, to: fileURL, maxRecords: 3)
        }

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        let decoder = JSONDecoder()
        let snapshots = try lines.map {
            try decoder.decode(ResourceCountSnapshot.self, from: Data($0.utf8))
        }
        XCTAssertEqual(snapshots.map(\.timestampMilliseconds), [4, 5, 6])
        XCTAssertEqual(snapshots.map(\.sourceCommit), ["commit-4", "commit-5", "commit-6"])
        XCTAssertEqual(snapshots.map { $0.counts["test.owner"] }, [4, 5, 6])
    }
}
