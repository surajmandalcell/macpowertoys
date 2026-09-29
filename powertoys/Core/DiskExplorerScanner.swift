import Foundation
import Darwin

nonisolated enum DiskEntryKind: Sendable {
    case directory
    case file
    case symbolicLink
    case other
    case aggregate
}

nonisolated final class DiskEntry: Identifiable, @unchecked Sendable {
    let id: String
    let kind: DiskEntryKind
    private let storedName: String
    private weak var parent: DiskEntry?
    private let rootURL: URL?
    private let ownAllocatedBytes: Int64
    private let ownApparentBytes: Int64
    private let ownFileCount: UInt64
    private let ownDirectoryCount: UInt64
    private let ownModifiedSeconds: Int64
    private var totalAllocatedBytes: Int64
    private var totalApparentBytes: Int64
    private var totalFileCount: UInt64
    private var totalDirectoryCount: UInt64
    private var newestModifiedSeconds: Int64
    private let deviceID: UInt32
    private let inodeID: UInt64
    private var childStorage: [DiskEntry]

    var url: URL {
        if let parent { return parent.url.appendingPathComponent(storedName) }
        return rootURL ?? URL(fileURLWithPath: storedName)
    }

    var name: String { storedName }
    var allocatedBytes: Int64 { totalAllocatedBytes }
    var apparentBytes: Int64 { totalApparentBytes }
    var fileCount: Int { Int(totalFileCount) }
    var directoryCount: Int { Int(totalDirectoryCount) }
    var modifiedAt: Date { Date(timeIntervalSince1970: TimeInterval(newestModifiedSeconds)) }
    var device: UInt64 { UInt64(deviceID) }
    var inode: UInt64 { inodeID }
    var children: [DiskEntry] { childStorage }
    var parentEntry: DiskEntry? { parent }

    init(url: URL, kind: DiskEntryKind, allocatedBytes: Int64, apparentBytes: Int64,
         fileCount: Int, directoryCount: Int, modifiedAt: Date, device: UInt64,
         inode: UInt64, children: [DiskEntry] = []) {
        let standardized = url.standardizedFileURL
        let component = standardized.lastPathComponent
        storedName = component.isEmpty ? standardized.path : component
        parent = nil
        rootURL = standardized
        self.kind = kind
        id = Self.makeID(name: standardized.path, parent: nil, kind: kind,
                         device: device, inode: inode)
        ownAllocatedBytes = allocatedBytes
        ownApparentBytes = apparentBytes
        ownFileCount = UInt64(fileCount)
        ownDirectoryCount = UInt64(directoryCount)
        ownModifiedSeconds = Self.seconds(modifiedAt)
        totalAllocatedBytes = allocatedBytes
        totalApparentBytes = apparentBytes
        totalFileCount = UInt64(fileCount)
        totalDirectoryCount = UInt64(directoryCount)
        newestModifiedSeconds = Self.seconds(modifiedAt)
        deviceID = UInt32(truncatingIfNeeded: device)
        inodeID = inode
        childStorage = children
        children.forEach { $0.parent = self }
    }

    fileprivate init(name: String, kind: DiskEntryKind, parent: DiskEntry?, rootURL: URL? = nil,
                     allocatedBytes: Int64, apparentBytes: Int64, fileCount: UInt64,
                     directoryCount: UInt64, modifiedSeconds: Int64, device: UInt64,
                     inode: UInt64, children: [DiskEntry] = []) {
        storedName = name
        self.parent = parent
        self.rootURL = rootURL
        self.kind = kind
        id = Self.makeID(name: kind == .aggregate ? "\0aggregate" : name,
                         parent: parent, kind: kind, device: device, inode: inode)
        ownAllocatedBytes = allocatedBytes
        ownApparentBytes = apparentBytes
        ownFileCount = fileCount
        ownDirectoryCount = directoryCount
        ownModifiedSeconds = modifiedSeconds
        totalAllocatedBytes = allocatedBytes
        totalApparentBytes = apparentBytes
        totalFileCount = fileCount
        totalDirectoryCount = directoryCount
        newestModifiedSeconds = modifiedSeconds
        deviceID = UInt32(truncatingIfNeeded: device)
        inodeID = inode
        childStorage = children
        children.forEach { $0.parent = self }
    }

    fileprivate init(copying entry: DiskEntry, parent: DiskEntry?) {
        storedName = entry.storedName
        self.parent = parent
        rootURL = entry.rootURL
        id = entry.id
        kind = entry.kind
        ownAllocatedBytes = entry.ownAllocatedBytes
        ownApparentBytes = entry.ownApparentBytes
        ownFileCount = entry.ownFileCount
        ownDirectoryCount = entry.ownDirectoryCount
        ownModifiedSeconds = entry.ownModifiedSeconds
        totalAllocatedBytes = entry.totalAllocatedBytes
        totalApparentBytes = entry.totalApparentBytes
        totalFileCount = entry.totalFileCount
        totalDirectoryCount = entry.totalDirectoryCount
        newestModifiedSeconds = entry.newestModifiedSeconds
        deviceID = entry.deviceID
        inodeID = entry.inodeID
        childStorage = []
    }

    func bytes(apparent: Bool) -> Int64 { apparent ? apparentBytes : allocatedBytes }

    func identityRoute(from rootID: String) -> [String]? {
        var route: [String] = []
        var node: DiskEntry? = self
        while let current = node {
            route.append(current.id)
            if current.id == rootID { return route.reversed() }
            node = current.parent
        }
        return nil
    }

    func isDescendant(of ancestor: DiskEntry) -> Bool {
        var node = parent
        while let current = node {
            if current.id == ancestor.id { return true }
            node = current.parent
        }
        return false
    }

    func replaceChildren(_ children: [DiskEntry]) {
        let oldAllocated = totalAllocatedBytes
        let oldApparent = totalApparentBytes
        let oldFiles = totalFileCount
        let oldDirectories = totalDirectoryCount
        childStorage = children.sorted { left, right in
            left.allocatedBytes == right.allocatedBytes ? left.name < right.name :
                left.allocatedBytes > right.allocatedBytes
        }
        childStorage.forEach { $0.parent = self }
        totalAllocatedBytes = ownAllocatedBytes + childStorage.reduce(0) { $0 + $1.totalAllocatedBytes }
        totalApparentBytes = ownApparentBytes + childStorage.reduce(0) { $0 + $1.totalApparentBytes }
        totalFileCount = ownFileCount + childStorage.reduce(0) { $0 + $1.totalFileCount }
        totalDirectoryCount = ownDirectoryCount + childStorage.reduce(0) { $0 + $1.totalDirectoryCount }
        newestModifiedSeconds = childStorage.reduce(ownModifiedSeconds) {
            max($0, $1.newestModifiedSeconds)
        }
        var ancestor = parent
        while let node = ancestor {
            node.totalAllocatedBytes += totalAllocatedBytes - oldAllocated
            node.totalApparentBytes += totalApparentBytes - oldApparent
            if totalFileCount >= oldFiles {
                node.totalFileCount += totalFileCount - oldFiles
            } else {
                node.totalFileCount -= oldFiles - totalFileCount
            }
            if totalDirectoryCount >= oldDirectories {
                node.totalDirectoryCount += totalDirectoryCount - oldDirectories
            } else {
                node.totalDirectoryCount -= oldDirectories - totalDirectoryCount
            }
            node.newestModifiedSeconds = max(node.newestModifiedSeconds, newestModifiedSeconds)
            ancestor = node.parent
        }
    }

    fileprivate func sortChildren() {
        childStorage.sort { left, right in
            left.allocatedBytes == right.allocatedBytes ? left.name < right.name :
                left.allocatedBytes > right.allocatedBytes
        }
    }

    fileprivate func snapshot(parent: DiskEntry?, depth: Int) -> DiskEntry {
        let copy = DiskEntry(copying: self, parent: parent)
        if depth > 0 {
            copy.childStorage = childStorage.map { $0.snapshot(parent: copy, depth: depth - 1) }
        }
        return copy
    }

    fileprivate func setSnapshotChildren(_ children: [DiskEntry]) {
        childStorage = children
    }

    private static func seconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.towardZero))
    }

    private static func makeID(name: String, parent: DiskEntry?, kind: DiskEntryKind,
                               device: UInt64, inode: UInt64) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        for byte in parent?.id.utf8 ?? "".utf8 { mix(byte) }
        for shift in stride(from: 0, to: 64, by: 8) { mix(UInt8(truncatingIfNeeded: device >> shift)) }
        for shift in stride(from: 0, to: 64, by: 8) { mix(UInt8(truncatingIfNeeded: inode >> shift)) }
        for byte in name.utf8 { mix(byte) }
        let kindByte: UInt8 = switch kind {
        case .directory: 1
        case .file: 2
        case .symbolicLink: 3
        case .other: 4
        case .aggregate: 5
        }
        mix(kindByte)
        return String(hash, radix: 16)
    }
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
    var entryCount: Int { lock.withLock { scannedEntries } }

    @discardableResult func counted() -> Bool {
        let count: Int? = lock.withLock {
            guard !stopped else { return nil }
            scannedEntries += 1
            guard Date().timeIntervalSince(lastReport) > 0.2 else { return nil }
            lastReport = Date()
            return scannedEntries
        }
        guard let count else { return false }
        report(count)
        return true
    }
}

