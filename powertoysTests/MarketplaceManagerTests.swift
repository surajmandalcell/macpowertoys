import XCTest
@testable import powertoys

@MainActor
final class MarketplaceManagerTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("marketplace-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private static let builtInToolIDs: Set<String> = [
        "cc-history", "rclone", "logs", "ruler", "awake", "color-picker", "text-extractor"
    ]

    private static let host = HostEnvironment(
        hostVersion: AppVersion("1.6.0")!,
        hostBuild: 10,
        macOSVersion: AppVersion("26.2")!
    )

    private static let acmeURL = URL(string: "https://raw.githubusercontent.com/acme/tools/main/catalog.json")!
    private static let betaURL = URL(string: "https://raw.githubusercontent.com/beta/tools/main/catalog.json")!

    private nonisolated final class FetchLog: @unchecked Sendable {
        var calls: [URL] = []
        var etags: [String?] = []
    }

    private func acmeData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("spec/marketplace/valid-catalog.json")
        return try Data(contentsOf: url)
    }

    private var betaData: Data {
        Data("""
        {
          "formatVersion": 1,
          "source": { "id": "beta-tools", "name": "Beta Tools", "updated": "2026-07-02T12:00:00Z" },
          "tools": [
            {
              "id": "window-snapper",
              "name": "Window Snapper Fork",
              "summary": "Duplicate ID that must lose to the first-added source.",
              "category": "system",
              "manual": [],
              "iconURL": "https://example.com/icon.png",
              "version": "9.0",
              "build": 99,
              "minHostVersion": "1.6.0",
              "minHostBuild": 10,
              "minMacOSVersion": "26.0",
              "artifact": {
                "url": "https://example.com/fork.zip",
                "sha256": "aaaa456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                "bundleID": "com.beta.fork",
                "teamID": "ZYXWV98765",
                "architectures": ["arm64"]
              }
            },
            {
              "id": "beta-tool",
              "name": "Beta Tool",
              "summary": "A unique tool from the second source.",
              "category": "developer",
              "manual": [],
              "iconURL": "https://example.com/beta.png",
              "version": "1.0",
              "build": 1,
              "minHostVersion": "1.6.0",
              "minHostBuild": 10,
              "minMacOSVersion": "26.0",
              "artifact": {
                "url": "https://example.com/beta.zip",
                "sha256": "bbbb456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                "bundleID": "com.beta.tool",
                "teamID": "ZYXWV98765",
                "architectures": ["arm64"]
              }
            }
          ]
        }
        """.utf8)
    }

    private func makeManager(
        responses: [URL: Result<CatalogFetchResult, Error>],
        log: FetchLog = FetchLog(),
        uninstall: (@MainActor (MarketplaceReceipt) async throws -> Void)? = nil
    ) -> MarketplaceManager {
        MarketplaceManager(
            rootDirectory: root,
            reservedToolIDs: Self.builtInToolIDs,
            hostEnvironment: Self.host,
            fetch: { url, etag in
                log.calls.append(url)
                log.etags.append(etag)
                guard let response = responses[url] else { throw MarketplaceSourceError.httpStatus(404) }
                return try response.get()
            },
            uninstall: uninstall
        )
    }

    private func makeAcmeManager() throws -> MarketplaceManager {
        try makeManager(responses: [
            Self.acmeURL: .success(CatalogFetchResult(data: acmeData(), etag: "\"v1\""))
        ])
    }

    private func installFirstTool(_ manager: MarketplaceManager) async throws -> MarketplaceReceipt {
        let manifest = try XCTUnwrap(manager.catalogs.values.first { $0.source.id == "acme-tools" }?.tools.first)
        let receipt = MarketplaceReceipt(
            manifest: manifest,
            sourceID: "acme-tools",
            sourceURL: Self.acmeURL,
            installedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        try await manager.recordInstall(receipt)
        return receipt
    }

    func testAddSourcePersistsAndAggregates() async throws {
        let manager = try makeAcmeManager()
        await manager.restore()
        try await manager.addSource(Self.acmeURL)

        XCTAssertEqual(manager.sources.count, 1)
        XCTAssertEqual(manager.sources[0].sourceID, "acme-tools")
        XCTAssertEqual(manager.sources[0].name, "Acme Tools")
        XCTAssertEqual(manager.sources[0].etag, "\"v1\"")
        XCTAssertNil(manager.sources[0].lastError)

        let entries = manager.entries
        XCTAssertEqual(entries.map(\.id), ["window-snapper", "clip-stack"])
        XCTAssertEqual(entries[0].status, .available)
        XCTAssertTrue(entries.allSatisfy(\.sourceAvailable))
    }

    func testAddSourceRejectsDuplicateAndNonHTTPS() async throws {
        let manager = try makeAcmeManager()
        try await manager.addSource(Self.acmeURL)

        do {
            try await manager.addSource(Self.acmeURL)
            XCTFail("Expected duplicateSource")
        } catch let error as MarketplaceSourceError {
            XCTAssertEqual(error, .duplicateSource)
        }

        do {
            try await manager.addSource(URL(string: "http://example.com/catalog.json")!)
            XCTFail("Expected invalidURL")
        } catch let error as MarketplaceSourceError {
            XCTAssertEqual(error, .invalidURL)
        }
        XCTAssertEqual(manager.sources.count, 1)
    }

    func testAddSourceFetchFailureSavesNothing() async throws {
        let manager = makeManager(responses: [:])
        do {
            try await manager.addSource(Self.acmeURL)
            XCTFail("Expected httpStatus")
        } catch let error as MarketplaceSourceError {
            XCTAssertEqual(error, .httpStatus(404))
        }
        XCTAssertTrue(manager.sources.isEmpty)

        let restored = try makeAcmeManager()
        await restored.restore()
        XCTAssertTrue(restored.sources.isEmpty)
    }

    func testRestoreLoadsPersistedStateWithoutFetching() async throws {
        let manager = try makeAcmeManager()
        try await manager.addSource(Self.acmeURL)
        _ = try await installFirstTool(manager)

        let log = FetchLog()
        let restored = makeManager(responses: [:], log: log)
        await restored.restore()

        XCTAssertTrue(log.calls.isEmpty)
        XCTAssertEqual(restored.sources.count, 1)
        XCTAssertEqual(restored.catalogs.count, 1)
        XCTAssertEqual(restored.receipts.map(\.toolID), ["window-snapper"])
        XCTAssertEqual(
            restored.entries.first(where: { $0.id == "window-snapper" })?.status,
            .installed
        )
    }

    func testRefreshNotModifiedKeepsCatalog() async throws {
        let log = FetchLog()
        let manager = try makeManager(
            responses: [Self.acmeURL: .success(CatalogFetchResult(data: acmeData(), etag: "\"v1\""))],
            log: log
        )
        try await manager.addSource(Self.acmeURL)

        let notModified = makeManager(
            responses: [Self.acmeURL: .success(CatalogFetchResult(data: nil, etag: "\"v1\""))],
            log: log
        )
        await notModified.restore()
        await notModified.refreshAll()

        XCTAssertEqual(log.etags.last, "\"v1\"")
        XCTAssertEqual(notModified.catalogs.count, 1)
        XCTAssertNil(notModified.sources[0].lastError)
        XCTAssertNotNil(notModified.sources[0].lastRefreshed)
    }

    func testRefreshFailureKeepsOldCatalogAndRecordsError() async throws {
        let manager = try makeAcmeManager()
        try await manager.addSource(Self.acmeURL)

        let failing = makeManager(responses: [
            Self.acmeURL: .failure(MarketplaceSourceError.httpStatus(500))
        ])
        await failing.restore()
        await failing.refreshAll()

        XCTAssertEqual(failing.catalogs.count, 1)
        XCTAssertEqual(failing.sources[0].lastError, "Server returned HTTP 500")
        XCTAssertEqual(failing.entries.map(\.id), ["window-snapper", "clip-stack"])
    }

    func testDuplicateToolIDAcrossSourcesFirstAddedWins() async throws {
        let manager = try makeManager(responses: [
            Self.acmeURL: .success(CatalogFetchResult(data: acmeData(), etag: nil)),
            Self.betaURL: .success(CatalogFetchResult(data: betaData, etag: nil))
        ])
        try await manager.addSource(Self.acmeURL)
        try await manager.addSource(Self.betaURL)

        let entries = manager.entries
        XCTAssertEqual(entries.map(\.id), ["window-snapper", "clip-stack", "beta-tool"])
        let snapper = try XCTUnwrap(entries.first { $0.id == "window-snapper" })
        XCTAssertEqual(snapper.sourceURL, Self.acmeURL)
        XCTAssertEqual(snapper.manifest?.name, "Window Snapper")
    }

    func testUpdateDetectionThroughEntries() async throws {
        let manager = try makeAcmeManager()
        try await manager.addSource(Self.acmeURL)
        let manifest = try XCTUnwrap(manager.catalogs[Self.acmeURL.absoluteString]?.tools.first)
        let stale = MarketplaceToolManifest(
            id: manifest.id,
            name: manifest.name,
            summary: manifest.summary,
            category: manifest.category,
            manual: manifest.manual,
            iconURL: manifest.iconURL,
            version: "2.0.0",
            build: manifest.build - 1,
            minHostVersion: manifest.minHostVersion,
            minHostBuild: manifest.minHostBuild,
            minMacOSVersion: manifest.minMacOSVersion,
            artifact: manifest.artifact,
            settingsSync: manifest.settingsSync
        )
        try await manager.recordInstall(MarketplaceReceipt(
            manifest: stale,
            sourceID: "acme-tools",
            sourceURL: Self.acmeURL,
            installedAt: Date(timeIntervalSince1970: 1_780_000_000)
        ))

        XCTAssertEqual(
            manager.entries.first(where: { $0.id == "window-snapper" })?.status,
            .updateAvailable
        )
    }

    func testRemoveSourceOnlyKeepsReceiptsAndReconnects() async throws {
        let manager = try makeAcmeManager()
        try await manager.addSource(Self.acmeURL)
        let receipt = try await installFirstTool(manager)

        try await manager.removeSourceOnly(Self.acmeURL)

        XCTAssertTrue(manager.sources.isEmpty)
        XCTAssertTrue(manager.catalogs.isEmpty)
        XCTAssertEqual(manager.receipts, [receipt])
        XCTAssertFalse(manager.sourceAvailable(for: receipt))

        let orphan = try XCTUnwrap(manager.entries.first { $0.id == "window-snapper" })
        XCTAssertEqual(orphan.status, .installed)
        XCTAssertFalse(orphan.sourceAvailable)
        XCTAssertNil(orphan.manifest)

        try await manager.addSource(Self.acmeURL)
        XCTAssertTrue(manager.sourceAvailable(for: receipt))
        let reconnected = try XCTUnwrap(manager.entries.first { $0.id == "window-snapper" })
        XCTAssertEqual(reconnected.status, .installed)
        XCTAssertNotNil(reconnected.manifest)
    }

    func testRemoveSourceAndAppsUninstallsOnlyOwnedReceipts() async throws {
        let uninstalledBox = FetchLog()
        let manager = try makeManager(
            responses: [
                Self.acmeURL: .success(CatalogFetchResult(data: acmeData(), etag: nil)),
                Self.betaURL: .success(CatalogFetchResult(data: betaData, etag: nil))
            ],
            uninstall: { receipt in
                uninstalledBox.calls.append(URL(string: "uninstalled://\(receipt.toolID)")!)
            }
        )
        try await manager.addSource(Self.acmeURL)
        try await manager.addSource(Self.betaURL)
        _ = try await installFirstTool(manager)
        let betaManifest = try XCTUnwrap(manager.catalogs[Self.betaURL.absoluteString]?.tools.last)
        let betaReceipt = MarketplaceReceipt(
            manifest: betaManifest,
            sourceID: "beta-tools",
            sourceURL: Self.betaURL,
            installedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        try await manager.recordInstall(betaReceipt)

        let failed = try await manager.removeSourceAndApps(Self.acmeURL)

        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(uninstalledBox.calls.map(\.absoluteString), ["uninstalled://window-snapper"])
        XCTAssertEqual(manager.receipts.map(\.toolID), ["beta-tool"])
        XCTAssertEqual(manager.sources.map(\.url), [Self.betaURL])

        let receiptFile = await manager.store.installedDirectory(toolID: "window-snapper")
            .appendingPathComponent("receipt.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: receiptFile.path))
    }

    func testInstalledToolsExposeMarketplaceTools() async throws {
        let manager = try makeAcmeManager()
        try await manager.addSource(Self.acmeURL)
        _ = try await installFirstTool(manager)

        let tools = manager.installedTools
        XCTAssertEqual(tools.map(\.id), ["window-snapper"])
        XCTAssertEqual(tools.first?.category, .system)
        XCTAssertNil(tools.first?.iconFileURL)
    }

    func testRejectsOversizedCatalog() async throws {
        let huge = Data(repeating: 0x20, count: MarketplaceManager.maxCatalogBytes + 1)
        let manager = makeManager(responses: [
            Self.acmeURL: .success(CatalogFetchResult(data: huge, etag: nil))
        ])
        do {
            try await manager.addSource(Self.acmeURL)
            XCTFail("Expected catalogTooLarge")
        } catch let error as MarketplaceSourceError {
            XCTAssertEqual(error, .catalogTooLarge)
        }
    }
}
