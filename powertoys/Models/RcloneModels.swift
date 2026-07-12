//
//  RcloneModels.swift
//  powertoys
//

import SwiftUI

// MARK: - Operation

enum RcloneOperation: String, Codable, CaseIterable, Identifiable, Sendable {
    case copy
    case sync
    case move

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copy: return "Copy"
        case .sync: return "Sync"
        case .move: return "Move"
        }
    }

    var rcEndpoint: String {
        switch self {
        case .copy: return "sync/copy"
        case .sync: return "sync/sync"
        case .move: return "sync/move"
        }
    }

    var icon: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .sync: return "arrow.triangle.2.circlepath"
        case .move: return "arrow.right.doc.on.clipboard"
        }
    }

    var summary: String {
        switch self {
        case .copy: return "Copy new or changed files to the destination. Nothing is deleted."
        case .sync: return "Make the destination identical to the source. Extra files at the destination are deleted."
        case .move: return "Move files to the destination, removing them from the source."
        }
    }

    var isDestructive: Bool {
        self == .sync || self == .move
    }
}

// MARK: - Transfer State

enum TransferState: String, Codable, Sendable {
    case queued
    case running
    case retrying
    case paused
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .retrying: return "Retrying"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .queued: return "clock"
        case .running: return "arrow.up.circle"
        case .retrying: return "arrow.clockwise.circle"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .queued: return .secondary
        case .running: return .accentColor
        case .retrying: return .orange
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    var isActive: Bool {
        self == .queued || self == .running || self == .retrying || self == .paused
    }

    var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

// MARK: - Job Filter

enum JobFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case completed
    case failed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All Transfers"
        case .active: return "Active"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .active: return "bolt.horizontal.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    func matches(_ state: TransferState) -> Bool {
        switch self {
        case .all: return true
        case .active: return state.isActive
        case .completed: return state == .completed
        case .failed: return state == .failed || state == .cancelled
        }
    }
}

// MARK: - Remote

struct RcloneRemote: Identifiable, Hashable, Sendable {
    let name: String
    let type: String

    var id: String { name }

    var displayName: String { name }

    var pathPrefix: String { "\(name):" }

    var icon: String {
        switch type {
        case "drive": return "externaldrive.badge.icloud"
        case "s3", "b2", "swift", "gcs", "azureblob": return "cloud"
        case "dropbox": return "shippingbox"
        case "onedrive", "sharepoint": return "cloud.fill"
        case "sftp", "ftp": return "server.rack"
        case "webdav", "http": return "globe"
        case "crypt": return "lock.shield"
        case "local", "alias": return "internaldrive"
        case "mega", "pcloud", "box", "yandex", "jottacloud": return "cloud"
        default: return "cloud"
        }
    }

    var typeLabel: String {
        type.isEmpty ? "remote" : type
    }
}

// MARK: - Per-file Progress

struct FileProgress: Identifiable, Sendable, Hashable {
    let name: String
    let size: Int64
    let bytes: Int64
    let percentage: Int
    let speed: Double
    let speedAvg: Double
    let eta: Double?

    var id: String { name }

    var fraction: Double {
        size > 0 ? min(1.0, Double(bytes) / Double(size)) : 0
    }
}

// MARK: - Aggregate Stats Snapshot

struct TransferStats: Sendable, Equatable {
    var bytes: Int64 = 0
    var totalBytes: Int64 = 0
    var speed: Double = 0
    var eta: Double?
    var errors: Int = 0
    var checks: Int = 0
    var totalChecks: Int = 0
    var transfers: Int = 0
    var totalTransfers: Int = 0
    var elapsedTime: Double = 0
    var fatalError: Bool = false
    var retryError: Bool = false
    var lastError: String = ""
    var transferring: [FileProgress] = []

    static let empty = TransferStats()

    var fraction: Double {
        totalBytes > 0 ? min(1.0, Double(bytes) / Double(totalBytes)) : 0
    }
}

// MARK: - Retry Policy

struct RetryPolicy: Sendable, Equatable {
    var maxRetries: Int
    var backoffSeconds: Double
    var backoffMultiplier: Double

    static let `default` = RetryPolicy(maxRetries: 3, backoffSeconds: 5, backoffMultiplier: 2)

    func delay(forAttempt attempt: Int) -> Double {
        backoffSeconds * pow(backoffMultiplier, Double(max(0, attempt)))
    }
}

// MARK: - Endpoint Kind (local vs remote)

enum EndpointKind: String, Sendable {
    case local
    case remote
}

// MARK: - Transfer Kind

enum TransferKind: String, Codable, Sendable {
    case directory
    case file
}