nonisolated private struct DiskEntryHeap {
    let limit: Int
    private(set) var entries: [DiskEntry] = []

    mutating func insert(_ entry: DiskEntry) -> (accepted: Bool, removed: DiskEntry?) {
        guard limit > 0 else { return (false, nil) }
        if entries.count < limit {
            entries.append(entry)
            siftUp(from: entries.count - 1)
            return (true, nil)
        }
        guard Self.higherPriority(entry, than: entries[0]) else { return (false, nil) }
        let removed = entries[0]
        entries[0] = entry
        siftDown(from: 0)
        return (true, removed)
    }

    var sortedEntries: [DiskEntry] {
        entries.sorted { left, right in
            if left.allocatedBytes != right.allocatedBytes {
                return left.allocatedBytes > right.allocatedBytes
            }
            if left.apparentBytes != right.apparentBytes {
                return left.apparentBytes > right.apparentBytes
            }
            return left.name < right.name
        }
    }

    private static func higherPriority(_ left: DiskEntry, than right: DiskEntry) -> Bool {
        if left.allocatedBytes != right.allocatedBytes {
            return left.allocatedBytes > right.allocatedBytes
        }
        if left.apparentBytes != right.apparentBytes {
            return left.apparentBytes > right.apparentBytes
        }
        return left.name < right.name
    }

    private static func lowerPriority(_ left: DiskEntry, than right: DiskEntry) -> Bool {
        higherPriority(right, than: left)
    }

    private mutating func siftUp(from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.lowerPriority(entries[child], than: entries[parent]) else { return }
            entries.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            guard left < entries.count else { return }
            let right = left + 1
            let child = right < entries.count && Self.lowerPriority(entries[right], than: entries[left])
                ? right : left
            guard Self.lowerPriority(entries[child], than: entries[parent]) else { return }
            entries.swapAt(parent, child)
            parent = child
        }
    }
}

