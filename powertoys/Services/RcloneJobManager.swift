//
//  RcloneJobManager.swift
//  powertoys
//

import Foundation
import SwiftData
import CryptoKit
import AppKit

// MARK: - Settings Keys (single source of truth)

enum RcloneDefaults {
    static let binaryPathKey = "rclone.binaryPath"
    static let ignorePatternsKey = "rclone.ignorePatterns"
    static let transfersKey = "rclone.transfers"
    static let checkersKey = "rclone.checkers"
    static let bandwidthLimitKey = "rclone.bandwidthLimit"
    static let maxRetriesKey = "rclone.maxRetries"
    static let retryBackoffKey = "rclone.retryBackoff"
    static let lowLevelRetriesKey = "rclone.lowLevelRetries"
    static let maxConcurrentJobsKey = "rclone.maxConcurrentJobs"
    static let defaultOperationKey = "rclone.defaultOperation"

    static let binaryPath = ""
    static let ignorePatterns = """
.DS_Store
._*
.fseventsd/**
.Spotlight-V100/**
.Trashes/**
.TemporaryItems/**
.DocumentRevisions-V100/**
System Volume Information/**
$RECYCLE.BIN/**
Thumbs.db
desktop.ini
*.tmp
*.partial
node_modules/**
.git/**
"""
    static let transfers = 4
    static let checkers = 8
    static let bandwidthLimit = ""
    static let maxRetries = 3
    static let retryBackoff = 5.0
    static let lowLevelRetries = 10
    static let maxConcurrentJobs = 2
    static let defaultOperation = "copy"

    static func parsePatterns(_ raw: String) -> [String] {
        raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func remoteTransfersKey(_ remote: String) -> String {
        "rclone.remote.\(remote).transfers"
    }

    static func remoteCheckersKey(_ remote: String) -> String {
        "rclone.remote.\(remote).checkers"
    }
}

// MARK: - Remote Auth State

enum RemoteAuthState: Equatable {
    case idle
    case waiting(name: String)
    case succeeded(name: String)
    case failed(String)
}

// MARK: - Job Manager

@Observable
final class RcloneJobManager {
    static let shared = RcloneJobManager()

    private(set) var remotes: [RcloneRemote] = []
    var jobs: [TransferJob] = []
    var filter: JobFilter = .all
    var errorBanner: String?
    var isPresentingNewTransfer = false
    var authState: RemoteAuthState = .idle
    var modelContext: ModelContext?
    private var authJobId: Int?
    private var authGeneration = UUID()
    private var authTask: Task<Void, Never>?
    private var authCleanupTask: Task<Void, Never>?
    private var authNeedsDaemonRestart = false
    private var reconnectProcess: Process?
    private var pendingAuthCleanupName: String?

    let daemon = RcloneDaemon()
    private var client: RcloneRCClient?
    private var pollTask: Task<Void, Never>?
    private var started = false
    private var lastAppliedBandwidth: String?
    private var loadedPersistedJobs = false
    private var persistJobsTask: Task<Void, Never>?
    private var volumeObservers: [NSObjectProtocol] = []

    private let pollInterval: Duration = .milliseconds(700)

    // MARK: Settings

    var settings: RcloneSettings {
        let defaults = UserDefaults.standard
        func str(_ key: String, _ fallback: String) -> String {
            defaults.string(forKey: key) ?? fallback
        }
        func int(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) != nil ? defaults.integer(forKey: key) : fallback
        }
        func dbl(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : fallback
        }
        return RcloneSettings(
            binaryPath: str(RcloneDefaults.binaryPathKey, RcloneDefaults.binaryPath),
            ignorePatterns: RcloneDefaults.parsePatterns(str(RcloneDefaults.ignorePatternsKey, RcloneDefaults.ignorePatterns)),
            transfers: max(1, int(RcloneDefaults.transfersKey, RcloneDefaults.transfers)),
            checkers: max(1, int(RcloneDefaults.checkersKey, RcloneDefaults.checkers)),
            bandwidthLimit: str(RcloneDefaults.bandwidthLimitKey, RcloneDefaults.bandwidthLimit),
            maxRetries: max(0, int(RcloneDefaults.maxRetriesKey, RcloneDefaults.maxRetries)),
            retryBackoffSeconds: max(0, dbl(RcloneDefaults.retryBackoffKey, RcloneDefaults.retryBackoff)),
            lowLevelRetries: max(1, int(RcloneDefaults.lowLevelRetriesKey, RcloneDefaults.lowLevelRetries)),
            maxConcurrentJobs: max(1, int(RcloneDefaults.maxConcurrentJobsKey, RcloneDefaults.maxConcurrentJobs)),
            defaultOperation: RcloneOperation(rawValue: str(RcloneDefaults.defaultOperationKey, RcloneDefaults.defaultOperation)) ?? .copy
        )
    }

    // MARK: Derived state

    var isDaemonRunning: Bool { daemon.isRunning }

    var daemonStatusText: String {
        switch daemon.state {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .running(_, let version): return "Connected · \(version)"
        case .failed(let message): return message
        }
    }

