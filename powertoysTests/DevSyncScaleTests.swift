import Darwin
import XCTest
@testable import powertoys

final class DevSyncScaleTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-scale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testTenThousandEventsCollapseToOneReconciliation() async throws {
        let projectID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = DevDirtyScheduler(timing: .default, performance: .init(), now: { now })
        let paths = (0..<10_000).map { "Sources/file-\($0).swift" }
        let started = Date()
        await scheduler.noteEvents(
            side: .internal,
            relativePaths: paths,
            projectResolver: { _ in projectID },
            at: now
        )
        let generations = await scheduler.due(at: now.addingTimeInterval(60))
        let duration = Date().timeIntervalSince(started)

        XCTAssertEqual(generations.count, 1)
        XCTAssertEqual(generations.first?.projectID, projectID)
        XCTAssertNil(generations.first?.paths)
        XCTAssertEqual(generations.first?.requiresFullScan, true)
        XCTAssertLessThan(duration, 5)
        XCTContext.runActivity(
            named: "DEVSYNC_SCALE events=10000 reconciliations=\(generations.count) seconds=\(duration)"
        ) { _ in }
    }

    func testOneHundredThousandFileScanAndPlanStayWithinBudget() async throws {
        let projectRoot = temporaryRoot.appendingPathComponent("repository", isDirectory: true)
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            for directoryIndex in 0..<100 {
                let directory = projectRoot.appendingPathComponent("dir-\(directoryIndex)", isDirectory: true)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
                for fileIndex in 0..<1_000 {
                    let path = directory.appendingPathComponent("file-\(fileIndex)").path
                    let descriptor = path.withCString {
                        Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
                    }
                    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    Darwin.close(descriptor)
                }
            }
        }.value
        let policy = DevFilePolicyEngine(
            policy: .init(),
            projectKind: .nonGit,
            gitDirectoryRelativePath: nil,
            gitTracked: nil,
            gitIgnored: nil,
            gitAvailable: false,
            projectIgnoreRules: []
        )
        let scanStarted = Date()
        let snapshot = await DevSnapshotScanner.scan(
            projectURL: projectRoot,
            policy: policy,
            gitDirectoryRelativePath: nil,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: false,
            hashPaths: []
        )
        let scanDuration = Date().timeIntervalSince(scanStarted)
        let pair = DevSyncPair(
            displayName: "Scale",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: projectRoot.path, volumeIdentifier: "internal", volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: temporaryRoot.path, volumeIdentifier: "external", volumeName: "External", fileSystemType: "apfs")
        )
        let project = DevProject(pairID: pair.id, relativePath: "", residency: .mirrored, kind: .nonGit)
        let empty = DevSnapshot(
            entries: [:],
            excluded: [:],
            unreadablePaths: [],
            complete: true,
            collisions: [],
            includedBytes: 0,
            excludedBytes: 0,
            scannedAt: Date()
        )
        let input = DevPlannerInput(
            pair: pair,
            project: project,
            baseline: nil,
            internalSnapshot: snapshot,
            externalSnapshot: empty,
            tombstones: [],
            unresolvedConflicts: [],
            capabilities: DevPairCapabilities(),
            unstablePaths: [],
            now: Date()
        )
        let planStarted = Date()
        let output = await Task.detached(priority: .utility) { DevReconciliationPlanner.plan(input) }.value
        let planDuration = Date().timeIntervalSince(planStarted)

        XCTAssertEqual(snapshot.entries.values.filter { $0.kind == .file }.count, 100_000)
        XCTAssertEqual(output.plan.manifestToExternal.count, 100_000)
        XCTAssertLessThan(scanDuration, 120)
        XCTAssertLessThan(planDuration, 120)
        XCTContext.runActivity(
            named: "DEVSYNC_SCALE files=100000 scan_seconds=\(scanDuration) plan_seconds=\(planDuration)"
        ) { _ in }
    }

    func testOneGigabyteStreamingHashUsesLessThanSixtyFourMegabytesResidentDelta() async throws {
        let file = temporaryRoot.appendingPathComponent("one-gigabyte.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 1_024 * 1_024 * 1_024)
        try handle.close()
        let before = residentMemory()
        let started = Date()
        let digest = try await Task.detached(priority: .utility) {
            try autoreleasepool { try DevSnapshotScanner.hash(url: file) }
        }.value
        let duration = Date().timeIntervalSince(started)
        let delta = max(0, residentMemory() - before)

        XCTAssertEqual(digest.count, 32)
        XCTAssertLessThan(delta, 64 * 1_024 * 1_024)
        XCTAssertLessThan(duration, 120)
        XCTContext.runActivity(
            named: "DEVSYNC_SCALE bytes=1073741824 hash_seconds=\(duration) resident_delta_bytes=\(delta)"
        ) { _ in }
    }

    private func residentMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