nonisolated struct DiskDirectoryAccumulator {
    private let parent: DiskEntry
    private var retainedFiles: DiskEntryHeap
    private var largestFiles = DiskEntryHeap(limit: 100)
    private var foldedAllocatedBytes: Int64 = 0
    private var foldedApparentBytes: Int64 = 0
    private var foldedFileCount: UInt64 = 0
    private var foldedModifiedSeconds = Int64.min

    init(parent: DiskEntry, fileLimit: Int = 64) {
        self.parent = parent
        retainedFiles = DiskEntryHeap(limit: fileLimit)
    }

    mutating func add(_ entry: DiskEntry) {
        let retained = retainedFiles.insert(entry)
        if retained.accepted {
            if let removed = retained.removed { fold(removed) }
        } else {
            fold(entry)
        }
        if entry.kind == .file && entry.allocatedBytes > 0 {
            _ = largestFiles.insert(entry)
        }
    }

    var children: [DiskEntry] {
        var result = retainedFiles.sortedEntries
        guard foldedFileCount > 0 else { return result }
        result.append(DiskEntry(
            name: "\(foldedFileCount) smaller files",
            kind: .aggregate,
            parent: parent,
            allocatedBytes: foldedAllocatedBytes,
            apparentBytes: foldedApparentBytes,
            fileCount: foldedFileCount,
            directoryCount: 0,
            modifiedSeconds: foldedModifiedSeconds,
            device: parent.device,
            inode: 0
        ))
        return result
    }

    var largestCandidates: [DiskEntry] { largestFiles.sortedEntries }

    private mutating func fold(_ entry: DiskEntry) {
        foldedAllocatedBytes += entry.allocatedBytes
        foldedApparentBytes += entry.apparentBytes
        foldedFileCount += UInt64(entry.fileCount)
        foldedModifiedSeconds = max(
            foldedModifiedSeconds,
            Int64(entry.modifiedAt.timeIntervalSince1970.rounded(.towardZero))
        )
    }
}

