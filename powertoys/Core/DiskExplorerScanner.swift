import Foundation
import Darwin

nonisolated enum DiskEntryKind: Sendable {
    case directory
    case file
    case symbolicLink
    case other
}

nonisolated final class DiskEntry: Identifiable, @unchecked Sendable {
    let url: URL
    let kind: DiskEntryKind
    let allocatedBytes: Int64
    let apparentBytes: Int64
    let fileCount: Int
    let directoryCount: Int
    let modifiedAt: Date
    let device: UInt64
    let inode: UInt64
    let children: [DiskEntry]

    var id: String { url.path }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }

    init(url: URL, kind: DiskEntryKind, allocatedBytes: Int64, apparentBytes: Int64,
         fileCount: Int, directoryCount: Int, modifiedAt: Date, device: UInt64,
         inode: UInt64, children: [DiskEntry] = []) {
        self.url = url
        self.kind = kind
        self.allocatedBytes = allocatedBytes
        self.apparentBytes = apparentBytes
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.modifiedAt = modifiedAt
        self.device = device
        self.inode = inode
        self.children = children
    }

    func bytes(apparent: Bool) -> Int64 { apparent ? apparentBytes : allocatedBytes }
}

nonisolated struct DiskScanResult: Sendable {
    let root: DiskEntry
    let largestFiles: [DiskEntry]
    let unreadableCount: Int
    let skippedVolumeCount: Int
    let scannedAt: Date
    let isComplete: Bool
}

nonisolated final class DiskScanSession: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var scannedEntries = 0
    private var lastReport = Date.distantPast
    private let report: @Sendable (Int) -> Void

    init(report: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.report = report
    }

    func cancel() { lock.withLock { stopped = true } }
    var isCancelled: Bool { lock.withLock { stopped } }

    @discardableResult func counted() -> Bool {
        let count: Int? = lock.withLock {
            scannedEntries += 1
            guard Date().timeIntervalSince(lastReport) > 0.2 else { return nil }
            lastReport = Date()
            return scannedEntries
        }
        if let count { report(count); return true }
        return false
    }
}

