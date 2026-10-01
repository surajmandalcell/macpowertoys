import AppKit
import Darwin
import Foundation

nonisolated enum SystemCareMode: String, CaseIterable, Identifiable {
    case quick = "Quick Cleanup"
    case guided = "Guided Cleanup"
    case analysis = "Analysis Only"

    var id: String { rawValue }
}

nonisolated enum SystemCareCategoryID: String, CaseIterable, Identifiable, Codable, Sendable {
    case caches
    case logs
    case installers
    case developer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .caches: "Application Caches"
        case .logs: "User Logs"
        case .installers: "Downloaded Installers"
        case .developer: "Xcode Derived Data"
        }
    }
    var detail: String {
        switch self {
        case .caches: "Rebuildable files in ~/Library/Caches"
        case .logs: "Diagnostic files in ~/Library/Logs"
        case .installers: "DMG, PKG, MPKG, ISO, and XIP files in Downloads"
        case .developer: "Rebuildable Xcode output in DerivedData"
        }
    }
    var icon: String {
        switch self {
        case .caches: "shippingbox"
        case .logs: "doc.text"
        case .installers: "opticaldiscdrive"
        case .developer: "hammer"
        }
    }
}

nonisolated struct CleanupCandidate: Identifiable, Hashable, Codable, Sendable {
    let url: URL
    let allowedRoot: URL
    let category: SystemCareCategoryID
    let size: Int64
    var fileIdentity: CleanupFileIdentity? = nil
    var rootIdentity: CleanupFileIdentity? = nil

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

nonisolated struct CleanupFileIdentity: Hashable, Codable, Sendable {
    let device: Int32
    let inode: UInt64
    let birthSeconds: Int64
    let birthNanoseconds: Int64
}

nonisolated struct CleanupScanSnapshot: Codable, Equatable, Sendable {
    let scannedAt: Date
    let candidates: [CleanupCandidate]
    var selectedCandidateIDs: Set<String>? = nil
    var coverage: [CleanupRootCoverage]? = nil
    var outcome: CleanupScanOutcome? = nil
}

nonisolated enum CleanupScanOutcome: String, Codable, Sendable {
    case completed, partial, canceled, failed
}

nonisolated struct SystemCareFileIssue: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case missing, accessDenied, unsafePath, io }
    let url: URL
    let kind: Kind
    let reason: String

    init(url: URL, error: Error) {
        self.url = url
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError ?? error
        if error.domain == "SystemCare", error.code == 1 { kind = .unsafePath }
        else if (underlying.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(underlying.code))
            || (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError) { kind = .accessDenied }
        else if (underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(ENOENT))
            || (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError) { kind = .missing }
        else { kind = .io }
        reason = error.localizedDescription
    }
}

nonisolated struct CleanupRootCoverage: Codable, Equatable, Sendable {
    let category: SystemCareCategoryID
    let root: URL
    var didReadRoot = false
    var examinedCount = 0
    var isTruncated = false
    var issues: [SystemCareFileIssue] = []
    var isComplete: Bool { didReadRoot && !isTruncated && issues.isEmpty }
}

nonisolated struct CleanupScanReport: Sendable {
    let candidates: [CleanupCandidate]
    let coverage: [CleanupRootCoverage]
    var outcome: CleanupScanOutcome {
        !coverage.isEmpty && coverage.allSatisfy(\.isComplete) ? .completed : .partial
    }
}

nonisolated struct CleanupTrashFailure: Sendable {
    let id: String
    let reason: String
}

nonisolated struct CleanupTrashResult: Sendable {
    let movedCount: Int
    let movedBytes: Int64
    let failures: [CleanupTrashFailure]
}

nonisolated struct StorageEntry: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    let size: Int64
    let isDirectory: Bool

    var id: String { url.path }
}

nonisolated struct InstalledApplication: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    var id: String { url.path }
}

nonisolated struct MoleHistoryItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
}

