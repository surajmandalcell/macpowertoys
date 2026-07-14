//
//  MarketplaceManager.swift
//  powertoys
//

import AppKit
import CryptoKit
import Foundation

// MARK: - Source

nonisolated struct MarketplaceSource: Codable, Equatable, Sendable, Identifiable {
    let url: URL
    var addedAt: Date
    var sourceID: String?
    var name: String?
    var etag: String?
    var lastRefreshed: Date?
    var lastError: String?

    var id: String { url.absoluteString }

    var displayName: String { name ?? url.host() ?? url.absoluteString }
}

nonisolated enum MarketplaceSourceError: Error, Equatable {
    case invalidURL
    case duplicateSource
    case unknownSource
    case httpStatus(Int)
    case catalogTooLarge
}

// MARK: - Fetching

nonisolated struct CatalogFetchResult: Sendable {
    let data: Data?
    let etag: String?
}

typealias CatalogFetcher = @Sendable (URL, String?) async throws -> CatalogFetchResult

// MARK: - Aggregated Entry

nonisolated struct MarketplaceEntry: Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case available
        case incompatible
        case installed
        case updateAvailable
    }

    let id: String
    let manifest: MarketplaceToolManifest?
    let receipt: MarketplaceReceipt?
    let sourceURL: URL?
    let sourceName: String
    let status: Status
    let sourceAvailable: Bool

    var name: String { manifest?.name ?? receipt?.name ?? id }
    var summary: String { manifest?.summary ?? receipt?.summary ?? "" }
}

// MARK: - Store

