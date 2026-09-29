import AppKit
import Foundation
import Darwin
import Observation

nonisolated struct DiskVolume: Identifiable, Sendable {
    let url: URL
    let name: String
    let capacity: Int64?
    let available: Int64?

    var id: String { url.path }

    static func mounted() -> [DiskVolume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                     .volumeAvailableCapacityKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.volumeIsBrowsable != false else { return nil }
            return DiskVolume(
                url: url,
                name: values?.volumeName ?? (url.path == "/" ? "Startup Disk" : url.lastPathComponent),
                capacity: values?.volumeTotalCapacity.map(Int64.init),
                available: values?.volumeAvailableCapacity.map(Int64.init)
            )
        }.sorted { $0.url.path == "/" || ($1.url.path != "/" && $0.name < $1.name) }
    }
}

nonisolated struct DiskLiveUpdateGate: Sendable {
    static let interval: TimeInterval = 0.25
    private(set) var lastPresentation = -TimeInterval.infinity

    func delay(at uptime: TimeInterval) -> TimeInterval {
        guard uptime.isFinite else { return Self.interval }
        return max(0, Self.interval - (uptime - lastPresentation))
    }

    mutating func didPresent(at uptime: TimeInterval) { lastPresentation = uptime }
    mutating func reset() { lastPresentation = -.infinity }
}