nonisolated enum DiskExplorerScanner {
    private struct FileID: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    private struct PreviewNode {
        let url: URL
        let kind: DiskEntryKind
        let device: UInt64
        let inode: UInt64
        var allocatedBytes: Int64 = 0
        var apparentBytes: Int64 = 0
        var fileCount = 0
        var directoryCount = 0
        var modifiedAt: Date

        init(_ url: URL, info: stat) {
            self.url = url
            kind = DiskExplorerScanner.kind(for: info)
            device = UInt64(truncatingIfNeeded: info.st_dev)
            inode = UInt64(truncatingIfNeeded: info.st_ino)
            modifiedAt = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        }

        mutating func include(_ entry: DiskEntry, allocated: Int64, apparent: Int64) {
            allocatedBytes += allocated
            apparentBytes += apparent
            fileCount += entry.kind == .directory ? 0 : 1
            directoryCount += entry.kind == .directory ? 1 : 0
            modifiedAt = max(modifiedAt, entry.modifiedAt)
        }

        func snapshot(children: [DiskEntry] = []) -> DiskEntry {
            DiskEntry(url: url, kind: kind, allocatedBytes: allocatedBytes,
                      apparentBytes: apparentBytes, fileCount: fileCount,
                      directoryCount: directoryCount, modifiedAt: modifiedAt,
                      device: device, inode: inode, children: children)
        }
    }

    private final class State: @unchecked Sendable {
        let session: DiskScanSession
        let allowedDevices: Set<UInt64>
        let includeHidden: Bool
        let skipDataMount: Bool
        let rootURL: URL
        let rootInfo: stat
        let progress: @Sendable (DiskScanResult) -> Void
        private let lock = NSLock()
        private var hardLinks = Set<FileID>()
        private(set) var unreadableCount = 0
        private(set) var skippedVolumeCount = 0
        private var topOrder: [String] = []
        private var topNodes: [String: PreviewNode] = [:]
        private var secondNodes: [String: [String: PreviewNode]] = [:]
        private var completedTop: [String: DiskEntry] = [:]
        private var largest: [DiskEntry] = []
        private var lastSnapshot = Date.distantPast

        init(session: DiskScanSession, allowedDevices: Set<UInt64>, includeHidden: Bool,
             skipDataMount: Bool, rootURL: URL, rootInfo: stat,
             progress: @escaping @Sendable (DiskScanResult) -> Void) {
            self.session = session
            self.allowedDevices = allowedDevices
            self.includeHidden = includeHidden
            self.skipDataMount = skipDataMount
            self.rootURL = rootURL
            self.rootInfo = rootInfo
            self.progress = progress
        }

        func countUnreadable() { lock.withLock { unreadableCount += 1 } }
        func countSkippedVolume() { lock.withLock { skippedVolumeCount += 1 } }
        func isFirstHardLink(_ info: stat) -> Bool {
            guard info.st_nlink > 1, info.st_mode & S_IFMT == S_IFREG else { return true }
            return lock.withLock {
                hardLinks.insert(FileID(
                    device: UInt64(truncatingIfNeeded: info.st_dev),
                    inode: UInt64(truncatingIfNeeded: info.st_ino)
                )).inserted
            }
        }

        func registerTop(_ children: [(URL, stat)]) {
            lock.withLock {
                topOrder = children.map { $0.0.path }
                for (url, info) in children { topNodes[url.path] = PreviewNode(url, info: info) }
            }
        }

        func registerSecond(_ children: [(URL, stat)], under top: String) {
            lock.withLock {
                var nodes = secondNodes[top] ?? [:]
                for (url, info) in children { nodes[url.path] = PreviewNode(url, info: info) }
                secondNodes[top] = nodes
            }
        }

        func record(_ entry: DiskEntry, ownAllocated: Int64, ownApparent: Int64,
                    top: String, second: String?) {
            lock.withLock {
                topNodes[top]?.include(entry, allocated: ownAllocated, apparent: ownApparent)
                if let second { secondNodes[top]?[second]?.include(entry, allocated: ownAllocated, apparent: ownApparent) }
                if entry.kind == .file && entry.allocatedBytes > 0 &&
                   (largest.count < 100 || entry.allocatedBytes > largest.last!.allocatedBytes) {
                    let index = largest.firstIndex { $0.allocatedBytes < entry.allocatedBytes } ?? largest.count
                    largest.insert(entry, at: index)
                    if largest.count > 100 { largest.removeLast() }
                }
            }
        }

        func completed(_ entry: DiskEntry) {
            let first = lock.withLock {
                completedTop[entry.id] = entry
                return completedTop.count == 1
            }
            publish(force: first)
        }

        func publish(force: Bool = false) {
            let snapshot: DiskScanResult? = lock.withLock {
                guard !session.isCancelled else { return nil }
                let now = Date()
                guard force || now.timeIntervalSince(lastSnapshot) >= 0.2 else { return nil }
                lastSnapshot = now
                let children = topOrder.compactMap { key -> DiskEntry? in
                    if let complete = completedTop[key] { return complete }
                    guard let node = topNodes[key] else { return nil }
                    let second = (secondNodes[key] ?? [:]).values.map { $0.snapshot() }
                        .sorted { $0.allocatedBytes > $1.allocatedBytes }
                    return node.snapshot(children: second)
                }.sorted { $0.allocatedBytes > $1.allocatedBytes }
                let root = DiskEntry(
                    url: rootURL, kind: .directory,
                    allocatedBytes: max(0, Int64(rootInfo.st_blocks) * 512) + children.reduce(0) { $0 + $1.allocatedBytes },
                    apparentBytes: max(0, Int64(rootInfo.st_size)) + children.reduce(0) { $0 + $1.apparentBytes },
                    fileCount: children.reduce(0) { $0 + $1.fileCount },
                    directoryCount: 1 + children.reduce(0) { $0 + $1.directoryCount },
                    modifiedAt: children.reduce(Date(timeIntervalSince1970: TimeInterval(rootInfo.st_mtimespec.tv_sec))) {
                        max($0, $1.modifiedAt)
                    },
                    device: UInt64(truncatingIfNeeded: rootInfo.st_dev),
                    inode: UInt64(truncatingIfNeeded: rootInfo.st_ino), children: children
                )
                return DiskScanResult(root: root, largestFiles: largest,
                                      unreadableCount: unreadableCount,
                                      skippedVolumeCount: skippedVolumeCount,
                                      scannedAt: now, isComplete: false)
            }
            if let snapshot { progress(snapshot) }
        }

        var finish: (unreadable: Int, skipped: Int, largest: [DiskEntry]) {
            lock.withLock { (unreadableCount, skippedVolumeCount, largest) }
        }
    }

    static func scan(_ url: URL, includeHidden: Bool = true,
                     session: DiskScanSession = DiskScanSession(),
                     progress: @escaping @Sendable (DiskScanResult) -> Void = { _ in }) throws -> DiskScanResult {
        let rootURL = url.standardizedFileURL
        var info = stat()
        guard rootURL.withUnsafeFileSystemRepresentation({ path in
            path.map { lstat($0, &info) == 0 } ?? false
        }) else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let isStartupDisk = rootURL.path == "/"
        var devices: Set<UInt64> = [UInt64(truncatingIfNeeded: info.st_dev)]
        if isStartupDisk {
            var dataInfo = stat()
            if lstat("/System/Volumes/Data", &dataInfo) == 0 {
                devices.insert(UInt64(truncatingIfNeeded: dataInfo.st_dev))
            }
        }
        let state = State(session: session, allowedDevices: devices,
                          includeHidden: includeHidden, skipDataMount: isStartupDisk,
                          rootURL: rootURL, rootInfo: info, progress: progress)
        let children = readChildren(at: rootURL, state: state)
        state.registerTop(children)
        state.publish(force: true)
        var scanned: [DiskEntry] = []
        let resultLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: min(4, children.count)) { lane in
            for index in stride(from: lane, to: children.count, by: min(4, children.count)) {
                if state.session.isCancelled { return }
                let (child, childInfo) = children[index]
                if let node = walk(child, info: childInfo, state: state,
                                   top: child.path, second: nil) {
                    resultLock.withLock { scanned.append(node) }
                    state.completed(node)
                }
            }
        }
        if session.isCancelled { throw CancellationError() }
        let root = entry(rootURL, info: info, children: scanned, state: state)
        let counts = state.finish
        return DiskScanResult(root: root, largestFiles: counts.largest, unreadableCount: counts.unreadable,
                              skippedVolumeCount: counts.skipped, scannedAt: Date(), isComplete: true)
    }

    private static func walk(_ url: URL, info: stat, state: State,
                             top: String, second: String?) -> DiskEntry? {
        guard !state.session.isCancelled else { return nil }
        let isDirectory = info.st_mode & S_IFMT == S_IFDIR
        let childInfo = isDirectory ? readChildren(at: url, state: state) : []
        if second == nil && isDirectory { state.registerSecond(childInfo, under: top) }
        let children = childInfo.compactMap { child, info in
            walk(child, info: info, state: state, top: top, second: second ?? child.path)
        }
        let node = entry(url, info: info, children: children, state: state,
                         top: top, second: second)
        if state.session.counted() { state.publish() }
        return node
    }

    private static func readChildren(at url: URL, state: State) -> [(URL, stat)] {
        guard let directory = url.withUnsafeFileSystemRepresentation({ $0.flatMap(opendir) }) else {
            state.countUnreadable()
            return []
        }
        defer { closedir(directory) }
        var result: [(URL, stat)] = []
        while let item = readdir(directory) {
            if state.session.isCancelled { break }
            let name = withUnsafePointer(to: &item.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." || (!state.includeHidden && name.hasPrefix(".")) { continue }
            let child = url.appendingPathComponent(name)
            if state.skipDataMount && child.path == "/System/Volumes/Data" { continue }
            var info = stat()
            let resultCode = name.withCString { fstatat(dirfd(directory), $0, &info, AT_SYMLINK_NOFOLLOW) }
            guard resultCode == 0 else {
                state.countUnreadable()
                continue
            }
            guard state.allowedDevices.contains(UInt64(truncatingIfNeeded: info.st_dev)) else {
                state.countSkippedVolume()
                continue
            }
            result.append((child, info))
        }
        return result
    }

    private static func kind(for info: stat) -> DiskEntryKind {
        switch info.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .file
        case S_IFLNK: .symbolicLink
        default: .other
        }
    }

    private static func entry(_ url: URL, info: stat, children: [DiskEntry],
                              state: State, top: String? = nil, second: String? = nil) -> DiskEntry {
        let kind = kind(for: info)
        let countSize = state.isFirstHardLink(info)
        let ownAllocated = countSize ? max(0, Int64(info.st_blocks) * 512) : 0
        let ownApparent = countSize ? max(0, Int64(info.st_size)) : 0
        var allocated = ownAllocated
        var apparent = ownApparent
        var files = kind == .directory ? 0 : 1
        var directories = kind == .directory ? 1 : 0
        var modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        for child in children {
            allocated += child.allocatedBytes
            apparent += child.apparentBytes
            files += child.fileCount
            directories += child.directoryCount
            modified = max(modified, child.modifiedAt)
        }
        let node = DiskEntry(
            url: url,
            kind: kind,
            allocatedBytes: allocated,
            apparentBytes: apparent,
            fileCount: files,
            directoryCount: directories,
            modifiedAt: modified,
            device: UInt64(truncatingIfNeeded: info.st_dev),
            inode: UInt64(truncatingIfNeeded: info.st_ino),
            children: children.sorted { $0.allocatedBytes > $1.allocatedBytes }
        )
        if let top {
            state.record(node, ownAllocated: ownAllocated, ownApparent: ownApparent,
                         top: top, second: second)
        }
        return node
    }
}
