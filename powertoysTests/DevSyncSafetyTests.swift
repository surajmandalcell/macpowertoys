import XCTest
@testable import powertoys

final class DevSyncSafetyTests: XCTestCase {
    private var root: URL!
    private var internalRoot: URL!
    private var externalRoot: URL!
    private var fileManager: FileManager { .default }

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("devsync-safety-\(UUID().uuidString)", isDirectory: true)
        internalRoot = root.appendingPathComponent("internal", isDirectory: true)
        externalRoot = root.appendingPathComponent("external", isDirectory: true)
        try fileManager.createDirectory(at: internalRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: externalRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        root = nil
        internalRoot = nil
        externalRoot = nil
    }

    func testScenario31RetainBeforeDeleteMovesWithoutOverwriting() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let source = externalRoot.appendingPathComponent("project/nested/old.swift")
        try write(Data("first".utf8), to: source)
        let operationID = UUID()

        let first = try await safety.retainBeforeDelete(
            side: .external,
            fileURL: source,
            relativePath: "project/nested/old.swift",
            projectID: nil,
            operationID: operationID,
            now: Date(timeIntervalSince1970: 100),
            retainDays: 30
        )
        XCTAssertFalse(fileManager.fileExists(atPath: source.path))
        let firstData = try Data(contentsOf: URL(fileURLWithPath: first.safetyPath))
        XCTAssertEqual(firstData, Data("first".utf8))

