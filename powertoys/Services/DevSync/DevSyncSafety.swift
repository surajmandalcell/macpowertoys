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
    nonisolated private static let secondsPerDay: TimeInterval = 86_400

    nonisolated let pair: DevSyncPair
    nonisolated let stateStore: DevSyncStateStore
    private let fileManager = FileManager.default

    init(pair: DevSyncPair, stateStore: DevSyncStateStore) {
        self.pair = pair
        self.stateStore = stateStore
    }

    nonisolated static func retentionPriority(for kind: DevSafetyRecordKind) -> Int {
        switch kind {
        case .staging: 0
        case .overwritten: 1
        case .deleted, .projectRetired: 2
        case .conflictCopy: 3
        }
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
            : projectRoot
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
                : rootURL(for: side)
            try createDirectory(root, below: permissionRoot)
        } catch {
            return false
        }
        let probe = root.appendingPathComponent(".cloudsync-availability-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: probe.path)
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
        return try await retainByMoving(
            source,
            side: side,
            relativePath: relativePath,
            projectID: projectID,
            operationID: operationID,
            kind: .deleted,
            now: now,
            retainDays: retainDays
        )
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
        do {
            try restrictPermissions(destination)
            try await record(safetyRecord)
            return safetyRecord
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
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
        return try await retainByMoving(
            source,
            side: side,
            relativePath: relativePath,
            projectID: projectID,
            operationID: operationID,
            kind: .projectRetired,
            now: Date(),
            retainDays: retainDays
        )
    }

    private func retainByMoving(
        _ source: URL,
        side: DevSyncSide,
        relativePath: String,
        projectID: UUID?,
        operationID: UUID,
        kind: DevSafetyRecordKind,
        now: Date,
        retainDays: Int
    ) async throws -> DevSafetyRecord {
        let history = try backupDirectory(side: side, operationID: operationID)
        let destination = try uniqueDestination(history.appendingPathComponent(relativePath))
        try createDirectory(destination.deletingLastPathComponent(), below: history)
        try ensureSameVolume(source, destinationParent: destination.deletingLastPathComponent())
        let bytes = try byteCount(source)
        let safetyRecord = DevSafetyRecord(
            operationID: operationID,
            projectID: projectID,
            kind: kind,
            side: side,
            originalRelativePath: relativePath,
            safetyPath: destination.path,
            bytes: bytes,
            createdAt: now,
            expiresAt: expiry(from: now, days: retainDays)
        )
        try await record(safetyRecord)
        do {
            try Task.checkCancellation()
            try moveItem(at: source, to: destination)
            try restrictPermissions(destination)
            return safetyRecord
        } catch {
            if !pathExists(source) {
                try? fileManager.moveItem(at: destination, to: source)
            }
            try? await stateStore.applySafetyRecordChanges(
                pairID: pair.id,
                removing: [safetyRecord.id],
                expirations: [:]
            )
            throw error
        }
    }

    func record(_ record: DevSafetyRecord) async throws {
        try Task.checkCancellation()
        try await stateStore.appendSafetyRecord(record, pairID: pair.id)
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
        try Task.checkCancellation()
        var records = await stateStore.loadSafetyRecords(pairID: pair.id)
        var removedRecordIDs = Set<UUID>()
        var skippedUnresolvedIDs = Set<UUID>()
        var skippedOpenOperationIDs = Set<UUID>()
        var expirationUpdates: [UUID: Date] = [:]
        var removedBytes: Int64 = 0

        for index in records.indices where records[index].kind == .conflictCopy && records[index].expiresAt == nil {
            try Task.checkCancellation()
            let record = records[index]
            guard !isUnresolvedConflict(record, IDs: unresolvedConflictIDs),
                  !openOperationIDs.contains(record.operationID) else { continue }
            let expiration = expiry(from: now, days: safety.retainResolvedConflictsDays)
            records[index].expiresAt = expiration
            expirationUpdates[record.id] = expiration
        }

        for record in records.sorted(by: cleanupOrder) {
            try Task.checkCancellation()
            guard isExpired(record, now: now) else { continue }
            if isUnresolvedConflict(record, IDs: unresolvedConflictIDs) {
                skippedUnresolvedIDs.insert(record.id)
                continue
            }
            if openOperationIDs.contains(record.operationID) {
                skippedOpenOperationIDs.insert(record.id)
                continue
            }
            if let bytes = try removeSafetyPath(record) {
                removedBytes += bytes
                removedRecordIDs.insert(record.id)
            }
        }

        if let maximum = safety.maximumSafetyStoreBytes {
            var currentUsage = usageBytes(side: .internal) + usageBytes(side: .external)
            let candidates = records
                .filter { !removedRecordIDs.contains($0.id) }
                .sorted(by: retentionOrder)
            for record in candidates where currentUsage > maximum {
                try Task.checkCancellation()
                if isUnresolvedConflict(record, IDs: unresolvedConflictIDs) {
                    skippedUnresolvedIDs.insert(record.id)
                    continue
                }
                if openOperationIDs.contains(record.operationID) {
                    skippedOpenOperationIDs.insert(record.id)
                    continue
                }
                if let bytes = try removeSafetyPath(record) {
                    removedBytes += bytes
                    currentUsage = max(0, currentUsage - bytes)
                    removedRecordIDs.insert(record.id)
                }
            }
        }

        if !removedRecordIDs.isEmpty || !expirationUpdates.isEmpty {
            try await stateStore.applySafetyRecordChanges(
                pairID: pair.id,
                removing: removedRecordIDs,
                expirations: expirationUpdates
            )
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
            try Task.checkCancellation()
            let partial: URL
            do {
                partial = try partialDirectory(side: side)
            } catch DevSafetyError.unavailable {
                continue
            }
            let entries = try fileManager.contentsOfDirectory(at: partial, includingPropertiesForKeys: nil)
            for entry in entries {
                try Task.checkCancellation()
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
        guard !isSymbolicLink(source) else { throw DevSafetyError.symbolicLink }
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
            try Task.checkCancellation()
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

    private func moveItem(at source: URL, to destination: URL) throws {
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            let failure = error as NSError
            let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
            if (failure.domain == NSPOSIXErrorDomain && failure.code == Int(EXDEV))
                || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(EXDEV)) {
                throw DevSafetyError.crossVolumeMove
            }
            throw error
        }
    }

    private func expiry(from date: Date, days: Int) -> Date {
        date.addingTimeInterval(TimeInterval(max(0, days)) * Self.secondsPerDay)
    }

    private func byteCount(_ url: URL) throws -> Int64 {
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        guard let info = fileInfo(url), !isSymbolicLink(url) else { return }
        let permissions: Int = isDirectory(info.st_mode) ? 0o700 : 0o600
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        if isDirectory(info.st_mode), let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for child in children {
                try restrictPermissions(child)
            }
        }
    }

    private func removeSafetyPath(_ record: DevSafetyRecord) throws -> Int64? {
        guard let url = safetyURL(for: record) else { return nil }
        guard pathExists(url) else { return 0 }
        let bytes = byteCountIfPresent(url)
        try fileManager.removeItem(at: url)
        return bytes
    }

    private func safetyURL(for record: DevSafetyRecord) -> URL? {
        let root = systemRoot(for: record.side).standardizedFileURL
        let candidate = record.safetyPath.hasPrefix("/")
            ? URL(fileURLWithPath: record.safetyPath).standardizedFileURL
            : root.appendingPathComponent(record.safetyPath).standardizedFileURL
        let recordRoot: URL
        switch record.kind {
        case .staging:
            recordRoot = root
                .appendingPathComponent(DevSafetyDirectory.staging.rawValue, isDirectory: true)
                .appendingPathComponent(record.operationID.uuidString, isDirectory: true)
        case .overwritten, .deleted, .projectRetired:
            recordRoot = root
                .appendingPathComponent(DevSafetyDirectory.history.rawValue, isDirectory: true)
                .appendingPathComponent(record.operationID.uuidString, isDirectory: true)
        case .conflictCopy:
            recordRoot = root
                .appendingPathComponent(DevSafetyDirectory.conflicts.rawValue, isDirectory: true)
                .appendingPathComponent(record.operationID.uuidString, isDirectory: true)
                .appendingPathComponent(record.side.rawValue, isDirectory: true)
        }
        guard isWithin(candidate, root: recordRoot),
              record.kind == .staging || candidate != recordRoot,
              record.kind == .staging || matchesRecordedPath(candidate, record: record, root: recordRoot),
              !hasSymbolicLinkBelowRoot(candidate, root: root) else { return nil }
        return candidate
    }

    private func matchesRecordedPath(_ candidate: URL, record: DevSafetyRecord, root: URL) -> Bool {
        guard DevRelativePath.isSafe(record.originalRelativePath) else { return false }
        let expected = root.appendingPathComponent(record.originalRelativePath).standardizedFileURL
        guard candidate.deletingLastPathComponent() == expected.deletingLastPathComponent() else { return false }
        if candidate == expected { return true }
        let prefix = expected.lastPathComponent + "-"
        return candidate.lastPathComponent.hasPrefix(prefix)
            && Int(candidate.lastPathComponent.dropFirst(prefix.count)).map { $0 > 0 } == true
    }

    private func isExpired(_ record: DevSafetyRecord, now: Date) -> Bool {
        return record.expiresAt.map { $0 <= now } ?? false
    }

    private func isUnresolvedConflict(_ record: DevSafetyRecord, IDs: Set<UUID>) -> Bool {
        record.kind == .conflictCopy && IDs.contains(record.operationID)
    }

    private func retentionOrder(_ lhs: DevSafetyRecord, _ rhs: DevSafetyRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func cleanupOrder(_ lhs: DevSafetyRecord, _ rhs: DevSafetyRecord) -> Bool {
        let lhsPriority = Self.retentionPriority(for: lhs.kind)
        let rhsPriority = Self.retentionPriority(for: rhs.kind)
        return lhsPriority == rhsPriority ? retentionOrder(lhs, rhs) : lhsPriority < rhsPriority
    }

    private func pathExists(_ url: URL) -> Bool {
        fileInfo(url) != nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        guard let info = fileInfo(url) else { return false }
        return isDirectory(info.st_mode)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        guard let info = fileInfo(url) else { return false }
        return info.st_mode & S_IFMT == S_IFLNK
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
        let rootPath = lexicalPath(root)
        let candidatePath = lexicalPath(candidate)
        if candidatePath == rootPath { return true }
        guard candidatePath.hasPrefix(rootPath + "/") else { return false }
        return DevRelativePath.isSafe(String(candidatePath.dropFirst(rootPath.count + 1)))
    }

    private func hasSymbolicLinkBelowRoot(_ url: URL, root: URL) -> Bool {
        let rootPath = lexicalPath(root)
        let candidatePath = lexicalPath(url)
        if isSymbolicLink(root) { return true }
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else { return true }
        let relative = String(candidatePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return isSymbolicLink(root) }
        guard DevRelativePath.isSafe(relative) else { return true }
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            if isSymbolicLink(current) { return true }
        }
        return false
    }

    private func lexicalPath(_ url: URL) -> String {
        let path = url.path
        return path == "/var" || path.hasPrefix("/var/") ? "/private\(path)" : path
    }
}
