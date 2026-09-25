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

    func counted() {
        let count: Int? = lock.withLock {
            scannedEntries += 1
            guard Date().timeIntervalSince(lastReport) > 0.2 else { return nil }
            lastReport = Date()
            return scannedEntries
        }
        if let count { report(count) }
    }
}

nonisolated enum DiskExplorerScanner {
    private struct FileID: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    private final class State: @unchecked Sendable {
        let session: DiskScanSession
        let allowedDevices: Set<UInt64>
        let includeHidden: Bool
        let skipDataMount: Bool
        private let lock = NSLock()
        private var hardLinks = Set<FileID>()
        private(set) var unreadableCount = 0
        private(set) var skippedVolumeCount = 0

        init(session: DiskScanSession, allowedDevices: Set<UInt64>, includeHidden: Bool,
             skipDataMount: Bool) {
            self.session = session
            self.allowedDevices = allowedDevices
            self.includeHidden = includeHidden
            self.skipDataMount = skipDataMount
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

        var counts: (Int, Int) { lock.withLock { (unreadableCount, skippedVolumeCount) } }
    }

    static func scan(_ url: URL, includeHidden: Bool = true,
                     session: DiskScanSession = DiskScanSession()) throws -> DiskScanResult {
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
                          includeHidden: includeHidden, skipDataMount: isStartupDisk)
        let children = readChildren(at: rootURL, state: state)
        var scanned: [DiskEntry] = []
        let resultLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: min(4, children.count)) { lane in
            for index in stride(from: lane, to: children.count, by: min(4, children.count)) {
                if state.session.isCancelled { return }
                let (child, childInfo) = children[index]
                if let node = walk(child, info: childInfo, state: state) {
                    resultLock.withLock { scanned.append(node) }
                }
            }
        }
        if session.isCancelled { throw CancellationError() }
        let root = entry(rootURL, info: info, children: scanned, state: state)
        let (unreadable, skipped) = state.counts
        return DiskScanResult(root: root, largestFiles: largestFiles(in: root), unreadableCount: unreadable,
                              skippedVolumeCount: skipped, scannedAt: Date())
    }

    private static func largestFiles(in root: DiskEntry) -> [DiskEntry] {
        var stack = [root]
        var largest: [DiskEntry] = []
        while let entry = stack.popLast() {
            if entry.kind == .directory {
                stack.append(contentsOf: entry.children)
            } else if entry.kind == .file && entry.allocatedBytes > 0 &&
                        (largest.count < 20 || entry.allocatedBytes > largest.last!.allocatedBytes) {
                let index = largest.firstIndex { $0.allocatedBytes < entry.allocatedBytes } ?? largest.count
                largest.insert(entry, at: index)
                if largest.count > 20 { largest.removeLast() }
            }
        }
        return largest
    }

    private static func walk(_ url: URL, info: stat, state: State) -> DiskEntry? {
        guard !state.session.isCancelled else { return nil }
        let isDirectory = info.st_mode & S_IFMT == S_IFDIR
        let children = isDirectory
            ? readChildren(at: url, state: state).compactMap { child, childInfo in
                walk(child, info: childInfo, state: state)
            }
            : []
        state.session.counted()
        return entry(url, info: info, children: children, state: state)
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

    private static func entry(_ url: URL, info: stat, children: [DiskEntry],
                              state: State) -> DiskEntry {
        let kind: DiskEntryKind = switch info.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .file
        case S_IFLNK: .symbolicLink
        default: .other
        }
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
        return DiskEntry(
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
    }
}
