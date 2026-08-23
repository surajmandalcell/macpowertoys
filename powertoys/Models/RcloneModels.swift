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

    var websiteName: String? {
        switch type {
        case "drive": "Google Drive"
        case "box": "Box"
        default: nil
        }
    }

    func websiteFolderURL(id: String?) -> URL? {
        switch type {
        case "drive":
            guard let id, !id.isEmpty else {
                return URL(string: "https://drive.google.com/drive/my-drive")
            }
            return URL(string: "https://drive.google.com/drive/folders/")?.appendingPathComponent(id)
        case "box":
            let folderID = id.flatMap { $0.isEmpty ? nil : $0 } ?? "0"
            return URL(string: "https://app.box.com/folder/")?.appendingPathComponent(folderID)
        default:
            return nil
        }
    }
}

// MARK: - Per-file Progress

enum TransferOrder: String, Codable, CaseIterable, Sendable {
    case `default`
    case largestFirst
    case smallestFirst

    var displayName: String {
        switch self {
        case .default: return "Default (as listed)"
        case .largestFirst: return "Largest files first"
        case .smallestFirst: return "Smallest files first"
        }
    }

    var orderByValue: String? {
        switch self {
        case .default: return nil
        case .largestFirst: return "size,descending"
        case .smallestFirst: return "size,ascending"
        }
    }
}

enum TransferPriority: Int, Codable, CaseIterable, Sendable {
    case background = 1
    case low = 2
    case normal = 3
    case high = 4
    case urgent = 5

