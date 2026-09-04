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

    func testScenario65RetentionProtectsConflictsAndOpenOperationsAndAppliesSizeCap() async throws {
        let pair = makePair()
        let stateStore = makeStateStore()
        let safety = DevSafetyStore(pair: pair, stateStore: stateStore)
        let history = try await safety.directory(.history, side: .external)
        let conflicts = try await safety.directory(.conflicts, side: .external)
        let now = Date(timeIntervalSince1970: 1_000_000)

        let expiredOverwriteOperation = UUID()
        let expiredDeleteOperation = UUID()
        let unresolvedConflictID = UUID()
        let openOperationID = UUID()
        let oldEligibleOperation = UUID()
        let newEligibleOperation = UUID()

        let expiredOverwritePath = history.appendingPathComponent("\(expiredOverwriteOperation.uuidString)/old.txt")
        let expiredDeletePath = history.appendingPathComponent("\(expiredDeleteOperation.uuidString)/gone.txt")
        let unresolvedPath = conflicts.appendingPathComponent("\(unresolvedConflictID.uuidString)/external/unresolved.txt")
        let openPath = history.appendingPathComponent("\(openOperationID.uuidString)/open.txt")
        let oldEligiblePath = history.appendingPathComponent("\(oldEligibleOperation.uuidString)/old-eligible.txt")
        let newEligiblePath = history.appendingPathComponent("\(newEligibleOperation.uuidString)/new-eligible.txt")
        try write(Data(repeating: 1, count: 10), to: expiredOverwritePath)
        try write(Data(repeating: 2, count: 20), to: expiredDeletePath)
        try write(Data(repeating: 3, count: 30), to: unresolvedPath)
        try write(Data(repeating: 4, count: 30), to: openPath)
        try write(Data(repeating: 5, count: 40), to: oldEligiblePath)
        try write(Data(repeating: 6, count: 50), to: newEligiblePath)

        let records = [
            makeRecord(operationID: expiredOverwriteOperation, kind: .overwritten, path: expiredOverwritePath, bytes: 10, createdAt: now.addingTimeInterval(-100), expiresAt: now.addingTimeInterval(-1)),
            makeRecord(operationID: expiredDeleteOperation, kind: .deleted, path: expiredDeletePath, bytes: 20, createdAt: now.addingTimeInterval(-99), expiresAt: now.addingTimeInterval(-1)),
            makeRecord(operationID: unresolvedConflictID, kind: .conflictCopy, path: unresolvedPath, bytes: 30, createdAt: now.addingTimeInterval(-98), expiresAt: nil),
            makeRecord(operationID: openOperationID, kind: .overwritten, path: openPath, bytes: 30, createdAt: now.addingTimeInterval(-90), expiresAt: now.addingTimeInterval(100)),
            makeRecord(operationID: oldEligibleOperation, kind: .overwritten, path: oldEligiblePath, bytes: 40, createdAt: now.addingTimeInterval(-20), expiresAt: now.addingTimeInterval(100)),
            makeRecord(operationID: newEligibleOperation, kind: .deleted, path: newEligiblePath, bytes: 50, createdAt: now.addingTimeInterval(-10), expiresAt: now.addingTimeInterval(100))
        ]
        try await stateStore.saveSafetyRecords(records, pairID: pair.id)
        var configuration = DevSyncConfiguration.Safety()
        configuration.maximumSafetyStoreBytes = 50

        let result = try await safety.runRetention(
            now: now,
            safety: configuration,
            unresolvedConflictIDs: [unresolvedConflictID],
            openOperationIDs: [openOperationID]
        )

        XCTAssertEqual(result.removedRecords, 4)
        XCTAssertEqual(result.removedBytes, 120)
        XCTAssertEqual(result.skippedUnresolved, 1)
        XCTAssertEqual(result.skippedOpenOperations, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: expiredOverwritePath.path))
        XCTAssertFalse(fileManager.fileExists(atPath: expiredDeletePath.path))
        XCTAssertFalse(fileManager.fileExists(atPath: oldEligiblePath.path))
        XCTAssertFalse(fileManager.fileExists(atPath: newEligiblePath.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unresolvedPath.path))
        XCTAssertTrue(fileManager.fileExists(atPath: openPath.path))
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
}
