import AppKit
import Foundation
import Darwin

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

nonisolated enum DiskRemoval {
    static func isAllowed(_ entry: DiskEntry, under root: URL) -> Bool {
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

    var markedEntries: [DiskEntry] { DiskRemoval.topLevel(Array(marks.values)) }
    var markedBytes: Int64 { markedEntries.reduce(0) { $0 + $1.allocatedBytes } }

    func refreshVolumes() { volumes = DiskVolume.mounted() }

    func start(_ url: URL, includeHidden: Bool) {
        cancel()
        generation += 1
        let scanGeneration = generation
        if sourceURL != url { result = nil; current = nil }
        sourceURL = url
        isScanning = true
        scannedEntries = 0
        errorMessage = nil
        operationMessage = nil
        marks = [:]
        let session = DiskScanSession { [weak self] count in
            Task { @MainActor [weak self] in
                guard self?.generation == scanGeneration else { return }
                self?.scannedEntries = count
            }
        }
        scanSession = session
        scanTask = Task { [weak self] in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try DiskExplorerScanner.scan(url, includeHidden: includeHidden, session: session)
                }.value
                guard let self, self.generation == scanGeneration else { return }
                self.result = snapshot
                self.current = snapshot.root
                self.isScanning = false
                self.scanSession = nil
                self.scanTask = nil
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
        scanSession = nil
        scanTask = nil
        isScanning = false
    }

    func leave() { cancel(); result = nil; current = nil; marks = [:] }

    func navigate(to entry: DiskEntry) {
        guard entry.kind == .directory else { return }
        current = entry
    }

    func toggleMark(_ entry: DiskEntry) {
        guard let root = result?.root.url, DiskRemoval.isAllowed(entry, under: root) else { return }
        if marks.removeValue(forKey: entry.id) != nil { return }
        guard !marks.keys.contains(where: { entry.id.hasPrefix($0 + "/") }) else { return }
        marks = marks.filter { !$0.key.hasPrefix(entry.id + "/") }
        marks[entry.id] = entry
    }

    func removeMarked(permanently: Bool, includeHidden: Bool) {
        guard let sourceURL, let root = result?.root, !isRemoving else { return }
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