actor MarketplaceStore {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
    }

    private var sourcesURL: URL { root.appendingPathComponent("Sources/sources.json") }
    private var cacheDirectory: URL { root.appendingPathComponent("Cache") }
    private var iconsDirectory: URL { root.appendingPathComponent("Cache/Icons") }
    private var installedDirectory: URL { root.appendingPathComponent("Installed") }

    nonisolated static func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func installedDirectory(toolID: String) -> URL {
        installedDirectory.appendingPathComponent(toolID, isDirectory: true)
    }

    func loadSources() -> [MarketplaceSource] {
        guard let data = try? Data(contentsOf: sourcesURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MarketplaceSource].self, from: data)) ?? []
    }

    func saveSources(_ sources: [MarketplaceSource]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sources)
        try fm.createDirectory(at: sourcesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: sourcesURL, options: .atomic)
    }

    func loadCatalogData(cacheKey: String) -> Data? {
        try? Data(contentsOf: cacheDirectory.appendingPathComponent("\(cacheKey).json"))
    }

    func saveCatalogData(_ data: Data, cacheKey: String) throws {
        try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheDirectory.appendingPathComponent("\(cacheKey).json"), options: .atomic)
    }

    func deleteCatalogData(cacheKey: String) {
        try? fm.removeItem(at: cacheDirectory.appendingPathComponent("\(cacheKey).json"))
    }

    func loadReceipts() -> [MarketplaceReceipt] {
        guard let entries = try? fm.contentsOfDirectory(at: installedDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("receipt.json")) else {
                return nil
            }
            return try? MarketplaceReceipt.decode(data)
        }
        .sorted { $0.toolID < $1.toolID }
    }

    func saveReceipt(_ receipt: MarketplaceReceipt) throws {
        let directory = installedDirectory(toolID: receipt.toolID)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try receipt.encoded().write(to: directory.appendingPathComponent("receipt.json"), options: .atomic)
    }

    func deleteInstalled(toolID: String) throws {
        let directory = installedDirectory(toolID: toolID)
        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
    }

    func cachedIconURL(toolID: String) -> URL? {
        let url = iconsDirectory.appendingPathComponent("\(toolID).png")
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func saveIcon(_ data: Data, toolID: String) throws -> URL {
        try fm.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        let url = iconsDirectory.appendingPathComponent("\(toolID).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Manager

@Observable
@MainActor
final class MarketplaceManager {
    static let shared = MarketplaceManager()

    static let maxCatalogBytes = 5_000_000

    private(set) var sources: [MarketplaceSource] = []
    private(set) var catalogs: [String: MarketplaceCatalog] = [:]
    private(set) var receipts: [MarketplaceReceipt] = []
    private(set) var isRestored = false

    let store: MarketplaceStore
    private let reservedToolIDs: Set<String>
    private let hostEnvironment: HostEnvironment
    private let fetch: CatalogFetcher
    private let installerAdapters: InstallerAdapters
    private let uninstallHandler: (@MainActor (MarketplaceReceipt) async throws -> Void)?
    private var installerInstance: MarketplaceInstaller?

    init(
        rootDirectory: URL? = nil,
        reservedToolIDs: Set<String>? = nil,
        hostEnvironment: HostEnvironment = .current,
        fetch: CatalogFetcher? = nil,
        installerAdapters: InstallerAdapters = .live,
        uninstall: (@MainActor (MarketplaceReceipt) async throws -> Void)? = nil
    ) {
        store = MarketplaceStore(
            root: rootDirectory
                ?? AppDataLocation.directory.appendingPathComponent("Marketplace", isDirectory: true)
        )
        self.reservedToolIDs = reservedToolIDs ?? Set(ToolRegistry.builtInTools.map(\.id))
        self.hostEnvironment = hostEnvironment
        self.fetch = fetch ?? Self.httpFetcher
        self.installerAdapters = installerAdapters
        uninstallHandler = uninstall
    }

    private var installer: MarketplaceInstaller {
        if let installerInstance { return installerInstance }
        let created = MarketplaceInstaller(store: store, adapters: installerAdapters)
        installerInstance = created
        return created
    }

    static let httpFetcher: CatalogFetcher = { url, etag in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200:
            return CatalogFetchResult(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
        case 304:
            return CatalogFetchResult(data: nil, etag: etag)
        default:
            throw MarketplaceSourceError.httpStatus(http.statusCode)
        }
    }

    // MARK: Restoration

    func restore() async {
        guard !isRestored else { return }
        let loadedSources = await store.loadSources()
        let loadedReceipts = await store.loadReceipts()
        var loadedCatalogs: [String: MarketplaceCatalog] = [:]
        for source in loadedSources {
            guard let data = await store.loadCatalogData(cacheKey: MarketplaceStore.cacheKey(for: source.url)) else {
                continue
            }
            do {
                loadedCatalogs[source.id] = try MarketplaceCatalog.decode(data, reservedToolIDs: reservedToolIDs)
            } catch {
                LogManager.shared.warning(
                    "Dropping invalid cached catalog for \(source.url): \(error)",
                    source: "MarketplaceManager"
                )
            }
        }
        sources = loadedSources
        receipts = loadedReceipts
        catalogs = loadedCatalogs
        isRestored = true
    }

    // MARK: Sources

    func addSource(_ url: URL) async throws {
        guard MarketplaceCatalog.isHTTPS(url) else { throw MarketplaceSourceError.invalidURL }
        guard !sources.contains(where: { $0.url == url }) else { throw MarketplaceSourceError.duplicateSource }

        let result = try await fetch(url, nil)
        guard let data = result.data else { throw MarketplaceSourceError.httpStatus(304) }
        let catalog = try decodeCatalog(data)

        var source = MarketplaceSource(url: url, addedAt: Date())
        source.sourceID = catalog.source.id
        source.name = catalog.source.name
        source.etag = result.etag
        source.lastRefreshed = Date()

        try await store.saveCatalogData(data, cacheKey: MarketplaceStore.cacheKey(for: url))
        var updated = sources
        updated.append(source)
        try await store.saveSources(updated)

        sources = updated
        catalogs[source.id] = catalog
        NotificationCenter.default.post(name: .marketplaceSourcesChanged, object: nil)
        LogManager.shared.info("Added marketplace source \(catalog.source.name) (\(url))", source: "MarketplaceManager")
    }

    func applySyncedSourceURLs(_ urlStrings: [String]) async {
        let desired = urlStrings.compactMap(URL.init(string:))
        for url in desired where !sources.contains(where: { $0.url == url }) {
            try? await addSource(url)
        }
        for source in sources where !desired.contains(source.url) {
            try? await removeSourceOnly(source.url)
        }
    }

    func refreshAll() async {
        for source in sources {
            await refresh(source.url)
        }
    }

    func refresh(_ url: URL) async {
        guard let index = sources.firstIndex(where: { $0.url == url }) else { return }
        var source = sources[index]
        do {
            let result = try await fetch(url, source.etag)
            if let data = result.data {
                let catalog = try decodeCatalog(data)
                try await store.saveCatalogData(data, cacheKey: MarketplaceStore.cacheKey(for: url))
                catalogs[source.id] = catalog
                source.sourceID = catalog.source.id
                source.name = catalog.source.name
                source.etag = result.etag
            }
            source.lastRefreshed = Date()
            source.lastError = nil
        } catch {
            source.lastError = describe(error)
            LogManager.shared.warning(
                "Failed to refresh marketplace source \(url): \(source.lastError ?? "")",
                source: "MarketplaceManager"
            )
        }
        sources[index] = source
        try? await store.saveSources(sources)
    }

    func removeSourceOnly(_ url: URL) async throws {
        guard sources.contains(where: { $0.url == url }) else { throw MarketplaceSourceError.unknownSource }
        let removed = sources.filter { $0.url != url }
        try await store.saveSources(removed)
        await store.deleteCatalogData(cacheKey: MarketplaceStore.cacheKey(for: url))
        catalogs[url.absoluteString] = nil
        sources = removed
        NotificationCenter.default.post(name: .marketplaceSourcesChanged, object: nil)
        LogManager.shared.info("Removed marketplace source \(url) (apps kept)", source: "MarketplaceManager")
    }

    func removeSourceAndApps(_ url: URL) async throws -> [String] {
        let owned = receipts.filter { $0.sourceURL == url }
        var failedToolIDs: [String] = []
        for receipt in owned {
            do {
                try await uninstall(receipt)
            } catch {
                failedToolIDs.append(receipt.toolID)
                LogManager.shared.error(
                    "Failed to uninstall \(receipt.toolID): \(describe(error))",
                    source: "MarketplaceManager"
                )
            }
        }
        try await removeSourceOnly(url)
        return failedToolIDs
    }

    // MARK: Installed tools

    func installTool(_ manifest: MarketplaceToolManifest, from source: MarketplaceSource) async throws {
        guard manifest.isCompatible(with: hostEnvironment) else {
            throw MarketplaceInstallError.incompatible
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: manifest.artifact.bundleID) {
            app.terminate()
        }
        let receipt = try await installer.install(
            manifest,
            sourceID: source.sourceID ?? source.id,
            sourceURL: source.url
        )
        try await recordInstall(receipt)
        LogManager.shared.info(
            "Installed \(manifest.name) \(manifest.version) (build \(manifest.build))",
            source: "MarketplaceManager"
        )
    }

    func installedAppURL(for toolID: String) async -> URL? {
        let url = await store.installedDirectory(toolID: toolID)
            .appendingPathComponent(MarketplaceInstaller.appBundleName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func launchInstalledTool(toolID: String) async throws {
        guard let appURL = await installedAppURL(for: toolID) else {
            throw MarketplaceInstallError.appMissing
        }
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    func recordInstall(_ receipt: MarketplaceReceipt) async throws {
        try await store.saveReceipt(receipt)
        receipts.removeAll { $0.toolID == receipt.toolID }
        receipts.append(receipt)
        receipts.sort { $0.toolID < $1.toolID }
        NotificationCenter.default.post(name: .marketplaceReceiptsChanged, object: nil)
    }

    func uninstall(_ receipt: MarketplaceReceipt) async throws {
        if let uninstallHandler {
            try await uninstallHandler(receipt)
        } else {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: receipt.bundleID) {
                app.terminate()
            }
        }
        try await store.deleteInstalled(toolID: receipt.toolID)
        receipts.removeAll { $0.toolID == receipt.toolID }
        NotificationCenter.default.post(name: .marketplaceReceiptsChanged, object: nil)
    }

    func sourceAvailable(for receipt: MarketplaceReceipt) -> Bool {
        sources.contains { $0.url == receipt.sourceURL || $0.sourceID == receipt.sourceID }
    }

    var installedTools: [any Tool] {
        receipts.map { MarketplaceTool(receipt: $0, iconFileURL: iconFileURL(for: $0.toolID)) }
    }

    nonisolated func iconFileURL(for toolID: String) -> URL? {
        let url = store.root.appendingPathComponent("Cache/Icons/\(toolID).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Aggregation

    var entries: [MarketplaceEntry] {
        var claimed = Set<String>()
        var result: [MarketplaceEntry] = []
        let receiptsByID = Dictionary(uniqueKeysWithValues: receipts.map { ($0.toolID, $0) })

        for source in sources {
            guard let catalog = catalogs[source.id] else { continue }
            for manifest in catalog.tools {
                guard claimed.insert(manifest.id).inserted else { continue }
                let receipt = receiptsByID[manifest.id]
                result.append(MarketplaceEntry(
                    id: manifest.id,
                    manifest: manifest,
                    receipt: receipt,
                    sourceURL: source.url,
                    sourceName: catalog.source.name,
                    status: status(manifest: manifest, receipt: receipt),
                    sourceAvailable: true
                ))
            }
        }

        let orphaned = receipts
            .filter { !claimed.contains($0.toolID) }
            .sorted { $0.name < $1.name }
        for receipt in orphaned {
            result.append(MarketplaceEntry(
                id: receipt.toolID,
                manifest: nil,
                receipt: receipt,
                sourceURL: nil,
                sourceName: receipt.sourceID,
                status: .installed,
                sourceAvailable: sourceAvailable(for: receipt)
            ))
        }
        return result
    }

    private func status(manifest: MarketplaceToolManifest, receipt: MarketplaceReceipt?) -> MarketplaceEntry.Status {
        if let receipt {
            return receipt.updateAvailable(in: manifest) && manifest.isCompatible(with: hostEnvironment)
                ? .updateAvailable
                : .installed
        }
        return manifest.isCompatible(with: hostEnvironment) ? .available : .incompatible
    }

    // MARK: Icons

    func cachedIconURL(for toolID: String) async -> URL? {
        await store.cachedIconURL(toolID: toolID)
    }

    func fetchIconIfNeeded(for manifest: MarketplaceToolManifest) async -> URL? {
        if let cached = await store.cachedIconURL(toolID: manifest.id) { return cached }
        guard let data = try? await fetch(manifest.iconURL, nil).data else { return nil }
        return try? await store.saveIcon(data, toolID: manifest.id)
    }

    // MARK: Helpers

    private func decodeCatalog(_ data: Data) throws -> MarketplaceCatalog {
        guard data.count <= Self.maxCatalogBytes else { throw MarketplaceSourceError.catalogTooLarge }
        return try MarketplaceCatalog.decode(data, reservedToolIDs: reservedToolIDs)
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case let MarketplaceCatalogError.invalidValue(field):
            return "Invalid catalog value: \(field)"
        case let MarketplaceCatalogError.unsupportedFormatVersion(version):
            return "Unsupported catalog format version \(version)"
        case let MarketplaceCatalogError.duplicateToolID(id):
            return "Duplicate tool ID: \(id)"
        case let MarketplaceCatalogError.reservedToolID(id):
            return "Tool ID conflicts with a built-in tool: \(id)"
        case MarketplaceCatalogError.malformedJSON:
            return "Catalog is not valid JSON for this format"
        case let MarketplaceSourceError.httpStatus(code):
            return "Server returned HTTP \(code)"
        case MarketplaceSourceError.catalogTooLarge:
            return "Catalog exceeds the size limit"
        default:
            return (error as NSError).localizedDescription
        }
    }
}