// MARK: - Remote Entry (browser listing)

struct RemoteEntry: Identifiable, Sendable, Hashable {
    let path: String
    let name: String
    let size: Int64
    let modTime: Date?
    let isDir: Bool
    let mimeType: String

    var id: String { path }

    var icon: String {
        if isDir { return "folder.fill" }
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.hasPrefix("text/") { return "doc.text" }
        if mimeType.contains("pdf") { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("compressed") { return "archivebox" }
        return "doc"
    }
}

// MARK: - Transfer Job

@Observable
final class TransferJob: Identifiable {
    let id: UUID
    let operation: RcloneOperation
    let kind: TransferKind
    let sourceFs: String
    let destinationFs: String
    let sourceDisplay: String
    let destinationDisplay: String
    let extraExcludes: [String]
    let bypassGlobalIgnores: Bool
    let createdAt: Date

    var excludePatterns: [String]
    var state: TransferState
    var stats: TransferStats
    var rcJobId: Int?
    var attempt: Int
    let maxRetries: Int
    var errorMessage: String?
    var startedAt: Date?
    var finishedAt: Date?
    var nextRetryAt: Date?
    var expectedBytes: Int64?
    var expectedFiles: Int?
    var autoPausedVolume: String?
    var isSizing = false
    private(set) var displayEta: Double?
    private var lastEtaRefresh = Date.distantPast

    var statsGroup: String { "job/\(id.uuidString)" }

    init(
        operation: RcloneOperation,
        kind: TransferKind = .directory,
        sourceFs: String,
        destinationFs: String,
        sourceDisplay: String,
        destinationDisplay: String,
        excludePatterns: [String],
        extraExcludes: [String] = [],
        bypassGlobalIgnores: Bool = false,
        maxRetries: Int,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.operation = operation
        self.kind = kind
        self.sourceFs = sourceFs
        self.destinationFs = destinationFs
        self.sourceDisplay = sourceDisplay
        self.destinationDisplay = destinationDisplay
        self.excludePatterns = excludePatterns
        self.extraExcludes = extraExcludes
        self.bypassGlobalIgnores = bypassGlobalIgnores
        self.createdAt = createdAt
        self.state = .queued
        self.stats = .empty
        self.rcJobId = nil
        self.attempt = 0
        self.maxRetries = maxRetries
        self.errorMessage = nil
    }

    var canRetry: Bool {
        state == .failed || state == .cancelled
    }

    var canCancel: Bool {
        state == .running || state == .queued || state == .retrying || state == .paused
    }

    var canPause: Bool {
        state == .running || state == .queued || state == .retrying
    }

    var canResume: Bool {
        state == .paused
    }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var effectiveTotalBytes: Int64 {
        max(stats.totalBytes, expectedBytes ?? 0)
    }

    var effectiveTotalFiles: Int {
        max(stats.totalTransfers, expectedFiles ?? 0)
    }

    var progressFraction: Double {
        let total = effectiveTotalBytes
        guard total > 0 else { return 0 }
        return min(1.0, Double(stats.bytes) / Double(total))
    }

    func refreshDisplayEta() {
        let raw: Double?
        if let expected = expectedBytes, expected > stats.totalBytes, stats.speed > 0 {
            raw = Double(expected - stats.bytes) / stats.speed
        } else {
            raw = stats.eta
        }
        let now = Date()
        if raw == nil || displayEta == nil || now.timeIntervalSince(lastEtaRefresh) >= 3 {
            displayEta = raw
            lastEtaRefresh = now
        }
    }
}

// MARK: - Ignore Pattern Matching (approximate rclone glob semantics)

enum IgnoreMatcher {
    static func matches(path: String, name: String, isDir: Bool, patterns: [String]) -> Bool {
        for pattern in patterns {
            if matches(path: path, name: name, isDir: isDir, pattern: pattern) {
                return true
            }
        }
        return false
    }

    static func matches(path: String, name: String, isDir: Bool, pattern: String) -> Bool {
        if pattern == name || pattern == path {
            return true
        }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(1))
            return name.hasSuffix(suffix)
        }
        if pattern.hasSuffix("*"), !pattern.contains("/") {
            let prefix = String(pattern.dropLast())
            return name.hasPrefix(prefix)
        }
        if pattern.hasSuffix("/**") {
            let directory = String(pattern.dropLast(3))
            if isDir && (name == directory || path == directory) { return true }
            if path.hasPrefix(directory + "/") { return true }
            if path.contains("/" + directory + "/") { return true }
            if isDir && path.hasSuffix("/" + directory) { return true }
        }
        return false
    }
}