    var daemonIsHealthy: Bool {
        if case .running = daemon.state { return true }
        return false
    }

    var daemonPort: Int? {
        if case .running(let port, _) = daemon.state { return port }
        return nil
    }

    var activeJobs: [TransferJob] { jobs.filter { $0.state.isActive } }

    var filteredJobs: [TransferJob] {
        jobs.filter { filter.matches($0.state) }
    }

    var aggregateSpeed: Double {
        jobs.filter { $0.state == .running }.reduce(0) { $0 + $1.stats.speed }
    }

    func count(for filter: JobFilter) -> Int {
        jobs.filter { filter.matches($0.state) }.count
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        errorBanner = nil
        loadPersistedJobs()
        startVolumeWatch()
        resumeJobsForMountedVolumes()
        autoResumeInterruptedJobs()

        do {
            let client = try await daemon.ensureRunning(binaryPath: settings.binaryPath)
            guard started else {
                daemon.stop()
                return
            }
            self.client = client
            lastAppliedBandwidth = nil
            pruneRecords()
            Task.detached(priority: .background) { Self.sweepTemporaryCaches() }
            await refreshRemotes()
            guard started else {
                daemon.stop()
                self.client = nil
                return
            }
            startPolling()
        } catch {
            started = false
            errorBanner = (error as? LocalizedError)?.errorDescription ?? "Could not start rclone."
            LogManager.shared.error("rclone start failed: \(error)", source: "RcloneJobManager")
        }
    }

    func restartDaemon() async {
        pollTask?.cancel()
        pollTask = nil
        daemon.stop()
        client = nil
        started = false
        await start()
    }

    func shutdown() async {
        pollTask?.cancel()
        pollTask = nil
        authTask?.cancel()
        authTask = nil
        reconnectProcess?.terminate()
        reconnectProcess = nil
        if case .waiting(let name) = authState {
            authGeneration = UUID()
            authState = .idle
            if let client {
                if let jobid = authJobId {
                    try? await client.stopJob(jobid: jobid)
                }
                try? await client.deleteRemoteConfig(name: name)
            }
            authJobId = nil
        }
        for job in jobs where job.state.isActive && !job.state.isTerminal {
            let jobid = job.rcJobId
            if job.state == .running {
                job.resumeBaselineBytes += job.stats.bytes
                job.resumeBaselineFiles += job.stats.transfers
                job.stats.bytes = 0
                job.stats.transfers = 0
            }
            if job.state != .paused {
                job.state = .paused
                job.autoResumeOnLaunch = true
            }
            job.rcJobId = nil
            job.nextRetryAt = nil
            if let jobid, let client {
                try? await client.stopJob(jobid: jobid)
            }
        }
        persistJobsTask?.cancel()
        persistJobsTask = nil
        persistJobsNow()
        daemon.stop()
        client = nil
        started = false
    }

