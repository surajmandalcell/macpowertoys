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
    case question(name: String, prompt: RemoteConfigurationPrompt)
    case succeeded(name: String)
    case failed(String)
}

struct RemoteConfigurationPrompt: Equatable {
    let providerName: String
    let state: String
    let option: RcloneProviderOption
    let parameters: [String: String]
}

// MARK: - Job Manager

@Observable
final class RcloneJobManager {
    static let shared = RcloneJobManager()
    static weak var current: RcloneJobManager?

    private(set) var remotes: [RcloneRemote] = []
    private(set) var providers: [RcloneProvider] = []
    private(set) var isLoadingProviders = false
    private(set) var providerLoadError: String?
    var jobs: [TransferJob] = []
    var filter: JobFilter = .all
    var errorBanner: String?
    var isPresentingNewTransfer = false
    var authState: RemoteAuthState = .idle
    var modelContext: ModelContext?
    private var authGeneration = UUID()
    private var authTask: Task<Void, Never>?
    private var reconnectProcess: Process?
    private var remoteBeingCreated: String?

    let daemon = RcloneDaemon()
    private var client: RcloneRCClient?
    private var pollTask: Task<Void, Never>?
    private var started = false
    private var engineRetryTask: Task<Void, Never>?
    private var engineRetryAttempt = 0
    private var engineFailureBanner: String?
    private var daemonRecoveryInFlight = false
    private var settingsApplyTasks: [UUID: Task<Void, Never>] = [:]
    private var lastAppliedBandwidth: String?
    private var loadedPersistedJobs = false
    private var persistJobsTask: Task<Void, Never>?
    private var volumeObservers: [NSObjectProtocol] = []
    private var sourceWatchers: [UUID: FileWatcher] = [:]
    private var continuousSyncTasks: [UUID: Task<Void, Never>] = [:]
    private var jobsWithPendingChanges: Set<UUID> = []
    private var windowOwners: Set<UUID> = []
    private var idleShutdownTask: Task<Void, Never>?

    private let pollInterval: Duration = .milliseconds(700)
    private let continuousSyncDelay: Duration = .seconds(30)

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

    var pollingOwnerCount: Int { pollTask == nil ? 0 : 1 }
    var visibleWindowOwnerCount: Int { windowOwners.count }
    var volumeObserverOwnerCount: Int { volumeObservers.count }
    var fileWatcherOwnerCount: Int { sourceWatchers.count }
    var longLivedTaskOwnerCount: Int {
        (authTask == nil ? 0 : 1)
            + (engineRetryTask == nil ? 0 : 1)
            + (persistJobsTask == nil ? 0 : 1)
            + (idleShutdownTask == nil ? 0 : 1)
            + settingsApplyTasks.count
            + continuousSyncTasks.count
    }
    var daemonOwnerCount: Int { isDaemonRunning ? 1 : 0 }

    init() {
        Self.current = self
    }

    private var runtimeIsNeeded: Bool {
        Self.needsRuntime(
            windowVisible: !windowOwners.isEmpty,
            jobs: jobs,
            backgroundEnabled: UserDefaults.standard.bool(forKey: "tool.rclone.startAtLaunch")
        )
    }

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

    static func needsRuntime(
        windowVisible: Bool,
        jobs: [TransferJob],
        backgroundEnabled: Bool
    ) -> Bool {
        windowVisible || backgroundEnabled || jobs.contains { $0.state.isActive || $0.continuousSync }
    }

    func windowDidOpen(owner: UUID) async {
        guard windowOwners.insert(owner).inserted else { return }
        await start()
    }

    func windowDidClose(owner: UUID) {
        guard windowOwners.remove(owner) != nil else { return }
        stopIfUnneededSoon()
    }

