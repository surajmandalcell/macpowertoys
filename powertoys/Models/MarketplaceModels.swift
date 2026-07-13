//
//  MarketplaceModels.swift
//  powertoys
//

import Foundation

// MARK: - Version

nonisolated struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  let value = Int(part)
            else { return nil }
            values.append(value)
        }
        components = values
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    var description: String { components.map(String.init).joined(separator: ".") }
}

nonisolated struct HostEnvironment: Sendable {
    let hostVersion: AppVersion
    let hostBuild: Int
    let macOSVersion: AppVersion

    static var current: HostEnvironment {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return HostEnvironment(
            hostVersion: AppVersion(info["CFBundleShortVersionString"] as? String ?? "0") ?? AppVersion("0")!,
            hostBuild: Int(info["CFBundleVersion"] as? String ?? "0") ?? 0,
            macOSVersion: AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")!
        )
    }
}

// MARK: - Catalog

nonisolated enum MarketplaceToolCategory: String, Codable, CaseIterable, Sendable {
    case developer
    case text
    case files
    case system

    var toolCategory: ToolCategory {
        switch self {
        case .developer: .dev
        case .text: .text
        case .files: .files
        case .system: .system
        }
    }
}

nonisolated enum MarketplaceArchitecture: String, Codable, CaseIterable, Sendable {
    case arm64
    case x86_64
}

nonisolated struct MarketplaceManualSection: Codable, Equatable, Sendable {
    let title: String
    let points: [String]
}

nonisolated struct MarketplaceSettingsSyncContract: Codable, Equatable, Sendable {
    let keys: [String]
}

nonisolated struct MarketplaceArtifact: Codable, Equatable, Sendable {
    let url: URL
    let sha256: String
    let bundleID: String
    let teamID: String
    let architectures: [MarketplaceArchitecture]
}

nonisolated struct MarketplaceToolManifest: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let summary: String
    let category: MarketplaceToolCategory
    let manual: [MarketplaceManualSection]
    let iconURL: URL
    let version: String
    let build: Int
    let minHostVersion: String
    let minHostBuild: Int
    let minMacOSVersion: String
    let artifact: MarketplaceArtifact
    let settingsSync: MarketplaceSettingsSyncContract?
}

nonisolated struct MarketplaceCatalog: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let updated: Date
    }

    let formatVersion: Int
    let source: Source
    let tools: [MarketplaceToolManifest]
}

// MARK: - Validation

nonisolated enum MarketplaceCatalogError: Error, Equatable {
    case malformedJSON(String)
    case unsupportedFormatVersion(Int)
    case invalidValue(String)
    case duplicateToolID(String)
    case reservedToolID(String)
}

nonisolated extension MarketplaceCatalog {
    static let supportedFormatVersion = 1

    private static let identifierPattern = /[a-z0-9][a-z0-9-]{0,63}/
    private static let sha256Pattern = /[a-f0-9]{64}/
    private static let teamIDPattern = /[A-Z0-9]{10}/
    private static let bundleIDPattern = /[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/
    private static let settingsKeyPattern = /[A-Za-z0-9._-]{1,128}/

    static func decode(_ data: Data, reservedToolIDs: Set<String>) throws -> MarketplaceCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog: MarketplaceCatalog
        do {
            catalog = try decoder.decode(MarketplaceCatalog.self, from: data)
        } catch {
            throw MarketplaceCatalogError.malformedJSON(String(describing: error))
        }
        try catalog.validate(reservedToolIDs: reservedToolIDs)
        return catalog
    }

    func validate(reservedToolIDs: Set<String>) throws {
        guard formatVersion == Self.supportedFormatVersion else {
            throw MarketplaceCatalogError.unsupportedFormatVersion(formatVersion)
        }
        guard Self.isIdentifier(source.id) else {
            throw MarketplaceCatalogError.invalidValue("source.id")
        }
        guard !source.name.isEmpty else {
            throw MarketplaceCatalogError.invalidValue("source.name")
        }
        var seen = Set<String>()
        for tool in tools {
            guard seen.insert(tool.id).inserted else {
                throw MarketplaceCatalogError.duplicateToolID(tool.id)
            }
            guard !reservedToolIDs.contains(tool.id) else {
                throw MarketplaceCatalogError.reservedToolID(tool.id)
            }
            try tool.validate()
        }
    }

    static func isIdentifier(_ value: String) -> Bool {
        value.wholeMatch(of: identifierPattern) != nil
    }

    static func isSHA256(_ value: String) -> Bool {
        value.wholeMatch(of: sha256Pattern) != nil
    }

    static func isTeamID(_ value: String) -> Bool {
        value.wholeMatch(of: teamIDPattern) != nil
    }

    static func isBundleID(_ value: String) -> Bool {
        value.wholeMatch(of: bundleIDPattern) != nil
    }

    static func isSettingsKey(_ value: String) -> Bool {
        value.wholeMatch(of: settingsKeyPattern) != nil
    }

    static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }
}

