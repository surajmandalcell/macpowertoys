import Darwin
import Foundation
import XCTest
@testable import powertoys

final class DevSyncRsyncTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-rsync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testScenario75SystemHelpParsingAndCapabilityProbe() async throws {
        let help = try runProcess(executable: URL(fileURLWithPath: "/usr/bin/rsync"), arguments: ["--help"])
        let options = DevRsyncProbe.parseHelp(String(decoding: help, as: UTF8.self))

        XCTAssertTrue(options.contains("--files-from"))
        XCTAssertTrue(options.contains("--partial-dir"))
        XCTAssertTrue(options.contains("--backup-dir"))
        XCTAssertTrue(options.contains("--itemize-changes"))
        XCTAssertTrue(options.contains("--executability"))
        XCTAssertTrue(options.contains("--extended-attributes"))
        XCTAssertFalse(options.contains("--acls"))
        XCTAssertFalse(options.contains("--crtimes"))

        let capabilities = try await DevRsyncProbe.probe(executable: URL(fileURLWithPath: "/usr/bin/rsync"), selfTestDirectory: temporaryRoot)
        XCTAssertTrue(capabilities.selfTestPassed, "\(capabilities.selfTestNotes)")
        XCTAssertEqual(capabilities.protocolVersion, 29)
        XCTAssertTrue(capabilities.isOpenrsync)
        XCTAssertTrue(capabilities.supportsFilesFrom)
        XCTAssertTrue(capabilities.supportsPartialDir)
        XCTAssertTrue(capabilities.supportsBackupDir)
    }

    func testScenario37ManifestRejectsUnsafePathsAndDefersUnsupportedNewlines() {
        let unsupported = makeCapabilities(supportsFrom0: false)
        let result = DevRsyncTransfer.validateManifest(
            ["../x", "/abs", "proj/.cloudsync-system/x", "safe/name", "line\nbreak"],
            capabilities: unsupported
        )

        XCTAssertEqual(result.accepted, ["safe/name"])
        XCTAssertEqual(result.deferred, ["line\nbreak"])
        XCTAssertEqual(result.rejected.count, 3)
        XCTAssertTrue(result.rejected.contains { if case .unsafePath("../x") = $0.1 { return true }; return false })
        XCTAssertTrue(result.rejected.contains { if case .unsafePath("/abs") = $0.1 { return true }; return false })
        XCTAssertTrue(result.rejected.contains { if case .unsafePath("proj/.cloudsync-system/x") = $0.1 { return true }; return false })
        XCTAssertTrue(DevRsyncTransfer.validateManifest(["line\nbreak"], capabilities: makeCapabilities(supportsFrom0: true)).accepted.contains("line\nbreak"))
    }

    func testScenario75ArgumentsNeverUseProhibitedOptions() {
        let capabilities = makeCapabilities(
            supportsFilesFrom: true,
            supportsFrom0: true,
            supportsPartialDir: true,
            supportsBackupDir: true,
            supportsItemizeChanges: true,
            supportsExecutability: true,
            supportsPerms: true,
            supportsXattrs: true,
            supportsHardLinks: true,
            supportsCrtimes: true,
            supportsOmitDirTimes: true,
            supportsModifyWindow: true,
            supportsDoubleDash: true
        )
        let arguments = DevRsyncCommand.arguments(
            capabilities: capabilities,
            options: DevRsyncOptions(
                preservePermissions: true,
                preserveXattrs: true,
                preserveHardLinks: true,
                modifyWindowSeconds: 2,
                partialDirectory: temporaryRoot.appendingPathComponent("partial"),
                backupDirectory: temporaryRoot.appendingPathComponent("backup")
            ),
            sourceRoot: temporaryRoot.appendingPathComponent("source"),
            destinationRoot: temporaryRoot.appendingPathComponent("destination")
        )
        let prohibited = [
            "--inplace", "--append", "--append-verify", "--copy-links",
            "--copy-dirlinks", "--keep-dirlinks", "--remove-source-files",
            "--ignore-errors", "--delete-excluded", "--trust-sender",
            "--old-args", "--delete"
        ]

        for option in prohibited {
            XCTAssertFalse(arguments.contains { $0 == option || $0.hasPrefix(option + "=") }, option)
        }
        XCTAssertTrue(arguments.contains("-p"))
        XCTAssertTrue(arguments.contains("-X"))
        XCTAssertTrue(arguments.contains("-H"))
        XCTAssertTrue(arguments.contains("--modify-window=2"))
        XCTAssertEqual(arguments.suffix(2), ["\(temporaryRoot.appendingPathComponent("source").path)/", "\(temporaryRoot.appendingPathComponent("destination").path)/"])
    }

    func testScenario59AutoOptionsRequireBothVolumesAndRsyncSupport() {
        let rsync = makeCapabilities(supportsPerms: true, supportsXattrs: true, supportsHardLinks: true)
        let internalVolume = makeVolume(path: temporaryRoot.appendingPathComponent("internal"), supportsAllMetadata: true)
        let externalVolume = makeVolume(path: temporaryRoot.appendingPathComponent("external"), supportsAllMetadata: false)
        let pair = DevPairCapabilities(internalVolume: internalVolume, externalVolume: externalVolume, rsync: rsync)
        let options = DevRsyncOptions.resolve(
            capabilities: rsync,
            pairCapabilities: pair,
            metadata: DevSyncConfiguration.Metadata(),
            partialDirectory: temporaryRoot.appendingPathComponent("partial"),
            backupDirectory: nil
        )

        XCTAssertFalse(options.preservePermissions)
        XCTAssertFalse(options.preserveXattrs)
        XCTAssertFalse(options.preserveHardLinks)
        XCTAssertEqual(options.modifyWindowSeconds, 2)
    }

    func testScenario38Scenario39Scenario41Scenario42PathMatrixCopiesSafely() async throws {
        let fileManager = FileManager.default
        let source = temporaryRoot.appendingPathComponent("source", isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent("destination", isDirectory: true)
        let partial = temporaryRoot.appendingPathComponent("partial", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        let spaceDirectory = source.appendingPathComponent("space dir", isDirectory: true)
        try fileManager.createDirectory(at: spaceDirectory, withIntermediateDirectories: true)
        try Data("space".utf8).write(to: spaceDirectory.appendingPathComponent("file name.txt"))
        try Data("emoji".utf8).write(to: source.appendingPathComponent("emoji 🚀.txt"))
        try Data("combining".utf8).write(to: source.appendingPathComponent("e\u{301}.txt"))
        try Data("dash".utf8).write(to: source.appendingPathComponent("-leading.txt"))
        let longName = String(repeating: "a", count: 250) + ".txt"
        try Data("long".utf8).write(to: source.appendingPathComponent(longName))
        try Data("hidden".utf8).write(to: source.appendingPathComponent(".hidden"))
        try fileManager.createDirectory(at: source.appendingPathComponent("empty directory"), withIntermediateDirectories: true)
        let script = source.appendingPathComponent("script.sh")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        chmod(script.path, mode_t(0o755))
        let outside = temporaryRoot.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        try fileManager.createSymbolicLink(at: source.appendingPathComponent("outside-link"), withDestinationURL: outside)

        let capabilities = makeCapabilities(supportsFrom0: true)
        let options = DevRsyncOptions(
            preservePermissions: true,
            preserveXattrs: false,
            preserveHardLinks: false,
            modifyWindowSeconds: nil,
            partialDirectory: partial,
            backupDirectory: nil
        )
        let arguments = DevRsyncCommand.arguments(
            capabilities: capabilities,
            options: options,
            sourceRoot: source,
            destinationRoot: destination
        )
        let manifest = [
            "space dir",
            "space dir/file name.txt",
            "emoji 🚀.txt",
            "e\u{301}.txt",
            "-leading.txt",
            longName,
            ".hidden",
            "empty directory",
            "script.sh",
            "outside-link"
        ]
        let transfer = DevRsyncTransfer(executable: URL(fileURLWithPath: "/usr/bin/rsync"), arguments: arguments, manifest: manifest, capabilities: capabilities)
        let result = try await transfer.run { _ in }

        XCTAssertEqual(result.exitClass, .success, result.stderrTail)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("space dir/file name.txt")), Data("space".utf8))
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent(longName).path))
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("empty directory").path))
        XCTAssertTrue((lstatMode(destination.appendingPathComponent("script.sh").path) & 0o111) != 0)
        XCTAssertEqual(lstatType(destination.appendingPathComponent("outside-link").path), S_IFLNK)
        XCTAssertEqual(readLink(destination.appendingPathComponent("outside-link").path), outside.path)
    }

    func testScenario76BackupDirectoryRetainsOverwrittenVersion() async throws {
        let fileManager = FileManager.default
        let source = temporaryRoot.appendingPathComponent("source", isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent("destination", isDirectory: true)
        let partial = temporaryRoot.appendingPathComponent("partial", isDirectory: true)
        let backup = temporaryRoot.appendingPathComponent("backup", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data("new content!".utf8).write(to: source.appendingPathComponent("regular.txt"))
        try Data("old content".utf8).write(to: destination.appendingPathComponent("regular.txt"))

        let capabilities = makeCapabilities(supportsFrom0: true)
        let arguments = DevRsyncCommand.arguments(
            capabilities: capabilities,
            options: DevRsyncOptions(
                preservePermissions: false,
                preserveXattrs: false,
                preserveHardLinks: false,
                modifyWindowSeconds: nil,
                partialDirectory: partial,
                backupDirectory: backup
            ),
            sourceRoot: source,
            destinationRoot: destination
        )
        let transfer = DevRsyncTransfer(executable: URL(fileURLWithPath: "/usr/bin/rsync"), arguments: arguments, manifest: ["regular.txt"], capabilities: capabilities)
        let result = try await transfer.run { _ in }

        XCTAssertEqual(result.exitClass, .success, result.stderrTail)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("regular.txt")), Data("new content!".utf8))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("regular.txt")), Data("old content".utf8))
    }

    func testScenario87CancelLeavesPartialDirectory() async throws {
        let fileManager = FileManager.default
        let source = temporaryRoot.appendingPathComponent("source", isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent("destination", isDirectory: true)
        let partial = temporaryRoot.appendingPathComponent("partial", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 32 * 1_024 * 1_024).write(to: source.appendingPathComponent("large.bin"))

        let capabilities = makeCapabilities(supportsFrom0: true)
        let arguments = DevRsyncCommand.arguments(
            capabilities: capabilities,
            options: DevRsyncOptions(
                preservePermissions: false,
                preserveXattrs: false,
                preserveHardLinks: false,
                modifyWindowSeconds: nil,
                partialDirectory: partial,
                backupDirectory: nil
            ),
            sourceRoot: source,
            destinationRoot: destination
        )
        let transfer = DevRsyncTransfer(executable: URL(fileURLWithPath: "/usr/bin/rsync"), arguments: arguments, manifest: ["large.bin"], capabilities: capabilities)
        let task = Task { try await transfer.run { _ in } }
        transfer.cancel()
        let result = try await task.value

        XCTAssertTrue(result.exitClass == .cancelled || result.exitClass == .failure)
        XCTAssertLessThan(result.duration, 6)
        XCTAssertTrue(fileManager.fileExists(atPath: partial.path))
    }

    private func makeCapabilities(
        supportsFilesFrom: Bool = true,
        supportsFrom0: Bool = true,
        supportsPartialDir: Bool = true,
        supportsBackupDir: Bool = true,
        supportsItemizeChanges: Bool = true,
        supportsExecutability: Bool = true,
        supportsPerms: Bool = true,
        supportsXattrs: Bool = false,
        supportsHardLinks: Bool = true,
        supportsCrtimes: Bool = false,
        supportsOmitDirTimes: Bool = true,
        supportsModifyWindow: Bool = true,
        supportsDoubleDash: Bool = true
    ) -> DevRsyncCapabilities {
        DevRsyncCapabilities(
            executablePath: "/usr/bin/rsync",
            versionText: "rsync version 3.2.7",
            protocolVersion: 31,
            isOpenrsync: false,
            supportedLongOptions: supportsFrom0 ? ["--from0"] : [],
            supportsFilesFrom: supportsFilesFrom,
            supportsFrom0: supportsFrom0,
            supportsPartialDir: supportsPartialDir,
            supportsBackupDir: supportsBackupDir,
            supportsItemizeChanges: supportsItemizeChanges,
            supportsExecutability: supportsExecutability,
            supportsPerms: supportsPerms,
            supportsXattrs: supportsXattrs,
            supportsACLs: false,
            supportsHardLinks: supportsHardLinks,
            supportsCrtimes: supportsCrtimes,
            supportsOmitDirTimes: supportsOmitDirTimes,
            supportsModifyWindow: supportsModifyWindow,
            supportsDoubleDash: supportsDoubleDash,
            selfTestPassed: true,
            selfTestNotes: [],
            fingerprint: "test",
            probedAt: Date()
        )
    }

    private func makeVolume(path: URL, supportsAllMetadata: Bool) -> DevVolumeCapabilities {
        DevVolumeCapabilities(
            volumeIdentifier: "uuid:\(path.lastPathComponent)",
            volumeName: path.lastPathComponent,
            mountPath: path.path,
            fileSystemType: "apfs",
            isReadOnly: false,
            isRemovable: false,
            isLocal: true,
            isEncrypted: true,
            availableCapacity: 10_000_000_000,
            totalCapacity: 20_000_000_000,
            isCaseSensitive: false,
            isCasePreserving: true,
            supportsSymbolicLinks: supportsAllMetadata,
            supportsHardLinks: supportsAllMetadata,
            supportsUnixPermissions: supportsAllMetadata,
            supportsExtendedAttributes: supportsAllMetadata,
            supportsCreationTimes: supportsAllMetadata,
            supportsPersistentIdentifiers: supportsAllMetadata,
            timestampResolutionNanoseconds: supportsAllMetadata ? 1 : 2_000_000_000,
            maximumPathComponentLength: 255,
            probedAt: Date(),
            fidelity: supportsAllMetadata ? .full : .portable,
            fidelityNotes: supportsAllMetadata ? [] : ["portable"]
        )
    }

    private func runProcess(executable: URL, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return output.fileHandleForReading.readDataToEndOfFile() + error.fileHandleForReading.readDataToEndOfFile()
    }

    private func lstatMode(_ path: String) -> mode_t {
        var value = stat()
        _ = path.withCString { lstat($0, &value) }
        return value.st_mode
    }

    private func lstatType(_ path: String) -> mode_t {
        lstatMode(path) & S_IFMT
    }

    private func readLink(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 1_024)
        let count = path.withCString { Darwin.readlink($0, &buffer, buffer.count) }
        guard count >= 0 else { return nil }
        return String(decoding: buffer.prefix(Int(count)).map(UInt8.init), as: UTF8.self)
    }
}