nonisolated enum DiskRemoval {
    static func isAllowed(_ entry: DiskEntry, under root: URL) -> Bool {
        guard entry.kind != .aggregate else { return false }
        let path = entry.url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path != rootPath, path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/") else {
            return false
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard path != home, path != "/", path != "/Users", path != "/Volumes" else { return false }
        if rootPath == "/" && !path.hasPrefix(home + "/") { return false }
        let protected = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/Applications"]
        return !protected.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func topLevel(_ entries: [DiskEntry]) -> [DiskEntry] {
        let sorted = entries.sorted { $0.url.path < $1.url.path }
        var result: [DiskEntry] = []
        for entry in sorted where !(result.last.map {
            entry.url.path.hasPrefix($0.url.path + "/")
        } ?? false) {
            result.append(entry)
        }
        return result
    }

    static func remove(_ entries: [DiskEntry], under root: DiskEntry, permanently: Bool) -> (removed: Int, errors: [String]) {
        var removed = 0
        var errors: [String] = []
        var rootInfo = stat()
        guard root.url.withUnsafeFileSystemRepresentation({ path in
            path.map { lstat($0, &rootInfo) == 0 } ?? false
        }), UInt64(truncatingIfNeeded: rootInfo.st_dev) == root.device,
              UInt64(truncatingIfNeeded: rootInfo.st_ino) == root.inode else {
            return (0, ["Scan location changed. Scan again before removing files."])
        }
        let rootPath = root.url.standardizedFileURL.path
        let resolvedRoot = root.url.resolvingSymlinksInPath().standardizedFileURL.path
        for entry in topLevel(entries) {
            guard isAllowed(entry, under: root.url) else {
                errors.append("Protected path: \(entry.url.path)")
                continue
            }
            let parent = entry.url.deletingLastPathComponent()
            let expected = resolvedRoot + parent.standardizedFileURL.path.dropFirst(rootPath.count)
            guard parent.resolvingSymlinksInPath().standardizedFileURL.path == expected else {
                errors.append("Path changed since scan: \(entry.url.path)")
                continue
            }
            var current = stat()
            guard entry.url.withUnsafeFileSystemRepresentation({ path in
                path.map { lstat($0, &current) == 0 } ?? false
            }), UInt64(truncatingIfNeeded: current.st_dev) == entry.device,
                  UInt64(truncatingIfNeeded: current.st_ino) == entry.inode else {
                errors.append("Changed since scan: \(entry.url.path)")
                continue
            }
            do {
                if permanently {
                    try FileManager.default.removeItem(at: entry.url)
                } else {
                    var destination: NSURL?
                    try FileManager.default.trashItem(at: entry.url, resultingItemURL: &destination)
                }
                removed += 1
            } catch {
                errors.append("\(entry.name): \(error.localizedDescription)")
            }
        }
        return (removed, errors)
    }
}

@Observable
@MainActor
final class DiskExplorerModel {
    private(set) var volumes: [DiskVolume] = []
    private(set) var result: DiskScanResult?
    private(set) var current: DiskEntry?
    private(set) var sourceURL: URL?
    private(set) var isScanning = false
    private(set) var isRemoving = false
    private(set) var scannedEntries = 0
    private(set) var errorMessage: String?
    private(set) var operationMessage: String?
    private var scanSession: DiskScanSession?
    private var scanTask: Task<Void, Never>?
    private var generation = 0
    private(set) var marks: [String: DiskEntry] = [:]
    @ObservationIgnored private var liveUpdateGate = DiskLiveUpdateGate()
    @ObservationIgnored private var liveUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var pendingResult: DiskScanResult?
    @ObservationIgnored private var pendingEntryCount = 0
    @ObservationIgnored private var pendingScanFinished = false
    @ObservationIgnored private var presentsLiveUpdates = true

    init(preview: DiskScanResult? = nil) {
        result = preview
        current = preview?.root
        sourceURL = preview?.root.url
    }

    var markedEntries: [DiskEntry] { DiskRemoval.topLevel(Array(marks.values)) }
    var markedBytes: Int64 { markedEntries.reduce(0) { $0 + $1.allocatedBytes } }

    func refreshVolumes(read: @escaping @Sendable () -> [DiskVolume] = DiskVolume.mounted) async {
        let latest = await Task.detached(priority: .utility, operation: read).value
        guard !Task.isCancelled else { return }
        volumes = latest
    }

    func start(_ url: URL, includeHidden: Bool) {
        cancel()
        generation += 1
        let scanGeneration = generation
        result = nil
        current = nil
        sourceURL = url
        isScanning = true
        scannedEntries = 0
        errorMessage = nil
        operationMessage = nil
        marks = [:]
        liveUpdateGate.reset()
        pendingResult = nil
        pendingEntryCount = 0
        pendingScanFinished = false
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        let session = DiskScanSession()
        scanSession = session
        scanTask = Task { [weak self] in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try DiskExplorerScanner.scan(url, includeHidden: includeHidden, session: session) { [weak self] partial in
                        Task { @MainActor [weak self] in
                            self?.queueLiveUpdate(partial, entryCount: session.entryCount,
                                                  finished: false, generation: scanGeneration)
                        }
                    }
                }.value
                guard let self, self.generation == scanGeneration, self.isScanning else { return }
                self.scanSession = nil
                self.scanTask = nil
                self.queueLiveUpdate(snapshot, entryCount: session.entryCount,
                                     finished: true, generation: scanGeneration)
            } catch is CancellationError {
                guard let self, self.generation == scanGeneration else { return }
                self.isScanning = false
                self.scanTask = nil
            } catch {
                guard let self, self.generation == scanGeneration else { return }
                self.errorMessage = error.localizedDescription
                self.isScanning = false
                self.scanTask = nil
            }
        }
    }

    func cancel() {
        scanSession?.cancel()
        scanTask?.cancel()
        liveUpdateTask?.cancel()
        scanSession = nil
        scanTask = nil
        liveUpdateTask = nil
        pendingResult = nil
        pendingEntryCount = 0
        pendingScanFinished = false
        isScanning = false
    }

    func leave() { cancel(); result = nil; current = nil; marks = [:] }

    func setPresentationActive(_ active: Bool) {
        guard presentsLiveUpdates != active else { return }
        presentsLiveUpdates = active
        if active {
            scheduleLiveUpdate()
        } else {
            liveUpdateTask?.cancel()
            liveUpdateTask = nil
        }
    }

    private func queueLiveUpdate(_ snapshot: DiskScanResult, entryCount: Int,
                                 finished: Bool, generation scanGeneration: Int) {
        guard generation == scanGeneration, isScanning, result?.isComplete != true else { return }
        let latest = pendingResult?.scannedAt ?? result?.scannedAt ?? .distantPast
        guard snapshot.scannedAt >= latest else { return }
        pendingResult = snapshot
        pendingEntryCount = max(pendingEntryCount, entryCount)
        pendingScanFinished = pendingScanFinished || finished
        scheduleLiveUpdate()
    }

    private func scheduleLiveUpdate() {
        guard presentsLiveUpdates, pendingResult != nil, liveUpdateTask == nil else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let delay = liveUpdateGate.delay(at: uptime)
        guard delay > 0 else {
            presentLiveUpdate(at: uptime)
            return
        }
        liveUpdateTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.liveUpdateTask = nil
            guard self.presentsLiveUpdates else { return }
            self.presentLiveUpdate(at: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func presentLiveUpdate(at uptime: TimeInterval) {
        guard let snapshot = pendingResult else { return }
        let entryCount = pendingEntryCount
        let finished = pendingScanFinished
        pendingResult = nil
        pendingEntryCount = 0
        pendingScanFinished = false
        liveUpdateGate.didPresent(at: uptime)
        apply(snapshot)
        scannedEntries = entryCount
        if finished {
            isScanning = false
            scanSession = nil
            scanTask = nil
        }
    }

    private func apply(_ snapshot: DiskScanResult) {
        let route = current.flatMap { current in
            result.flatMap { current.identityRoute(from: $0.root.id) }
        } ?? []
        result = snapshot
        var node = snapshot.root
        for id in route.dropFirst() {
            guard let next = node.children.first(where: { $0.id == id }) else { break }
            node = next
        }
        current = node
    }

    func navigate(to entry: DiskEntry) {
        guard entry.kind == .directory else { return }
        current = entry
    }

    func toggleMark(_ entry: DiskEntry) {
        guard let result, result.isComplete,
              entry.kind != .aggregate,
              DiskRemoval.isAllowed(entry, under: result.root.url) else { return }
        if marks.removeValue(forKey: entry.id) != nil { return }
        guard !marks.values.contains(where: { entry.isDescendant(of: $0) }) else { return }
        marks = marks.filter { !$0.value.isDescendant(of: entry) }
        marks[entry.id] = entry
    }

    func removeMarked(permanently: Bool, includeHidden: Bool) {
        guard let sourceURL, let result, result.isComplete, !isRemoving else { return }
        let root = result.root
        let entries = markedEntries
        guard !entries.isEmpty else { return }
        let removalGeneration = generation
        isRemoving = true
        errorMessage = nil
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                DiskRemoval.remove(entries, under: root, permanently: permanently)
            }.value
            guard let self else { return }
            self.isRemoving = false
            if outcome.removed > 0 && self.generation == removalGeneration {
                self.start(sourceURL, includeHidden: includeHidden)
            }
            self.errorMessage = outcome.errors.isEmpty ? nil : outcome.errors.joined(separator: "\n")
            self.operationMessage = outcome.removed > 0
                ? "\(outcome.removed) item\(outcome.removed == 1 ? "" : "s") \(permanently ? "deleted" : "moved to Trash")."
                : nil
        }
    }
}