        try write(Data("second".utf8), to: source)
        let second = try await safety.retainBeforeDelete(
            side: .external,
            fileURL: source,
            relativePath: "project/nested/old.swift",
            projectID: nil,
            operationID: operationID,
            now: Date(timeIntervalSince1970: 101),
            retainDays: 30
        )
        XCTAssertNotEqual(first.safetyPath, second.safetyPath)
        let secondData = try Data(contentsOf: URL(fileURLWithPath: second.safetyPath))
        XCTAssertEqual(secondData, Data("second".utf8))
        let records = await stateStore.loadSafetyRecords(pairID: pair.id)
        XCTAssertEqual(records.count, 2)
    }

    func testScenario49ExcludedBuildTreeMovesToHistory() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let buildDirectory = externalRoot.appendingPathComponent("project/build", isDirectory: true)
        try write(Data("artifact".utf8), to: buildDirectory.appendingPathComponent("nested/output.bin"))

        let record = try await safety.retainBeforeDelete(
            side: .external,
            fileURL: buildDirectory,
            relativePath: "project/build",
            projectID: UUID(),
            operationID: UUID(),
            now: Date(timeIntervalSince1970: 100),
            retainDays: 30
        )

        let retainedDirectory = URL(fileURLWithPath: record.safetyPath, isDirectory: true)
        XCTAssertFalse(fileManager.fileExists(atPath: buildDirectory.path))
        XCTAssertEqual(try Data(contentsOf: retainedDirectory.appendingPathComponent("nested/output.bin")), Data("artifact".utf8))
        XCTAssertTrue(record.safetyPath.hasSuffix("/project/build"))
    }

    func testConflictCopiesKeepBothSides() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let internalFile = internalRoot.appendingPathComponent("project/README.md")
        let externalFile = externalRoot.appendingPathComponent("project/README.md")
        try write(Data("internal".utf8), to: internalFile)
        try write(Data("external".utf8), to: externalFile)
        let conflictID = UUID()

        let internalRecord = try await safety.retainConflictCopy(
            side: .internal,
            fileURL: internalFile,
            relativePath: "project/README.md",
            projectID: pair.id,
            conflictID: conflictID
        )
        let externalRecord = try await safety.retainConflictCopy(
            side: .external,
            fileURL: externalFile,
            relativePath: "project/README.md",
            projectID: pair.id,
            conflictID: conflictID
        )

        let internalData = try Data(contentsOf: URL(fileURLWithPath: internalRecord.safetyPath))
        let externalData = try Data(contentsOf: URL(fileURLWithPath: externalRecord.safetyPath))
        XCTAssertEqual(internalData, Data("internal".utf8))
        XCTAssertEqual(externalData, Data("external".utf8))
        XCTAssertTrue(fileManager.fileExists(atPath: internalFile.path))
        XCTAssertTrue(fileManager.fileExists(atPath: externalFile.path))
        let records = await stateStore.loadSafetyRecords(pairID: pair.id)
        XCTAssertEqual(records.count, 2)
    }

    func testRetireProjectMovesWholeTree() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let project = externalRoot.appendingPathComponent("project", isDirectory: true)
        try write(Data("one".utf8), to: project.appendingPathComponent("Sources/one.swift"))
        try write(Data("two".utf8), to: project.appendingPathComponent("Sources/two.swift"))

        let record = try await safety.retireProject(
            side: .external,
            projectURL: project,
            relativePath: "project",
            projectID: pair.id,
            operationID: UUID(),
            retainDays: 30
        )

        XCTAssertFalse(fileManager.fileExists(atPath: project.path))
        XCTAssertTrue(fileManager.fileExists(atPath: URL(fileURLWithPath: record.safetyPath).appendingPathComponent("Sources/one.swift").path))
        XCTAssertTrue(fileManager.fileExists(atPath: URL(fileURLWithPath: record.safetyPath).appendingPathComponent("Sources/two.swift").path))
    }

    func testScenario80FailedSafetyRecordWriteRollsBackMove() async throws {
        let pair = makePair()
        let stateTarget = root.appendingPathComponent("state-target", isDirectory: true)
        let stateLink = root.appendingPathComponent("state-link", isDirectory: true)
        try fileManager.createDirectory(at: stateTarget, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: stateLink, withDestinationURL: stateTarget)
        let safety = DevSafetyStore(pair: pair, stateStore: DevSyncStateStore(rootURL: stateLink))
        let source = externalRoot.appendingPathComponent("project/important.txt")
        try write(Data("important".utf8), to: source)

        do {
            _ = try await safety.retainBeforeDelete(
                side: .external,
                fileURL: source,
                relativePath: "project/important.txt",
                projectID: nil,
                operationID: UUID(),
                retainDays: 30
            )
            XCTFail("Expected safety record persistence to fail")
        } catch {}

        XCTAssertEqual(try Data(contentsOf: source), Data("important".utf8))
    }

    func testConcurrentRecordWritesDoNotLoseEntries() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let records = (0..<50).map { index in
            DevSafetyRecord(
                operationID: UUID(),
                projectID: nil,
                kind: .overwritten,
                side: .external,
                originalRelativePath: "file-\(index)",
                safetyPath: "history/file-\(index)",
                createdAt: Date(timeIntervalSince1970: Double(index)),
                expiresAt: nil
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for record in records {
                group.addTask {
                    try await safety.record(record)
                }
            }
            try await group.waitForAll()
        }

        let stored = await stateStore.loadSafetyRecords(pairID: pair.id)
        XCTAssertEqual(Set(stored.map(\.id)), Set(records.map(\.id)))
    }

    func testRetainBeforeDeleteRejectsPathEscape() async throws {
        let pair = makePair()
        let safety = DevSafetyStore(pair: pair, stateStore: makeStateStore())
        let outsideFile = root.appendingPathComponent("outside.txt")
        try write(Data("outside".utf8), to: outsideFile)

        do {
            _ = try await safety.retainBeforeDelete(
                side: .external,
                fileURL: outsideFile,
                relativePath: "../outside.txt",
                projectID: nil,
                operationID: UUID(),
                retainDays: 30
            )
            XCTFail("Expected an invalid relative path error")
        } catch {
            XCTAssertEqual(error as? DevSafetyError, .invalidRelativePath)
        }
        XCTAssertTrue(fileManager.fileExists(atPath: outsideFile.path))
    }

    func testRetainBeforeDeleteRejectsSymbolicLink() async throws {
        let pair = makePair()
        let safety = DevSafetyStore(pair: pair, stateStore: makeStateStore())
        let target = externalRoot.appendingPathComponent("project/target.txt")
        let link = externalRoot.appendingPathComponent("project/link.txt")
        try write(Data("target".utf8), to: target)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        do {
            _ = try await safety.retainBeforeDelete(
                side: .external,
                fileURL: link,
                relativePath: "project/link.txt",
                projectID: nil,
                operationID: UUID(),
                retainDays: 30
            )
            XCTFail("Expected a symbolic link error")
        } catch {
            XCTAssertEqual(error as? DevSafetyError, .symbolicLink)
        }
        XCTAssertTrue(fileManager.fileExists(atPath: link.path))
        XCTAssertEqual(try Data(contentsOf: target), Data("target".utf8))
    }

    func testSafetyDirectoriesAndRetainedFilesUseRestrictivePermissions() async throws {
        let pair = makePair()
        let safety = DevSafetyStore(pair: pair, stateStore: makeStateStore())
        let source = externalRoot.appendingPathComponent("project/private.txt")
        try write(Data("private".utf8), to: source)
        let record = try await safety.retainBeforeDelete(
            side: .external,
            fileURL: source,
            relativePath: "project/private.txt",
            projectID: nil,
            operationID: UUID(),
            retainDays: 30
        )
        let retainedFile = URL(fileURLWithPath: record.safetyPath)

        XCTAssertEqual(permissions(at: safety.systemRoot(for: .external)), 0o700)
        XCTAssertEqual(permissions(at: retainedFile.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(permissions(at: retainedFile), 0o600)
    }

    func testScenario65RetentionProtectsConflictsAndOpenOperationsAndAppliesSizeCap() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let history = try await safety.directory(.history, side: .external)
        let conflicts = try await safety.directory(.conflicts, side: .external)
        let staging = try await safety.directory(.staging, side: .external)
        let now = Date(timeIntervalSince1970: 1_000_000)

        let expiredStagingOperation = UUID()
        let expiredOverwriteOperation = UUID()
        let expiredDeleteOperation = UUID()
        let unresolvedConflictID = UUID()
        let openOperationID = UUID()
        let oldEligibleOperation = UUID()
        let newEligibleOperation = UUID()

        let expiredStagingPath = staging.appendingPathComponent("\(expiredStagingOperation.uuidString)/done.txt")
        let expiredOverwritePath = history.appendingPathComponent("\(expiredOverwriteOperation.uuidString)/old.txt")
        let expiredDeletePath = history.appendingPathComponent("\(expiredDeleteOperation.uuidString)/gone.txt")
        let unresolvedPath = conflicts.appendingPathComponent("\(unresolvedConflictID.uuidString)/external/unresolved.txt")
        let openPath = history.appendingPathComponent("\(openOperationID.uuidString)/open.txt")
        let oldEligiblePath = history.appendingPathComponent("\(oldEligibleOperation.uuidString)/old-eligible.txt")
        let newEligiblePath = history.appendingPathComponent("\(newEligibleOperation.uuidString)/new-eligible.txt")
        try write(Data(repeating: 0, count: 5), to: expiredStagingPath)
        try write(Data(repeating: 1, count: 10), to: expiredOverwritePath)
        try write(Data(repeating: 2, count: 20), to: expiredDeletePath)
        try write(Data(repeating: 3, count: 30), to: unresolvedPath)
        try write(Data(repeating: 4, count: 30), to: openPath)
        try write(Data(repeating: 5, count: 40), to: oldEligiblePath)
        try write(Data(repeating: 6, count: 50), to: newEligiblePath)

        let records = [
            makeRecord(operationID: expiredStagingOperation, kind: .staging, path: expiredStagingPath, bytes: 5, createdAt: now.addingTimeInterval(-101), expiresAt: now.addingTimeInterval(-1)),
            makeRecord(operationID: expiredOverwriteOperation, kind: .overwritten, path: expiredOverwritePath, bytes: 10, createdAt: now.addingTimeInterval(-100), expiresAt: now.addingTimeInterval(-1)),
            makeRecord(operationID: expiredDeleteOperation, kind: .deleted, path: expiredDeletePath, bytes: 20, createdAt: now.addingTimeInterval(-99), expiresAt: now.addingTimeInterval(-1)),
            makeRecord(operationID: unresolvedConflictID, kind: .conflictCopy, path: unresolvedPath, bytes: 30, createdAt: now.addingTimeInterval(-98), expiresAt: nil),
            makeRecord(operationID: openOperationID, kind: .overwritten, path: openPath, bytes: 30, createdAt: now.addingTimeInterval(-90), expiresAt: now.addingTimeInterval(100)),
            makeRecord(operationID: oldEligibleOperation, kind: .overwritten, path: oldEligiblePath, bytes: 40, createdAt: now.addingTimeInterval(-20), expiresAt: now.addingTimeInterval(100)),
            makeRecord(operationID: newEligibleOperation, kind: .deleted, path: newEligiblePath, bytes: 50, createdAt: now.addingTimeInterval(-10), expiresAt: now.addingTimeInterval(100))
        ]
        try await stateStore.saveSafetyRecords(records, pairID: pair.id)
        var configuration = DevSyncConfiguration.Safety()
        configuration.maximumSafetyStoreBytes = 115

        let result = try await safety.runRetention(
            now: now,
            safety: configuration,
            unresolvedConflictIDs: [unresolvedConflictID],
            openOperationIDs: [openOperationID]
        )

        XCTAssertEqual(result.removedRecords, 4)
        XCTAssertEqual(result.removedBytes, 75)
        XCTAssertEqual(result.skippedUnresolved, 1)
        XCTAssertEqual(result.skippedOpenOperations, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: expiredStagingPath.path))
        XCTAssertFalse(fileManager.fileExists(atPath: expiredOverwritePath.path))
        XCTAssertFalse(fileManager.fileExists(atPath: expiredDeletePath.path))
        XCTAssertFalse(fileManager.fileExists(atPath: oldEligiblePath.path))
        XCTAssertTrue(fileManager.fileExists(atPath: newEligiblePath.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unresolvedPath.path))
        XCTAssertTrue(fileManager.fileExists(atPath: openPath.path))
    }

    func testScenario65RetentionRejectsRecordThatTargetsSafetyRoot() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let history = try await safety.directory(.history, side: .external)
        let retainedFile = history.appendingPathComponent("other-operation/keep.txt")
        try write(Data("keep".utf8), to: retainedFile)
        let record = makeRecord(
            operationID: UUID(),
            kind: .deleted,
            path: safety.systemRoot(for: .external),
            bytes: 4,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        try await stateStore.saveSafetyRecords([record], pairID: pair.id)

        let result = try await safety.runRetention(
            now: Date(timeIntervalSince1970: 300),
            safety: DevSyncConfiguration.Safety(),
            unresolvedConflictIDs: [],
            openOperationIDs: []
        )

        XCTAssertEqual(result.removedRecords, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: retainedFile.path))
        let records = await stateStore.loadSafetyRecords(pairID: pair.id)
        XCTAssertEqual(records, [record])
    }

    func testScenario65ResolvedConflictRetentionStartsWhenResolutionIsObserved() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let conflictID = UUID()
        let conflicts = try await safety.directory(.conflicts, side: .external)
        let safetyPath = conflicts.appendingPathComponent("\(conflictID.uuidString)/external/resolved.txt")
        try write(Data("resolved".utf8), to: safetyPath)
        let record = makeRecord(
            operationID: conflictID,
            kind: .conflictCopy,
            path: safetyPath,
            bytes: 8,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: nil
        )
        try await stateStore.saveSafetyRecords([record], pairID: pair.id)
        let resolutionObservedAt = Date(timeIntervalSince1970: 10_000_000)

        let firstResult = try await safety.runRetention(
            now: resolutionObservedAt,
            safety: DevSyncConfiguration.Safety(),
            unresolvedConflictIDs: [],
            openOperationIDs: []
        )

        XCTAssertEqual(firstResult.removedRecords, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: safetyPath.path))
        let retained = await stateStore.loadSafetyRecords(pairID: pair.id)
        XCTAssertEqual(retained.first?.expiresAt, resolutionObservedAt.addingTimeInterval(30 * 86_400))

        let finalResult = try await safety.runRetention(
            now: resolutionObservedAt.addingTimeInterval(30 * 86_400 + 1),
            safety: DevSyncConfiguration.Safety(),
            unresolvedConflictIDs: [],
            openOperationIDs: []
        )
        XCTAssertEqual(finalResult.removedRecords, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: safetyPath.path))
    }

    func testScenario65ExpiredOverwriteIsRemovedBeforeExpiredDelete() {
        XCTAssertLessThan(
            DevSafetyStore.retentionPriority(for: .overwritten),
            DevSafetyStore.retentionPriority(for: .deleted)
        )
    }

    func testStalePartialCleanupSkipsOpenOperations() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let openOperationID = UUID()
        let staleOperationID = UUID()
        for side in DevSyncSide.allCases {
            let partial = try await safety.partialDirectory(side: side)
            try write(Data("partial".utf8), to: partial.appendingPathComponent(staleOperationID.uuidString).appendingPathComponent("file"))
            try write(Data("partial".utf8), to: partial.appendingPathComponent(openOperationID.uuidString).appendingPathComponent("file"))
        }

        let removed = try await safety.cleanStalePartials(openOperationIDs: [openOperationID])

        XCTAssertEqual(removed, 2)
        for side in DevSyncSide.allCases {
            let partial = try await safety.partialDirectory(side: side)
            XCTAssertFalse(fileManager.fileExists(atPath: partial.appendingPathComponent(staleOperationID.uuidString).path))
            XCTAssertTrue(fileManager.fileExists(atPath: partial.appendingPathComponent(openOperationID.uuidString).appendingPathComponent("file").path))
        }
    }

    private func makePair() -> DevSyncPair {
        DevSyncPair(
            displayName: "DevSSD",
            mode: .devBidirectional,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: "volume", volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalRoot.path, volumeIdentifier: "volume", volumeName: "DevSSD", fileSystemType: "apfs")
        )
    }

    private func makeStateStore() -> DevSyncStateStore {
        DevSyncStateStore(rootURL: root.appendingPathComponent("state", isDirectory: true))
    }

    private func makeRecord(
        operationID: UUID,
        kind: DevSafetyRecordKind,
        path: URL,
        bytes: Int64,
        createdAt: Date,
        expiresAt: Date?
    ) -> DevSafetyRecord {
        DevSafetyRecord(
            operationID: operationID,
            projectID: nil,
            kind: kind,
            side: .external,
            originalRelativePath: path.lastPathComponent,
            safetyPath: path.path,
            bytes: bytes,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }

    private func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func permissions(at url: URL) -> Int? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}
