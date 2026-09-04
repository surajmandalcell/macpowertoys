import XCTest
@testable import powertoys

final class DevSyncStateStoreTests: XCTestCase {
    private var root: URL!
    private var fileManager: FileManager { .default }

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("devsync-state-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        root = nil
    }

    func testScenario31RoundTripsEveryStateDocument() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        let project = DevProject(pairID: pair.id, relativePath: "app", residency: .mirrored, kind: .gitRepository)
        let baseline = DevBaseline(
            projectID: project.id,
            entries: ["main.swift": DevBaselineEntry(
                signature: DevFileSignature(kind: .file, size: 4, modificationTimeNanoseconds: 10),
                lastVerifiedAt: Date(timeIntervalSince1970: 100)
            )],
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let tombstone = DevTombstone(
            projectID: project.id,
            relativePath: "old.swift",
            deletedFromSide: .internal,
            baselineSignature: DevFileSignature(kind: .file, size: 3),
            createdAt: Date(timeIntervalSince1970: 100),
            observedInternal: true,
            observedExternal: false,
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        let conflict = DevConflict(projectID: project.id, relativePath: "README.md", type: .contentContent)
        let link = DevManagedLink(
            projectID: project.id,
            linkRelativePath: "app",
            targetVolumeIdentifier: "external",
            targetRelativePath: "app",
            lastWrittenTargetText: "/Volumes/DevSSD/app",
            linkResourceIdentifier: Data([1]),
            state: .healthy,
            createdAt: Date(timeIntervalSince1970: 100),
            lastValidatedAt: Date(timeIntervalSince1970: 100),
            adoptedFromUserLink: false
        )
        let dirty = DevDirtyEntry(
            projectID: project.id,
            side: .internal,
            relativePath: "main.swift",
            firstEventAt: Date(timeIntervalSince1970: 100),
            lastEventAt: Date(timeIntervalSince1970: 101),
            reason: .fileEvent,
            requiresFullScan: false,
            attemptCount: 1
        )
        let cursor = DevEventCursor(
            pairID: pair.id,
            side: .external,
            volumeIdentifier: "external",
            lastEventID: 42,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let plan = DevSyncPlan(pairID: pair.id, projectID: project.id)
        let operation = DevOperation(pairID: pair.id, projectID: project.id, kind: .reconcile, plan: plan)
        let records = [DevSafetyRecord(
            operationID: operation.id,
            projectID: project.id,
            kind: .deleted,
            side: .external,
            originalRelativePath: "old.swift",
            safetyPath: "/tmp/old.swift",
            bytes: 3,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )]

        try await store.savePairs([pair])
        try await store.saveProjects([project], pairID: pair.id)
        try await store.saveBaseline(baseline, pairID: pair.id)
        try await store.saveTombstones([tombstone], pairID: pair.id)
        try await store.saveConflicts([conflict], pairID: pair.id)
        try await store.saveLinks([link], pairID: pair.id)
        try await store.saveDirty([dirty], pairID: pair.id)
        try await store.saveCursors([cursor], pairID: pair.id)
        try await store.saveCapabilities(DevPairCapabilities(), pairID: pair.id)
        try await store.saveSafetyRecords(records, pairID: pair.id)
        try await store.saveOperation(operation)

        let loadedPairs = await store.loadPairs()
        let loadedProjects = await store.loadProjects(pairID: pair.id)
        let loadedBaseline = await store.loadBaseline(projectID: project.id, pairID: pair.id)
        let loadedTombstones = await store.loadTombstones(pairID: pair.id)
        let loadedConflicts = await store.loadConflicts(pairID: pair.id)
        let loadedLinks = await store.loadLinks(pairID: pair.id)
        let loadedDirty = await store.loadDirty(pairID: pair.id)
        let loadedCursors = await store.loadCursors(pairID: pair.id)
        let loadedCapabilities = await store.loadCapabilities(pairID: pair.id)
        let loadedSafetyRecords = await store.loadSafetyRecords(pairID: pair.id)
        let loadedOperation = await store.loadOperation(id: operation.id, pairID: pair.id)

        XCTAssertEqual(loadedPairs, [pair])
        XCTAssertEqual(loadedProjects, [project])
        XCTAssertEqual(loadedBaseline, baseline)
        XCTAssertEqual(loadedTombstones, [tombstone])
        XCTAssertEqual(loadedConflicts, [conflict])
        XCTAssertEqual(loadedLinks, [link])
        XCTAssertEqual(loadedDirty, [dirty])
        XCTAssertEqual(loadedCursors, [cursor])
        XCTAssertEqual(loadedCapabilities, DevPairCapabilities())
        XCTAssertEqual(loadedSafetyRecords, records)
        XCTAssertEqual(loadedOperation, operation)
    }

    func testMissingDocumentsReturnEmptyValues() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pairID = UUID()
        let projects = await store.loadProjects(pairID: pairID)
        let tombstones = await store.loadTombstones(pairID: pairID)
        let conflicts = await store.loadConflicts(pairID: pairID)
        let links = await store.loadLinks(pairID: pairID)
        let dirty = await store.loadDirty(pairID: pairID)
        let cursors = await store.loadCursors(pairID: pairID)
        let capabilities = await store.loadCapabilities(pairID: pairID)
        let records = await store.loadSafetyRecords(pairID: pairID)
        let baseline = await store.loadBaseline(projectID: UUID(), pairID: pairID)
        let operations = await store.loadOperations(pairID: pairID, limit: 10)

        XCTAssertTrue(projects.isEmpty)
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertTrue(links.isEmpty)
        XCTAssertTrue(dirty.isEmpty)
        XCTAssertTrue(cursors.isEmpty)
        XCTAssertEqual(capabilities, DevPairCapabilities())
        XCTAssertTrue(records.isEmpty)
        XCTAssertNil(baseline)
        XCTAssertTrue(operations.isEmpty)
    }

    func testScenario81CorruptProjectsMoveAsideAndRecoverFromBackup() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        let project = DevProject(pairID: pair.id, relativePath: "app", residency: .mirrored, kind: .gitRepository)
        try await store.saveProjects([project], pairID: pair.id)
        _ = try await store.backup(pairID: pair.id)

        let projectsURL = store.pairDirectory(pair.id).appendingPathComponent("projects.json")
        try Data("not-json".utf8).write(to: projectsURL, options: .atomic)

        let loadedProjects = await store.loadProjects(pairID: pair.id)
        XCTAssertEqual(loadedProjects, [project])
        let issues = await store.issues
        XCTAssertTrue(issues.contains { $0.document == "projects.json" && $0.recoveredFromBackup })
        let corruptCopies = try fileManager.contentsOfDirectory(at: store.pairDirectory(pair.id), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("projects.corrupt-") }
        XCTAssertEqual(corruptCopies.count, 1)
    }

