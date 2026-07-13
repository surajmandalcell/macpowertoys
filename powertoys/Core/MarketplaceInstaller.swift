//
//  MarketplaceInstaller.swift
//  powertoys
//

import CryptoKit
import Foundation

nonisolated enum MarketplaceInstallError: Error, Equatable {
    case incompatible
    case downloadFailed(String)
    case checksumMismatch
    case unsafeArchiveEntry(String)
    case notSingleAppBundle
    case teamIDMismatch(String)
    case notNotarized(String)
    case bundleIDMismatch(String)
    case architectureUnsupported
    case appMissing
    case commandFailed(String)
}

nonisolated struct InstallerAdapters: Sendable {
    var download: @Sendable (URL, URL) async throws -> Void
    var extract: @Sendable (URL, URL) async throws -> Void
    var verifyCodeSignature: @Sendable (URL) async throws -> String
    var assessNotarization: @Sendable (URL) async throws -> Void

    static let live = InstallerAdapters(
        download: { remote, destination in
            let (temp, response) = try await URLSession.shared.download(from: remote)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw MarketplaceInstallError.downloadFailed("HTTP \(status)")
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
        },
        extract: { archive, destination in
            let listing = try await MarketplaceInstaller.run("/usr/bin/zipinfo", ["-1", archive.path])
            for entry in listing.split(separator: "\n") {
                let path = String(entry)
                if path.hasPrefix("/") || path.split(separator: "/").contains("..") {
                    throw MarketplaceInstallError.unsafeArchiveEntry(path)
                }
            }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            _ = try await MarketplaceInstaller.run("/usr/bin/ditto", ["-x", "-k", archive.path, destination.path])
        },
        verifyCodeSignature: { appURL in
            _ = try await MarketplaceInstaller.run(
                "/usr/bin/codesign", ["--verify", "--deep", "--strict=all", appURL.path]
            )
            let details = try await MarketplaceInstaller.run("/usr/bin/codesign", ["-dvv", appURL.path])
            guard let line = details.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }),
                  case let team = String(line.dropFirst("TeamIdentifier=".count)),
                  MarketplaceCatalog.isTeamID(team)
            else {
                throw MarketplaceInstallError.teamIDMismatch("no TeamIdentifier in signature")
            }
            return team
        },
        assessNotarization: { appURL in
            let verdict = try await MarketplaceInstaller.run(
                "/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", appURL.path]
            )
            guard verdict.contains("Notarized Developer ID") else {
                throw MarketplaceInstallError.notNotarized(verdict.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    )
}

actor MarketplaceInstaller {
    static let appBundleName = "Tool.app"
    static let dataDirectoryName = "Data"

    private let store: MarketplaceStore
    private let adapters: InstallerAdapters
    private let fm = FileManager.default

    init(store: MarketplaceStore, adapters: InstallerAdapters = .live) {
        self.store = store
        self.adapters = adapters
    }

    func install(
        _ manifest: MarketplaceToolManifest,
        sourceID: String,
        sourceURL: URL
    ) async throws -> MarketplaceReceipt {
        guard Self.architectureSupported(declared: manifest.artifact.architectures) else {
            throw MarketplaceInstallError.architectureUnsupported
        }

        let staging = store.root
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let archive = staging.appendingPathComponent("artifact.zip")
        try await adapters.download(manifest.artifact.url, archive)

        guard try Self.sha256(of: archive) == manifest.artifact.sha256.lowercased() else {
            throw MarketplaceInstallError.checksumMismatch
        }

        let extracted = staging.appendingPathComponent("extracted", isDirectory: true)
        try await adapters.extract(archive, extracted)
        try Self.verifyNoEscapingSymlinks(in: extracted)
        let appURL = try Self.singleAppBundle(in: extracted)

        let signingTeam = try await adapters.verifyCodeSignature(appURL)
        guard signingTeam == manifest.artifact.teamID else {
            throw MarketplaceInstallError.teamIDMismatch(signingTeam)
        }
        try await adapters.assessNotarization(appURL)

        let bundleID = Bundle(url: appURL)?.bundleIdentifier ?? ""
        guard bundleID == manifest.artifact.bundleID else {
            throw MarketplaceInstallError.bundleIDMismatch(bundleID)
        }

        try await activate(appURL: appURL, toolID: manifest.id)
        return MarketplaceReceipt(
            manifest: manifest,
            sourceID: sourceID,
            sourceURL: sourceURL,
            installedAt: Date()
        )
    }

    private func activate(appURL: URL, toolID: String) async throws {
        let directory = await store.installedDirectory(toolID: toolID)
        try fm.createDirectory(
            at: directory.appendingPathComponent(Self.dataDirectoryName, isDirectory: true),
            withIntermediateDirectories: true
        )

        let destination = directory.appendingPathComponent(Self.appBundleName)
        let backup = directory.appendingPathComponent(".previous.app")
        try? fm.removeItem(at: backup)
        let hadExisting = fm.fileExists(atPath: destination.path)
        if hadExisting {
            try fm.moveItem(at: destination, to: backup)
        }
        do {
            try fm.moveItem(at: appURL, to: destination)
        } catch {
            if hadExisting {
                try? fm.moveItem(at: backup, to: destination)
            }
            throw error
        }
        try? fm.removeItem(at: backup)
    }

    // MARK: - Pure checks

    nonisolated static func architectureSupported(
        declared: [MarketplaceArchitecture],
        current: MarketplaceArchitecture = currentArchitecture
    ) -> Bool {
        guard !declared.isEmpty else { return false }
        if declared.contains(current) { return true }
        return current == .arm64 && declared.contains(.x86_64)
    }

    nonisolated static var currentArchitecture: MarketplaceArchitecture {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 16), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func singleAppBundle(in directory: URL) throws -> URL {
        let items = (try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))
        .filter { $0.lastPathComponent != "__MACOSX" }
        guard items.count == 1, let app = items.first, app.pathExtension == "app" else {
            throw MarketplaceInstallError.notSingleAppBundle
        }
        return app
    }

    nonisolated static func verifyNoEscapingSymlinks(in directory: URL) throws {
        let base = directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        ) else { return }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink == true else { continue }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            if resolved != base, !resolved.hasPrefix(base + "/") {
                throw MarketplaceInstallError.unsafeArchiveEntry(url.lastPathComponent)
            }
        }
    }

    // ponytail: blocks one cooperative thread for the subprocess lifetime; move to a
    // readabilityHandler pump if extraction of very large archives becomes a problem
    nonisolated static func run(_ tool: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = await Task.detached(priority: .userInitiated) {
            let output = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()
            return output
        }.value
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw MarketplaceInstallError.commandFailed("\(tool): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }
}
