import XCTest
@testable import powertoys

@MainActor
final class DevSyncRedactionTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-redaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        LogManager.shared.clearMemoryLogs()
    }

    override func tearDownWithError() throws {
        LogManager.shared.clearMemoryLogs()
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testRepresentativeOperationNeverLogsContentsCredentialsOrBookmarkBytes() async throws {
        let source = temporaryRoot.appendingPathComponent("nested/source/internal", isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent("nested/destination/external", isDirectory: true)
        let partial = temporaryRoot.appendingPathComponent("private/partial", isDirectory: true)
        let backup = temporaryRoot.appendingPathComponent("private/backup", isDirectory: true)
        for directory in [source, destination, partial, backup] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let secret = "redaction-secret-value"
        let privateKey = "-----BEGIN PRIVATE KEY----- redaction-private-key"
        let credential = "redaction-user:redaction-password"
        let remoteURL = "https://\(credential)@example.com/repository.git"
        let bookmark = Data("bookmark-secret-bytes".utf8)
        try Data("TOKEN=\(secret)".utf8).write(to: source.appendingPathComponent(".env"))
        try Data(privateKey.utf8).write(to: source.appendingPathComponent("id_rsa"))
        try Data("ordinary".utf8).write(to: source.appendingPathComponent("ordinary.txt"))

        let repository = temporaryRoot.appendingPathComponent("repository", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        if DevGit.isAvailable {
            _ = try await DevGit.run(["init", "-q", "-b", "master"], in: repository)
            _ = try await DevGit.run(["remote", "add", "origin", remoteURL], in: repository)
            let identityResult = await DevGit.identity(projectURL: repository)
            let identity = try XCTUnwrap(identityResult)
            XCTAssertEqual(identity.remoteURLHints, ["https://example.com/repository.git"])
        }
        let volumeIdentifier = try XCTUnwrap(DevSyncRoots.volumeIdentifier(for: source))
        _ = DevSyncPair(
            displayName: "Redaction",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: bookmark, path: source.path, volumeIdentifier: volumeIdentifier, volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: bookmark, path: destination.path, volumeIdentifier: volumeIdentifier, volumeName: "External", fileSystemType: "apfs")
        )

        let executable = URL(fileURLWithPath: "/usr/bin/rsync")
        let rsync = try await DevRsyncProbe.probe(executable: executable, selfTestDirectory: temporaryRoot)
        let volume = DevVolumeProbe.probe(rootURL: source, probeDirectory: source)
        let capabilities = DevPairCapabilities(internalVolume: volume, externalVolume: volume, rsync: rsync)
        let options = DevRsyncOptions.resolve(
            capabilities: rsync,
            pairCapabilities: capabilities,
            metadata: .init(),
            partialDirectory: partial,
            backupDirectory: backup
        )
        let arguments = DevRsyncCommand.arguments(
            capabilities: rsync,
            options: options,
            sourceRoot: source,
            destinationRoot: destination
        )
        let result = try await DevRsyncTransfer(
            executable: executable,
            arguments: arguments,
            manifest: [".env", "id_rsa", "ordinary.txt"],
            capabilities: rsync
        ).run { _ in }
        XCTAssertEqual(result.exitClass, .success)
        await Task.yield()
        let messages = LogManager.shared.logs.filter { $0.source == "DevSync" }.map(\.message)
        let combined = messages.joined(separator: "\n")

        XCTAssertFalse(messages.isEmpty)
        for value in [secret, privateKey, credential, "redaction-password", remoteURL, "bookmark-secret-bytes", bookmark.base64EncodedString()] {
            XCTAssertFalse(combined.contains(value), value)
        }
        XCTAssertFalse(combined.contains(temporaryRoot.path))
        XCTAssertFalse(combined.contains(source.deletingLastPathComponent().path))
        XCTAssertTrue(combined.contains("…/rsync"))
        XCTAssertTrue(combined.contains("…/internal"))
        XCTAssertTrue(combined.contains("…/external"))
    }
}
