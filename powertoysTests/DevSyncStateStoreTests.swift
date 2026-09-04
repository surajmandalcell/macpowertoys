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
        let pairs = await store.loadPairs()
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
        let openOperations = await store.loadOpenOperations(pairID: pairID)
        let operation = await store.loadOperation(id: UUID(), pairID: pairID)

        XCTAssertTrue(pairs.isEmpty)
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
        XCTAssertTrue(openOperations.isEmpty)
        XCTAssertNil(operation)
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
        XCTAssertEqual(permissions(at: corruptCopies[0]), 0o600)
    }

    func testScenario81CorruptOperationIsQuarantinedOnlyOnce() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        let operation = DevOperation(pairID: pair.id, projectID: nil, kind: .reconcile, plan: DevSyncPlan(pairID: pair.id))
        try await store.saveOperation(operation)
        let operationsDirectory = store.pairDirectory(pair.id).appendingPathComponent("operations", isDirectory: true)
        let operationURL = operationsDirectory.appendingPathComponent("\(operation.id.uuidString).json")
        try Data("not-json".utf8).write(to: operationURL, options: .atomic)

        let firstLoad = await store.loadOperations(pairID: pair.id, limit: 10)
        let firstIssues = await store.issues
        let secondLoad = await store.loadOperations(pairID: pair.id, limit: 10)
        let secondIssues = await store.issues

        XCTAssertTrue(firstLoad.isEmpty)
        XCTAssertTrue(secondLoad.isEmpty)
        XCTAssertEqual(firstIssues.count, 1)
        XCTAssertEqual(secondIssues.count, 1)
        let corruptCopies = try fileManager.contentsOfDirectory(at: operationsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(operation.id.uuidString).corrupt-") }
        XCTAssertEqual(corruptCopies.count, 1)
    }

    func testScenario81StateStoreNeverReadsThroughSymlinkedPairDirectory() async throws {
        let pair = makePair()
        let project = DevProject(pairID: pair.id, relativePath: "outside", residency: .mirrored, kind: .gitRepository)
        let outsideStore = DevSyncStateStore(rootURL: root.appendingPathComponent("outside-store", isDirectory: true))
        try await outsideStore.saveProjects([project], pairID: pair.id)
        let storeRoot = root.appendingPathComponent("store", isDirectory: true)
        try fileManager.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: storeRoot.appendingPathComponent(pair.id.uuidString, isDirectory: true),
            withDestinationURL: outsideStore.pairDirectory(pair.id)
        )
        let store = DevSyncStateStore(rootURL: storeRoot)

        let loadedProjects = await store.loadProjects(pairID: pair.id)

        XCTAssertTrue(loadedProjects.isEmpty)
        do {
            try await store.saveProjects([], pairID: pair.id)
            XCTFail("Expected a symbolic link write to fail")
        } catch {}
        let outsideProjects = await outsideStore.loadProjects(pairID: pair.id)
        XCTAssertEqual(outsideProjects, [project])
    }

    func testScenario81UnrecoverableCorruptProjectsReturnEmpty() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        try await store.saveProjects([], pairID: pair.id)
        let projectsURL = store.pairDirectory(pair.id).appendingPathComponent("projects.json")
        try Data("not-json".utf8).write(to: projectsURL, options: .atomic)

        let loadedProjects = await store.loadProjects(pairID: pair.id)

        XCTAssertTrue(loadedProjects.isEmpty)
        let issues = await store.issues
        XCTAssertTrue(issues.contains { $0.document == "projects.json" && !$0.recoveredFromBackup })
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
        let baselineURL = store.pairDirectory(pair.id).appendingPathComponent("baselines/\(projectID.uuidString).json")
        XCTAssertFalse(try Data(contentsOf: baselineURL).contains(0x0A))
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

    func testRestoreLatestBackupReplacesCurrentMetadata() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        let backedUpProject = DevProject(pairID: pair.id, relativePath: "backed-up", residency: .mirrored, kind: .gitRepository)
        let currentProject = DevProject(pairID: pair.id, relativePath: "current", residency: .mirrored, kind: .gitRepository)
        try await store.saveProjects([backedUpProject], pairID: pair.id)
        _ = try await store.backup(pairID: pair.id)
        try await store.saveProjects([currentProject], pairID: pair.id)

        let restored = try await store.restoreLatestBackup(pairID: pair.id)

        XCTAssertTrue(restored)
        let projects = await store.loadProjects(pairID: pair.id)
        XCTAssertEqual(projects, [backedUpProject])
    }

    func testBackupsContainMetadataButNeverBaselines() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        let projectID = UUID()
        let operation = DevOperation(pairID: pair.id, projectID: projectID, kind: .reconcile, plan: DevSyncPlan(pairID: pair.id, projectID: projectID))
        try await store.saveProjects([], pairID: pair.id)
        try await store.saveBaseline(DevBaseline(projectID: projectID), pairID: pair.id)
        try await store.saveOperation(operation)

        let backup = try await store.backup(pairID: pair.id)

        XCTAssertTrue(fileManager.fileExists(atPath: backup.appendingPathComponent("projects.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: backup.appendingPathComponent("operations/\(operation.id.uuidString).json").path))
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

    func testOperationsLoadNewestFirstAndCanBeDeleted() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        var oldOperation = DevOperation(pairID: pair.id, projectID: nil, kind: .reconcile, plan: DevSyncPlan(pairID: pair.id))
        oldOperation.state = .committed
        oldOperation.updatedAt = Date(timeIntervalSince1970: 100)
        var newOperation = DevOperation(pairID: pair.id, projectID: nil, kind: .reconcile, plan: DevSyncPlan(pairID: pair.id))
        newOperation.state = .verifying
        newOperation.updatedAt = Date(timeIntervalSince1970: 200)
        try await store.saveOperation(oldOperation)
        try await store.saveOperation(newOperation)

        let newest = await store.loadOperations(pairID: pair.id, limit: 1)
        let open = await store.loadOpenOperations(pairID: pair.id)
        XCTAssertEqual(newest, [newOperation])
        XCTAssertEqual(open, [newOperation])

        try await store.deleteOperation(id: newOperation.id, pairID: pair.id)
        let deleted = await store.loadOperation(id: newOperation.id, pairID: pair.id)
        XCTAssertNil(deleted)
    }

    func testBaselineCanBeDeleted() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        let baseline = DevBaseline(projectID: UUID())
        try await store.saveBaseline(baseline, pairID: pair.id)

        try await store.deleteBaseline(projectID: baseline.projectID, pairID: pair.id)

        let deleted = await store.loadBaseline(projectID: baseline.projectID, pairID: pair.id)
        XCTAssertNil(deleted)
    }

    func testRemovePairDeletesOnlyTheSelectedPairDirectory() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let firstPair = makePair()
        let secondPair = makePair()
        try await store.saveProjects([], pairID: firstPair.id)
        try await store.saveProjects([], pairID: secondPair.id)

        try await store.removePair(firstPair.id)

        XCTAssertFalse(fileManager.fileExists(atPath: store.pairDirectory(firstPair.id).path))
        XCTAssertTrue(fileManager.fileExists(atPath: store.pairDirectory(secondPair.id).path))
    }

    func testStateDocumentsAndDirectoriesUseRestrictivePermissions() async throws {
        let store = DevSyncStateStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let pair = makePair()
        try await store.savePairs([pair])
        try await store.saveProjects([], pairID: pair.id)

        let pairsURL = store.rootURL.appendingPathComponent("pairs.json")
        let pairDirectory = store.pairDirectory(pair.id)
        let projectsURL = pairDirectory.appendingPathComponent("projects.json")
        XCTAssertEqual(permissions(at: store.rootURL), 0o700)
        XCTAssertEqual(permissions(at: pairDirectory), 0o700)
        XCTAssertEqual(permissions(at: pairsURL), 0o600)
        XCTAssertEqual(permissions(at: projectsURL), 0o600)
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

    private func permissions(at url: URL) -> Int? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}