    func backgroundPreferenceDidChange(enabled: Bool) async {
        if enabled, SettingsManager.shared.isToolEnabled("rclone") {
            await start()
        } else {
            stopIfUnneededSoon()
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        loadPersistedJobs()
        restoreSourceWatchers()
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
            engineRetryAttempt = 0
            clearEngineFailureBanner()
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
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not start rclone."
            engineFailureBanner = message
            errorBanner = message
            LogManager.shared.error("rclone start failed: \(error)", source: "RcloneJobManager")
            if runtimeIsNeeded { scheduleEngineRetry() }
        }
    }

    private func scheduleEngineRetry() {
        guard engineRetryTask == nil else { return }
        engineRetryAttempt += 1
        let delay = min(30.0, pow(2.0, Double(engineRetryAttempt)))
        LogManager.shared.info("Retrying rclone engine start in \(Int(delay))s (attempt \(engineRetryAttempt))", source: "RcloneJobManager")
        engineRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.engineRetryTask = nil
            guard !self.started, self.runtimeIsNeeded else { return }
            await self.start()
        }
    }

    private func clearEngineFailureBanner() {
        if let failure = engineFailureBanner, errorBanner == failure {
            errorBanner = nil
        }
        engineFailureBanner = nil
    }

    func restartDaemon() async {
        engineRetryTask?.cancel()
        engineRetryTask = nil
        pollTask?.cancel()
        pollTask = nil
        daemon.stop()
        client = nil
        started = false
        guard runtimeIsNeeded else { return }
        await start()
    }

    func shutdown() async {
        engineRetryTask?.cancel()
        engineRetryTask = nil
        pollTask?.cancel()
        pollTask = nil
        authTask?.cancel()
        authTask = nil
        reconnectProcess?.terminate()
        reconnectProcess = nil
        authGeneration = UUID()
        authState = .idle
        if let name = remoteBeingCreated, let client {
            try? await client.deleteRemoteConfig(name: name)
        }
        remoteBeingCreated = nil
        for watcher in sourceWatchers.values {
            watcher.stop()
        }
        sourceWatchers.removeAll()
        for task in continuousSyncTasks.values {
            task.cancel()
        }
        continuousSyncTasks.removeAll()
        await LocalChangeHistory.shared.flush()
        for job in jobs where job.state.isActive && !job.state.isTerminal {
            let jobid = job.rcJobId
            if job.state == .running {
                job.commitAttemptProgress()
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

    private func stopIfUnneededSoon() {
        guard idleShutdownTask == nil else { return }
        idleShutdownTask = Task { [weak self] in
            guard let self else { return }
            if !self.runtimeIsNeeded {
                await self.shutdown()
            }
            self.idleShutdownTask = nil
        }
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

    func loadProviders() async {
        guard providers.isEmpty, !isLoadingProviders else { return }
        guard let client else {
            providerLoadError = "Cloud Sync engine is not running."
            return
        }
        isLoadingProviders = true
        providerLoadError = nil
        defer { isLoadingProviders = false }
        do {
            providers = try await client.providers().filter { $0.name != "local" }
        } catch {
            providerLoadError = (error as? LocalizedError)?.errorDescription ?? "Could not load connectors."
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

    func websiteName(for fs: String) -> String? {
        websiteRemote(for: fs)?.websiteName
    }

    func openFolderInWebsite(fs: String, transferKind: TransferKind) {
        guard let remote = websiteRemote(for: fs),
              let folderPath = Self.remoteFolderPath(fromFs: fs, transferKind: transferKind) else { return }
        guard let client else {
            errorBanner = "Cloud Sync engine is not running."
            return
        }
        let provider = remote.websiteName ?? "cloud provider"

        Task {
            do {
                let folderID = folderPath.isEmpty ? nil : try await client.folderID(fs: remote.pathPrefix, remote: folderPath)
                guard let url = remote.websiteFolderURL(id: folderID) else {
                    errorBanner = "Could not build the \(provider) folder link."
                    return
                }
                if !NSWorkspace.shared.open(url) {
                    errorBanner = "Could not open \(provider)."
                }
            } catch {
                errorBanner = "Could not open \(provider): \(error.localizedDescription)"
            }
        }
    }

    private func websiteRemote(for fs: String) -> RcloneRemote? {
        guard let name = Self.remoteName(fromFs: fs) else { return nil }
        return remotes.first { $0.name == name && $0.websiteName != nil }
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
        switch authState {
        case .waiting, .question: return true
        default: return false
        }
    }

    static func isValidRemoteName(_ name: String) -> Bool {
        guard !name.isEmpty, let first = name.first, first.isLetter || first.isNumber else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    func beginAddRemote(named rawName: String, provider: RcloneProvider, parameters: [String: String]) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard Self.isValidRemoteName(name) else {
            authState = .failed("Names can use letters, numbers, dots, dashes, and underscores.")
            return
        }
        guard !remotes.contains(where: { $0.name == name }) else {
            authState = .failed("A remote named \"\(name)\" already exists.")
            return
        }
        let generation = UUID()
        authGeneration = generation
        remoteBeingCreated = name
        authState = .waiting(name: name)
        LogManager.shared.info("Starting \(provider.displayName) authorization for remote '\(name)'", source: "RcloneJobManager")

        authTask?.cancel()
        authTask = Task { [weak self] in
            await self?.runConfiguration(
                name: name,
                providerName: provider.name,
                parameters: parameters,
                generation: generation
            )
        }
    }

    func beginReconnect(_ remote: RcloneRemote) {
        guard !isAuthInProgress else { return }
        let generation = UUID()
        authGeneration = generation
        remoteBeingCreated = nil
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

    private func runConfiguration(
        name: String,
        providerName: String,
        parameters: [String: String],
        generation: UUID
    ) async {
        guard let client else {
            remoteBeingCreated = nil
            finishAuth(generation: generation, state: .failed("Cloud Sync engine is not running."))
            return
        }

        do {
            let step = try await client.beginConfiguration(name: name, type: providerName, parameters: parameters)
            await handleConfigurationStep(
                step,
                name: name,
                providerName: providerName,
                parameters: parameters,
                generation: generation
            )
        } catch {
            guard authGeneration == generation, !Task.isCancelled else { return }
            try? await client.deleteRemoteConfig(name: name)
            remoteBeingCreated = nil
            finishAuth(generation: generation, state: .failed((error as? LocalizedError)?.errorDescription ?? "Could not configure this connector."))
        }
    }

    private func handleConfigurationStep(
        _ step: RcloneConfigurationStep,
        name: String,
        providerName: String,
        parameters: [String: String],
        generation: UUID
    ) async {
        guard authGeneration == generation, !Task.isCancelled else { return }
        if step.isComplete {
            if step.error.isEmpty {
                await refreshRemotes()
                remoteBeingCreated = nil
                finishAuth(generation: generation, state: .succeeded(name: name))
                LogManager.shared.info("Remote '\(name)' connected", source: "RcloneJobManager")
            } else {
                if let client { try? await client.deleteRemoteConfig(name: name) }
                remoteBeingCreated = nil
                finishAuth(generation: generation, state: .failed(step.error))
            }
            return
        }
        guard let option = step.option else {
            if let client { try? await client.deleteRemoteConfig(name: name) }
            remoteBeingCreated = nil
            finishAuth(generation: generation, state: .failed(step.error.isEmpty ? "rclone returned an incomplete configuration step." : step.error))
            return
        }

        if option.name == "config_is_local" {
            await continueConfiguration(
                name: name,
                prompt: RemoteConfigurationPrompt(
                    providerName: providerName,
                    state: step.state,
                    option: option,
                    parameters: parameters
                ),
                answer: "true",
                generation: generation
            )
            return
        }

        authState = .question(
            name: name,
            prompt: RemoteConfigurationPrompt(
                providerName: providerName,
                state: step.state,
                option: option,
                parameters: parameters
            )
        )
    }

    func answerConfigurationPrompt(_ answer: String) {
        guard case .question(let name, let prompt) = authState else { return }
        let generation = authGeneration
        authState = .waiting(name: name)
        authTask?.cancel()
        authTask = Task { [weak self] in
            await self?.continueConfiguration(name: name, prompt: prompt, answer: answer, generation: generation)
        }
    }

    private func continueConfiguration(
        name: String,
        prompt: RemoteConfigurationPrompt,
        answer: String,
        generation: UUID
    ) async {
        guard let client else {
            remoteBeingCreated = nil
            finishAuth(generation: generation, state: .failed("Cloud Sync engine is not running."))
            return
        }
        do {
            let step = try await client.continueConfiguration(
                name: name,
                parameters: prompt.parameters,
                state: prompt.state,
                result: answer
            )
            await handleConfigurationStep(
                step,
                name: name,
                providerName: prompt.providerName,
                parameters: prompt.parameters,
                generation: generation
            )
        } catch {
            guard authGeneration == generation, !Task.isCancelled else { return }
            try? await client.deleteRemoteConfig(name: name)
            remoteBeingCreated = nil
            finishAuth(generation: generation, state: .failed((error as? LocalizedError)?.errorDescription ?? "Could not continue connector setup."))
        }
    }

    private func finishAuth(generation: UUID, state: RemoteAuthState) {
        guard authGeneration == generation else { return }
        authState = state
        if case .failed(let message) = state {
            LogManager.shared.warning("Remote authorization failed: \(message)", source: "RcloneJobManager")
        }
    }

    func cancelAuth() {
        reconnectProcess?.terminate()
        reconnectProcess = nil
        let activeName: String
        switch authState {
        case .waiting(let remoteName), .question(let remoteName, _): activeName = remoteName
        default:
            authGeneration = UUID()
            authState = .idle
            return
        }
        let createdName = remoteBeingCreated == activeName ? activeName : nil
        remoteBeingCreated = nil
        authGeneration = UUID()
        authTask?.cancel()
        authTask = nil
        authState = .idle

        Task { [weak self] in
            guard let self else { return }
            if let createdName, let client = self.client {
                try? await client.deleteRemoteConfig(name: createdName)
                await self.refreshRemotes()
            }
        }
    }

    func acknowledgeAuthResult() {
        if isAuthInProgress {
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
            errorBanner = "An active transfer uses \"\(remote.name)\". Cancel the transfer first."
            return
        }

        Task {
            guard let client else { return }
            do {
                try await client.deleteRemoteConfig(name: remote.name)
                await refreshRemotes()
                LogManager.shared.info("Removed remote '\(remote.name)'", source: "RcloneJobManager")
            } catch {
                errorBanner = "Unable to remove remote \"\(remote.name)\"."
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
        startSourceWatcher(for: job)
        persistJobsSoon()
        LogManager.shared.info("Queued \(operation.displayName): \(sourceDisplay) → \(destinationDisplay)", source: "RcloneJobManager")
        return job
    }

    static func supportsContinuousSync(_ job: TransferJob) -> Bool {
        job.kind == .directory && job.sourceFs.hasPrefix("/")
    }

    func setContinuousSync(_ enabled: Bool, for job: TransferJob) {
        guard Self.supportsContinuousSync(job), job.continuousSync != enabled else { return }
        job.continuousSync = enabled

        if enabled {
            startSourceWatcher(for: job)
            if job.state == .completed, jobsWithPendingChanges.contains(job.id) {
                scheduleContinuousSync(for: job)
            }
            LogManager.shared.info("Continuous \(job.operation.displayName) enabled for \(job.sourceDisplay)", source: "RcloneJobManager")
        } else {
            continuousSyncTasks[job.id]?.cancel()
            continuousSyncTasks[job.id] = nil
            if job.state.isTerminal {
                stopSourceWatcher(for: job)
            }
            LogManager.shared.info("Continuous \(job.operation.displayName) disabled for \(job.sourceDisplay)", source: "RcloneJobManager")
        }
        persistJobsSoon()
        if !enabled { stopIfUnneededSoon() }
    }

    private func restoreSourceWatchers() {
        for job in jobs where !job.state.isTerminal || job.continuousSync {
            startSourceWatcher(for: job)
            if job.continuousSync, job.state == .completed {
                jobsWithPendingChanges.insert(job.id)
                scheduleContinuousSync(for: job)
            }
        }
    }

    private func startSourceWatcher(for job: TransferJob) {
        guard Self.supportsContinuousSync(job), sourceWatchers[job.id] == nil else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: job.sourceFs, isDirectory: &isDirectory), isDirectory.boolValue else { return }

        let watcher = FileWatcher(path: job.sourceFs, latency: 1) { [weak self, weak job] changes in
            guard let self, let job else { return }
            Task { @MainActor in
                self.handleSourceChanges(changes, for: job)
            }
        }
        sourceWatchers[job.id] = watcher
        watcher.start()
    }

    private func stopSourceWatcher(for job: TransferJob, discardPendingChanges: Bool = true) {
        sourceWatchers.removeValue(forKey: job.id)?.stop()
        continuousSyncTasks.removeValue(forKey: job.id)?.cancel()
        if discardPendingChanges {
            jobsWithPendingChanges.remove(job.id)
        }
    }

    private func handleSourceChanges(_ changes: [FileChangeEvent], for job: TransferJob) {
        guard jobs.contains(where: { $0.id == job.id }), !job.state.isTerminal || job.continuousSync else { return }
        let root = URL(fileURLWithPath: job.sourceFs).standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        let records = changes.compactMap { change -> LocalChangeRecord? in
            let path = URL(fileURLWithPath: change.path).standardizedFileURL.path
            guard path.hasPrefix(prefix) else { return nil }
            let relativePath = String(path.dropFirst(prefix.count))
            guard !relativePath.isEmpty else { return nil }

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            let name = (relativePath as NSString).lastPathComponent
            guard !IgnoreMatcher.matches(
                path: relativePath,
                name: name,
                isDir: exists && isDirectory.boolValue,
                patterns: job.excludePatterns
            ) else { return nil }

            return LocalChangeRecord(
                jobID: job.id,
                operation: job.operation,
                sourceDisplay: job.sourceDisplay,
                relativePath: relativePath,
                kind: change.kind
            )
        }
        guard !records.isEmpty else { return }

        LocalChangeHistory.shared.record(records)
        jobsWithPendingChanges.insert(job.id)
        if job.continuousSync, job.state == .completed {
            scheduleContinuousSync(for: job)
        }
    }

    private func scheduleContinuousSync(for job: TransferJob) {
        guard job.continuousSync, job.state == .completed else { return }
        continuousSyncTasks[job.id]?.cancel()
        continuousSyncTasks[job.id] = Task { [weak self, weak job] in
            guard let self, let job else { return }
            try? await Task.sleep(for: self.continuousSyncDelay)
            guard !Task.isCancelled else { return }
            self.continuousSyncTasks[job.id] = nil
            self.queueContinuousSync(for: job)
        }
    }

    private func queueContinuousSync(for job: TransferJob) {
        guard job.continuousSync,
              job.state == .completed,
              jobsWithPendingChanges.remove(job.id) != nil else { return }

        job.prepareForNewRun()
        persistJobsSoon()
        LogManager.shared.info("Queued continuous \(job.operation.displayName) for \(job.sourceDisplay)", source: "RcloneJobManager")
    }

    func cancel(_ job: TransferJob) {
        guard job.canCancel else { return }
        let jobid = job.rcJobId
        job.continuousSync = false
        job.state = .cancelled
        job.finishedAt = Date()
        job.nextRetryAt = nil
        insertRecord(for: job)
        stopSourceWatcher(for: job)
        persistJobsSoon()
        Task {
            if let jobid, let client {
                try? await client.stopJob(jobid: jobid)
                await client.deleteStats(group: job.statsGroup)
            }
        }
        stopIfUnneededSoon()
    }

    func pause(_ job: TransferJob) {
        guard job.canPause else { return }
        let jobid = job.rcJobId
        if job.state == .running {
            job.commitAttemptProgress()
        }
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

    func setExpanded(_ expanded: Bool, for job: TransferJob) {
        guard job.isExpanded != expanded else { return }
        job.isExpanded = expanded
        persistJobsSoon()
    }

    func setPriority(_ priority: TransferPriority, for job: TransferJob) {
        guard job.kind == .file, job.priority != priority else { return }
        job.priority = priority
        persistJobsSoon()
        LogManager.shared.info("Set file priority to \(priority.displayName): \(job.sourceDisplay)", source: "RcloneJobManager")
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
        for job in jobs where Self.fsUsesVolume(job.sourceFs, volumePath) {
            stopSourceWatcher(for: job, discardPendingChanges: false)
        }
        for job in jobs where job.canPause && Self.jobUsesVolume(job, volumePath) {
            pause(job)
            job.autoPausedVolume = volumePath
            job.errorMessage = "Drive \"\(volumeName)\" disconnected. MacPowerToys will resume the transfer when the drive reconnects."
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
        for job in jobs where Self.jobUsesVolume(job, volumePath) && (!job.state.isTerminal || job.continuousSync) {
            startSourceWatcher(for: job)
            if job.continuousSync, job.state == .completed, jobsWithPendingChanges.contains(job.id) {
                scheduleContinuousSync(for: job)
            }
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
            job.errorMessage = "Drive \"\(name)\" disconnected. MacPowerToys will resume the transfer when the drive reconnects."
            LogManager.shared.warning("Auto-paused (drive offline): \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
        case .wrongDrive(let volume):
            let name = (volume as NSString).lastPathComponent
            if job.canPause { pause(job) }
            job.autoPausedVolume = volume
            job.errorMessage = "A different drive is mounted as \"\(name)\". Reconnect the original drive to resume the transfer."
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
        job.prepareForNewRun()
        job.autoResumeOnLaunch = false
        startSourceWatcher(for: job)
        persistJobsSoon()
    }

    func remove(_ job: TransferJob) {
        guard job.state.isTerminal else { return }
        stopSourceWatcher(for: job)
        jobs.removeAll { $0.id == job.id }
        LocalChangeHistory.shared.removeEntries(for: [job.id])
        persistJobsSoon()
    }

    func clearFinished() {
        let finished = jobs.filter(\.state.isTerminal)
        for job in finished {
            stopSourceWatcher(for: job)
        }
        LocalChangeHistory.shared.removeEntries(for: Set(finished.map(\.id)))
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

        if !daemon.isRunning {
            recoverFromDaemonLoss()
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

    private func recoverFromDaemonLoss() {
        guard !daemonRecoveryInFlight else { return }
        daemonRecoveryInFlight = true
        LogManager.shared.error("The rclone daemon stopped unexpectedly. MacPowerToys is restarting the transfer engine.", source: "RcloneJobManager")
        for job in jobs where job.state == .running {
            job.commitAttemptProgress()
            job.rcJobId = nil
            job.state = .queued
        }
        persistJobsSoon()
        Task { [weak self] in
            await self?.restartDaemon()
            self?.daemonRecoveryInFlight = false
        }
    }

    private func applyProbe(_ job: TransferJob, stats: TransferStats?, status: JobStatusResult?, client: RcloneRCClient) {
        if let stats {
            job.stats = stats
            job.captureAttemptPlan()
            job.refreshDisplayEta()
        }

        guard job.rcJobId != nil, let status, status.finished else { return }
        job.captureAttemptPlan(force: true)

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
            job.commitAttemptProgress()
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
        job.captureAttemptPlan(force: true)
        if success {
            LogManager.shared.info("Completed: \(job.sourceDisplay) → \(job.destinationDisplay)", source: "RcloneJobManager")
        } else {
            LogManager.shared.error("Failed: \(job.sourceDisplay) → \(job.destinationDisplay): \(error ?? "")", source: "RcloneJobManager")
        }
        insertRecord(for: job)
        if success, job.continuousSync, jobsWithPendingChanges.contains(job.id) {
            scheduleContinuousSync(for: job)
        } else if !job.continuousSync {
            stopSourceWatcher(for: job, discardPendingChanges: false)
        }
        persistJobsSoon()
        Task { await client.deleteStats(group: job.statsGroup) }
        stopIfUnneededSoon()
    }

    // MARK: Job persistence

    private func loadPersistedJobs() {
        guard !loadedPersistedJobs else { return }
        loadedPersistedJobs = true
        guard let data = try? Data(contentsOf: AppDataLocation.transfersURL),
              let snapshots = try? JSONDecoder().decode([TransferJobSnapshot].self, from: data) else { return }
        jobs = snapshots.map { TransferJob(snapshot: $0) }
    }

    static func hasPersistedContinuousJobs() async -> Bool {
        let url = AppDataLocation.transfersURL
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let snapshots = try? JSONDecoder().decode([TransferJobSnapshot].self, from: data) else { return false }
            return snapshots.contains { $0.continuousSync == true }
        }.value
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
        guard loadedPersistedJobs else { return }
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

        for job in Self.orderedReadyJobs(jobs, at: now) {
            guard runningCount < maxConcurrent else { break }

            let readyRetry = job.state == .retrying && (job.nextRetryAt ?? now) <= now
            guard job.state == .queued || readyRetry else { continue }

            submit(job, client: client)
            runningCount += 1
        }
    }

    static func orderedReadyJobs(_ jobs: [TransferJob], at now: Date = Date()) -> [TransferJob] {
        jobs
            .filter { job in
                job.state == .queued || (job.state == .retrying && (job.nextRetryAt ?? now) <= now)
            }
            .sorted {
                if $0.effectivePriority != $1.effectivePriority {
                    return $0.effectivePriority.rawValue > $1.effectivePriority.rawValue
                }
                return $0.createdAt < $1.createdAt
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
        persistJobsSoon()

        job.state = .running
        job.isSizing = job.kind == .directory
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
                if job.state != .running {
                    try? await client.stopJob(jobid: jobid)
                    await client.deleteStats(group: group)
                } else {
                    job.rcJobId = jobid
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Could not start transfer."
                handleFailure(job, message: message, client: client, permanent: Self.isPermanentSubmitError(error))
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

    static func remoteFolderPath(fromFs fs: String, transferKind: TransferKind) -> String? {
        guard remoteName(fromFs: fs) != nil else { return nil }
        let path = fileEndpointComponents(fs).remote
        return transferKind == .file ? (path as NSString).deletingLastPathComponent : path
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

        if job.transfersOverride > 0 { transfers = job.transfersOverride }
        if job.checkersOverride > 0 { checkers = job.checkersOverride }

        var config: [String: Any] = [
            "Transfers": transfers,
            "Checkers": checkers,
            "LowLevelRetries": current.lowLevelRetries,
            "Retries": 1,
            "CheckFirst": true
        ]
        if let orderBy = job.transferOrder.orderByValue {
            config["OrderBy"] = orderBy
        }
        if job.updateOlderOnly {
            config["UpdateOlder"] = true
        }
        if job.ignoreExisting {
            config["IgnoreExisting"] = true
        }
        if job.compareChecksums {
            config["CheckSum"] = true
        }
        return config
    }

    func recalculate(_ job: TransferJob) {
        guard let client, job.kind == .directory, !job.isRecalculating else { return }

        let baselineRemainingBytes = max(0, job.effectiveTotalBytes - job.displayBytes)
        let baselineRemainingFiles = max(0, job.effectiveTotalFiles - job.displayFiles)
        let group = "recalculate/\(job.id.uuidString)/\(UUID().uuidString)"
        var config = effectiveJobConfig(for: job)
        config["DryRun"] = true
        config["CheckFirst"] = true

        job.isRecalculating = true
        job.recalculationError = nil

        Task { [weak self, weak job] in
            guard let self, let job else { return }
            var scanJobID: Int?

            do {
                scanJobID = try await client.startJob(
                    endpoint: job.operation.rcEndpoint,
                    srcFs: job.sourceFs,
                    dstFs: job.destinationFs,
                    group: group,
                    excludePatterns: job.excludePatterns,
                    config: config
                )

                let deadline = Date().addingTimeInterval(600)
                var latestStats = TransferStats.empty
                var completedScan = false
                while Date() < deadline {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(500))
                    if let stats = try? await client.stats(group: group) {
                        latestStats = stats
                    }
                    guard let scanJobID,
                          let status = try? await client.jobStatus(jobid: scanJobID),
                          status.finished else { continue }
                    guard status.success, latestStats.errors == 0, !latestStats.fatalError else {
                        throw RcloneRCError.http(
                            status: 0,
                            message: firstNonEmpty(status.error, latestStats.lastError, "Could not recalculate the transfer plan.")
                        )
                    }

                    guard jobs.contains(where: { $0.id == job.id }) else {
                        completedScan = true
                        break
                    }
                    let added = job.applyRecalculatedPlan(
                        remainingBytes: latestStats.totalBytes,
                        remainingFiles: latestStats.totalTransfers,
                        baselineRemainingBytes: baselineRemainingBytes,
                        baselineRemainingFiles: baselineRemainingFiles
                    )
                    job.refreshDisplayEta()
                    persistJobsSoon()
                    LogManager.shared.info(
                        "MacPowerToys recalculated \(job.sourceDisplay). \(RcloneFormat.bytes(latestStats.totalBytes)) and \(latestStats.totalTransfers) files remain. The plan increased by \(RcloneFormat.bytes(added.bytes)) and \(added.files) files.",
                        source: "RcloneJobManager"
                    )
                    completedScan = true
                    break
                }

                if !completedScan, let scanJobID {
                    try? await client.stopJob(jobid: scanJobID)
                    throw RcloneRCError.http(status: 0, message: "Recalculation timed out.")
                }
            } catch is CancellationError {
                if let scanJobID { try? await client.stopJob(jobid: scanJobID) }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Could not recalculate the transfer plan."
                job.recalculationError = message
                LogManager.shared.warning("Recalculate failed for \(job.sourceDisplay): \(message)", source: "RcloneJobManager")
            }

            job.isRecalculating = false
            await client.deleteStats(group: group)
        }
    }

    func restartTransferQuietly(_ job: TransferJob) {
        if job.state == .running {
            pause(job)
        }
        if job.state == .paused, job.canResume {
            resume(job)
        }
    }

    func applyTransferSettingsChange(_ job: TransferJob) {
        persistJobsSoon()
        settingsApplyTasks[job.id]?.cancel()
        settingsApplyTasks[job.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, !Task.isCancelled else { return }
            self.settingsApplyTasks[job.id] = nil
            if job.state == .running {
                self.restartTransferQuietly(job)
            }
        }
    }

    func ignoreFile(_ job: TransferJob, path: String, addToGlobalList: Bool) {
        let rule = "/" + path
        if !job.excludePatterns.contains(rule) {
            job.excludePatterns.append(rule)
        }
        if addToGlobalList {
            let name = (path as NSString).lastPathComponent
            let defaults = UserDefaults.standard
            let raw = defaults.string(forKey: RcloneDefaults.ignorePatternsKey) ?? RcloneDefaults.ignorePatterns
            if !RcloneDefaults.parsePatterns(raw).contains(name) {
                defaults.set(raw.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + name, forKey: RcloneDefaults.ignorePatternsKey)
            }
            LogManager.shared.info("Added \"\(name)\" to the global ignore list.", source: "RcloneJobManager")
        }
        LogManager.shared.info("Ignoring \(rule) on \(job.sourceDisplay)", source: "RcloneJobManager")
        persistJobsSoon()
        restartTransferQuietly(job)
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
