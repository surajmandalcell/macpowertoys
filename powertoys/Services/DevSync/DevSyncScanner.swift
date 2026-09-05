import CryptoKit
import Darwin
import Foundation

nonisolated struct DevSnapshot: Equatable, Sendable {
    var entries: [String: DevFileSignature]
    var excluded: [String: DevFilePolicyReason]
    var unreadablePaths: [String]
    var complete: Bool
    var collisions: [[String]]
    var includedBytes: Int64
    var excludedBytes: Int64
    var scannedAt: Date

    static var emptyDestination: DevSnapshot {
        DevSnapshot(entries: [:], excluded: [:], unreadablePaths: [], complete: true, collisions: [], includedBytes: 0, excludedBytes: 0, scannedAt: Date())
    }
}

nonisolated protocol DevPathPolicy: Sendable {
    func decide(relativePath: String, kind: DevEntryKind, size: Int64, isInsideGitDirectory: Bool) -> DevFilePolicyDecision
}

nonisolated enum DevSnapshotScanner {
    private static let hashChunkSize = 1_048_576

    nonisolated private struct FileSystemEntry: Sendable {
        var kind: DevEntryKind
        var size: UInt64
        var modificationTimeNanoseconds: Int64
        var changeTimeNanoseconds: Int64
        var mode: UInt16
        var symlinkTarget: String?
        var resourceIdentifier: Data?
    }

    nonisolated private enum ScannerError: Error {
        case changedDuringScan
    }

    nonisolated private struct ScanState {
        var entries: [String: DevFileSignature] = [:]
        var excluded: [String: DevFilePolicyReason] = [:]
        var unreadablePaths: [String] = []
        var complete = true
        var includedBytes: Int64 = 0
        var excludedBytes: Int64 = 0
    }

    static func scan(
        projectURL: URL,
        policy: DevPathPolicy,
        gitDirectoryRelativePath: String?,
        managedLinkPaths: Set<String>,
        nestedProjectPaths: Set<String> = [],
        collisionKeyCaseInsensitive: Bool,
        hashPaths: Set<String>,
        limitToPaths: Set<String>? = nil
    ) async -> DevSnapshot {
        let worker = Task.detached(priority: .userInitiated) {
            scanSynchronously(
                projectURL: projectURL,
                policy: policy,
                gitDirectoryRelativePath: gitDirectoryRelativePath,
                managedLinkPaths: managedLinkPaths,
                nestedProjectPaths: nestedProjectPaths,
                collisionKeyCaseInsensitive: collisionKeyCaseInsensitive,
                hashPaths: hashPaths,
                limitToPaths: limitToPaths
            )
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func signature(of url: URL, includeHash: Bool) throws -> DevFileSignature {
        let entry = try fileSystemEntry(at: url)
        return try signature(of: url, entry: entry, includeHash: includeHash)
    }

    static func hash(url: URL) throws -> Data {
        try Task.checkCancellation()
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }

        var fileStatus = Darwin.stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0 else { throw posixError() }
        guard fileStatus.st_mode & S_IFMT == S_IFREG else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: hashChunkSize)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if bytesRead == 0 { break }
            buffer.withUnsafeBytes {
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: $0.baseAddress, count: bytesRead))
            }
            try Task.checkCancellation()
        }
        return Data(hasher.finalize())
    }

    static func isStable(url: URL, previous: DevFileSignature, windowSeconds: Double) async -> Bool {
        let worker = Task.detached(priority: .utility) {
            guard let first = try? signature(of: url, includeHash: false),
                  stableMatches(previous, first)
            else { return false }

            if windowSeconds > 0 {
                let maximumSeconds = Double(UInt64.max / 1_000_000_000)
                let nanoseconds = UInt64(min(windowSeconds, maximumSeconds) * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return false
                }
            }

            guard let second = try? signature(of: url, includeHash: false) else { return false }
            return stableMatches(first, second)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func collisions(paths: [String], caseInsensitive: Bool) -> [[String]] {
        var groups: [String: [String]] = [:]
        var seenPaths: Set<Data> = []
        for path in paths where seenPaths.insert(Data(path.utf8)).inserted {
            let key = caseInsensitive
                ? DevRelativePath.normalizedKey(path)
                : path.precomposedStringWithCanonicalMapping
            groups[key, default: []].append(path)
        }
        return groups.values
            .filter { $0.count > 1 }
            .map { $0.sorted(by: bytewisePrecedes) }
            .sorted { lhs, rhs in
                guard let left = lhs.first, let right = rhs.first else { return lhs.count < rhs.count }
                return bytewisePrecedes(left, right)
            }
    }

    static func manifest(paths: Set<String>) -> [String] {
        var result = paths
        for path in paths {
            var current = path
            while let parent = DevRelativePath.parent(current) {
                result.insert(parent)
                current = parent
            }
        }
        return result.sorted(by: bytewisePrecedes)
    }

    static func verify(
        plannedSource: DevFileSignature,
        destinationURL: URL,
        toleranceNanoseconds: Int64,
        compareMode: Bool,
        requireHash: Bool
    ) throws -> Bool {
        let destination: DevFileSignature
        do {
            destination = try signature(of: destinationURL, includeHash: requireHash)
        } catch let error as NSError {
            if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) || error.code == Int(ENOTDIR) {
                return false
            }
            throw error
        }
        guard destination.kind == plannedSource.kind,
              destination.size == plannedSource.size,
              timesMatch(
                  plannedSource.modificationTimeNanoseconds,
                  destination.modificationTimeNanoseconds,
                  toleranceNanoseconds: toleranceNanoseconds
              )
        else { return false }

        if plannedSource.kind == .symlink,
           destination.symlinkTarget != plannedSource.symlinkTarget {
            return false
        }

        if compareMode, destination.mode != plannedSource.mode { return false }
        if requireHash, plannedSource.kind == .file {
            guard let plannedHash = plannedSource.contentHash,
                  destination.contentHash == plannedHash
            else { return false }
        }
        return true
    }

    private static func scanSynchronously(
        projectURL: URL,
        policy: DevPathPolicy,
        gitDirectoryRelativePath: String?,
        managedLinkPaths: Set<String>,
        nestedProjectPaths: Set<String>,
        collisionKeyCaseInsensitive: Bool,
        hashPaths: Set<String>,
        limitToPaths: Set<String>?
    ) -> DevSnapshot {
        var state = ScanState()
        do {
            try Task.checkCancellation()
            let root = try fileSystemEntry(at: projectURL)
            guard root.kind == .directory else {
                state.complete = false
                state.unreadablePaths.append("")
                return snapshot(from: state, caseInsensitive: collisionKeyCaseInsensitive)
            }
            let limitTargets = limitToPaths.map { Set($0.filter(DevRelativePath.isSafe)) }
            let limitMembers = limitTargets.map { Set(manifest(paths: $0)) }
            try walk(
                directoryURL: projectURL,
                relativeDirectoryPath: "",
                expectedDirectoryEntry: root,
                policy: policy,
                gitDirectoryRelativePath: gitDirectoryRelativePath,
                managedLinkPaths: managedLinkPaths,
                nestedProjectPaths: nestedProjectPaths,
                hashPaths: hashPaths,
                limitTargets: limitTargets,
                limitMembers: limitMembers,
                scanAllDescendants: limitToPaths == nil,
                state: &state
            )
        } catch is CancellationError {
            state.complete = false
        } catch {
            state.complete = false
            state.unreadablePaths.append("")
        }
        return snapshot(from: state, caseInsensitive: collisionKeyCaseInsensitive)
    }

    private static func walk(
        directoryURL: URL,
        relativeDirectoryPath: String,
        expectedDirectoryEntry: FileSystemEntry,
        policy: DevPathPolicy,
        gitDirectoryRelativePath: String?,
        managedLinkPaths: Set<String>,
        nestedProjectPaths: Set<String>,
        hashPaths: Set<String>,
        limitTargets: Set<String>?,
        limitMembers: Set<String>?,
        scanAllDescendants: Bool,
        state: inout ScanState
    ) throws {
        try Task.checkCancellation()
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [])
        } catch {
            state.complete = false
            state.unreadablePaths.append(relativeDirectoryPath)
            return
        }
        try Task.checkCancellation()

        for childURL in children {
            try Task.checkCancellation()
            let name = childURL.lastPathComponent
            let relativePath = relativeDirectoryPath.isEmpty ? name : relativeDirectoryPath + "/" + name
            let childScansAllDescendants = scanAllDescendants || limitTargets?.contains(relativePath) == true
            guard childScansAllDescendants || limitMembers?.contains(relativePath) == true else { continue }

            let entry: FileSystemEntry
            do {
                entry = try fileSystemEntry(at: childURL)
            } catch {
                state.complete = false
                state.unreadablePaths.append(relativePath)
                continue
            }

            let decision: DevFilePolicyDecision
            if DevRelativePath.isCloudSyncSystemPath(relativePath) {
                decision = .exclude(.cloudSyncInternalPath)
            } else if managedLinkPaths.contains(relativePath) {
                decision = .exclude(.managedLink)
            } else if nestedProjectPaths.contains(relativePath) {
                decision = .exclude(.separateProject)
            } else {
                decision = policy.decide(
                    relativePath: relativePath,
                    kind: entry.kind,
                    size: signedSize(entry.size),
                    isInsideGitDirectory: isInsideGitDirectory(relativePath, gitDirectoryRelativePath: gitDirectoryRelativePath)
                )
            }

            if !decision.included {
                state.excluded[relativePath] = decision.reason
                addBytes(signedSize(entry.size), to: &state.excludedBytes)
                continue
            }

            do {
                state.entries[relativePath] = try signature(of: childURL, entry: entry, includeHash: hashPaths.contains(relativePath))
                addBytes(signedSize(entry.size), to: &state.includedBytes)
            } catch {
                state.complete = false
                state.unreadablePaths.append(relativePath)
                continue
            }

            if entry.kind == .directory {
                try walk(
                    directoryURL: childURL,
                    relativeDirectoryPath: relativePath,
                    expectedDirectoryEntry: entry,
                    policy: policy,
                    gitDirectoryRelativePath: gitDirectoryRelativePath,
                    managedLinkPaths: managedLinkPaths,
                    nestedProjectPaths: nestedProjectPaths,
                    hashPaths: hashPaths,
                    limitTargets: limitTargets,
                    limitMembers: limitMembers,
                    scanAllDescendants: childScansAllDescendants,
                    state: &state
                )
            }
        }

        do {
            let currentDirectoryEntry = try fileSystemEntry(at: directoryURL)
            if !sameFileSystemEntry(expectedDirectoryEntry, currentDirectoryEntry) {
                state.complete = false
            }
        } catch {
            state.complete = false
            let path = relativeDirectoryPath.isEmpty ? "" : relativeDirectoryPath
            state.unreadablePaths.append(path)
        }
    }

    private static func snapshot(from state: ScanState, caseInsensitive: Bool) -> DevSnapshot {
        DevSnapshot(
            entries: state.entries,
            excluded: state.excluded,
            unreadablePaths: state.unreadablePaths,
            complete: state.complete,
            collisions: collisions(paths: Array(state.entries.keys), caseInsensitive: caseInsensitive),
            includedBytes: state.includedBytes,
            excludedBytes: state.excludedBytes,
            scannedAt: Date()
        )
    }

    private static func signature(of url: URL, entry: FileSystemEntry, includeHash: Bool) throws -> DevFileSignature {
        let contentHash = includeHash && entry.kind == .file ? try hash(url: url) : nil
        let xattrDigest = xattrDigest(of: url)
        if contentHash != nil {
            let currentEntry = try fileSystemEntry(at: url)
            guard sameFileSystemEntry(entry, currentEntry) else {
                throw ScannerError.changedDuringScan
            }
        }
        return DevFileSignature(
            kind: entry.kind,
            size: entry.kind == .directory ? nil : entry.size,
            modificationTimeNanoseconds: entry.modificationTimeNanoseconds,
            mode: entry.mode,
            symlinkTarget: entry.symlinkTarget,
            resourceIdentifier: entry.resourceIdentifier,
            contentHash: contentHash,
            xattrDigest: xattrDigest
        )
    }

    private static func fileSystemEntry(at url: URL) throws -> FileSystemEntry {
        var fileStatus = Darwin.stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &fileStatus)
        }
        guard result == 0 else { throw posixError() }

        let type = fileStatus.st_mode & S_IFMT
        let kind: DevEntryKind
        switch type {
        case S_IFREG: kind = .file
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symlink
        default: kind = .unsupported
        }

        let symlinkTarget = kind == .symlink ? try symlinkTarget(of: url, size: fileStatus.st_size) : nil
        let resourceIdentifier = resourceIdentifier(of: url, kind: kind, fileStatus: fileStatus)
        var confirmedStatus = Darwin.stat()
        let confirmationResult = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &confirmedStatus)
        }
        guard confirmationResult == 0 else { throw posixError() }
        guard sameFileStatus(fileStatus, confirmedStatus) else { throw ScannerError.changedDuringScan }

        return FileSystemEntry(
            kind: kind,
            size: fileStatus.st_size >= 0 ? UInt64(fileStatus.st_size) : 0,
            modificationTimeNanoseconds: Int64(fileStatus.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(fileStatus.st_mtimespec.tv_nsec),
            changeTimeNanoseconds: Int64(fileStatus.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(fileStatus.st_ctimespec.tv_nsec),
            mode: UInt16(fileStatus.st_mode & 0o7777),
            symlinkTarget: symlinkTarget,
            resourceIdentifier: resourceIdentifier
        )
    }

    private static func symlinkTarget(of url: URL, size: off_t) throws -> String {
        let maximumCapacity = Int(PATH_MAX)
        var capacity = size > 0 && size < off_t(maximumCapacity) ? Int(size) + 1 : min(256, maximumCapacity)
        while true {
            var buffer = [CChar](repeating: 0, count: capacity)
            let count = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return -1 }
                return Darwin.readlink(path, &buffer, buffer.count)
            }
            guard count >= 0 else { throw posixError() }
            if count < capacity {
                let bytes = buffer.prefix(count).map { UInt8(bitPattern: $0) }
                return String(decoding: bytes, as: UTF8.self)
            }
            guard capacity < maximumCapacity else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG))
            }
            capacity = min(capacity * 2, maximumCapacity)
        }
    }

    private static func xattrDigest(of url: URL) -> Data? {
        let path = url.path
        let size = path.withCString { listxattr($0, nil, 0, XATTR_NOFOLLOW) }
        guard size >= 0 else { return nil }
        guard size > 0 else { return Data(SHA256.hash(data: Data())) }

        var buffer = [CChar](repeating: 0, count: size)
        let count = path.withCString { pathPointer in
            buffer.withUnsafeMutableBufferPointer { bufferPointer in
                listxattr(pathPointer, bufferPointer.baseAddress, bufferPointer.count, XATTR_NOFOLLOW)
            }
        }
        guard count >= 0 else { return nil }

        var names: [String] = []
        var start = 0
        for index in 0..<count where buffer[index] == 0 {
            names.append(String(decoding: buffer[start..<index].map { UInt8(bitPattern: $0) }, as: UTF8.self))
            start = index + 1
        }

        var payload = Data()
        for name in names.sorted(by: bytewisePrecedes) {
            guard let value = xattrValue(of: path, name: name) else { continue }
            appendLength(name.utf8.count, to: &payload)
            payload.append(contentsOf: name.utf8)
            appendLength(value.count, to: &payload)
            payload.append(value)
        }
        return Data(SHA256.hash(data: payload))
    }

    private static func xattrValue(of path: String, name: String) -> Data? {
        let size = path.withCString { pathPointer in
            name.withCString { namePointer in
                getxattr(pathPointer, namePointer, nil, 0, 0, XATTR_NOFOLLOW)
            }
        }
        guard size >= 0 else { return nil }
        var value = Data(count: size)
        let count = value.withUnsafeMutableBytes { buffer in
            path.withCString { pathPointer in
                name.withCString { namePointer in
                    getxattr(pathPointer, namePointer, buffer.baseAddress, size, 0, XATTR_NOFOLLOW)
                }
            }
        }
        guard count >= 0 else { return nil }
        value.count = count
        return value
    }

    private static func resourceIdentifier(of url: URL, kind: DevEntryKind, fileStatus: stat) -> Data? {
        if kind != .symlink,
           let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let identifier = values.fileResourceIdentifier {
            if let data = identifier as? Data { return data }
            if let number = identifier as? NSNumber {
                var value = number.uint64Value.bigEndian
                return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
            }
            return Data(String(describing: identifier).utf8)
        }

        var device = UInt64(fileStatus.st_dev).bigEndian
        var inode = UInt64(fileStatus.st_ino).bigEndian
        var data = Data()
        withUnsafeBytes(of: &device) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &inode) { data.append(contentsOf: $0) }
        return data
    }

    private static func isInsideGitDirectory(_ path: String, gitDirectoryRelativePath: String?) -> Bool {
        guard let gitDirectoryRelativePath, !gitDirectoryRelativePath.isEmpty else { return false }
        return path == gitDirectoryRelativePath || path.hasPrefix(gitDirectoryRelativePath + "/")
    }

    private static func signedSize(_ size: UInt64) -> Int64 {
        size > UInt64(Int64.max) ? Int64.max : Int64(size)
    }

    private static func addBytes(_ bytes: Int64, to total: inout Int64) {
        let result = total.addingReportingOverflow(bytes)
        total = result.overflow ? Int64.max : result.partialValue
    }

    private static func appendLength(_ length: Int, to data: inout Data) {
        var value = UInt64(length).bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func timesMatch(_ lhs: Int64?, _ rhs: Int64?, toleranceNanoseconds: Int64) -> Bool {
        guard let lhs, let rhs else { return lhs == rhs }
        let tolerance = max(0, toleranceNanoseconds)
        let difference = lhs.subtractingReportingOverflow(rhs)
        guard !difference.overflow else { return false }
        return difference.partialValue >= -tolerance && difference.partialValue <= tolerance
    }

    private static func stableMatches(_ lhs: DevFileSignature, _ rhs: DevFileSignature) -> Bool {
        lhs.resourceIdentifier == rhs.resourceIdentifier
            && lhs.quickMatches(rhs, toleranceNanoseconds: 0, compareMode: true)
    }

    private static func sameFileSystemEntry(_ lhs: FileSystemEntry, _ rhs: FileSystemEntry) -> Bool {
        lhs.kind == rhs.kind
            && lhs.size == rhs.size
            && lhs.modificationTimeNanoseconds == rhs.modificationTimeNanoseconds
            && lhs.changeTimeNanoseconds == rhs.changeTimeNanoseconds
            && lhs.mode == rhs.mode
            && lhs.symlinkTarget == rhs.symlinkTarget
            && lhs.resourceIdentifier == rhs.resourceIdentifier
    }

    private static func sameFileStatus(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_mode == rhs.st_mode
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func bytewisePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }
}
