import XCTest
@testable import powertoys

final class DevSyncServiceTests: XCTestCase {
    private var temporaryRoot: URL!
    private var services: [DevSyncService] = []

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for service in services { await service.stop() }
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testProbeRootsRejectsNestedRoots() async throws {
        let internalRoot = temporaryRoot.appendingPathComponent("internal", isDirectory: true)
        let externalRoot = internalRoot.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        let service = makeService()

        let result = await service.probeRoots(internal: internalRoot, external: externalRoot)

        XCTAssertTrue(result.issues.contains { issue in
            if case .nested = issue { return true }
            return false
        })
        XCTAssertFalse(result.canContinue)
    }

    func testDiscoverAndPreviewDoNotMutateRoots() async throws {
        let fixture = try makeRoots(internalOnly: true)
        let draft = setupDraft(fixture: fixture)
        let service = makeService()
        let beforeInternal = try listing(fixture.internalRoot)
        let beforeExternal = try listing(fixture.externalRoot)

        _ = await service.discover(draft: draft)
        _ = await service.preview(draft: draft)

        XCTAssertEqual(try listing(fixture.internalRoot), beforeInternal)
        XCTAssertEqual(try listing(fixture.externalRoot), beforeExternal)
    }

    func testPreviewPlansPendingMirrorsLinksSensitiveFilesAndSpace() async throws {
        let fixture = try makeRoots(internalOnly: true)
        try Data("SECRET=1".utf8).write(to: fixture.internalRoot.appendingPathComponent("app/.env.local"))
        let externalOnly = fixture.externalRoot.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: externalOnly, withIntermediateDirectories: true)
        try Data("// marker".utf8).write(to: externalOnly.appendingPathComponent("Package.swift"))
        var draft = setupDraft(fixture: fixture)
        draft.includedCandidatePaths = ["app", "data"]
        let service = makeService()

        let preview = await service.preview(draft: draft)

        XCTAssertTrue(preview.scanComplete)
        XCTAssertEqual(preview.summary.copyToExternalCount, 3)
        XCTAssertEqual(preview.summary.managedLinksToCreate, 1)
        XCTAssertEqual(preview.summary.sensitiveIncludedCount, 1)
        XCTAssertEqual(preview.sensitiveIncludedPaths, ["app/.env.local"])
        XCTAssertGreaterThan(preview.summary.requiredFreeBytes, 0)
        XCTAssertEqual(preview.summary.primaryActionTitle, "Copy 3 files and 1 managed link")
        XCTAssertTrue(preview.plan.actions.contains { $0.kind == .copyPath && $0.destinationSide == .external && $0.relativePath == "app/source.swift" })
        XCTAssertFalse(preview.warnings.contains { $0.hasPrefix("Not enough space") })
        let scanned = preview.groups.flatMap(\.items).first { $0.relativePath == "app" }
        XCTAssertGreaterThan(scanned?.includedBytes ?? 0, 0)