// MARK: - Transfer Job Snapshot (persistence)

struct TransferJobSnapshot: Codable, Sendable {
    let id: UUID
    let operation: String
    let kind: String
    let sourceFs: String
    let destinationFs: String
    let sourceDisplay: String
    let destinationDisplay: String
    let excludePatterns: [String]
    let extraExcludes: [String]
    let bypassGlobalIgnores: Bool
    let createdAt: Date
    let state: String
    let attempt: Int
    let maxRetries: Int
    let errorMessage: String?
    let startedAt: Date?
    let finishedAt: Date?
    let bytes: Int64
    let totalBytes: Int64
    let transfers: Int
    let totalTransfers: Int
    let expectedBytes: Int64?
    let expectedFiles: Int?
    let autoPausedVolume: String?
}

extension TransferJob {
    var snapshot: TransferJobSnapshot {
        TransferJobSnapshot(
            id: id,
            operation: operation.rawValue,
            kind: kind.rawValue,
            sourceFs: sourceFs,
            destinationFs: destinationFs,
            sourceDisplay: sourceDisplay,
            destinationDisplay: destinationDisplay,
            excludePatterns: excludePatterns,
            extraExcludes: extraExcludes,
            bypassGlobalIgnores: bypassGlobalIgnores,
            createdAt: createdAt,
            state: state.rawValue,
            attempt: attempt,
            maxRetries: maxRetries,
            errorMessage: errorMessage,
            startedAt: startedAt,
            finishedAt: finishedAt,
            bytes: stats.bytes,
            totalBytes: stats.totalBytes,
            transfers: stats.transfers,
            totalTransfers: stats.totalTransfers,
            expectedBytes: expectedBytes,
            expectedFiles: expectedFiles,
            autoPausedVolume: autoPausedVolume
        )
    }

    convenience init(snapshot: TransferJobSnapshot) {
        self.init(
            operation: RcloneOperation(rawValue: snapshot.operation) ?? .copy,
            kind: TransferKind(rawValue: snapshot.kind) ?? .directory,
            sourceFs: snapshot.sourceFs,
            destinationFs: snapshot.destinationFs,
            sourceDisplay: snapshot.sourceDisplay,
            destinationDisplay: snapshot.destinationDisplay,
            excludePatterns: snapshot.excludePatterns,
            extraExcludes: snapshot.extraExcludes,
            bypassGlobalIgnores: snapshot.bypassGlobalIgnores,
            maxRetries: snapshot.maxRetries,
            id: snapshot.id,
            createdAt: snapshot.createdAt
        )

        attempt = snapshot.attempt
        errorMessage = snapshot.errorMessage
        startedAt = snapshot.startedAt
        finishedAt = snapshot.finishedAt
        expectedBytes = snapshot.expectedBytes
        expectedFiles = snapshot.expectedFiles
        autoPausedVolume = snapshot.autoPausedVolume

        var restoredStats = TransferStats.empty
        restoredStats.bytes = snapshot.bytes
        restoredStats.totalBytes = snapshot.totalBytes
        restoredStats.transfers = snapshot.transfers
        restoredStats.totalTransfers = snapshot.totalTransfers
        stats = restoredStats

        let restoredState = TransferState(rawValue: snapshot.state) ?? .failed
        if restoredState.isTerminal || restoredState == .paused {
            state = restoredState
        } else {
            state = .failed
            errorMessage = "Interrupted — PowerToys quit while this transfer was active."
        }
    }
}

// MARK: - Settings

struct RcloneSettings: Sendable, Equatable {
    var binaryPath: String
    var ignorePatterns: [String]
    var transfers: Int
    var checkers: Int
    var bandwidthLimit: String
    var maxRetries: Int
    var retryBackoffSeconds: Double
    var lowLevelRetries: Int
    var maxConcurrentJobs: Int
    var defaultOperation: RcloneOperation

    var retryPolicy: RetryPolicy {
        RetryPolicy(maxRetries: maxRetries, backoffSeconds: retryBackoffSeconds, backoffMultiplier: 2)
    }
}

// MARK: - Formatting Helpers

enum RcloneFormat {
    static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(value)
        var unit = 0
        while size >= 1024 && unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        if unit == 0 { return "\(value) B" }
        return String(format: "%.1f %@", size, units[unit])
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "—" }
        return bytes(Int64(bytesPerSecond)) + "/s"
    }

    static func eta(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %dm", h, m) }
        if m > 0 { return String(format: "%dm %ds", m, s) }
        return "\(s)s"
    }

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        return eta(seconds)
    }
}
