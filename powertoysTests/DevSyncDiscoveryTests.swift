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
        let repository = try makeRepository(named: "mono")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("apps/api"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("apps/web"), withIntermediateDirectories: true)

        let result = await discover()
        XCTAssertEqual(result.projects.map(\.relativePath), ["mono"])
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testScenario13NestedIndependentRepositoryIsCandidateOnly() async throws {
        let outer = try makeRepository(named: "outer")
        let nested = outer.appendingPathComponent("vendor/lib", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try runGit(["init", "-q", "-b", "master"], in: nested)

        let result = await discover()
        XCTAssertEqual(result.projects.map(\.relativePath), ["outer"])
        XCTAssertTrue(result.candidates.contains {
            $0.relativePath == "outer/vendor/lib" && $0.kind == .nestedRepository
        })
    }

    func testScenario14SubmoduleIsNotOfferedAsNestedProject() async throws {
        let source = try makeRepository(named: "source")
        try write("submodule", to: source.appendingPathComponent("file.txt"))
        try runGit(["add", "file.txt"], in: source)
        try commit(in: source, message: "source")

        let superproject = try makeRepository(named: "superproject")
        try runGit(["-c", "protocol.file.allow=always", "submodule", "add", source.path, "modules/lib"], in: superproject)
        try commit(in: superproject, message: "submodule")

        let result = await discover()
        XCTAssertEqual(result.projects.map(\.relativePath), ["source", "superproject"])
        XCTAssertFalse(result.candidates.contains { $0.relativePath.hasSuffix("modules/lib") })
    }

    func testScenario15LinkedWorktreeIsDiscoveredWithTopologyKind() async throws {
        let main = try makeRepository(named: "main")
        try write("content", to: main.appendingPathComponent("file.txt"))
        try runGit(["add", "file.txt"], in: main)
        try commit(in: main, message: "initial")
        let linked = temporaryRoot.appendingPathComponent("linked", isDirectory: true)
        try runGit(["worktree", "add", "--detach", linked.path], in: main)

        let result = await discover()
        XCTAssertEqual(result.projects.first(where: { $0.relativePath == "linked" })?.kind, .gitLinkedWorktree)
    }

    func testScenario16BareRepositoryIsCandidate() async throws {
        let bare = temporaryRoot.appendingPathComponent("bare.git", isDirectory: true)
        try runGit(["init", "--bare", bare.path], in: temporaryRoot)

        let result = await discover()
        XCTAssertTrue(result.projects.isEmpty)
        XCTAssertTrue(result.candidates.contains {
            $0.relativePath == "bare.git" && $0.kind == .bareRepository
        })
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

    func testScenario19UnreadableDirectoryMakesScanIncomplete() async throws {
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

    func testScenario10RenameMatchesByResourceIdentifier() {
        let pairID = UUID()
        let project = DevProject(
            pairID: pairID,
            relativePath: "old/app",
            residency: .mirrored,
            kind: .gitRepository,
            internalResourceIdentifier: Data([1, 2, 3])
        )
        let current = DevDiscoveredProject(
            relativePath: "new/app",
            side: .internal,
            kind: .gitRepository,
            url: temporaryRoot.appendingPathComponent("new/app"),
            resourceIdentifier: Data([1, 2, 3])
        )

        let matches = DevProjectDiscovery.matchRenames(previous: [project], current: [current], side: .internal)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].confidence, 1.0)
        XCTAssertEqual(matches[0].previous.relativePath, "old/app")
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

    private func makeRepository(named name: String) throws -> URL {
        let repository = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-q", "-b", "master"], in: repository)
        return repository
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func commit(in repository: URL, message: String) throws {
        try runGit(["-c", "user.name=Dev Sync", "-c", "user.email=devsync@example.com", "commit", "-m", message], in: repository)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let stdout = try output.fileHandleForReading.readToEnd() ?? Data()
        let stderr = try error.fileHandleForReading.readToEnd() ?? Data()
        guard process.terminationStatus == 0 else {
            XCTFail(String(decoding: stderr, as: UTF8.self))
            return stdout
        }
        return stdout
    }
}
