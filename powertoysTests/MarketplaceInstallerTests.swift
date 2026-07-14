import CryptoKit
import XCTest
@testable import powertoys

@MainActor
final class MarketplaceInstallerTests: XCTestCase {
    private var root: URL!
    private var store: MarketplaceStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("installer-tests-\(UUID().uuidString)", isDirectory: true)
        store = MarketplaceStore(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private nonisolated static let sourceURL = URL(string: "https://raw.githubusercontent.com/acme/tools/main/catalog.json")!
    private nonisolated static let zipData = Data("fake-zip-bytes".utf8)

    private nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func makeFakeApp(at url: URL, bundleID: String, marker: String = "v1") throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleID],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("marker.txt"))
    }

    private func manifest(
        sha256: String = MarketplaceInstallerTests.digest(MarketplaceInstallerTests.zipData),
        bundleID: String = "com.acme.window-snapper",
        teamID: String = "ABCDE12345",
        architectures: [MarketplaceArchitecture] = [.arm64, .x86_64]
    ) -> MarketplaceToolManifest {
        MarketplaceToolManifest(
            id: "window-snapper",
            name: "Window Snapper",
            summary: "Snap windows.",
            category: .system,
            manual: [],
            iconURL: URL(string: "https://example.com/icon.png")!,
            version: "2.1.0",
            build: 34,
            minHostVersion: "1.6.0",
            minHostBuild: 10,
            minMacOSVersion: "26.0",
            artifact: MarketplaceArtifact(
                url: URL(string: "https://example.com/app.zip")!,
                sha256: sha256,
                bundleID: bundleID,
                teamID: teamID,
                architectures: architectures
            ),
            settingsSync: nil
        )
    }

    private func adapters(
        bundleID: String = "com.acme.window-snapper",
        signingTeam: String = "ABCDE12345",
        marker: String = "v1",
        extract: (@Sendable (URL, URL) async throws -> Void)? = nil,
        assess: (@Sendable (URL) async throws -> Void)? = nil
    ) -> InstallerAdapters {
        InstallerAdapters(
            download: { _, destination in try Self.zipData.write(to: destination) },
            extract: extract ?? { _, destination in
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Self.makeFakeApp(
                    at: destination.appendingPathComponent("Fake.app"),
                    bundleID: bundleID,
                    marker: marker
                )
            },
            verifyCodeSignature: { _ in signingTeam },
            assessNotarization: assess ?? { _ in }
        )
    }

    private func installedFile(_ path: String) async -> URL {
        await store.installedDirectory(toolID: "window-snapper").appendingPathComponent(path)
    }

    func testInstallHappyPath() async throws {
        let installer = MarketplaceInstaller(store: store, adapters: adapters())
        let receipt = try await installer.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)

        XCTAssertEqual(receipt.toolID, "window-snapper")
        XCTAssertEqual(receipt.build, 34)
        let appPlist = await installedFile("Tool.app/Contents/Info.plist")
        let dataDir = await installedFile("Data")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appPlist.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataDir.path))

        let staging = root.appendingPathComponent("Staging")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testChecksumMismatchAbortsAndPreservesExistingInstall() async throws {
        let installer = MarketplaceInstaller(store: store, adapters: adapters())
        _ = try await installer.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)

        let bad = manifest(sha256: String(repeating: "0", count: 64))
        do {
            _ = try await installer.install(bad, sourceID: "acme-tools", sourceURL: Self.sourceURL)
            XCTFail("Expected checksumMismatch")
        } catch let error as MarketplaceInstallError {
            XCTAssertEqual(error, .checksumMismatch)
        }

        let appPlist = await installedFile("Tool.app/Contents/Info.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appPlist.path))
    }

    func testWrongSigningTeamAborts() async throws {
        let installer = MarketplaceInstaller(store: store, adapters: adapters(signingTeam: "ZYXWV98765"))
        do {
            _ = try await installer.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)
            XCTFail("Expected teamIDMismatch")
        } catch let error as MarketplaceInstallError {
            XCTAssertEqual(error, .teamIDMismatch("ZYXWV98765"))
        }
        let app = await installedFile("Tool.app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path))
    }

    func testWrongBundleIDAborts() async throws {
        let installer = MarketplaceInstaller(store: store, adapters: adapters(bundleID: "com.evil.other"))
        do {
            _ = try await installer.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)
            XCTFail("Expected bundleIDMismatch")
        } catch let error as MarketplaceInstallError {
            XCTAssertEqual(error, .bundleIDMismatch("com.evil.other"))
        }
    }

    func testNotarizationRejectionAborts() async throws {
        let installer = MarketplaceInstaller(store: store, adapters: adapters(assess: { _ in
            throw MarketplaceInstallError.notNotarized("rejected")
        }))
        do {
            _ = try await installer.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)
            XCTFail("Expected notNotarized")
        } catch let error as MarketplaceInstallError {
            XCTAssertEqual(error, .notNotarized("rejected"))
        }
    }

    func testMultipleAppBundlesAbort() async throws {
        let installer = MarketplaceInstaller(store: store, adapters: adapters(extract: { _, destination in
            try Self.makeFakeApp(at: destination.appendingPathComponent("One.app"), bundleID: "com.acme.one")
            try Self.makeFakeApp(at: destination.appendingPathComponent("Two.app"), bundleID: "com.acme.two")
        }))
        do {
            _ = try await installer.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)
            XCTFail("Expected notSingleAppBundle")
        } catch let error as MarketplaceInstallError {
            XCTAssertEqual(error, .notSingleAppBundle)
        }
    }

    func testEscapingSymlinkAborts() async throws {
        let installer = MarketplaceInstaller(store: store, adapters: adapters(extract: { _, destination in
            try Self.makeFakeApp(at: destination.appendingPathComponent("Fake.app"), bundleID: "com.acme.window-snapper")
            try FileManager.default.createSymbolicLink(
                at: destination.appendingPathComponent("Fake.app/Contents/escape"),
                withDestinationURL: URL(fileURLWithPath: "/etc")
            )
        }))
        do {
            _ = try await installer.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)
            XCTFail("Expected unsafeArchiveEntry")
        } catch let error as MarketplaceInstallError {
            XCTAssertEqual(error, .unsafeArchiveEntry("escape"))
        }
    }

    func testUpdateReplacesBundleAndRemovesBackup() async throws {
        let v1 = MarketplaceInstaller(store: store, adapters: adapters(marker: "v1"))
        _ = try await v1.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)

        let v2 = MarketplaceInstaller(store: store, adapters: adapters(marker: "v2"))
        _ = try await v2.install(manifest(), sourceID: "acme-tools", sourceURL: Self.sourceURL)

        let markerURL = await installedFile("Tool.app/Contents/marker.txt")
        XCTAssertEqual(try String(contentsOf: markerURL, encoding: .utf8), "v2")
        let backup = await installedFile(".previous.app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testArchitectureSupportMatrix() {
        XCTAssertTrue(MarketplaceInstaller.architectureSupported(declared: [.arm64], current: .arm64))
        XCTAssertTrue(MarketplaceInstaller.architectureSupported(declared: [.x86_64], current: .arm64))
        XCTAssertTrue(MarketplaceInstaller.architectureSupported(declared: [.x86_64], current: .x86_64))
        XCTAssertFalse(MarketplaceInstaller.architectureSupported(declared: [.arm64], current: .x86_64))
        XCTAssertFalse(MarketplaceInstaller.architectureSupported(declared: [], current: .arm64))
    }

    func testStreamingSHA256MatchesKnownVector() throws {
        let file = root.appendingPathComponent("abc.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(
            try MarketplaceInstaller.sha256(of: file),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testManagerInstallToolRecordsReceipt() async throws {
        let manager = MarketplaceManager(
            rootDirectory: root,
            reservedToolIDs: ["logs"],
            hostEnvironment: HostEnvironment(
                hostVersion: AppVersion("1.6.0")!,
                hostBuild: 10,
                macOSVersion: AppVersion("26.2")!
            ),
            fetch: { _, _ in CatalogFetchResult(data: nil, etag: nil) },
            installerAdapters: adapters()
        )
        let source = MarketplaceSource(
            url: Self.sourceURL,
            addedAt: Date(),
            sourceID: "acme-tools",
            name: "Acme Tools"
        )
        try await manager.installTool(manifest(), from: source)

        XCTAssertEqual(manager.receipts.map(\.toolID), ["window-snapper"])
        let appURL = await manager.installedAppURL(for: "window-snapper")
        XCTAssertNotNil(appURL)

        let incompatible = manifest(sha256: String(repeating: "0", count: 64))
        let strictManager = MarketplaceManager(
            rootDirectory: root,
            reservedToolIDs: ["logs"],
            hostEnvironment: HostEnvironment(
                hostVersion: AppVersion("1.0.0")!,
                hostBuild: 1,
                macOSVersion: AppVersion("26.2")!
            ),
            fetch: { _, _ in CatalogFetchResult(data: nil, etag: nil) },
            installerAdapters: adapters()
        )
        do {
            try await strictManager.installTool(incompatible, from: source)
            XCTFail("Expected incompatible")
        } catch let error as MarketplaceInstallError {
            XCTAssertEqual(error, .incompatible)
        }
    }
}