        draft.configuration.safety.minimumFreeSpaceReserveBytes = Int64.max / 2
        let starved = await service.preview(draft: draft)
        XCTAssertTrue(starved.warnings.contains { $0.hasPrefix("Not enough space") })
    }

    func testExternalSafetyHistoryUsesCanonicalTemporaryRoot() async throws {
        let fixture = try makeRoots(internalOnly: true)
        let internalRoot = try DevSyncRoots.makeRoot(url: fixture.internalRoot)
        let externalRoot = try DevSyncRoots.makeRoot(url: fixture.externalRoot)
        XCTAssertTrue(externalRoot.path.hasPrefix("/private/var/"))
        let pair = DevSyncPair(displayName: "Safety", mode: .devOneWay, internalRoot: internalRoot, externalRoot: externalRoot)
        let store = DevSyncStateStore(rootURL: temporaryRoot.appendingPathComponent("safety-state"))
        let safety = DevSafetyStore(pair: pair, stateStore: store)

        let history = try await safety.directory(.history, side: .external)

        XCTAssertTrue(FileManager.default.fileExists(atPath: history.path))
        XCTAssertTrue(history.path.hasPrefix(externalRoot.path + "/"))
    }

    func testSafetyRejectsDotDotEscapeAfterCanonicalRootFix() async throws {
        let fixture = try makeRoots(internalOnly: true)
        let pair = DevSyncPair(
            displayName: "Safety",
            mode: .devOneWay,
            internalRoot: try DevSyncRoots.makeRoot(url: fixture.internalRoot),
            externalRoot: try DevSyncRoots.makeRoot(url: fixture.externalRoot)
        )
        let store = DevSyncStateStore(rootURL: temporaryRoot.appendingPathComponent("escape-state"))
        let outside = fixture.externalRoot.deletingLastPathComponent().appendingPathComponent("escape.txt")
        try Data("escape".utf8).write(to: outside)

        do {
            _ = try await DevSafetyStore(pair: pair, stateStore: store).retainBeforeDelete(
                side: .external,
                fileURL: outside,
                relativePath: "../escape.txt",
                projectID: nil,
                operationID: UUID(),
                retainDays: 1
            )
            XCTFail("Expected an unsafe relative path to be rejected")
        } catch let error as DevSafetyError {
            XCTAssertEqual(error, .invalidRelativePath)
        }
    }

    func testCreatePairRunsFirstRunAndLeavesMirroredProjectIdle() async throws {
        let fixture = try makeRoots(internalOnly: true)
        let draft = setupDraft(fixture: fixture)
        let service = makeService()
        let preview = await service.preview(draft: draft)

        var pair = try await service.createPair(draft: draft, approvedPreview: preview)
        for _ in 0..<100 {
            let status = await service.status(pairID: pair.id)
            let projects = await service.projects(pairID: pair.id)
            if status?.state == .idle, projects.allSatisfy({ $0.state == .clean }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let storedPairs = await service.pairs()
        pair = try XCTUnwrap(storedPairs.first { $0.id == pair.id })
        let operations = await service.operations(pairID: pair.id, limit: 20)
        let status = await service.status(pairID: pair.id)

        XCTAssertTrue(pair.hasCompletedFirstRun, operations.map { "\($0.state.rawValue):\($0.errorSummary ?? "none")" }.joined(separator: ", "))
        XCTAssertEqual(status?.state, .idle)
        let projects = await service.projects(pairID: pair.id)
        XCTAssertEqual(projects.map(\.relativePath), ["app", ""])
        XCTAssertEqual(projects[0].residency, .mirrored)
        XCTAssertEqual(projects[0].state, .clean)
        XCTAssertEqual(projects[1].state, .clean)
        XCTAssertEqual(
            try Data(contentsOf: fixture.externalRoot.appendingPathComponent("app/source.swift")),
            Data("source".utf8)
        )
    }

    private func makeService() -> DevSyncService {
        let store = DevSyncStateStore(rootURL: temporaryRoot.appendingPathComponent("state-\(UUID().uuidString)", isDirectory: true))
        let service = DevSyncService(stateStore: store, rsyncPreferredPath: "/usr/bin/rsync")
        services.append(service)
        return service
    }

    private func makeRoots(internalOnly: Bool) throws -> RootFixture {
        let internalRoot = temporaryRoot.appendingPathComponent("internal-\(UUID().uuidString)", isDirectory: true)
        let externalRoot = temporaryRoot.appendingPathComponent("external-\(UUID().uuidString)", isDirectory: true)
        let internalProject = internalRoot.appendingPathComponent("app", isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        try Data("// marker".utf8).write(to: internalProject.appendingPathComponent("Package.swift"))
        try Data("source".utf8).write(to: internalProject.appendingPathComponent("source.swift"))
        if !internalOnly {
            try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
            try Data("// marker".utf8).write(to: externalProject.appendingPathComponent("Package.swift"))
            try Data("source".utf8).write(to: externalProject.appendingPathComponent("source.swift"))
        }
        return RootFixture(internalRoot: internalRoot, externalRoot: externalRoot)
    }

    private func setupDraft(fixture: RootFixture) -> DevSetupDraft {
        var configuration = DevSyncConfiguration.default
        configuration.safety.minimumFreeSpaceReserveBytes = 0
        return DevSetupDraft(
            displayName: "Test",
            mode: .devOneWay,
            internalURL: fixture.internalRoot,
            externalURL: fixture.externalRoot,
            configuration: configuration,
            includedCandidatePaths: ["app"]
        )
    }

    private func listing(_ root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else { return [] }
        return try enumerator.compactMap { value -> String? in
            guard let url = value as? URL else { return nil }
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                enumerator.skipDescendants()
            }
            return String(url.path.dropFirst(root.path.count + 1))
        }.sorted()
    }
}

private struct RootFixture {
    var internalRoot: URL
    var externalRoot: URL
}