nonisolated extension MarketplaceToolManifest {
    func validate() throws {
        func require(_ condition: Bool, _ field: String) throws {
            guard condition else {
                throw MarketplaceCatalogError.invalidValue("tools[\(id)].\(field)")
            }
        }

        try require(MarketplaceCatalog.isIdentifier(id), "id")
        try require(!name.isEmpty, "name")
        try require(!summary.isEmpty, "summary")
        try require(MarketplaceCatalog.isHTTPS(iconURL), "iconURL")
        try require(AppVersion(version) != nil, "version")
        try require(build >= 1, "build")
        try require(AppVersion(minHostVersion) != nil, "minHostVersion")
        try require(minHostBuild >= 0, "minHostBuild")
        try require(AppVersion(minMacOSVersion) != nil, "minMacOSVersion")
        for section in manual {
            try require(!section.title.isEmpty, "manual.title")
            try require(!section.points.isEmpty && section.points.allSatisfy { !$0.isEmpty }, "manual.points")
        }
        try require(MarketplaceCatalog.isHTTPS(artifact.url), "artifact.url")
        try require(MarketplaceCatalog.isSHA256(artifact.sha256), "artifact.sha256")
        try require(MarketplaceCatalog.isBundleID(artifact.bundleID), "artifact.bundleID")
        try require(MarketplaceCatalog.isTeamID(artifact.teamID), "artifact.teamID")
        try require(!artifact.architectures.isEmpty, "artifact.architectures")
        try require(Set(artifact.architectures).count == artifact.architectures.count, "artifact.architectures")
        if let settingsSync {
            try require(!settingsSync.keys.isEmpty, "settingsSync.keys")
            try require(settingsSync.keys.allSatisfy(MarketplaceCatalog.isSettingsKey), "settingsSync.keys")
            try require(Set(settingsSync.keys).count == settingsSync.keys.count, "settingsSync.keys")
        }
    }

    func isCompatible(with host: HostEnvironment) -> Bool {
        guard let minHost = AppVersion(minHostVersion),
              let minMac = AppVersion(minMacOSVersion)
        else { return false }
        return host.hostVersion >= minHost
            && host.hostBuild >= minHostBuild
            && host.macOSVersion >= minMac
    }
}

// MARK: - Receipt

nonisolated struct MarketplaceReceipt: Codable, Equatable, Sendable, Identifiable {
    let toolID: String
    let name: String
    let summary: String
    let category: MarketplaceToolCategory
    let manual: [MarketplaceManualSection]
    let version: String
    let build: Int
    let bundleID: String
    let teamID: String
    let sourceID: String
    let sourceURL: URL
    let installedAt: Date
    let settingsSync: MarketplaceSettingsSyncContract?

    var id: String { toolID }

    init(manifest: MarketplaceToolManifest, sourceID: String, sourceURL: URL, installedAt: Date) {
        toolID = manifest.id
        name = manifest.name
        summary = manifest.summary
        category = manifest.category
        manual = manifest.manual
        version = manifest.version
        build = manifest.build
        bundleID = manifest.artifact.bundleID
        teamID = manifest.artifact.teamID
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.installedAt = installedAt
        settingsSync = manifest.settingsSync
    }

    func updateAvailable(in manifest: MarketplaceToolManifest) -> Bool {
        manifest.id == toolID && manifest.build > build
    }

    static func decode(_ data: Data) throws -> MarketplaceReceipt {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MarketplaceReceipt.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