    func refreshRemotes() async {
        guard let client else { return }
        do {
            let names = try await client.listRemotes()
            let types = (try? await client.remoteTypes()) ?? [:]
            remotes = names
                .map { raw -> RcloneRemote in
                    let clean = raw.hasSuffix(":") ? String(raw.dropLast()) : raw
                    return RcloneRemote(name: clean, type: types[clean] ?? "")
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            LogManager.shared.warning("Failed to list remotes: \(error)", source: "RcloneJobManager")
        }
    }

    // MARK: Browsing

    func listDirectory(remote: RcloneRemote, path: String) async throws -> [RemoteEntry] {
        try await listDirectory(fs: remote.pathPrefix, path: path)
    }

    func listDirectory(fs: String, path: String, recurse: Bool = false) async throws -> [RemoteEntry] {
        guard let client else { throw RcloneRCError.notReachable }
        return try await client.listDirectory(fs: fs, remote: path, recurse: recurse)
    }

    func downloadForPreview(remote: RcloneRemote, entry: RemoteEntry) async throws -> URL {
        guard let client else { throw RcloneRCError.notReachable }

        let cacheKey = SHA256.hash(data: Data("\(remote.name):\(entry.path)".utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rsync-preview", isDirectory: true)
            .appendingPathComponent(cacheKey, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(entry.name)

        if let cachedSize = try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64,
           cachedSize == entry.size {
            return destination
        }
        try? FileManager.default.removeItem(at: destination)

        let group = "preview/\(UUID().uuidString)"
        let jobid = try await client.startCopyFileJob(
            srcFs: remote.pathPrefix,
            srcRemote: entry.path,
            dstFs: directory.path,
            dstRemote: entry.name,
            group: group
        )

        defer { Task { await client.deleteStats(group: group) } }

        let timeout = min(900, max(30, Double(entry.size) / 500_000))
        let deadline = Date().addingTimeInterval(timeout)
        var consecutiveFailures = 0
        while Date() < deadline {
            if Task.isCancelled {
                try? await client.stopJob(jobid: jobid)
                throw CancellationError()
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard let status = try? await client.jobStatus(jobid: jobid) else {
                consecutiveFailures += 1
                if consecutiveFailures >= 20 {
                    try? await client.stopJob(jobid: jobid)
                    throw RcloneRCError.notReachable
                }
                continue
            }
            consecutiveFailures = 0
            if status.finished {
                if status.success { return destination }
                throw RcloneRCError.http(status: 0, message: status.error.isEmpty ? "Download failed." : status.error)
            }
        }
        try? await client.stopJob(jobid: jobid)
        throw RcloneRCError.http(status: 0, message: "Preview download timed out.")
    }

    private nonisolated static func sweepTemporaryCaches() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-3 * 86400)
        for name in ["rsync-preview", "rsync-drag"] {
            let root = fm.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for child in children {
                let modified = (try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if modified < cutoff {
                    try? fm.removeItem(at: child)
                }
            }
        }
    }

    func createDroppedTransfers(urls: [URL], remote: RcloneRemote, directoryPath: String) {
        let base = directoryPath.isEmpty ? "" : directoryPath + "/"
        for rawURL in urls where rawURL.isFileURL {
            let url = rawURL.resolvingSymlinksInPath()
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isDirectory = values?.isDirectory ?? false
            let isPackage = values?.isPackage ?? false
            createTransfer(
                operation: .copy,
                kind: isDirectory ? .directory : .file,
                sourceFs: url.path,
                destinationFs: remote.pathPrefix + base + name,
                sourceDisplay: "\(name) (local)",
                destinationDisplay: "\(remote.name):\(base)\(name)",
                extraExcludes: [],
                bypassGlobalIgnores: isPackage
            )
        }
    }

    // MARK: Remote management

    var isAuthInProgress: Bool {
        if case .waiting = authState { return true }
        return false
    }

    static func isValidRemoteName(_ name: String) -> Bool {
        guard !name.isEmpty, let first = name.first, first.isLetter || first.isNumber else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    func beginAddGoogleDrive(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard Self.isValidRemoteName(name) else {
            authState = .failed("Names can use letters, numbers, dots, dashes, and underscores.")
            return
        }
        guard !remotes.contains(where: { $0.name == name }) else {
            authState = .failed("A remote named “\(name)” already exists.")
            return
        }
        if authNeedsDaemonRestart && !activeJobs.isEmpty {
            authState = .failed("A previous attempt is still winding down. Finish or cancel running transfers, then retry.")
            return
        }

        let generation = UUID()
        authGeneration = generation
        authState = .waiting(name: name)
        LogManager.shared.info("Starting Google Drive authorization for remote '\(name)'", source: "RcloneJobManager")

        authTask?.cancel()
        authTask = Task { [weak self] in
            await self?.runAuthFlow(name: name, generation: generation)
        }
    }

    func beginReconnect(_ remote: RcloneRemote) {
        guard !isAuthInProgress else { return }
        let generation = UUID()
        authGeneration = generation
        authState = .waiting(name: remote.name)
        LogManager.shared.info("Reconnecting remote '\(remote.name)'", source: "RcloneJobManager")

        let preferredBinary = settings.binaryPath
        authTask?.cancel()
        authTask = Task { [weak self] in
            await self?.runReconnectFlow(remoteName: remote.name, preferredBinary: preferredBinary, generation: generation)
        }
    }

    private func runReconnectFlow(remoteName: String, preferredBinary: String, generation: UUID) async {
        let binary = await Task.detached(priority: .userInitiated) {
            RcloneDaemon.resolveBinaryPath(preferred: preferredBinary)
        }.value

        guard authGeneration == generation else { return }
        guard let binary else {
            finishAuth(generation: generation, state: .failed("rclone binary not found."))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["config", "reconnect", "\(remoteName):", "--auto-confirm"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        reconnectProcess = process

        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }

        reconnectProcess = nil
        guard authGeneration == generation else { return }

        if status == 0 {
            await refreshRemotes()
            finishAuth(generation: generation, state: .succeeded(name: remoteName))
            LogManager.shared.info("Remote '\(remoteName)' reconnected", source: "RcloneJobManager")
        } else {
            finishAuth(generation: generation, state: .failed("Reconnect was cancelled or failed. Try again."))
        }
    }

    private func runAuthFlow(name: String, generation: UUID) async {
        await authCleanupTask?.value
        guard authGeneration == generation else { return }

        if authNeedsDaemonRestart {
            authNeedsDaemonRestart = false
            let stale = pendingAuthCleanupName
            pendingAuthCleanupName = nil
            await restartDaemon()
            if let stale, let client {
                try? await client.deleteRemoteConfig(name: stale)
            }
            guard authGeneration == generation else { return }
        }

        guard let client else {
            finishAuth(generation: generation, state: .failed("RSync engine is not running."))
            return
        }

        do {
            let jobid = try await client.startConfigCreate(name: name, type: "drive", parameters: ["scope": "drive"])
            guard authGeneration == generation, !Task.isCancelled else {
                try? await client.stopJob(jobid: jobid)
                try? await client.deleteRemoteConfig(name: name)
                return
            }
            authJobId = jobid

            let deadline = Date().addingTimeInterval(300)
            while authGeneration == generation, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard authGeneration == generation, !Task.isCancelled else { return }

                if Date() > deadline {
                    await abandonAuthAttempt(name: name, generation: generation, message: "Authorization timed out. Try again.")
                    return
                }

                guard let status = try? await client.jobStatus(jobid: jobid), status.finished else { continue }
                guard authGeneration == generation else { return }
                authJobId = nil

                if status.success {
                    await refreshRemotes()
                    finishAuth(generation: generation, state: .succeeded(name: name))
                    LogManager.shared.info("Google Drive remote '\(name)' connected", source: "RcloneJobManager")
                } else {
                    try? await client.deleteRemoteConfig(name: name)
                    await refreshRemotes()
                    finishAuth(generation: generation, state: .failed(status.error.isEmpty ? "Google Drive authorization failed." : status.error))
                }
                return
            }
        } catch {
            authJobId = nil
            finishAuth(generation: generation, state: .failed((error as? LocalizedError)?.errorDescription ?? "Could not start Google Drive sign-in."))
        }
    }

    private func finishAuth(generation: UUID, state: RemoteAuthState) {
        guard authGeneration == generation else { return }
        authState = state
        if case .failed(let message) = state {
            LogManager.shared.warning("Google Drive authorization failed: \(message)", source: "RcloneJobManager")
        }
    }

    private func abandonAuthAttempt(name: String, generation: UUID, message: String) async {
        if let jobid = authJobId, let client {
            try? await client.stopJob(jobid: jobid)
        }
        authJobId = nil
        if let client {
            try? await client.deleteRemoteConfig(name: name)
        }
        if activeJobs.isEmpty {
            await restartDaemon()
        } else {
            authNeedsDaemonRestart = true
            pendingAuthCleanupName = name
        }
        await refreshRemotes()
        finishAuth(generation: generation, state: .failed(message))
    }

    func cancelAuth() {
        reconnectProcess?.terminate()
        reconnectProcess = nil
        guard case .waiting(let name) = authState else {
            authGeneration = UUID()
            authState = .idle
            return
        }
        let jobid = authJobId
        authJobId = nil
        authGeneration = UUID()
        authTask?.cancel()
        authTask = nil
        authState = .idle

        authCleanupTask = Task { [weak self] in
            guard let self else { return }
            if let client = self.client {
                if let jobid {
                    try? await client.stopJob(jobid: jobid)
                }
                try? await client.deleteRemoteConfig(name: name)
                await self.refreshRemotes()
            }
            if self.activeJobs.isEmpty {
                await self.restartDaemon()
            } else {
                self.authNeedsDaemonRestart = true
                self.pendingAuthCleanupName = name
            }
            self.authCleanupTask = nil
        }
    }

    func acknowledgeAuthResult() {
        if case .waiting = authState {
            cancelAuth()
            return
        }
        authGeneration = UUID()
        authState = .idle
    }

    func removeRemote(_ remote: RcloneRemote) {
        let prefix = remote.pathPrefix
        let inUse = jobs.contains { !$0.state.isTerminal && ($0.sourceFs.hasPrefix(prefix) || $0.destinationFs.hasPrefix(prefix)) }
        guard !inUse else {
            errorBanner = "“\(remote.name)” is used by an active transfer. Cancel it first."
            return
        }

        Task {
            guard let client else { return }
            do {
                try await client.deleteRemoteConfig(name: remote.name)
                await refreshRemotes()
                LogManager.shared.info("Removed remote '\(remote.name)'", source: "RcloneJobManager")
            } catch {
                errorBanner = "Could not remove remote “\(remote.name)”."
            }
        }
    }

    // MARK: Job creation

    @discardableResult
    func createTransfer(
        operation: RcloneOperation,
        kind: TransferKind = .directory,
        sourceFs: String,
        destinationFs: String,
        sourceDisplay: String,
        destinationDisplay: String,
        extraExcludes: [String],
        bypassGlobalIgnores: Bool = false
    ) -> TransferJob {
        let current = settings
        var excludes = bypassGlobalIgnores ? [] : current.ignorePatterns
        for pattern in extraExcludes where !excludes.contains(pattern) {
            excludes.append(pattern)
        }

        let job = TransferJob(
            operation: operation,
            kind: kind,
            sourceFs: sourceFs,
            destinationFs: destinationFs,
            sourceDisplay: sourceDisplay,
            destinationDisplay: destinationDisplay,
            excludePatterns: kind == .file ? [] : excludes,
            extraExcludes: extraExcludes,
            bypassGlobalIgnores: bypassGlobalIgnores,
            maxRetries: current.maxRetries
        )
        job.sourceVolumeFingerprint = VolumeIdentity.fingerprint(forPath: sourceFs)
        job.destinationVolumeFingerprint = VolumeIdentity.fingerprint(forPath: destinationFs)
        jobs.insert(job, at: 0)
        persistJobsSoon()
        LogManager.shared.info("Queued \(operation.displayName): \(sourceDisplay) → \(destinationDisplay)", source: "RcloneJobManager")
        return job
    }

    func cancel(_ job: TransferJob) {
        guard job.canCancel else { return }
        let jobid = job.rcJobId
        job.state = .cancelled
        job.finishedAt = Date()
        job.nextRetryAt = nil
        insertRecord(for: job)
        persistJobsSoon()
        Task {
            if let jobid, let client {
                try? await client.stopJob(jobid: jobid)
                await client.deleteStats(group: job.statsGroup)
            }
        }
    }

    func pause(_ job: TransferJob) {
        guard job.canPause else { return }
        let jobid = job.rcJobId
        job.resumeBaselineBytes += job.stats.bytes
        job.resumeBaselineFiles += job.stats.transfers
        job.stats.bytes = 0
        job.stats.transfers = 0
        job.state = .paused
        job.rcJobId = nil
        job.nextRetryAt = nil
        persistJobsSoon()
        LogManager.shared.info("Paused: \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
        Task {
            if let jobid, let client {
                try? await client.stopJob(jobid: jobid)
                await client.deleteStats(group: job.statsGroup)
            }
        }
    }

    func resume(_ job: TransferJob) {
        guard job.canResume else { return }
        job.state = .queued
        job.errorMessage = nil
        job.nextRetryAt = nil
        persistJobsSoon()
        LogManager.shared.info("Resumed: \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
    }

    var isGloballyPaused = false

    func pauseAll() {
        isGloballyPaused = true
        for job in jobs where job.canPause {
            pause(job)
        }
    }

    func resumeAll() {
        isGloballyPaused = false
        for job in jobs where job.canResume {
            resume(job)
        }
    }

    // MARK: Volume watch (external drives)

    private func startVolumeWatch() {
        guard volumeObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        for name in [NSWorkspace.willUnmountNotification, NSWorkspace.didUnmountNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let path = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
                Task { @MainActor in
                    if let path {
                        RcloneJobManager.shared.handleVolumeUnmounted(path)
                    }
                }
            })
        }

        volumeObservers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { note in
            let path = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
            Task { @MainActor in
                if let path {
                    RcloneJobManager.shared.handleVolumeMounted(path)
                }
            }
        })
    }

    private func handleVolumeUnmounted(_ volumePath: String) {
        let volumeName = (volumePath as NSString).lastPathComponent
        for job in jobs where job.canPause && Self.jobUsesVolume(job, volumePath) {
            pause(job)
            job.autoPausedVolume = volumePath
            job.errorMessage = "Drive disconnected — will resume when “\(volumeName)” reconnects."
            LogManager.shared.warning("Auto-paused (drive disconnected): \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
        }
        persistJobsSoon()
    }

    private func handleVolumeMounted(_ volumePath: String) {
        for job in jobs where job.state == .paused && job.autoPausedVolume == volumePath {
            if let issue = Self.localEndpointIssue(for: job) {
                applyEndpointIssue(job, issue)
                continue
            }
            job.autoPausedVolume = nil
            job.errorMessage = nil
            resume(job)
            LogManager.shared.info("Auto-resumed (drive reconnected): \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
        }
    }

    private func autoResumeInterruptedJobs() {
        for job in jobs where job.state == .paused && job.autoResumeOnLaunch {
            job.autoResumeOnLaunch = false
            if let issue = Self.localEndpointIssue(for: job) {
                applyEndpointIssue(job, issue)
                continue
            }
            resume(job)
        }
        persistJobsSoon()
    }

    private func resumeJobsForMountedVolumes() {
        for job in jobs where job.state == .paused {
            guard let volume = job.autoPausedVolume else { continue }
            guard FileManager.default.fileExists(atPath: volume) else { continue }
            if let issue = Self.localEndpointIssue(for: job) {
                applyEndpointIssue(job, issue)
                continue
            }
            job.autoPausedVolume = nil
            job.errorMessage = nil
            resume(job)
        }
    }

    static func jobUsesVolume(_ job: TransferJob, _ volumePath: String) -> Bool {
        fsUsesVolume(job.sourceFs, volumePath) || fsUsesVolume(job.destinationFs, volumePath)
    }

    private static func fsUsesVolume(_ fs: String, _ volumePath: String) -> Bool {
        fs.hasPrefix("/") && (fs == volumePath || fs.hasPrefix(volumePath + "/"))
    }

    enum LocalEndpointIssue {
        case offline(volume: String)
        case wrongDrive(volume: String)
    }

    static func localEndpointIssue(for job: TransferJob) -> LocalEndpointIssue? {
        let endpoints = [
            (job.sourceFs, job.sourceVolumeFingerprint),
            (job.destinationFs, job.destinationVolumeFingerprint)
        ]
        for (fs, expected) in endpoints {
            guard let mountPoint = VolumeIdentity.mountPoint(forPath: fs) else { continue }
            guard FileManager.default.fileExists(atPath: mountPoint) else {
                return .offline(volume: mountPoint)
            }
            if let expected,
               let current = VolumeIdentity.fingerprint(forMountPoint: mountPoint),
               current != expected {
                return .wrongDrive(volume: mountPoint)
            }
        }
        return nil
    }

    private func applyEndpointIssue(_ job: TransferJob, _ issue: LocalEndpointIssue) {
        switch issue {
        case .offline(let volume):
            let name = (volume as NSString).lastPathComponent
            if job.canPause { pause(job) }
            job.autoPausedVolume = volume
            job.errorMessage = "Drive disconnected — will resume when “\(name)” reconnects."
            LogManager.shared.warning("Auto-paused (drive offline): \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
        case .wrongDrive(let volume):
            let name = (volume as NSString).lastPathComponent
            if job.canPause { pause(job) }
            job.autoPausedVolume = volume
            job.errorMessage = "A different drive is mounted at “\(name)” — reconnect the original drive to resume."
            LogManager.shared.warning("Auto-paused (wrong drive at \(volume)): \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
        }
        persistJobsSoon()
    }


    func retry(_ job: TransferJob) {
        guard job.canRetry else { return }
        if job.kind == .directory && !job.bypassGlobalIgnores {
            var excludes = settings.ignorePatterns
            for pattern in job.extraExcludes where !excludes.contains(pattern) {
                excludes.append(pattern)
            }
            job.excludePatterns = excludes
        }
        job.state = .queued
        job.attempt = 0
        job.errorMessage = nil
        job.stats = .empty
        job.rcJobId = nil
        job.startedAt = nil
        job.finishedAt = nil
        job.nextRetryAt = nil
        job.expectedBytes = nil
        job.expectedFiles = nil
        job.resumeBaselineBytes = 0
        job.resumeBaselineFiles = 0
        job.autoResumeOnLaunch = false
        persistJobsSoon()
    }

    func remove(_ job: TransferJob) {
        guard job.state.isTerminal else { return }
        jobs.removeAll { $0.id == job.id }
        persistJobsSoon()
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isTerminal }
        persistJobsSoon()
    }

    // MARK: Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.tick()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    private func tick() async {
        guard let client else { return }

        if authNeedsDaemonRestart && activeJobs.isEmpty && !isAuthInProgress {
            authNeedsDaemonRestart = false
            let stale = pendingAuthCleanupName
            pendingAuthCleanupName = nil
            Task { [weak self] in
                guard let self else { return }
                await self.restartDaemon()
                if let stale, let freshClient = self.client {
                    try? await freshClient.deleteRemoteConfig(name: stale)
                    await self.refreshRemotes()
                }
            }
            return
        }

        await applyBandwidthLimitIfNeeded(client: client)

        let running = jobs.filter { $0.state == .running }
        if !running.isEmpty {
            let probes = running.map { (id: $0.id, group: $0.statsGroup, jobid: $0.rcJobId) }
            var results: [UUID: (TransferStats?, JobStatusResult?)] = [:]

            await withTaskGroup(of: (UUID, TransferStats?, JobStatusResult?).self) { group in
                for probe in probes {
                    group.addTask {
                        async let statsTask = try? await client.stats(group: probe.group)
                        let stats = await statsTask
                        var status: JobStatusResult?
                        if let jobid = probe.jobid {
                            status = try? await client.jobStatus(jobid: jobid)
                        }
                        return (probe.id, stats, status)
                    }
                }
                for await result in group {
                    results[result.0] = (result.1, result.2)
                }
            }

            for job in running {
                guard job.state == .running else { continue }
                let (stats, status) = results[job.id] ?? (nil, nil)
                applyProbe(job, stats: stats, status: status, client: client)
            }
        }

        promoteQueuedJobs(client: client)
    }

    private func applyProbe(_ job: TransferJob, stats: TransferStats?, status: JobStatusResult?, client: RcloneRCClient) {
        if let stats {
            job.stats = stats
            job.refreshDisplayEta()
        }

        guard job.rcJobId != nil, let status, status.finished else { return }

        if status.success && job.stats.errors == 0 && !job.stats.fatalError {
            finish(job, success: true, error: nil, client: client)
        } else {
            let message = firstNonEmpty(status.error, job.stats.lastError, "Transfer failed with \(job.stats.errors) error(s).")
            handleFailure(job, message: message, client: client, permanent: Self.isPermanentJobError(message))
        }
    }

    private static func isPermanentJobError(_ message: String) -> Bool {
        let lower = message.lowercased()
        let markers = [
            "didn't find section in config file",
            "not found in config file",
            "directory not found",
            "couldn't find section",
            "unknown remote",
            "no such host"
        ]
        return markers.contains { lower.contains($0) }
    }

    private func applyBandwidthLimitIfNeeded(client: RcloneRCClient) async {
        let desired = settings.bandwidthLimit.trimmingCharacters(in: .whitespaces)
        guard desired != lastAppliedBandwidth else { return }
        lastAppliedBandwidth = desired
        do {
            try await client.setBandwidthLimit(desired.isEmpty ? "off" : desired)
        } catch {
            LogManager.shared.warning("Invalid bandwidth limit '\(desired)': \(error)", source: "RcloneJobManager")
        }
    }

    private func handleFailure(_ job: TransferJob, message: String, client: RcloneRCClient, permanent: Bool = false) {
        guard job.state == .running else { return }

        if let issue = Self.localEndpointIssue(for: job) {
            applyEndpointIssue(job, issue)
            return
        }

        let policy = settings.retryPolicy
        if !permanent && job.attempt < job.maxRetries {
            job.attempt += 1
            job.state = .retrying
            job.errorMessage = message
            job.rcJobId = nil
            job.nextRetryAt = Date().addingTimeInterval(policy.delay(forAttempt: job.attempt - 1))
            Task { await client.deleteStats(group: job.statsGroup) }
            LogManager.shared.warning("Transfer failed (attempt \(job.attempt)/\(job.maxRetries)), retrying: \(message)", source: "RcloneJobManager")
        } else {
            finish(job, success: false, error: message, client: client)
        }
    }

    private func finish(_ job: TransferJob, success: Bool, error: String?, client: RcloneRCClient) {
        guard job.state == .running else { return }
        job.state = success ? .completed : .failed
        job.errorMessage = error
        job.finishedAt = Date()
        job.nextRetryAt = nil
        if success {
            job.stats.bytes = job.stats.totalBytes
            LogManager.shared.info("Completed: \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
        } else {
            LogManager.shared.error("Failed: \(job.sourceDisplay) → \(job.destinationDisplay): \(error ?? "")", source: "RcloneJobManager")
        }
        insertRecord(for: job)
        persistJobsSoon()
        Task { await client.deleteStats(group: job.statsGroup) }
    }

    // MARK: Job persistence

    private func loadPersistedJobs() {
        guard !loadedPersistedJobs else { return }
        loadedPersistedJobs = true
        guard let data = try? Data(contentsOf: AppDataLocation.transfersURL),
              let snapshots = try? JSONDecoder().decode([TransferJobSnapshot].self, from: data) else { return }
        jobs = snapshots.map { TransferJob(snapshot: $0) }
    }

    func persistJobsSoon() {
        guard persistJobsTask == nil else { return }
        persistJobsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.persistJobsTask = nil
            self?.persistJobsNow()
        }
    }

    private func persistJobsNow() {
        let snapshots = jobs.map(\.snapshot)
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: AppDataLocation.transfersURL, options: .atomic)
    }

    // MARK: Activity records

    private func insertRecord(for job: TransferJob) {
        guard let modelContext else { return }
        modelContext.insert(TransferRecord(job: job))
        try? modelContext.save()
    }

    private func pruneRecords() {
        guard let modelContext else { return }
        let maxRecords = 500
        var descriptor = FetchDescriptor<TransferRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchOffset = maxRecords
        guard let stale = try? modelContext.fetch(descriptor), !stale.isEmpty else { return }
        for record in stale {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    private func promoteQueuedJobs(client: RcloneRCClient) {
        guard !isGloballyPaused else { return }
        let maxConcurrent = settings.maxConcurrentJobs
        var runningCount = jobs.filter { $0.state == .running }.count
        let now = Date()

        for job in jobs.reversed() {
            guard runningCount < maxConcurrent else { break }

            let readyRetry = job.state == .retrying && (job.nextRetryAt ?? now) <= now
            guard job.state == .queued || readyRetry else { continue }

            submit(job, client: client)
            runningCount += 1
        }
    }

    private func submit(_ job: TransferJob, client: RcloneRCClient) {
        if let issue = Self.localEndpointIssue(for: job) {
            applyEndpointIssue(job, issue)
            return
        }
        if job.sourceVolumeFingerprint == nil {
            job.sourceVolumeFingerprint = VolumeIdentity.fingerprint(forPath: job.sourceFs)
        }
        if job.destinationVolumeFingerprint == nil {
            job.destinationVolumeFingerprint = VolumeIdentity.fingerprint(forPath: job.destinationFs)
        }

        job.state = .running
        job.startedAt = job.startedAt ?? Date()
        job.errorMessage = nil
        job.nextRetryAt = nil

        let config = effectiveJobConfig(for: job)

        let endpoint = job.operation.rcEndpoint
        let excludes = job.excludePatterns
        let group = job.statsGroup
        let kind = job.kind
        let src = job.sourceFs
        let dst = job.destinationFs

        Task {
            do {
                let jobid: Int
                switch kind {
                case .directory:
                    jobid = try await client.startJob(
                        endpoint: endpoint,
                        srcFs: src,
                        dstFs: dst,
                        group: group,
                        excludePatterns: excludes,
                        config: config
                    )
                case .file:
                    let source = Self.fileEndpointComponents(src)
                    let destination = Self.fileEndpointComponents(dst)
                    jobid = try await client.startCopyFileJob(
                        srcFs: source.fs,
                        srcRemote: source.remote,
                        dstFs: destination.fs,
                        dstRemote: destination.remote,
                        group: group,
                        config: config
                    )
                }
                if job.state == .cancelled {
                    try? await client.stopJob(jobid: jobid)
                    await client.deleteStats(group: group)
                } else {
                    job.rcJobId = jobid
                    beginSizing(job, client: client)
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Could not start transfer."
                handleFailure(job, message: message, client: client, permanent: Self.isPermanentSubmitError(error))
            }
        }
    }

    private func beginSizing(_ job: TransferJob, client: RcloneRCClient) {
        guard job.kind == .directory, job.expectedBytes == nil, !job.isSizing else { return }
        job.isSizing = true

        Task { [weak self] in
            defer { job.isSizing = false }
            guard self != nil else { return }
            do {
                let jobid = try await client.startSizeJob(fs: job.sourceFs, excludePatterns: job.excludePatterns)
                let deadline = Date().addingTimeInterval(600)
                while Date() < deadline, !job.state.isTerminal {
                    try? await Task.sleep(for: .seconds(1))
                    guard let status = try? await client.jobStatus(jobid: jobid) else { continue }
                    if status.finished {
                        if status.success {
                            job.expectedBytes = status.outputBytes
                            job.expectedFiles = status.outputCount
                            if let bytes = status.outputBytes {
                                LogManager.shared.info("Sized \(job.sourceDisplay): \(RcloneFormat.bytes(bytes)) in \(status.outputCount ?? 0) files", source: "RcloneJobManager")
                            }
                        }
                        return
                    }
                }
                try? await client.stopJob(jobid: jobid)
            } catch {
                LogManager.shared.debug("Sizing failed for \(job.sourceDisplay): \(error)", source: "RcloneJobManager")
            }
        }
    }

    static func fileEndpointComponents(_ full: String) -> (fs: String, remote: String) {
        if !full.hasPrefix("/"), let colon = full.firstIndex(of: ":") {
            return (String(full[...colon]), String(full[full.index(after: colon)...]))
        }
        let path = full as NSString
        return (path.deletingLastPathComponent, path.lastPathComponent)
    }

    static func remoteName(fromFs fs: String) -> String? {
        guard !fs.hasPrefix("/"), let colon = fs.firstIndex(of: ":") else { return nil }
        return String(fs[..<colon])
    }

    private func effectiveJobConfig(for job: TransferJob) -> [String: Any] {
        let current = settings
        var transfers = current.transfers
        var checkers = current.checkers

        if let remote = Self.remoteName(fromFs: job.destinationFs) ?? Self.remoteName(fromFs: job.sourceFs) {
            let defaults = UserDefaults.standard
            let remoteTransfers = defaults.integer(forKey: RcloneDefaults.remoteTransfersKey(remote))
            let remoteCheckers = defaults.integer(forKey: RcloneDefaults.remoteCheckersKey(remote))
            if remoteTransfers > 0 { transfers = remoteTransfers }
            if remoteCheckers > 0 { checkers = remoteCheckers }
        }

        return [
            "Transfers": transfers,
            "Checkers": checkers,
            "LowLevelRetries": current.lowLevelRetries
        ]
    }

    func deleteRemoteEntries(remote: RcloneRemote, entries: [RemoteEntry]) async -> (deleted: Int, failed: Int) {
        guard !remote.name.isEmpty,
              !remote.name.hasPrefix("/"),
              remote.pathPrefix.hasSuffix(":") else {
            LogManager.shared.error("Cleanup refused: '\(remote.pathPrefix)' is not a configured remote", source: "RcloneJobManager")
            return (0, entries.count)
        }
        guard let client else { return (0, entries.count) }
        var deleted = 0
        var failed = 0
        for entry in entries {
            do {
                if entry.isDir {
                    try await client.purgeDirectory(fs: remote.pathPrefix, remote: entry.path)
                } else {
                    try await client.deleteFile(fs: remote.pathPrefix, remote: entry.path)
                }
                deleted += 1
            } catch {
                failed += 1
                LogManager.shared.warning("Cleanup failed for \(entry.path): \(error)", source: "RcloneJobManager")
            }
        }
        LogManager.shared.info("Cleanup on \(remote.name): deleted \(deleted), failed \(failed)", source: "RcloneJobManager")
        return (deleted, failed)
    }

    func estimateSize(fs: String, excludePatterns: [String]) async throws -> (bytes: Int64, files: Int) {
        guard let client else { throw RcloneRCError.notReachable }
        let jobid = try await client.startSizeJob(fs: fs, excludePatterns: excludePatterns)
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if Task.isCancelled {
                try? await client.stopJob(jobid: jobid)
                throw CancellationError()
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard let status = try? await client.jobStatus(jobid: jobid) else { continue }
            if status.finished {
                guard status.success, let bytes = status.outputBytes else {
                    throw RcloneRCError.http(status: 0, message: status.error.isEmpty ? "Could not size the source." : status.error)
                }
                return (bytes, status.outputCount ?? 0)
            }
        }
        try? await client.stopJob(jobid: jobid)
        throw RcloneRCError.http(status: 0, message: "Size estimate timed out.")
    }

    private static func isPermanentSubmitError(_ error: Error) -> Bool {
        if case RcloneRCError.http(let status, _) = error, status >= 400 {
            return true
        }
        return false
    }

    private func firstNonEmpty(_ values: String...) -> String {
        for value in values where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return value
        }
        return "Transfer failed."
    }
}
