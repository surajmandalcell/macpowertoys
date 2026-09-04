import Foundation
import XCTest
@testable import powertoys

final class DevSyncDiscoveryTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
        try super.tearDownWithError()
    }

    func testScenario12MonorepoProducesOneProject() async throws {
        let repository = try await makeRepository(named: "mono")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("apps/api"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("apps/web"), withIntermediateDirectories: true)

        let result = await discover()
        XCTAssertEqual(result.projects.map(\.relativePath), ["mono"])
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testScenario13NestedIndependentRepositoryIsCandidateOnly() async throws {
        let outer = try await makeRepository(named: "outer")
        let nested = outer.appendingPathComponent("vendor/lib", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try await runGit(["init", "-q", "-b", "master"], in: nested)

        let result = await discover()
        XCTAssertEqual(result.projects.map(\.relativePath), ["outer"])
        XCTAssertTrue(result.candidates.contains {
            $0.relativePath == "outer/vendor/lib" && $0.kind == .nestedRepository
        })
    }

    func testScenario14SubmoduleIsNotOfferedAsNestedProject() async throws {
        let source = try await makeRepository(named: "source")
        try write("submodule", to: source.appendingPathComponent("file.txt"))
        try await runGit(["add", "file.txt"], in: source)
        try await commit(in: source, message: "source")

        let superproject = try await makeRepository(named: "superproject")
        try await runGit(["-c", "protocol.file.allow=always", "submodule", "add", source.path, "modules/lib with space"], in: superproject)
        try await commit(in: superproject, message: "submodule")

        let result = await discover()
        XCTAssertEqual(result.projects.map(\.relativePath), ["source", "superproject"])
        XCTAssertFalse(result.candidates.contains { $0.relativePath.hasSuffix("modules/lib with space") })
    }

    func testScenario15LinkedWorktreeIsDiscoveredWithTopologyKind() async throws {
        let main = try await makeRepository(named: "outside/main")
        try write("content", to: main.appendingPathComponent("file.txt"))
        try await runGit(["add", "file.txt"], in: main)
        try await commit(in: main, message: "initial")
        let pairRoot = temporaryRoot.appendingPathComponent("pair", isDirectory: true)
        try FileManager.default.createDirectory(at: pairRoot, withIntermediateDirectories: true)
        let linked = pairRoot.appendingPathComponent("linked", isDirectory: true)
        try await runGit(["worktree", "add", "--detach", linked.path], in: main)

        let result = await DevProjectDiscovery.discover(
            root: pairRoot,
            side: .internal,
            configuration: .init(),
            managedLinkPaths: [],
            otherRoot: nil
        )
        XCTAssertEqual(result.projects.first(where: { $0.relativePath == "linked" })?.kind, .gitLinkedWorktree)
        XCTAssertEqual(result.projects.count, 1)
    }

    func testScenario16BareRepositoryIsCandidate() async throws {
        let bare = temporaryRoot.appendingPathComponent("bare.git", isDirectory: true)
        try await runGit(["init", "--bare", bare.path], in: temporaryRoot)

        let result = await discover()
        XCTAssertTrue(result.projects.isEmpty)
        XCTAssertTrue(result.candidates.contains {
            $0.relativePath == "bare.git" && $0.kind == .bareRepository
        })
    }

    func testScenario17ClonesWithMatchingRemoteStaySeparateProjects() async throws {
        let first = try await makeRepository(named: "clone-a")
        let second = try await makeRepository(named: "clone-b")
        for repository in [first, second] {
            try await runGit(["remote", "add", "origin", "https://example.com/team/project.git"], in: repository)
        }

        let result = await discover()
        XCTAssertEqual(result.projects.map(\.relativePath), ["clone-a", "clone-b"])
    }

    func testScenario18MarkerIsUnmanagedCandidate() async throws {
        let package = temporaryRoot.appendingPathComponent("package", isDirectory: true)
        try write("{}", to: package.appendingPathComponent("package.json"))

        let result = await discover()
        XCTAssertTrue(result.projects.isEmpty)
        XCTAssertEqual(result.candidates, [
            DevProjectCandidate(relativePath: "package", side: .internal, kind: .marker, markerName: "package.json")
        ])
    }

    func testScenario19BroadRootFindsProjectsAndSkipsDependencyTrees() async throws {
        _ = try await makeRepository(named: "personal/app")
        _ = try await makeRepository(named: "work/service")
        let dependency = temporaryRoot.appendingPathComponent("node_modules/package", isDirectory: true)
        try FileManager.default.createDirectory(at: dependency.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let result = await discover()
        XCTAssertEqual(result.projects.map(\.relativePath), ["personal/app", "work/service"])
        XCTAssertTrue(result.complete)
    }

    func testUnreadableDirectoryMakesScanIncomplete() async throws {
        let unreadable = temporaryRoot.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try write("ignored", to: unreadable.appendingPathComponent("file.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path) }

        let result = await discover()
        XCTAssertFalse(result.complete)
        XCTAssertTrue(result.unreadablePaths.contains("private"))
    }

    func testScenario6SymlinkToExternalRootIsReportedWithoutDescent() async throws {
        let external = temporaryRoot.appendingPathComponent("external", isDirectory: true)
        let internalRoot = temporaryRoot.appendingPathComponent("internal", isDirectory: true)
        try FileManager.default.createDirectory(at: external.appendingPathComponent("project"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: internalRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: internalRoot.appendingPathComponent("project-link"),
            withDestinationURL: external.appendingPathComponent("project")
        )

        let result = await DevProjectDiscovery.discover(
            root: internalRoot,
            side: .internal,
            configuration: .init(),
            managedLinkPaths: [],
            otherRoot: external
        )
        XCTAssertTrue(result.projects.isEmpty)
        XCTAssertEqual(
            result.symlinksToExternal["project-link"],
            external.appendingPathComponent("project").resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testScenario10RenameMatchesByResourceIdentifier() async throws {
        _ = try await makeRepository(named: "old/app")
        let beforeRename = await discover()
        let previousDiscovery = try XCTUnwrap(beforeRename.projects.first { $0.relativePath == "old/app" })
        let newParent = temporaryRoot.appendingPathComponent("new", isDirectory: true)
        try FileManager.default.createDirectory(at: newParent, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: temporaryRoot.appendingPathComponent("old/app"),
            to: temporaryRoot.appendingPathComponent("new/app")
        )
        let afterRename = await discover()
        let current = try XCTUnwrap(afterRename.projects.first { $0.relativePath == "new/app" })
        let project = DevProject(
            pairID: UUID(),
            relativePath: "old/app",
            residency: .mirrored,
            kind: .gitRepository,
            internalResourceIdentifier: previousDiscovery.resourceIdentifier
        )

        let matches = DevProjectDiscovery.matchRenames(previous: [project], current: [current], side: .internal)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].confidence, 1.0)
        XCTAssertEqual(matches[0].previous.relativePath, "old/app")
    }

    func testRenameMatchesByIdentityFingerprint() {
        let identity = DevProjectIdentity(
            remoteURLHints: ["https://example.com/team/project.git"],
            headReference: "main",
            firstCommit: String(repeating: "a", count: 40),
            topologyKind: .gitRepository,
            fingerprint: "identity-fingerprint"
        )
        let project = DevProject(
            pairID: UUID(),
            relativePath: "old/project",
            residency: .mirrored,
            kind: .gitRepository,
            identity: identity
        )
        let current = DevDiscoveredProject(
            relativePath: "new/project",
            side: .internal,
            kind: .gitRepository,
            url: temporaryRoot.appendingPathComponent("new/project"),
            resourceIdentifier: nil
        )

        let matches = DevProjectDiscovery.matchRenames(
            previous: [project],
            current: [current],
            side: .internal,
            identitiesByRelativePath: [current.relativePath: identity]
        )

        XCTAssertEqual(matches.map(\.confidence), [0.9])
        XCTAssertEqual(matches.first?.evidence, "Matching project identity")
    }

    func testRenameSameKindAndNameIsOnlyLowConfidence() {
        let project = DevProject(
            pairID: UUID(),
            relativePath: "old/project",
            residency: .mirrored,
            kind: .gitRepository
        )
        let current = DevDiscoveredProject(
            relativePath: "new/project",
            side: .internal,
            kind: .gitRepository,
            url: temporaryRoot.appendingPathComponent("new/project"),
            resourceIdentifier: nil
        )

        let matches = DevProjectDiscovery.matchRenames(previous: [project], current: [current], side: .internal)

        XCTAssertEqual(matches.map(\.confidence), [0.5])
    }

    func testManagedLinkPathIsSkippedWithoutFollowingIt() async throws {
        let external = temporaryRoot.appendingPathComponent("external-project", isDirectory: true)
        try FileManager.default.createDirectory(at: external.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: temporaryRoot.appendingPathComponent("managed"),
            withDestinationURL: external
        )

        let result = await DevProjectDiscovery.discover(
            root: temporaryRoot,
            side: .internal,
            configuration: .init(),
            managedLinkPaths: ["managed"],
            otherRoot: nil
        )

        XCTAssertFalse(result.projects.contains { $0.relativePath == "managed" })
        XCTAssertNil(result.symlinksToExternal["managed"])
    }

    private func discover() async -> DevDiscoveryResult {
        await DevProjectDiscovery.discover(
            root: temporaryRoot,
            side: .internal,
            configuration: .init(),
            managedLinkPaths: [],
            otherRoot: nil
        )
    }

    private func makeRepository(named name: String) async throws -> URL {
        let repository = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try await runGit(["init", "-q", "-b", "master"], in: repository)
        return repository
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func commit(in repository: URL, message: String) async throws {
        try await runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", message], in: repository)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) async throws -> Data {
        try XCTSkipUnless(DevGit.isAvailable, "Git is unavailable")
        return try await DevGit.run(arguments, in: directory)
    }
}
