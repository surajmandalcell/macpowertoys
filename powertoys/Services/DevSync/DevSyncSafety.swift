import Darwin
import Foundation

nonisolated enum DevSafetyDirectory: String, CaseIterable, Sendable {
    case staging
    case history
    case conflicts
    case manifests
    case recovery
    case partial
}

nonisolated struct DevRetentionResult: Equatable, Sendable {
    var removedRecords: Int
    var removedBytes: Int64
    var skippedUnresolved: Int
    var skippedOpenOperations: Int
}

nonisolated enum DevSafetyError: Error, Equatable, Sendable {
    case invalidRelativePath
    case sourceMissing
    case sourceOutsideRoot
    case symbolicLink
    case notDirectory
    case unavailable
    case crossVolumeMove
}

actor DevSafetyStore {
    nonisolated let pair: DevSyncPair
    nonisolated let stateStore: DevSyncStateStore
    private let fileManager = FileManager.default

    init(pair: DevSyncPair, stateStore: DevSyncStateStore) {
        self.pair = pair
        self.stateStore = stateStore
    }

    nonisolated func systemRoot(for side: DevSyncSide) -> URL {
        switch side {
        case .external:
            return pair.externalRoot.url
                .appendingPathComponent(DevSyncDefaults.systemDirectoryName, isDirectory: true)
                .appendingPathComponent(pair.id.uuidString, isDirectory: true)
        case .internal:
            return stateStore.internalSafetyHistoryDirectory(pair.id).deletingLastPathComponent()
        }
    }

    func directory(_ kind: DevSafetyDirectory, side: DevSyncSide) throws -> URL {
        let root = systemRoot(for: side)
        let projectRoot = rootURL(for: side)
        if side == .external {
            guard isDirectory(projectRoot), !isSymbolicLink(projectRoot) else {
                throw DevSafetyError.unavailable
            }
        }
        let permissionRoot = side == .internal
            ? stateStore.rootURL
            : projectRoot.appendingPathComponent(DevSyncDefaults.systemDirectoryName, isDirectory: true)
        try createDirectory(root, below: permissionRoot)
        let directory = root.appendingPathComponent(kind.rawValue, isDirectory: true)
        try createDirectory(directory, below: root)
        return directory
    }

    func isAvailable(side: DevSyncSide) -> Bool {
        if side == .external {
            let projectRoot = rootURL(for: side)
            guard isDirectory(projectRoot), !isSymbolicLink(projectRoot), fileManager.isWritableFile(atPath: projectRoot.path) else {
                return false
            }
        }

        let root = systemRoot(for: side)
        do {
            let permissionRoot = side == .internal
                ? stateStore.rootURL
                : rootURL(for: side).appendingPathComponent(DevSyncDefaults.systemDirectoryName, isDirectory: true)
            try createDirectory(root, below: permissionRoot)
        } catch {
            return false
        }
        let probe = root.appendingPathComponent(".cloudsync-availability-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .atomic)
            try fileManager.removeItem(at: probe)
            return true
        } catch {
            try? fileManager.removeItem(at: probe)
            return false
        }
    }

    func backupDirectory(side: DevSyncSide, operationID: UUID) throws -> URL {
        let history = try directory(.history, side: side)
        let operationDirectory = history.appendingPathComponent(operationID.uuidString, isDirectory: true)
        try createDirectory(operationDirectory, below: history)
        return operationDirectory
    }

    func partialDirectory(side: DevSyncSide) throws -> URL {
        try directory(.partial, side: side)
    }

    func retainBeforeDelete(
        side: DevSyncSide,
        fileURL: URL,
        relativePath: String,
        projectID: UUID?,
        operationID: UUID,
        now: Date = Date(),
        retainDays: Int
    ) async throws -> DevSafetyRecord {
        let source = try validateSource(fileURL, side: side, relativePath: relativePath)
        let history = try backupDirectory(side: side, operationID: operationID)
        let destination = try uniqueDestination(history.appendingPathComponent(relativePath))
        try createDirectory(destination.deletingLastPathComponent(), below: history)
        try ensureSameVolume(source, destinationParent: destination.deletingLastPathComponent())
        let bytes = try byteCount(source)
        try fileManager.moveItem(at: source, to: destination)
        try restrictPermissions(destination)
        let safetyRecord = DevSafetyRecord(
            operationID: operationID,
            projectID: projectID,
            kind: .deleted,
            side: side,
            originalRelativePath: relativePath,
            safetyPath: destination.path,
            bytes: bytes,
            createdAt: now,
            expiresAt: expiry(from: now, days: retainDays)
        )
        try await record(safetyRecord)
        return safetyRecord
    }

    func retainConflictCopy(
        side: DevSyncSide,
        fileURL: URL,
        relativePath: String,
        projectID: UUID,
        conflictID: UUID
    ) async throws -> DevSafetyRecord {
        let source = try validateSource(fileURL, side: side, relativePath: relativePath)
        let conflicts = try directory(.conflicts, side: side)
        let conflictDirectory = conflicts
            .appendingPathComponent(conflictID.uuidString, isDirectory: true)
            .appendingPathComponent(side.rawValue, isDirectory: true)
        try createDirectory(conflictDirectory, below: conflicts)
        let destination = try uniqueDestination(conflictDirectory.appendingPathComponent(relativePath))
        try createDirectory(destination.deletingLastPathComponent(), below: conflicts)
        let bytes = try byteCount(source)
        try fileManager.copyItem(at: source, to: destination)
        try restrictPermissions(destination)
        let safetyRecord = DevSafetyRecord(
            operationID: conflictID,
            projectID: projectID,
            kind: .conflictCopy,
            side: side,
            originalRelativePath: relativePath,
            safetyPath: destination.path,
            bytes: bytes,
            createdAt: Date(),
            expiresAt: nil
        )
        try await record(safetyRecord)
        return safetyRecord
    }

    func retireProject(
        side: DevSyncSide,
        projectURL: URL,
        relativePath: String,
        projectID: UUID,
        operationID: UUID,
        retainDays: Int
    ) async throws -> DevSafetyRecord {
        let source = try validateSource(projectURL, side: side, relativePath: relativePath)
        guard isDirectory(source) else { throw DevSafetyError.notDirectory }
        let history = try backupDirectory(side: side, operationID: operationID)
        let destination = try uniqueDestination(history.appendingPathComponent(relativePath))
        try createDirectory(destination.deletingLastPathComponent(), below: history)
        try ensureSameVolume(source, destinationParent: destination.deletingLastPathComponent())
        let bytes = try byteCount(source)
        try fileManager.moveItem(at: source, to: destination)
        try restrictPermissions(destination)
        let now = Date()
        let safetyRecord = DevSafetyRecord(
            operationID: operationID,
            projectID: projectID,
            kind: .projectRetired,
            side: side,
            originalRelativePath: relativePath,
            safetyPath: destination.path,
            bytes: bytes,
            createdAt: now,
            expiresAt: expiry(from: now, days: retainDays)
        )
        try await record(safetyRecord)
        return safetyRecord
    }

    func record(_ record: DevSafetyRecord) async throws {
        var records = await stateStore.loadSafetyRecords(pairID: pair.id)
        records.append(record)
        try await stateStore.saveSafetyRecords(records, pairID: pair.id)
    }

    func usageBytes(side: DevSyncSide) -> Int64 {
        byteCountIfPresent(systemRoot(for: side))
    }

    func runRetention(
        now: Date,
        safety: DevSyncConfiguration.Safety,
        unresolvedConflictIDs: Set<UUID>,
        openOperationIDs: Set<UUID>
    ) async throws -> DevRetentionResult {
        let records = await stateStore.loadSafetyRecords(pairID: pair.id)
        var kept = records
        var removedRecordIDs = Set<UUID>()
        var skippedUnresolvedIDs = Set<UUID>()
        var skippedOpenOperationIDs = Set<UUID>()
        var removedBytes: Int64 = 0

        let groups: [[DevSafetyRecord]] = [
            records.filter { $0.kind == .staging },
            records.filter { $0.kind == .overwritten },
            records.filter { $0.kind == .deleted || $0.kind == .projectRetired },
            records.filter { $0.kind == .conflictCopy }
        ]

        for group in groups {
            for record in group.sorted(by: retentionOrder) {
                guard !removedRecordIDs.contains(record.id), isExpired(record, now: now, safety: safety) else { continue }
                if isUnresolvedConflict(record, IDs: unresolvedConflictIDs) {
                    skippedUnresolvedIDs.insert(record.id)
                    continue
                }
                if openOperationIDs.contains(record.operationID) {
                    skippedOpenOperationIDs.insert(record.id)
                    continue
                }
                if let bytes = try removeSafetyPath(record, side: record.side) {
                    removedBytes += bytes
                    removedRecordIDs.insert(record.id)
                }
            }
        }

        if let maximum = safety.maximumSafetyStoreBytes {
            var currentUsage = usageBytes(side: .internal) + usageBytes(side: .external)
            let candidates = records
                .filter { !removedRecordIDs.contains($0.id) }
                .sorted(by: retentionOrder)
            for record in candidates where currentUsage > maximum {
                if isUnresolvedConflict(record, IDs: unresolvedConflictIDs) {
                    skippedUnresolvedIDs.insert(record.id)
                    continue
                }
                if openOperationIDs.contains(record.operationID) {
                    skippedOpenOperationIDs.insert(record.id)
                    continue
                }
                if let bytes = try removeSafetyPath(record, side: record.side) {
                    removedBytes += bytes
                    currentUsage = max(0, currentUsage - bytes)
                    removedRecordIDs.insert(record.id)
                }
            }
        }

        if !removedRecordIDs.isEmpty {
            kept.removeAll { removedRecordIDs.contains($0.id) }
            try await stateStore.saveSafetyRecords(kept, pairID: pair.id)
        }

        return DevRetentionResult(
            removedRecords: removedRecordIDs.count,
            removedBytes: removedBytes,
            skippedUnresolved: skippedUnresolvedIDs.count,
            skippedOpenOperations: skippedOpenOperationIDs.count
        )
    }

    func cleanStalePartials(openOperationIDs: Set<UUID>) async throws -> Int {
        var removed = 0
        for side in DevSyncSide.allCases {
            guard let partial = try? partialDirectory(side: side),
                  let entries = try? fileManager.contentsOfDirectory(at: partial, includingPropertiesForKeys: nil) else {
                continue
            }
            for entry in entries {
                if let operationID = UUID(uuidString: entry.lastPathComponent), openOperationIDs.contains(operationID) {
                    continue
                }
                try fileManager.removeItem(at: entry)
                removed += 1
            }
        }
        return removed
    }

    private func rootURL(for side: DevSyncSide) -> URL {
        pair.root(for: side).url
    }

    private func validateSource(_ fileURL: URL, side: DevSyncSide, relativePath: String) throws -> URL {
        guard DevRelativePath.isSafe(relativePath) else { throw DevSafetyError.invalidRelativePath }
        let root = rootURL(for: side)
        let source = fileURL.standardizedFileURL
        let expected = root.appendingPathComponent(relativePath).standardizedFileURL
        guard source == expected, isWithin(source, root: root) else { throw DevSafetyError.sourceOutsideRoot }
        guard !hasSymbolicLinkBelowRoot(source.deletingLastPathComponent(), root: root) else {
            throw DevSafetyError.symbolicLink
        }
        guard pathExists(source) else { throw DevSafetyError.sourceMissing }
        return source
    }

    private func createDirectory(_ url: URL, below root: URL? = nil) throws {
        if let root {
            guard isWithin(url.standardizedFileURL, root: root.standardizedFileURL),
                  !hasSymbolicLinkBelowRoot(url, root: root) else {
                throw DevSafetyError.symbolicLink
            }
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        if let root {
            var current = url.standardizedFileURL
            let root = root.standardizedFileURL
            while current.path == root.path || current.path.hasPrefix(root.path + "/") {
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: current.path)
                guard current.path != root.path else { break }
                current.deleteLastPathComponent()
            }
        } else {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    private func uniqueDestination(_ base: URL) throws -> URL {
        guard !hasSymbolicLinkBelowRoot(base, root: base.deletingLastPathComponent()) else {
            throw DevSafetyError.symbolicLink
        }
        var destination = base
        var suffix = 1
        while pathExists(destination) {
            destination = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent)-\(suffix)")
            suffix += 1
        }
        return destination
    }

    private func ensureSameVolume(_ source: URL, destinationParent: URL) throws {
        guard let sourceDevice = deviceNumber(source), let destinationDevice = deviceNumber(destinationParent) else {
            throw DevSafetyError.crossVolumeMove
        }
        guard sourceDevice == destinationDevice else { throw DevSafetyError.crossVolumeMove }
    }

    private func expiry(from date: Date, days: Int) -> Date {
        date.addingTimeInterval(TimeInterval(max(0, days)) * 86_400)
    }

    private func byteCount(_ url: URL) throws -> Int64 {
        guard let info = fileInfo(url) else { throw DevSafetyError.sourceMissing }
        if isDirectory(info.st_mode) {
            guard let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
                throw DevSafetyError.sourceMissing
            }
            return try children.reduce(Int64(0)) { total, child in
                total + (try byteCount(child))
            }
        }
        return Int64(max(0, info.st_size))
    }

    private func byteCountIfPresent(_ url: URL) -> Int64 {
        guard let info = fileInfo(url) else { return 0 }
        if isDirectory(info.st_mode) {
            guard let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
                return 0
            }
            return children.reduce(Int64(0)) { $0 + byteCountIfPresent($1) }
        }
        return Int64(max(0, info.st_size))
    }

    private func restrictPermissions(_ url: URL) throws {
        guard let info = fileInfo(url), !isSymbolicLink(url) else { return }
        let permissions: Int = isDirectory(info.st_mode) ? 0o700 : 0o600
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        if isDirectory(info.st_mode), let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for child in children {
                try restrictPermissions(child)
            }
        }
    }

    private func removeSafetyPath(_ record: DevSafetyRecord, side: DevSyncSide) throws -> Int64? {
        guard let url = safetyURL(record.safetyPath, side: side) else { return nil }
        guard pathExists(url) else { return 0 }
        let bytes = byteCountIfPresent(url)
        try fileManager.removeItem(at: url)
        return bytes
    }

    private func safetyURL(_ path: String, side: DevSyncSide) -> URL? {
        let root = systemRoot(for: side).standardizedFileURL
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path).standardizedFileURL
            : root.appendingPathComponent(path).standardizedFileURL
        guard isWithin(candidate, root: root), !hasSymbolicLinkBelowRoot(candidate, root: root) else { return nil }
        return candidate
    }

    private func isExpired(_ record: DevSafetyRecord, now: Date, safety: DevSyncConfiguration.Safety) -> Bool {
        if record.kind == .conflictCopy {
            return (record.expiresAt ?? record.createdAt.addingTimeInterval(TimeInterval(max(0, safety.retainResolvedConflictsDays)) * 86_400)) <= now
        }
        return record.expiresAt.map { $0 <= now } ?? false
    }

    private func isUnresolvedConflict(_ record: DevSafetyRecord, IDs: Set<UUID>) -> Bool {
        guard record.kind == .conflictCopy else { return false }
        if IDs.contains(record.operationID) { return true }
        let components = URL(fileURLWithPath: record.safetyPath).pathComponents
        guard let index = components.lastIndex(of: DevSafetyDirectory.conflicts.rawValue),
              components.indices.contains(index + 1),
              let conflictID = UUID(uuidString: components[index + 1]) else {
            return false
        }
        return IDs.contains(conflictID)
    }

    private func retentionOrder(_ lhs: DevSafetyRecord, _ rhs: DevSafetyRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func pathExists(_ url: URL) -> Bool {
        fileInfo(url) != nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        guard let info = fileInfo(url) else { return false }
        return isDirectory(info.st_mode)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func isDirectory(_ mode: mode_t) -> Bool {
        mode & S_IFMT == S_IFDIR
    }

    private func fileInfo(_ url: URL) -> stat? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info
    }

    private func deviceNumber(_ url: URL) -> dev_t? {
        fileInfo(url)?.st_dev
    }

    private func isWithin(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func hasSymbolicLinkBelowRoot(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        if isSymbolicLink(root) { return true }
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else { return true }
        let relative = String(candidatePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return isSymbolicLink(root) }
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            if isSymbolicLink(current) { return true }
        }
        return false
    }
}
