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
        var mode: UInt16
        var symlinkTarget: String?
        var resourceIdentifier: Data
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
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw posixError() }

        var fileStatus = Darwin.stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0 else {
            Darwin.close(descriptor)
            throw posixError()
        }
        guard fileStatus.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let fileHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var hasher = SHA256()
        while true {
            guard let chunk = try fileHandle.read(upToCount: hashChunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
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
                let nanoseconds = UInt64(min(windowSeconds, Double(UInt64.max) / 1_000_000_000) * 1_000_000_000)
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
        for path in paths {
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
        guard let destination = try? signature(of: destinationURL, includeHash: requireHash),
              destination.kind == plannedSource.kind
        else { return false }

        switch plannedSource.kind {
        case .file:
            guard destination.size == plannedSource.size,
                  timesMatch(plannedSource.modificationTimeNanoseconds, destination.modificationTimeNanoseconds, toleranceNanoseconds: toleranceNanoseconds)
            else { return false }
        case .symlink:
            guard destination.size == plannedSource.size,
                  timesMatch(plannedSource.modificationTimeNanoseconds, destination.modificationTimeNanoseconds, toleranceNanoseconds: toleranceNanoseconds),
                  destination.symlinkTarget == plannedSource.symlinkTarget
            else { return false }
        case .directory, .unsupported:
            break
        }

        if compareMode, destination.mode != plannedSource.mode { return false }
        if requireHash {
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
        collisionKeyCaseInsensitive: Bool,
        hashPaths: Set<String>,
        limitToPaths: Set<String>?
    ) -> DevSnapshot {
        var state = ScanState()
        do {
            let root = try fileSystemEntry(at: projectURL)
            guard root.kind == .directory else {
                state.complete = false
                state.unreadablePaths.append(projectURL.path)
                return snapshot(from: state, caseInsensitive: collisionKeyCaseInsensitive)
            }
            try walk(
                directoryURL: projectURL,
                relativeDirectoryPath: "",
                policy: policy,
                gitDirectoryRelativePath: gitDirectoryRelativePath,
                managedLinkPaths: managedLinkPaths,
                hashPaths: hashPaths,
                limitToPaths: limitToPaths,
                state: &state
            )
        } catch is CancellationError {
            state.complete = false
        } catch {
            state.complete = false
            state.unreadablePaths.append(projectURL.path)
        }
        return snapshot(from: state, caseInsensitive: collisionKeyCaseInsensitive)
    }

    private static func walk(
        directoryURL: URL,
        relativeDirectoryPath: String,
        policy: DevPathPolicy,
        gitDirectoryRelativePath: String?,
        managedLinkPaths: Set<String>,
        hashPaths: Set<String>,
        limitToPaths: Set<String>?,
        state: inout ScanState
    ) throws {
        try Task.checkCancellation()
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [])
        } catch {
            state.complete = false
            state.unreadablePaths.append(relativeDirectoryPath.isEmpty ? directoryURL.path : relativeDirectoryPath)
            return
        }

        for childURL in children {
            try Task.checkCancellation()
            let name = childURL.lastPathComponent
            let relativePath = relativeDirectoryPath.isEmpty ? name : relativeDirectoryPath + "/" + name
            guard shouldVisit(relativePath, limitToPaths: limitToPaths) else { continue }

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
                state.excludedBytes += signedSize(entry.size)
                continue
            }

            do {
                state.entries[relativePath] = try signature(of: childURL, entry: entry, includeHash: hashPaths.contains(relativePath))
                state.includedBytes += signedSize(entry.size)
            } catch {
                state.complete = false
                state.unreadablePaths.append(relativePath)
                continue
            }

            if entry.kind == .directory {
                try walk(
                    directoryURL: childURL,
                    relativeDirectoryPath: relativePath,
                    policy: policy,
                    gitDirectoryRelativePath: gitDirectoryRelativePath,
                    managedLinkPaths: managedLinkPaths,
                    hashPaths: hashPaths,
                    limitToPaths: limitToPaths,
                    state: &state
                )
            }
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
        DevFileSignature(
            kind: entry.kind,
            size: entry.kind == .directory ? nil : entry.size,
            modificationTimeNanoseconds: entry.modificationTimeNanoseconds,
            mode: entry.mode,
            symlinkTarget: entry.symlinkTarget,
            resourceIdentifier: entry.resourceIdentifier,
            contentHash: includeHash && entry.kind == .file ? try hash(url: url) : nil,
            xattrDigest: xattrDigest(of: url)
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

        var device = UInt64(fileStatus.st_dev)
        var inode = UInt64(fileStatus.st_ino)
        var resourceIdentifier = Data()
        withUnsafeBytes(of: &device) { resourceIdentifier.append(contentsOf: $0) }
        withUnsafeBytes(of: &inode) { resourceIdentifier.append(contentsOf: $0) }

        return FileSystemEntry(
            kind: kind,
            size: fileStatus.st_size >= 0 ? UInt64(fileStatus.st_size) : 0,
            modificationTimeNanoseconds: Int64(fileStatus.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(fileStatus.st_mtimespec.tv_nsec),
            mode: UInt16(fileStatus.st_mode & 0o7777),
            symlinkTarget: kind == .symlink ? try symlinkTarget(of: url, size: fileStatus.st_size) : nil,
            resourceIdentifier: resourceIdentifier
        )
    }

    private static func symlinkTarget(of url: URL, size: off_t) throws -> String {
        let capacity = max(Int(size), 1) + 1
        var buffer = [CChar](repeating: 0, count: capacity)
        let count = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.readlink(path, &buffer, buffer.count)
        }
        guard count >= 0 else { throw posixError() }
        let bytes = buffer.prefix(count).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
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
            payload.append(contentsOf: name.utf8)
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

    private static func shouldVisit(_ path: String, limitToPaths: Set<String>?) -> Bool {
        guard let limitToPaths else { return true }
        return limitToPaths.contains { target in
            path == target || path.hasPrefix(target + "/") || target.hasPrefix(path + "/")
        }
    }

    private static func isInsideGitDirectory(_ path: String, gitDirectoryRelativePath: String?) -> Bool {
        guard let gitDirectoryRelativePath, !gitDirectoryRelativePath.isEmpty else { return false }
        return path == gitDirectoryRelativePath || path.hasPrefix(gitDirectoryRelativePath + "/")
    }

    private static func signedSize(_ size: UInt64) -> Int64 {
        size > UInt64(Int64.max) ? Int64.max : Int64(size)
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

    private static func bytewisePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }
}