    func testBaselineWithOneHundredThousandEntriesStaysWithinBudget() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        let projectID = UUID()
        let timestamp = Date(timeIntervalSince1970: 100)
        var entries = [String: DevBaselineEntry](minimumCapacity: 100_000)
        for index in 0..<100_000 {
            entries["Sources/File\(index).swift"] = DevBaselineEntry(
                signature: DevFileSignature(kind: .file, size: UInt64(index), modificationTimeNanoseconds: Int64(index)),
                lastVerifiedAt: timestamp
            )
        }
        let baseline = DevBaseline(projectID: projectID, entries: entries, updatedAt: timestamp)
        let start = DispatchTime.now().uptimeNanoseconds
        try await store.saveBaseline(baseline, pairID: pair.id)
        let loaded = await store.loadBaseline(projectID: projectID, pairID: pair.id)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000

        XCTAssertEqual(loaded?.entries.count, 100_000)
        XCTAssertLessThan(elapsed, 4)
    }

    func testBackupsKeepOnlyNewestFive() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        for index in 0..<7 {
            let project = DevProject(pairID: pair.id, relativePath: "app-\(index)", residency: .mirrored, kind: .gitRepository)
            try await store.saveProjects([project], pairID: pair.id)
            _ = try await store.backup(pairID: pair.id)
        }

        let backupsURL = store.pairDirectory(pair.id).appendingPathComponent("backups")
        let backups = try fileManager.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 5)
    }

    func testScenario49BackupsContainMetadataButNeverBaselines() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        let projectID = UUID()
        try await store.saveProjects([], pairID: pair.id)
        try await store.saveBaseline(DevBaseline(projectID: projectID), pairID: pair.id)

        let backup = try await store.backup(pairID: pair.id)

        XCTAssertTrue(fileManager.fileExists(atPath: backup.appendingPathComponent("projects.json").path))
        XCTAssertFalse(fileManager.fileExists(atPath: backup.appendingPathComponent("baselines").path))
    }

    func testScenario79OpenOperationIsAvailableForRecovery() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        var operation = DevOperation(pairID: pair.id, projectID: nil, kind: .reconcile, plan: DevSyncPlan(pairID: pair.id))
        operation.state = .transferComplete
        try await store.saveOperation(operation)

        let openOperations = await store.loadOpenOperations(pairID: pair.id)

        XCTAssertEqual(openOperations, [operation])
    }

    func testScenario80SafetyPreparedOperationKeepsJournalUntilResolved() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        var operation = DevOperation(pairID: pair.id, projectID: nil, kind: .reconcile, plan: DevSyncPlan(pairID: pair.id))
        operation.state = .safetyPrepared
        try await store.saveOperation(operation)

        let loadedOperation = await store.loadOperation(id: operation.id, pairID: pair.id)
        let openOperations = await store.loadOpenOperations(pairID: pair.id)
        XCTAssertEqual(loadedOperation?.state.rawValue, DevOperationState.safetyPrepared.rawValue)
        XCTAssertEqual(openOperations.count, 1)
    }

    private func makePair() -> DevSyncPair {
        DevSyncPair(
            displayName: "DevSSD",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(
                bookmark: nil,
                path: root.appendingPathComponent("internal", isDirectory: true).path,
                volumeIdentifier: "internal",
                volumeName: "Internal",
                fileSystemType: "apfs"
            ),
            externalRoot: DevSyncRoot(
                bookmark: nil,
                path: root.appendingPathComponent("external", isDirectory: true).path,
                volumeIdentifier: "external",
                volumeName: "DevSSD",
                fileSystemType: "apfs"
            )
        )
    }
}