nonisolated enum MoleOperation: String, CaseIterable, Identifiable, Sendable {
    case clean
    case optimize
    case purge
    case installer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clean: "Deep Cleanup"
        case .optimize: "System Maintenance"
        case .purge: "Project Artifacts"
        case .installer: "Installer Files"
        }
    }
    var detail: String {
        switch self {
        case .clean: "Caches, logs, temporary files, and orphaned leftovers"
        case .optimize: "Safe cache and service maintenance"
        case .purge: "Rebuildable artifacts in development projects"
        case .installer: "DMG, PKG, ISO, XIP, and installer ZIP files"
        }
    }
    var icon: String {
        switch self {
        case .clean: "sparkles"
        case .optimize: "wrench.and.screwdriver"
        case .purge: "hammer"
        case .installer: "opticaldiscdrive"
        }
    }
}

@Observable
@MainActor
final class SystemCareManager {
    static let shared = SystemCareManager()
    static let cleanupScanKey = "systemCare.cleanupScan.v1"

    private(set) var molePath: URL?
    private(set) var moleVersion: String?
    private(set) var supportedMolePreviews: Set<MoleOperation> = []
    private(set) var canPreviewUninstall = false
    private var supportsUninstallInventory = false
    private(set) var isWorking = false
    private(set) var canCancel = false
    private(set) var isCancelling = false
    private(set) var progressMessage: String?
    private(set) var errorMessage: String?
    private(set) var cleanupCandidates: [CleanupCandidate] = []
    private(set) var selectedCandidateIDs: Set<String> = []
    private(set) var storageEntries: [StorageEntry] = []
    private(set) var storageTotal: Int64 = 0
    private(set) var storageFileCount = 0
    private(set) var storageURL: URL?
    private(set) var storageBreadcrumbs: [URL] = []
    private(set) var applications: [InstalledApplication] = []
    private(set) var history: [MoleHistoryItem] = []
    private(set) var lastRecoveredBytes: Int64 = 0
    private(set) var lastTrashResult: CleanupTrashResult?
    private(set) var cleanupScanDate: Date?
    private(set) var cleanupCoverage: [CleanupRootCoverage] = []
    private(set) var cleanupScanOutcome: CleanupScanOutcome?
    private(set) var storageCountIsFiles = false
    private(set) var storageIssue: SystemCareFileIssue?

    private let defaults: UserDefaults
    private let homeDirectory: URL
    private let trashItem: @Sendable (URL) throws -> Void
    private var task: Task<Void, Never>?
    private var isRestoring = false
    private var refreshAfterRestore = false

