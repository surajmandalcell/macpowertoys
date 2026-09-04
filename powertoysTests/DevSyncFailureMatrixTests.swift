import Darwin
import XCTest
@testable import powertoys

final class DevSyncFailureMatrixTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-failure-matrix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testDeepVerificationFindsSilentContentAndMetadataDifferences() async throws {
        let fixture = try makeVerificationFixture()
        let internalFile = fixture.internalProject.appendingPathComponent("silent.txt")
        let externalFile = fixture.externalProject.appendingPathComponent("silent.txt")
        try Data("internal".utf8).write(to: internalFile)
        try Data("external".utf8).write(to: externalFile)
        let sharedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: sharedDate, .posixPermissions: 0o700], ofItemAtPath: internalFile.path)
        try FileManager.default.setAttributes([.modificationDate: sharedDate, .posixPermissions: 0o600], ofItemAtPath: externalFile.path)

        let report = try await fixture.verifier.verify(pairID: fixture.pair.id, projectID: fixture.project.id)

        XCTAssertTrue(report.complete)
        XCTAssertEqual(report.verifiedFileCount, 1)
        XCTAssertTrue(report.differences.contains { $0.relativePath == "silent.txt" && $0.kind == .content })
        XCTAssertTrue(report.differences.contains { $0.relativePath == "silent.txt" && $0.kind == .permissions })
    }

    func testDeepVerificationCancellationStopsWithinFile() async throws {
        let fixture = try makeVerificationFixture()
        let internalFile = fixture.internalProject.appendingPathComponent("large.bin")
        let externalFile = fixture.externalProject.appendingPathComponent("large.bin")
        for file in [internalFile, externalFile] {
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: 512 * 1_024 * 1_024)
            try handle.close()
        }
        let task = Task {
            try await fixture.verifier.verify(pairID: fixture.pair.id, projectID: fixture.project.id)
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected deep verification to cancel")
        } catch is CancellationError {
        }
    }

    private func makeVerificationFixture() throws -> VerificationFixture {
        let internalRoot = temporaryRoot.appendingPathComponent("internal", isDirectory: true)
        let externalRoot = temporaryRoot.appendingPathComponent("external", isDirectory: true)
        let internalProject = internalRoot.appendingPathComponent("app", isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: internalProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalProject, withIntermediateDirectories: true)
        let identifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: internalRoot))
        let pair = DevSyncPair(
            displayName: "Verification",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: internalRoot.path, volumeIdentifier: identifier, volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: externalRoot.path, volumeIdentifier: identifier, volumeName: "External", fileSystemType: "apfs")
        )
        let project = DevProject(pairID: pair.id, relativePath: "app", residency: .mirrored, kind: .nonGit, explicitlyIncluded: true)
        let capabilities = DevPairCapabilities(
            internalVolume: DevVolumeProbe.probe(rootURL: internalRoot, probeDirectory: internalRoot),
            externalVolume: DevVolumeProbe.probe(rootURL: externalRoot, probeDirectory: externalRoot),
            probedAt: Date()
        )
        let verifier = DevDeepVerifier(pair: pair, projects: [project], internalRoot: internalRoot, externalRoot: externalRoot, capabilities: capabilities)
        return VerificationFixture(pair: pair, project: project, internalProject: internalProject, externalProject: externalProject, verifier: verifier)
    }
}

private struct VerificationFixture {
    var pair: DevSyncPair
    var project: DevProject
    var internalProject: URL
    var externalProject: URL
    var verifier: DevDeepVerifier
}