    var displayName: String {
        switch self {
        case .background: return "Background"
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var icon: String {
        switch self {
        case .background: return "1.circle"
        case .low: return "2.circle"
        case .normal: return "3.circle"
        case .high: return "4.circle"
        case .urgent: return "5.circle.fill"
        }
    }
}

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

    var completedBytes: Int64 {
        max(0, bytes - transferring.reduce(0) { $0 + $1.bytes })
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

enum TransferFileStatus: String, Sendable, Equatable {
    case uploaded
    case pending

    private static let modificationTolerance: TimeInterval = 2

    static func resolve(source: RemoteEntry, destination: RemoteEntry?) -> TransferFileStatus {
        guard let destination,
              source.isDir == destination.isDir,
              source.isDir || source.size == destination.size else { return .pending }
        if let sourceDate = source.modTime, let destinationDate = destination.modTime,
           abs(sourceDate.timeIntervalSince(destinationDate)) > modificationTolerance {
            return .pending
        }
        return .uploaded
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
    var sourceVolumeFingerprint: String?
    var destinationVolumeFingerprint: String?
    var autoResumeOnLaunch = false
    var resumeBaselineBytes: Int64 = 0
    var resumeBaselineFiles: Int = 0
    var attemptPlannedBytes: Int64?
    var attemptPlannedFiles: Int?
    var networkBaselineBytes: Int64 = 0
    var continuousSync = false
    var isSizing = false
    var isRecalculating = false
    var recalculationError: String?
    var transferOrder: TransferOrder = .default
    var priority: TransferPriority = .normal
    var isExpanded = false
    var updateOlderOnly = false
    var ignoreExisting = false
    var compareChecksums = false
    var transfersOverride = 0
    var checkersOverride = 0
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

    var effectivePriority: TransferPriority {
        kind == .file ? priority : .normal
    }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var effectiveTotalBytes: Int64 {
        expectedBytes ?? (resumeBaselineBytes + (attemptPlannedBytes ?? stats.totalBytes))
    }

    var effectiveTotalFiles: Int {
        expectedFiles ?? (resumeBaselineFiles + (attemptPlannedFiles ?? stats.totalTransfers))
    }

    var displayBytes: Int64 {
        guard stats.totalBytes > 0 else {
            return min(effectiveTotalBytes, resumeBaselineBytes)
        }
        let plan = attemptPlannedBytes ?? stats.totalBytes
        let remaining = max(0, stats.totalBytes - stats.bytes)
        let completed = max(0, plan - min(plan, remaining))
        return min(effectiveTotalBytes == 0 ? Int64.max : effectiveTotalBytes, resumeBaselineBytes + completed)
    }

    var displayFiles: Int {
        min(effectiveTotalFiles, resumeBaselineFiles + completedAttemptFiles)
    }

    private var completedAttemptFiles: Int {
        let plan = attemptPlannedFiles ?? stats.totalTransfers
        guard stats.totalTransfers > 0 else { return min(plan, stats.transfers) }
        let remaining = max(0, stats.totalTransfers - stats.transfers)
        return max(min(plan, stats.transfers), plan - min(plan, remaining))
    }

    var networkBytes: Int64 {
        networkBaselineBytes + stats.bytes
    }

    var progressFraction: Double {
        let total = effectiveTotalBytes
        guard total > 0 else { return 0 }
        return min(1.0, Double(displayBytes) / Double(total))
    }

    func captureAttemptPlan(force: Bool = false) {
        guard attemptPlannedBytes == nil, attemptPlannedFiles == nil else { return }
        guard force || stats.bytes > 0 || stats.transfers > 0 || !stats.transferring.isEmpty else { return }

        attemptPlannedBytes = stats.totalBytes
        attemptPlannedFiles = stats.totalTransfers
        expectedBytes = resumeBaselineBytes + stats.totalBytes
        expectedFiles = resumeBaselineFiles + stats.totalTransfers
        isSizing = false
    }

    func commitAttemptProgress() {
        captureAttemptPlan(force: true)
        let inFlightBytes = stats.transferring.reduce(0) { $0 + $1.bytes }
        let plan = attemptPlannedBytes ?? stats.totalBytes
        let remaining = max(0, stats.totalBytes - stats.bytes) + inFlightBytes
        let committed = max(0, plan - min(plan, remaining))

        resumeBaselineBytes += committed
        resumeBaselineFiles += completedAttemptFiles
        networkBaselineBytes += stats.bytes
        attemptPlannedBytes = nil
        attemptPlannedFiles = nil
        stats = .empty
    }

    func prepareForNewRun() {
        state = .queued
        attempt = 0
        errorMessage = nil
        stats = .empty
        rcJobId = nil
        startedAt = nil
        finishedAt = nil
        nextRetryAt = nil
        expectedBytes = nil
        expectedFiles = nil
        resumeBaselineBytes = 0
        resumeBaselineFiles = 0
        attemptPlannedBytes = nil
        attemptPlannedFiles = nil
        networkBaselineBytes = 0
        isSizing = false
    }

    func refreshDisplayEta() {
        let remaining = max(0, effectiveTotalBytes - displayBytes)
        let raw = stats.speed > 0 ? Double(remaining) / stats.speed : stats.eta
        let now = Date()
        if raw == nil || displayEta == nil || now.timeIntervalSince(lastEtaRefresh) >= 3 {
            displayEta = raw
            lastEtaRefresh = now
        }
    }

    @discardableResult
    func applyRecalculatedPlan(
        remainingBytes: Int64,
        remainingFiles: Int,
        baselineRemainingBytes: Int64,
        baselineRemainingFiles: Int
    ) -> (bytes: Int64, files: Int) {
        let addedBytes = max(0, remainingBytes - baselineRemainingBytes)
        let addedFiles = max(0, remainingFiles - baselineRemainingFiles)

        if addedBytes > 0 {
            expectedBytes = effectiveTotalBytes + addedBytes
        }
        if addedFiles > 0 {
            expectedFiles = effectiveTotalFiles + addedFiles
        }
        return (addedBytes, addedFiles)
    }
}

// MARK: - Volume Identity (external drive fingerprinting)

enum VolumeIdentity {
    static func mountPoint(forPath path: String) -> String? {
        guard path.hasPrefix("/Volumes/") else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }
        return "/" + components[0] + "/" + components[1]
    }

    static func fingerprint(forMountPoint mountPoint: String) -> String? {
        let url = URL(fileURLWithPath: mountPoint)
        guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeTotalCapacityKey, .volumeNameKey]) else {
            return nil
        }
        if let uuid = values.volumeUUIDString, !uuid.isEmpty {
            return "uuid:" + uuid
        }
        let name = values.volumeName ?? (mountPoint as NSString).lastPathComponent
        let capacity = values.volumeTotalCapacity ?? 0
        return "vol:\(name):\(capacity)"
    }

    static func fingerprint(forPath path: String) -> String? {
        mountPoint(forPath: path).flatMap { fingerprint(forMountPoint: $0) }
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
    let inFlightBytes: Int64?
    let totalBytes: Int64
    let transfers: Int
    let totalTransfers: Int
    let expectedBytes: Int64?
    let expectedFiles: Int?
    let autoPausedVolume: String?
    let sourceVolumeFingerprint: String?
    let destinationVolumeFingerprint: String?
    let autoResumeOnLaunch: Bool?
    let resumeBaselineBytes: Int64?
    let resumeBaselineFiles: Int?
    let attemptPlannedBytes: Int64?
    let attemptPlannedFiles: Int?
    let networkBaselineBytes: Int64?
    let continuousSync: Bool?
    let transferOrder: String?
    let priority: Int?
    let isExpanded: Bool?
    let updateOlderOnly: Bool?
    let ignoreExisting: Bool?
    let compareChecksums: Bool?
    let transfersOverride: Int?
    let checkersOverride: Int?
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
            inFlightBytes: stats.transferring.reduce(0) { $0 + $1.bytes },
            totalBytes: stats.totalBytes,
            transfers: stats.transfers,
            totalTransfers: stats.totalTransfers,
            expectedBytes: expectedBytes,
            expectedFiles: expectedFiles,
            autoPausedVolume: autoPausedVolume,
            sourceVolumeFingerprint: sourceVolumeFingerprint,
            destinationVolumeFingerprint: destinationVolumeFingerprint,
            autoResumeOnLaunch: autoResumeOnLaunch,
            resumeBaselineBytes: resumeBaselineBytes,
            resumeBaselineFiles: resumeBaselineFiles,
            attemptPlannedBytes: attemptPlannedBytes,
            attemptPlannedFiles: attemptPlannedFiles,
            networkBaselineBytes: networkBaselineBytes,
            continuousSync: continuousSync ? true : nil,
            transferOrder: transferOrder == .default ? nil : transferOrder.rawValue,
            priority: kind == .file && priority != .normal ? priority.rawValue : nil,
            isExpanded: isExpanded ? true : nil,
            updateOlderOnly: updateOlderOnly ? true : nil,
            ignoreExisting: ignoreExisting ? true : nil,
            compareChecksums: compareChecksums ? true : nil,
            transfersOverride: transfersOverride > 0 ? transfersOverride : nil,
            checkersOverride: checkersOverride > 0 ? checkersOverride : nil
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
        sourceVolumeFingerprint = snapshot.sourceVolumeFingerprint
        destinationVolumeFingerprint = snapshot.destinationVolumeFingerprint
        autoResumeOnLaunch = snapshot.autoResumeOnLaunch ?? false
        resumeBaselineBytes = snapshot.resumeBaselineBytes ?? 0
        resumeBaselineFiles = snapshot.resumeBaselineFiles ?? 0
        attemptPlannedBytes = snapshot.attemptPlannedBytes
            ?? max(0, (snapshot.expectedBytes ?? snapshot.totalBytes) - resumeBaselineBytes)
        attemptPlannedFiles = snapshot.attemptPlannedFiles
            ?? max(0, (snapshot.expectedFiles ?? snapshot.totalTransfers) - resumeBaselineFiles)
        networkBaselineBytes = snapshot.networkBaselineBytes ?? 0
        continuousSync = snapshot.continuousSync ?? false
        transferOrder = snapshot.transferOrder.flatMap(TransferOrder.init(rawValue:)) ?? .default
        priority = kind == .file
            ? snapshot.priority.flatMap(TransferPriority.init(rawValue:)) ?? .normal
            : .normal
        isExpanded = snapshot.isExpanded ?? false
        updateOlderOnly = snapshot.updateOlderOnly ?? false
        ignoreExisting = snapshot.ignoreExisting ?? false
        compareChecksums = snapshot.compareChecksums ?? false
        transfersOverride = snapshot.transfersOverride ?? 0
        checkersOverride = snapshot.checkersOverride ?? 0

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
            state = .paused
            autoResumeOnLaunch = true
            let inFlight = snapshot.inFlightBytes ?? 0
            let plan = attemptPlannedBytes ?? snapshot.totalBytes
            let remaining = max(0, snapshot.totalBytes - snapshot.bytes) + inFlight
            resumeBaselineBytes += max(0, plan - min(plan, remaining))
            resumeBaselineFiles += completedAttemptFiles
            networkBaselineBytes += snapshot.bytes
            attemptPlannedBytes = nil
            attemptPlannedFiles = nil
            stats = .empty
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

// MARK: - Connector Authentication

enum RcloneAuthenticationMode: String, Identifiable, Sendable {
    case browser
    case serviceAccount
    case boxApp
    case accessToken
    case environment
    case publicAccess
    case customOAuth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browser: return "Browser"
        case .serviceAccount: return "Service account"
        case .boxApp: return "Box app"
        case .accessToken: return "Access token"
        case .environment: return "Environment"
        case .publicAccess: return "Public"
        case .customOAuth: return "Custom OAuth"
        }
    }

    var detail: String {
        switch self {
        case .browser: return "Sign in on the provider's website. No credentials are needed here."
        case .serviceAccount: return "Use service-account credentials instead of a personal sign-in."
        case .boxApp: return "Use credentials exported from a Box application."
        case .accessToken: return "Connect with an existing provider access token."
        case .environment: return "Use credentials already available to rclone on this Mac."
        case .publicAccess: return "Connect without credentials to public data."
        case .customOAuth: return "Use credentials from your own OAuth application."
        }
    }

    func optionNames(in provider: RcloneProvider) -> Set<String> {
        Set(provider.options.map(\.name).filter(matches))
    }

    func isConfigured(parameters: [String: String], provider: RcloneProvider) -> Bool {
        let names: Set<String>
        switch self {
        case .browser, .environment, .publicAccess:
            return true
        case .customOAuth:
            names = optionNames(in: provider).intersection(["client_id"])
        case .boxApp:
            names = optionNames(in: provider).intersection(["box_config_file", "config_credentials"])
        case .serviceAccount, .accessToken:
            names = optionNames(in: provider)
        }
        return names.contains { !(parameters[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var parameterOverrides: [String: String] {
        switch self {
        case .environment: return ["env_auth": "true"]
        case .publicAccess: return ["anonymous": "true"]
        default: return [:]
        }
    }

    private func matches(_ name: String) -> Bool {
        switch self {
        case .browser: return false
        case .serviceAccount: return name == "service_account_file" || name == "service_account_credentials"
        case .boxApp: return name == "box_config_file" || name == "config_credentials" || name == "box_sub_type"
        case .accessToken: return name == "access_token"
        case .environment: return name == "env_auth"
        case .publicAccess: return name == "anonymous"
        case .customOAuth: return ["client_id", "client_secret", "scope", "tenant"].contains(name)
        }
    }
}

extension RcloneProvider {
    var authenticationModes: [RcloneAuthenticationMode] {
        guard supportsBrowserAuthentication else { return [] }
        var modes: [RcloneAuthenticationMode] = [.browser]
        for mode in [
            RcloneAuthenticationMode.serviceAccount,
            .boxApp,
            .accessToken,
            .environment,
            .publicAccess
        ] where !mode.optionNames(in: self).isEmpty {
            modes.append(mode)
        }
        modes.append(.customOAuth)
        return modes
    }

    var authenticationOptionNames: Set<String> {
        authenticationModes.reduce(into: Set<String>()) { names, mode in
            names.formUnion(mode.optionNames(in: self))
        }
    }

    private var supportsBrowserAuthentication: Bool {
        let credentialOptions = options.filter { $0.name == "client_id" || $0.name == "client_secret" }
        return credentialOptions.count == 2
            && credentialOptions.contains { $0.help.localizedCaseInsensitiveContains("oauth") }
    }
}

// MARK: - Formatting Helpers

enum RcloneFormat {
    static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(value)
        var unit = 0
        while size >= 1_000 && unit < units.count - 1 {
            size /= 1_000
            unit += 1
        }
        if unit == 0 { return "\(value) B" }
        return String(format: "%.1f %@", size, units[unit])
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "Not available" }
        return bytes(Int64(bytesPerSecond)) + "/s"
    }

    static func eta(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "Not available" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h >= 24 { return String(format: "%dd %dh", h / 24, h % 24) }
        if h > 0 { return String(format: "%dh %dm", h, m) }
        if m > 0 { return String(format: "%dm %ds", m, s) }
        return "\(s)s"
    }

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds > 0 else { return "Not available" }
        return eta(seconds)
    }
}
