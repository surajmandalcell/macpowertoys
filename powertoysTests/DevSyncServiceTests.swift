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

        let pair = try await service.createPair(draft: draft, approvedPreview: preview)
        let operations = await service.operations(pairID: pair.id, limit: 20)

        XCTAssertTrue(pair.hasCompletedFirstRun, operations.map { "\($0.state.rawValue):\($0.errorSummary ?? "none")" }.joined(separator: ", "))
        XCTAssertEqual(pair.state, .idle)
        let projects = await service.projects(pairID: pair.id)
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].residency, .mirrored)
        XCTAssertEqual(projects[0].state, .clean)
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