    init(
        defaults: UserDefaults = .standard,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        trashItem: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        self.trashItem = trashItem
        guard let data = defaults.data(forKey: Self.cleanupScanKey) else { return }
        isRestoring = true
        _ = beginWork("Restoring the saved scan...")
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishWork() }
            do {
                let snapshot = try await Self.runWorker {
                    let saved = try JSONDecoder().decode(CleanupScanSnapshot.self, from: data)
                    let candidates = saved.candidates.filter { Self.isSafe($0, homeDirectory: homeDirectory) }
                    let validIDs = Set(candidates.map(\.id))
                    return CleanupScanSnapshot(scannedAt: saved.scannedAt, candidates: candidates,
                                               selectedCandidateIDs: saved.selectedCandidateIDs?.intersection(validIDs) ?? validIDs,
                                               coverage: saved.coverage,
                                               outcome: candidates.count == saved.candidates.count ? saved.outcome ?? .partial : .partial)
                }
                cleanupCandidates = snapshot.candidates
                selectedCandidateIDs = snapshot.selectedCandidateIDs ?? []
                cleanupScanDate = snapshot.scannedAt
                cleanupCoverage = snapshot.coverage ?? []
                cleanupScanOutcome = snapshot.outcome
                if snapshot.outcome == .partial {
                    errorMessage = "The saved scan has incomplete coverage or changed paths. Rescan before cleanup."
                }
            } catch is CancellationError {
            } catch {
                errorMessage = "The saved cleanup scan could not be restored. Rescan the locations."
            }
        }
    }

    var hasCleanupScan: Bool { cleanupScanDate != nil }

    private func beginWork(_ message: String, cancelable: Bool = true) -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        canCancel = cancelable
        isCancelling = false
        errorMessage = nil
        progressMessage = message
        return true
    }

    private func finishWork() {
        task = nil
        isWorking = false
        canCancel = false
        isCancelling = false
        progressMessage = nil
        isRestoring = false
        if refreshAfterRestore {
            refreshAfterRestore = false
            refresh()
        }
    }

    nonisolated static func runWorker<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    func refresh() {
        if isRestoring { refreshAfterRestore = true; return }
        guard beginWork("Checking Mole and applications...") else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishWork() }
            do {
                let result = try await Self.runWorker { (Self.detectMole(), try Self.installedApplications()) }
                applyMoleDetection(result.0)
                applications = result.1
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        guard isWorking, canCancel, !isCancelling else { return }
        isCancelling = true
        canCancel = false
        progressMessage = "Canceling..."
        task?.cancel()
    }

    func scanCleanup(categories: Set<SystemCareCategoryID>) {
        performCleanupScan(categories: categories, retry: false)
    }

    func retryCleanupScan() {
        let affected = Set(cleanupCoverage.filter { !$0.isComplete }.map(\.category))
        guard !affected.isEmpty else { return }
        performCleanupScan(categories: affected, retry: true)
    }

    private func performCleanupScan(categories: Set<SystemCareCategoryID>, retry: Bool) {
        guard !categories.isEmpty else { return }
        guard beginWork("Scanning selected locations...") else { return }
        let homeDirectory = homeDirectory
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishWork() }
            do {
                let report = try await Self.runWorker {
                    try Self.cleanupReport(for: categories, homeDirectory: homeDirectory)
                }
                let readable = Set(report.coverage.filter(\.didReadRoot).map(\.category))
                let retained = self.cleanupCandidates.filter {
                    readable.isEmpty || (!readable.contains($0.category) && (retry || categories.contains($0.category)))
                }
                let oldSelection = self.selectedCandidateIDs
                self.cleanupCandidates = (retained + report.candidates).sorted { $0.size > $1.size }
                self.selectedCandidateIDs = oldSelection.intersection(retained.map(\.id)).union(report.candidates.map(\.id))
                self.cleanupCoverage = (retry ? self.cleanupCoverage.filter { !categories.contains($0.category) } : []) + report.coverage
                self.cleanupScanOutcome = readable.isEmpty ? .failed
                    : self.cleanupCoverage.allSatisfy(\.isComplete) ? .completed : .partial
                if !readable.isEmpty { self.cleanupScanDate = Date() }
                if self.cleanupScanOutcome != .completed {
                    self.errorMessage = "Some locations were skipped or not fully scanned. Review coverage before cleanup."
                }
                self.persistCleanupScan()
            } catch is CancellationError {
                self.cleanupScanOutcome = .canceled
                return
            } catch {
                self.cleanupScanOutcome = .failed
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func setCandidate(_ id: String, selected: Bool) {
        guard !isWorking, cleanupCandidates.contains(where: { $0.id == id }) else { return }
        if selected { selectedCandidateIDs.insert(id) }
        else { selectedCandidateIDs.remove(id) }
        persistCleanupScan()
    }

    func setCandidates(_ ids: Set<String>, selected: Bool) {
        guard !isWorking else { return }
        let validIDs = ids.intersection(cleanupCandidates.map(\.id))
        if selected { selectedCandidateIDs.formUnion(validIDs) }
        else { selectedCandidateIDs.subtract(ids) }
        persistCleanupScan()
    }

    func clearCleanupScan() {
        guard !isWorking else { return }
        cleanupCandidates.removeAll()
        selectedCandidateIDs.removeAll()
        cleanupScanDate = nil
        cleanupCoverage = []
        cleanupScanOutcome = nil
        defaults.removeObject(forKey: Self.cleanupScanKey)
    }

    func moveSelectedToTrash() {
        guard !isWorking else { return }
        let candidates = cleanupCandidates.filter { selectedCandidateIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }
        let originalSelectedIDs = Set(candidates.map(\.id))
        guard beginWork("Moving selected items to Trash...", cancelable: false) else { return }
        let homeDirectory = homeDirectory
        let trashItem = trashItem
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishWork() }
            let outcome = await Task.detached(priority: .utility) {
                var recovered: Int64 = 0
                var movedCount = 0
                var failures: [CleanupTrashFailure] = []
                for candidate in candidates {
                    guard Self.isSafe(candidate, homeDirectory: homeDirectory) else {
                        failures.append(CleanupTrashFailure(id: candidate.id, reason: "The path or file identity changed. Rescan before retrying."))
                        continue
                    }
                    do {
                        try trashItem(candidate.url)
                        recovered += candidate.size
                        movedCount += 1
                    } catch {
                        failures.append(CleanupTrashFailure(id: candidate.id, reason: error.localizedDescription))
                    }
                }
                return CleanupTrashResult(movedCount: movedCount, movedBytes: recovered, failures: failures)
            }.value
            self.lastRecoveredBytes = outcome.movedBytes
            self.lastTrashResult = outcome
            let failedIDs = Set(outcome.failures.map(\.id))
            let successfulIDs = originalSelectedIDs.subtracting(failedIDs)
            self.cleanupCandidates.removeAll { successfulIDs.contains($0.id) }
            self.selectedCandidateIDs = failedIDs
            self.persistCleanupScan()
            if !outcome.failures.isEmpty {
                self.errorMessage = "Could not move \(outcome.failures.count) item(s) to Trash."
            }
        }
    }

    func analyze(_ url: URL, resetBreadcrumbs: Bool = false) {
        guard beginWork("Analyzing \(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)...") else { return }
        storageIssue = nil
        let mole = molePath
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishWork() }
            do {
                let report = try await Self.runWorker {
                    if let mole {
                        return try Self.moleAnalyze(executable: mole, url: url)
                    }
                    return try Self.nativeAnalyze(url: url)
                }
                self.storageURL = url
                self.storageEntries = report.entries
                self.storageTotal = report.totalSize
                self.storageFileCount = report.totalFiles
                self.storageCountIsFiles = report.countIsFiles
                if resetBreadcrumbs || self.storageBreadcrumbs.isEmpty == true {
                    self.storageBreadcrumbs = [url]
                } else if let index = self.storageBreadcrumbs.firstIndex(of: url) {
                    self.storageBreadcrumbs = Array(self.storageBreadcrumbs.prefix(index + 1))
                } else if self.storageBreadcrumbs.last != url {
                    self.storageBreadcrumbs.append(url)
                }
            } catch is CancellationError {
                return
            } catch {
                self.storageIssue = SystemCareFileIssue(url: url, error: error)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func navigateStorage(to url: URL) {
        analyze(url)
    }

    func loadHistory() {
        guard !isWorking, let molePath else { return }
        guard beginWork("Reading Mole history...") else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishWork() }
            do {
                history = try await Self.runWorker { try Self.moleHistory(executable: molePath) }
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func installOrUpdateMole() {
        guard !isWorking else { return }
        guard let brew = Self.firstExecutable(paths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            errorMessage = "Homebrew was not found. Install Mole from its official instructions instead."
            return
        }
        guard beginWork(molePath == nil ? "Installing Mole with Homebrew..." : "Updating Mole with Homebrew...",
                        cancelable: false) else { return }
        let arguments = molePath == nil ? ["install", "mole"] : ["upgrade", "mole"]
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishWork() }
            do {
                let installation = try await Self.runWorker {
                    _ = try Self.run(executable: brew, arguments: arguments, timeout: 300)
                    return Self.detectMole()
                }
                self.applyMoleDetection(installation)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func applyMoleDetection(_ detection: MoleDetection) {
        molePath = detection.path
        moleVersion = detection.version
        supportedMolePreviews = detection.previews
        canPreviewUninstall = detection.uninstallPreview
        supportsUninstallInventory = detection.uninstallInventory
        if let error = detection.error { errorMessage = error }
    }

    func canPreview(_ operation: MoleOperation) -> Bool {
        !isWorking && molePath != nil && supportedMolePreviews.contains(operation)
    }

    func openMole(_ operation: MoleOperation, dryRun: Bool) {
        guard !isWorking, let molePath else { return }
        guard !dryRun || supportedMolePreviews.contains(operation) else {
            errorMessage = "This Mole version has no verified preview for \(operation.title). Update Mole first."
            return
        }
        openTerminal(arguments: [operation.rawValue] + (dryRun ? ["--dry-run"] : []), executable: molePath)
    }

    func uninstallUnavailableReason(for application: InstalledApplication) -> String? {
        guard molePath != nil else { return "Install Mole to review and uninstall applications." }
        guard supportsUninstallInventory else { return "Update Mole to verify the selected application before uninstalling." }
        return Self.uninstallRefusal(for: application, applications: applications)
    }

    nonisolated static func uninstallRefusal(
        for application: InstalledApplication, applications: [InstalledApplication]
    ) -> String? {
        guard !application.name.isEmpty, !application.name.hasPrefix("-"),
              application.name.rangeOfCharacter(from: .controlCharacters) == nil,
              application.name == application.url.deletingPathExtension().lastPathComponent else {
            return "The application name cannot be passed safely to Mole."
        }
        let matches = applications.filter { $0.name.lowercased() == application.name.lowercased() }
        guard matches.count == 1 else { return "More than one application has this name, or the application is missing. Refresh the list before uninstalling." }
        return matches[0].url.standardizedFileURL == application.url.standardizedFileURL
            ? nil : "The selected bundle no longer matches the application list. Refresh before uninstalling."
    }

    nonisolated static func validatedUninstallName(for application: InstalledApplication, inventory: Data) throws -> String {
        let rows = try JSONDecoder().decode([MoleUninstallApplication].self, from: inventory)
        let name = application.name.lowercased()
        let matches = rows.filter {
            $0.name.lowercased() == name || URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent.lowercased() == name
        }
        guard matches.count == 1,
              URL(fileURLWithPath: matches[0].path).standardizedFileURL == application.url.standardizedFileURL else {
            throw SystemCareCommandError.failed("Mole could not resolve this name to the selected bundle alone. Name-based uninstall is disabled.")
        }
        return application.name
    }

    func openMoleUninstall(_ application: InstalledApplication, dryRun: Bool) {
        guard !isWorking, let molePath else { return }
        if let reason = uninstallUnavailableReason(for: application) { errorMessage = reason; return }
        guard !dryRun || canPreviewUninstall else {
            errorMessage = "This Mole version has no verified uninstall preview. Update Mole first."
            return
        }
        guard beginWork("Checking the selected application...") else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishWork() }
            do {
                let name = try await Self.runWorker {
                    let liveApplications = try Self.installedApplications()
                    if let reason = Self.uninstallRefusal(for: application, applications: liveApplications) {
                        throw SystemCareCommandError.failed(reason)
                    }
                    let identity = try Self.fileIdentity(at: application.url)
                    let inventory = try Self.run(executable: molePath, arguments: ["uninstall", "--list"])
                    let name = try Self.validatedUninstallName(for: application, inventory: inventory)
                    guard try Self.fileIdentity(at: application.url) == identity else {
                        throw SystemCareCommandError.failed("The application changed during review. Refresh before uninstalling.")
                    }
                    return name
                }
                openTerminal(arguments: ["uninstall"] + (dryRun ? ["--dry-run"] : []) + [name], executable: molePath)
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openMoleWhitelist() {
        guard !isWorking, let molePath else { return }
        openTerminal(arguments: ["clean", "--whitelist"], executable: molePath)
    }

    var selectedSize: Int64 {
        cleanupCandidates.lazy
            .filter { self.selectedCandidateIDs.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    private func persistCleanupScan() {
        guard let cleanupScanDate,
              let data = try? JSONEncoder().encode(CleanupScanSnapshot(
                  scannedAt: cleanupScanDate,
                  candidates: cleanupCandidates,
                  selectedCandidateIDs: selectedCandidateIDs,
                  coverage: cleanupCoverage, outcome: cleanupScanOutcome
              )) else { return }
        defaults.set(data, forKey: Self.cleanupScanKey)
    }

    private func openTerminal(arguments: [String], executable: URL) {
        let command = ([executable.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
        let source = "#!/bin/zsh\ntrap 'rm -f -- \"$0\"' EXIT\nclear\n\(command)\nprintf '\\nPress Return to close…'\nread\n"
        Task { [weak self] in
            do {
                let script = try await Task.detached(priority: .userInitiated) {
                    try Self.makeTerminalScript(source)
                }.value
                NSWorkspace.shared.open(script)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    nonisolated private static func makeTerminalScript(_ source: String) throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPowerToys-SystemCare-\(UUID().uuidString).command")
        try Data(source.utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    nonisolated static let cleanupChildLimit = 500

    nonisolated static func cleanupReport(
        for categories: Set<SystemCareCategoryID>, homeDirectory: URL,
        childLimit: Int = cleanupChildLimit
    ) throws -> CleanupScanReport {
        var candidates: [CleanupCandidate] = []
        var coverage: [CleanupRootCoverage] = []
        for category in SystemCareCategoryID.allCases where categories.contains(category) {
            try Task.checkCancellation()
            let root = cleanupRoot(for: category, homeDirectory: homeDirectory)
            var location = CleanupRootCoverage(category: category, root: root)
            do {
                let rootIdentity = try fileIdentity(at: root)
                let children = try FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ).sorted { $0.path < $1.path }
                location.didReadRoot = true
                location.isTruncated = children.count > max(childLimit, 0)
                for url in children.prefix(max(childLimit, 0)) {
                    try Task.checkCancellation()
                    location.examinedCount += 1
                    if category == .installers,
                       !["dmg", "pkg", "mpkg", "iso", "xip"].contains(url.pathExtension.lowercased()) { continue }
                    do {
                        let identity = try fileIdentity(at: url)
                        let size = try allocatedSize(of: url)
                        guard try fileIdentity(at: url) == identity else {
                            throw NSError(domain: "SystemCare", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: "The file changed while its size was read."
                            ])
                        }
                        candidates.append(CleanupCandidate(url: url, allowedRoot: root, category: category,
                                                           size: size, fileIdentity: identity, rootIdentity: rootIdentity))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        location.issues.append(SystemCareFileIssue(url: url, error: error))
                    }
                }
                guard try fileIdentity(at: root) == rootIdentity else {
                    throw NSError(domain: "SystemCare", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "The location changed during the scan."
                    ])
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                location.didReadRoot = false
                candidates.removeAll { $0.category == category }
                location.issues.append(SystemCareFileIssue(url: root, error: error))
            }
            coverage.append(location)
        }
        return CleanupScanReport(candidates: candidates.sorted { $0.size > $1.size }, coverage: coverage)
    }

    nonisolated static func allocatedSize(of url: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            guard let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize else {
                throw CocoaError(.fileReadUnknown)
            }
            return Int64(size)
        }
        var readError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, error in readError = error; return false }
        ) else { throw CocoaError(.fileReadUnknown) }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            try Task.checkCancellation()
            let childValues = try child.resourceValues(forKeys: keys)
            if childValues.isSymbolicLink == true {
                enumerator.skipDescendants()
            } else if childValues.isDirectory != true {
                guard let bytes = childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize else {
                    throw CocoaError(.fileReadUnknown)
                }
                let (sum, overflow) = total.addingReportingOverflow(Int64(bytes))
                guard !overflow else { throw CocoaError(.fileReadTooLarge) }
                total = sum
            }
        }
        if let readError { throw readError }
        return total
    }

    nonisolated static func cleanupRoot(for category: SystemCareCategoryID, homeDirectory: URL) -> URL {
        let path: String
        switch category {
        case .caches: path = "Library/Caches"
        case .logs: path = "Library/Logs"
        case .installers: path = "Downloads"
        case .developer: path = "Library/Developer/Xcode/DerivedData"
        }
        return homeDirectory.appendingPathComponent(path, isDirectory: true)
    }

    nonisolated static func fileIdentity(at url: URL) throws -> CleanupFileIdentity {
        guard url.isFileURL, !url.pathComponents.contains("."), !url.pathComponents.contains("..") else {
            throw NSError(domain: "SystemCare", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The file path is not an absolute, normalized file URL."
            ])
        }
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        var info = stat()
        for component in url.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            guard lstat(current.path, &info) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            guard info.st_mode & S_IFMT != S_IFLNK else {
                throw NSError(domain: "SystemCare", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Symbolic links are not allowed: \(current.path)"
                ])
            }
        }
        return CleanupFileIdentity(device: info.st_dev, inode: UInt64(info.st_ino),
                                   birthSeconds: Int64(info.st_birthtimespec.tv_sec),
                                   birthNanoseconds: Int64(info.st_birthtimespec.tv_nsec))
    }

    nonisolated static func isSafe(
        _ candidate: CleanupCandidate,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let root = cleanupRoot(for: candidate.category, homeDirectory: homeDirectory)
        let url = candidate.url
        guard url.isFileURL, candidate.allowedRoot.isFileURL,
              candidate.allowedRoot.path == root.path,
              url.path != root.path, url.deletingLastPathComponent().path == root.path,
              candidate.size >= 0,
              let identity = candidate.fileIdentity, let rootIdentity = candidate.rootIdentity,
              (try? fileIdentity(at: root)) == rootIdentity,
              (try? fileIdentity(at: url)) == identity else { return false }
        return candidate.category != .installers || ["dmg", "pkg", "mpkg", "iso", "xip"].contains(url.pathExtension.lowercased())
    }

    nonisolated private static func nativeAnalyze(url: URL) throws -> StorageReport {
        let children = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var entries: [StorageEntry] = []
        var total: Int64 = 0
        for child in children {
            try Task.checkCancellation()
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            let size = try allocatedSize(of: child)
            total += size
            entries.append(StorageEntry(
                name: child.lastPathComponent,
                url: child,
                size: size,
                isDirectory: values?.isDirectory == true
            ))
        }
        entries.sort { $0.size > $1.size }
        return StorageReport(entries: entries, totalSize: total, totalFiles: entries.count, countIsFiles: false)
    }

    nonisolated private static func moleAnalyze(executable: URL, url: URL) throws -> StorageReport {
        let data = try run(executable: executable, arguments: ["analyze", "--json", url.path])
        let report = try JSONDecoder().decode(MoleAnalyzeReport.self, from: data)
        return StorageReport(
            entries: report.entries.map {
                StorageEntry(name: $0.name, url: URL(fileURLWithPath: $0.path), size: $0.size, isDirectory: $0.isDir)
            }.sorted { $0.size > $1.size },
            totalSize: report.totalSize,
            totalFiles: report.totalFiles, countIsFiles: true
        )
    }

    nonisolated private static func moleHistory(executable: URL) throws -> [MoleHistoryItem] {
        let data = try run(executable: executable, arguments: ["history", "--json", "--limit", "100"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let rows = (root["sessions"] as? [[String: Any]] ?? []) + (root["deletions"] as? [[String: Any]] ?? [])
        return rows.map { row in
            let title = (row["operation"] ?? row["command"] ?? row["path"] ?? "Mole operation") as? String ?? "Mole operation"
            let detail = row.keys.sorted().map { "\($0): \(row[$0] ?? "")" }.joined(separator: " · ")
            return MoleHistoryItem(title: title, detail: detail)
        }
    }

    nonisolated private static func detectMole() -> MoleDetection {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/opt/homebrew/bin/mo", "/usr/local/bin/mo", "\(home)/.local/bin/mo"]
        guard let path = firstExecutable(paths: paths) else { return MoleDetection() }
        var detection = MoleDetection(path: path)
        do {
            let output = String(decoding: try run(executable: path, arguments: ["--version"], timeout: 3, maximumOutputBytes: 65_536), as: UTF8.self)
            detection.version = output.split(separator: "\n").first(where: { $0.contains("Mole version") })
                .map { $0.replacingOccurrences(of: "Mole version ", with: "") }
            for operation in MoleOperation.allCases {
                try Task.checkCancellation()
                let help = try run(executable: path, arguments: [operation.rawValue, "--help"], timeout: 3, maximumOutputBytes: 65_536)
                if String(decoding: help, as: UTF8.self).contains("--dry-run") { detection.previews.insert(operation) }
            }
            let help = String(decoding: try run(executable: path, arguments: ["uninstall", "--help"], timeout: 3, maximumOutputBytes: 65_536), as: UTF8.self)
            detection.uninstallPreview = help.contains("--dry-run")
            detection.uninstallInventory = help.contains("--list")
        } catch {
            detection.error = "Mole capabilities could not be verified: \(error.localizedDescription)"
        }
        return detection
    }

    nonisolated private static func installedApplications() throws -> [InstalledApplication] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var applications: [InstalledApplication] = []
        for root in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            try Task.checkCancellation()
            do {
                let children = try FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )
                applications += children.filter { $0.pathExtension.lowercased() == "app" }
                    .map { InstalledApplication(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            } catch {
                if SystemCareFileIssue(url: root, error: error).kind != .missing { throw error }
            }
        }
        return applications.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func firstExecutable(paths: [String]) -> URL? {
        paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    nonisolated static func run(
        executable: URL, arguments: [String], timeout: TimeInterval = 30,
        maximumOutputBytes: Int = 8 * 1_024 * 1_024
    ) throws -> Data {
        guard timeout.isFinite, timeout > 0 else { throw SystemCareCommandError.timeout }
        guard maximumOutputBytes > 0 else { throw SystemCareCommandError.outputLimit }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        for handle in [output.fileHandleForReading, errors.fileHandleForReading] {
            guard fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) != -1 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
        var data = Data()
        var errorData = Data()
        var didLaunch = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        defer {
            if didLaunch, process.isRunning {
                process.terminate()
                let killDeadline = ProcessInfo.processInfo.systemUptime + 0.25
                while process.isRunning, ProcessInfo.processInfo.systemUptime < killDeadline { usleep(10_000) }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            if didLaunch { process.waitUntilExit() }
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForReading.close()
            try? errors.fileHandleForWriting.close()
        }
        func drain(_ handle: FileHandle, into target: inout Data, otherCount: Int) throws {
            var buffer = [UInt8](repeating: 0, count: 8_192)
            while true {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw SystemCareCommandError.timeout }
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count)
                }
                if count == 0 { return }
                if count < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK { return }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                guard count <= maximumOutputBytes - target.count - otherCount else { throw SystemCareCommandError.outputLimit }
                target.append(contentsOf: buffer.prefix(count))
            }
        }
        try Task.checkCancellation()
        try process.run()
        didLaunch = true
        repeat {
            try drain(output.fileHandleForReading, into: &data, otherCount: errorData.count)
            try drain(errors.fileHandleForReading, into: &errorData, otherCount: data.count)
            if !process.isRunning { break }
            usleep(10_000)
        } while true
        process.waitUntilExit()
        // Drain bytes written between the last read and the child's exit.
        try drain(output.fileHandleForReading, into: &data, otherCount: errorData.count)
        try drain(errors.fileHandleForReading, into: &errorData, otherCount: data.count)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: (errorData.isEmpty ? data : errorData).prefix(8_192), as: UTF8.self)
            throw SystemCareCommandError.failed(message.isEmpty ? "The command failed." : message)
        }
        return data
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

nonisolated enum SystemCareCommandError: LocalizedError, Equatable {
    case timeout, outputLimit, failed(String)
    var errorDescription: String? {
        switch self {
        case .timeout: "The command timed out. Try again."
        case .outputLimit: "The command returned more data than System Care can read."
        case .failed(let reason): reason
        }
    }
}

nonisolated private struct MoleDetection: Sendable {
    var path: URL? = nil
    var version: String? = nil
    var previews: Set<MoleOperation> = []
    var uninstallPreview = false
    var uninstallInventory = false
    var error: String? = nil
}

nonisolated private struct MoleUninstallApplication: Decodable {
    let name: String
    let path: String
}

nonisolated private struct StorageReport: Sendable {
    let entries: [StorageEntry]
    let totalSize: Int64
    let totalFiles: Int
    let countIsFiles: Bool
}

nonisolated private struct MoleAnalyzeReport: Decodable, Sendable {
    nonisolated struct Entry: Decodable, Sendable {
        let name: String
        let path: String
        let size: Int64
        let isDir: Bool

        enum CodingKeys: String, CodingKey {
            case name, path, size
            case isDir = "is_dir"
        }
    }

    let entries: [Entry]
    let totalSize: Int64
    let totalFiles: Int

    enum CodingKeys: String, CodingKey {
        case entries
        case totalSize = "total_size"
        case totalFiles = "total_files"
    }
}