nonisolated enum DiskExplorerScanner {
    private static let retainedFilesPerDirectory = 64
    private static let largestFileLimit = 100

    private struct FileID: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    private final class State: @unchecked Sendable {
        let session: DiskScanSession
        let allowedDevices: Set<UInt64>
        let includeHidden: Bool
        let skipDataMount: Bool
        let root: DiskEntry
        let progress: @Sendable (DiskScanResult) -> Void
        private let lock = NSLock()
        private var hardLinks = Set<FileID>()
        private var unreadableCount = 0
        private var skippedVolumeCount = 0
        private var completedTop = Set<ObjectIdentifier>()
        private var largest = DiskEntryHeap(limit: DiskExplorerScanner.largestFileLimit)
        private var largestIDs = Set<ObjectIdentifier>()
        private var lastSnapshot = Date.distantPast

        init(session: DiskScanSession, allowedDevices: Set<UInt64>, includeHidden: Bool,
             skipDataMount: Bool, root: DiskEntry,
             progress: @escaping @Sendable (DiskScanResult) -> Void) {
            self.session = session
            self.allowedDevices = allowedDevices
            self.includeHidden = includeHidden
            self.skipDataMount = skipDataMount
            self.root = root
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

        func update(_ directory: DiskEntry, directories: [DiskEntry],
                    files: DiskDirectoryAccumulator) {
            lock.withLock {
                mergeLargest(files.largestCandidates)
                directory.replaceChildren(directories + files.children)
            }
        }

        func directoryChildren(of directory: DiskEntry) -> [DiskEntry] {
            lock.withLock { directory.children.filter { $0.kind == .directory } }
        }

        func sortChildren(of directory: DiskEntry) {
            lock.withLock { directory.sortChildren() }
        }

        func completed(_ entry: DiskEntry) {
            _ = lock.withLock { completedTop.insert(ObjectIdentifier(entry)) }
            publish(force: true)
        }

        func publish(force: Bool = false) {
            let result: DiskScanResult? = lock.withLock {
                guard !session.isCancelled else { return nil }
                let now = Date()
                guard force || now.timeIntervalSince(lastSnapshot) >= 0.2 else { return nil }
                lastSnapshot = now
                let snapshotRoot = DiskEntry(copying: root, parent: nil)
                snapshotRoot.setSnapshotChildren(root.children.map { child in
                    if child.kind == .directory,
                       !completedTop.contains(ObjectIdentifier(child)) {
                        return child.snapshot(parent: snapshotRoot, depth: 1)
                    }
                    return child
                })
                return DiskScanResult(
                    root: snapshotRoot,
                    largestFiles: largest.sortedEntries,
                    unreadableCount: unreadableCount,
                    skippedVolumeCount: skippedVolumeCount,
                    scannedAt: now,
                    isComplete: false
                )
            }
            if let result { progress(result) }
        }

        var finish: (unreadable: Int, skipped: Int, largest: [DiskEntry]) {
            lock.withLock { (unreadableCount, skippedVolumeCount, largest.sortedEntries) }
        }

        private func mergeLargest(_ candidates: [DiskEntry]) {
            for candidate in candidates {
                let id = ObjectIdentifier(candidate)
                guard !largestIDs.contains(id) else { continue }
                let result = largest.insert(candidate)
                guard result.accepted else { continue }
                largestIDs.insert(id)
                if let removed = result.removed {
                    largestIDs.remove(ObjectIdentifier(removed))
                }
            }
        }
    }

    static func scan(_ url: URL, includeHidden: Bool = true,
                     session: DiskScanSession = DiskScanSession(),
                     progress: @escaping @Sendable (DiskScanResult) -> Void = { _ in }) throws -> DiskScanResult {
        let rootURL = url.standardizedFileURL
        var rootInfo = stat()
        guard rootURL.withUnsafeFileSystemRepresentation({ path in
            path.map { lstat($0, &rootInfo) == 0 } ?? false
        }) else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        guard rootInfo.st_mode & S_IFMT == S_IFDIR else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let root = entry(name: rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent,
                         parent: nil, rootURL: rootURL, info: rootInfo, countSize: true)
        let isStartupDisk = rootURL.path == "/"
        var devices: Set<UInt64> = [UInt64(truncatingIfNeeded: rootInfo.st_dev)]
        if isStartupDisk {
            var dataInfo = stat()
            if lstat("/System/Volumes/Data", &dataInfo) == 0 {
                devices.insert(UInt64(truncatingIfNeeded: dataInfo.st_dev))
            }
        }
        let state = State(session: session, allowedDevices: devices,
                          includeHidden: includeHidden, skipDataMount: isStartupDisk,
                          root: root, progress: progress)

        let topDirectories = scanContents(of: root, state: state)
        if session.isCancelled { throw CancellationError() }
        state.publish(force: true)

        for directory in topDirectories {
            _ = scanContents(of: directory, state: state)
            if session.isCancelled { throw CancellationError() }
        }
        state.publish(force: true)

        let laneCount = min(4, topDirectories.count)
        if laneCount > 0 {
            DispatchQueue.concurrentPerform(iterations: laneCount) { lane in
                for index in stride(from: lane, to: topDirectories.count, by: laneCount) {
                    if state.session.isCancelled { return }
                    scanDescendants(of: topDirectories[index], state: state)
                    if state.session.isCancelled { return }
                    state.completed(topDirectories[index])
                }
            }
        }
        if session.isCancelled { throw CancellationError() }
        state.sortChildren(of: root)
        let counts = state.finish
        return DiskScanResult(root: root, largestFiles: counts.largest,
                              unreadableCount: counts.unreadable,
                              skippedVolumeCount: counts.skipped,
                              scannedAt: Date(), isComplete: true)
    }

    private static func scanDescendants(of directory: DiskEntry, state: State) {
        let children = state.directoryChildren(of: directory)
        for child in children {
            guard !state.session.isCancelled else { return }
            _ = scanContents(of: child, state: state)
            scanDescendants(of: child, state: state)
        }
        state.sortChildren(of: directory)
    }

    private static func scanContents(of directory: DiskEntry, state: State) -> [DiskEntry] {
        let directoryURL = directory.url
        guard let handle = directoryURL.withUnsafeFileSystemRepresentation({ $0.flatMap(opendir) }) else {
            state.countUnreadable()
            return []
        }
        defer { closedir(handle) }

        var directories: [DiskEntry] = []
        var files = DiskDirectoryAccumulator(parent: directory,
                                             fileLimit: retainedFilesPerDirectory)
        while let item = readdir(handle) {
            if state.session.isCancelled { break }
            let name = withUnsafePointer(to: &item.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." || (!state.includeHidden && name.hasPrefix(".")) {
                continue
            }
            if state.skipDataMount && directoryURL.path == "/System/Volumes" && name == "Data" {
                continue
            }
            var info = stat()
            let result = name.withCString { fstatat(dirfd(handle), $0, &info, AT_SYMLINK_NOFOLLOW) }
            guard result == 0 else {
                state.countUnreadable()
                continue
            }
            guard state.allowedDevices.contains(UInt64(truncatingIfNeeded: info.st_dev)) else {
                state.countSkippedVolume()
                continue
            }

            let shouldPublish = state.session.counted()
            guard !state.session.isCancelled else { break }
            let node = entry(name: name, parent: directory, info: info,
                             countSize: state.isFirstHardLink(info))
            if node.kind == .directory {
                directories.append(node)
            } else {
                files.add(node)
            }
            if shouldPublish {
                state.update(directory, directories: directories, files: files)
                state.publish()
            }
        }
        state.update(directory, directories: directories, files: files)
        return directories
    }

    private static func kind(for info: stat) -> DiskEntryKind {
        switch info.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .file
        case S_IFLNK: .symbolicLink
        default: .other
        }
    }

    private static func entry(name: String, parent: DiskEntry?, rootURL: URL? = nil,
                              info: stat, countSize: Bool) -> DiskEntry {
        let kind = kind(for: info)
        return DiskEntry(
            name: name,
            kind: kind,
            parent: parent,
            rootURL: rootURL,
            allocatedBytes: countSize ? max(0, Int64(info.st_blocks) * 512) : 0,
            apparentBytes: countSize ? max(0, Int64(info.st_size)) : 0,
            fileCount: kind == .directory ? 0 : 1,
            directoryCount: kind == .directory ? 1 : 0,
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            device: UInt64(truncatingIfNeeded: info.st_dev),
            inode: UInt64(truncatingIfNeeded: info.st_ino)
        )
    }
}
