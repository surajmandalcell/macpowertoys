import Darwin
import Foundation

nonisolated enum DevManagedLinkError: Error, Equatable, Sendable {
    case targetNotBelowExternalRoot
    case targetNotAProject
    case internalPathExists(kind: DevEntryKind)
    case parentInsideProject(String)
    case collision(String)
    case volumeMismatch
    case wrongSide
    case notManaged
    case targetMissing
}

actor DevManagedLinkManager {
    nonisolated let pair: DevSyncPair
    nonisolated let stateStore: DevSyncStateStore
    private let fileManager = FileManager.default

    init(pair: DevSyncPair, stateStore: DevSyncStateStore) {
        self.pair = pair
        self.stateStore = stateStore
    }

    func links() async -> [DevManagedLink] {
        await stateStore.loadLinks(pairID: pair.id)
    }

    func isManagedLinkPath(_ internalRelativePath: String) async -> Bool {
        let key = DevRelativePath.normalizedKey(internalRelativePath)
        return await links().contains { DevRelativePath.normalizedKey($0.linkRelativePath) == key }
    }

    func create(
        project: DevProject,
        internalRoot: URL,
        externalRoot: URL,
        externalVolumeIdentifier: String,
        knownProjectPaths: Set<String>,
        allowInsideProject: Bool = false
    ) async throws -> DevManagedLink {
        try validateProject(project, externalRoot: externalRoot, externalVolumeIdentifier: externalVolumeIdentifier)
        try validateProjectNesting(project.relativePath, knownProjectPaths: knownProjectPaths, allowInsideProject: allowInsideProject)

        let linkURL = internalRoot.appendingPathComponent(project.relativePath)
        if let kind = Self.entryKind(at: linkURL) {
            throw DevManagedLinkError.internalPathExists(kind: kind)
        }
        try createSafeParents(for: project.relativePath, under: internalRoot)
        try ensureNoCollision(for: linkURL.lastPathComponent, in: linkURL.deletingLastPathComponent(), relativePath: project.relativePath)

        let targetURL = externalRoot.appendingPathComponent(project.relativePath).standardizedFileURL
        try Self.createMarkedLink(at: linkURL, target: targetURL, marker: project.id.uuidString)

        let now = Date()
        let link = DevManagedLink(
            projectID: project.id,
            linkRelativePath: project.relativePath,
            targetVolumeIdentifier: externalVolumeIdentifier,
            targetRelativePath: project.relativePath,
            lastWrittenTargetText: targetURL.path,
            linkResourceIdentifier: try DevSnapshotScanner.signature(of: linkURL, includeHash: false).resourceIdentifier,
            state: .healthy,
            createdAt: now,
            lastValidatedAt: now,
            adoptedFromUserLink: false
        )

        do {
            try await upsert(link, requireNewPath: true)
            return link
        } catch {
            try? Self.removeSymlink(at: linkURL)
            throw error
        }
    }

    func validate(
        _ link: DevManagedLink,
        internalRoot: URL,
        externalRoot: URL?,
        externalVolumeIdentifier: String?
    ) -> DevManagedLinkState {
        let linkURL = internalRoot.appendingPathComponent(link.linkRelativePath)
        guard !Self.hasUnsafeParent(for: link.linkRelativePath, under: internalRoot) else { return .wrongTarget }
        guard let kind = Self.entryKind(at: linkURL) else { return .missing }
        guard kind == .symlink else { return .replaced }
        guard let externalRoot else { return .offline }
        guard externalVolumeIdentifier == link.targetVolumeIdentifier,
              let targetText = Self.readTarget(of: linkURL),
              let resolvedTarget = Self.resolvedTarget(targetText, linkURL: linkURL)
        else { return .wrongTarget }

        let root = externalRoot.standardizedFileURL
        let expected = root.appendingPathComponent(link.targetRelativePath).standardizedFileURL
        guard Self.isBelow(resolvedTarget, root: root), resolvedTarget.path == expected.path else {
            return .wrongTarget
        }
        return .healthy
    }

    func refreshStates(
        internalRoot: URL,
        externalRoot: URL?,
        externalVolumeIdentifier: String?
    ) async throws -> [DevManagedLink] {
        let now = Date()
        let refreshed = await links().map { stored in
            var link = stored
            link.state = validate(
                stored,
                internalRoot: internalRoot,
                externalRoot: externalRoot,
                externalVolumeIdentifier: externalVolumeIdentifier
            )
            link.lastValidatedAt = now
            return link
        }
        try await stateStore.saveLinks(refreshed, pairID: pair.id)
        return refreshed
    }

    func repair(
        _ link: DevManagedLink,
        internalRoot: URL,
        externalRoot: URL,
        externalVolumeIdentifier: String,
        recreateMissing: Bool
    ) async throws -> DevManagedLink {
        guard await links().contains(where: { $0.projectID == link.projectID }) else {
            throw DevManagedLinkError.notManaged
        }
        guard externalVolumeIdentifier == link.targetVolumeIdentifier,
              externalVolumeIdentifier == pair.externalRoot.volumeIdentifier else {
            throw DevManagedLinkError.volumeMismatch
        }

        let linkURL = internalRoot.appendingPathComponent(link.linkRelativePath)
        let targetURL = externalRoot.appendingPathComponent(link.targetRelativePath).standardizedFileURL
        try Self.validateRealDirectory(targetURL, below: externalRoot)
        guard !Self.hasUnsafeParent(for: link.linkRelativePath, under: internalRoot) else {
            throw DevManagedLinkError.collision(link.linkRelativePath)
        }

        switch Self.entryKind(at: linkURL) {
        case nil:
            guard recreateMissing else { throw DevManagedLinkError.targetMissing }
            try createSafeParents(for: link.linkRelativePath, under: internalRoot)
            try ensureNoCollision(
                for: linkURL.lastPathComponent,
                in: linkURL.deletingLastPathComponent(),
                relativePath: link.linkRelativePath
            )
        case .symlink:
            guard Self.readTarget(of: linkURL) == link.lastWrittenTargetText else {
                throw DevManagedLinkError.wrongSide
            }
        case .some:
            throw DevManagedLinkError.collision(link.linkRelativePath)
        }

        try Self.replaceWithMarkedLink(at: linkURL, target: targetURL, marker: link.projectID.uuidString)
        var repaired = link
        repaired.lastWrittenTargetText = targetURL.path
        repaired.linkResourceIdentifier = try DevSnapshotScanner.signature(of: linkURL, includeHash: false).resourceIdentifier
        repaired.state = .healthy
        repaired.lastValidatedAt = Date()
        try await upsert(repaired, requireNewPath: false)
        return repaired
    }

    func adopt(
        userLinkRelativePath: String,
        project: DevProject,
        internalRoot: URL,
        externalRoot: URL,
        externalVolumeIdentifier: String
    ) async throws -> DevManagedLink {
        try validateProject(project, externalRoot: externalRoot, externalVolumeIdentifier: externalVolumeIdentifier)
        guard DevRelativePath.isSafe(userLinkRelativePath), userLinkRelativePath == project.relativePath else {
            throw DevManagedLinkError.wrongSide
        }

        let linkURL = internalRoot.appendingPathComponent(userLinkRelativePath)
        guard !Self.hasUnsafeParent(for: userLinkRelativePath, under: internalRoot) else {
            throw DevManagedLinkError.wrongSide
        }
        guard Self.isSymlink(linkURL),
              let targetText = Self.readTarget(of: linkURL),
              let resolvedTarget = Self.resolvedTarget(targetText, linkURL: linkURL)
        else { throw DevManagedLinkError.targetMissing }

        let expectedTarget = externalRoot.appendingPathComponent(project.relativePath).standardizedFileURL
        guard resolvedTarget.path == expectedTarget.path else { throw DevManagedLinkError.wrongSide }
        try Self.setMarker(at: linkURL, value: project.id.uuidString)

        let now = Date()
        let link = DevManagedLink(
            projectID: project.id,
            linkRelativePath: userLinkRelativePath,
            targetVolumeIdentifier: externalVolumeIdentifier,
            targetRelativePath: project.relativePath,
            lastWrittenTargetText: targetText,
            linkResourceIdentifier: try DevSnapshotScanner.signature(of: linkURL, includeHash: false).resourceIdentifier,
            state: .healthy,
            createdAt: now,
            lastValidatedAt: now,
            adoptedFromUserLink: true
        )
        do {
            try await upsert(link, requireNewPath: true)
            return link
        } catch {
            Self.removeMarker(at: linkURL)
            throw error
        }
    }

    func remove(_ link: DevManagedLink, internalRoot: URL, operationID: UUID) async throws {
        var storedLinks = await links()
        guard storedLinks.contains(where: { $0.projectID == link.projectID }) else {
            throw DevManagedLinkError.notManaged
        }

        let action = DevSyncAction(
            kind: .removeManagedLink,
            destinationSide: .internal,
            relativePath: link.linkRelativePath,
            preconditions: preconditions(volumeIdentifier: link.targetVolumeIdentifier),
            reason: "Remove from the internal namespace"
        )
        var operation = DevOperation(
            id: operationID,
            pairID: pair.id,
            projectID: link.projectID,
            kind: .linkRepair,
            plan: DevSyncPlan(pairID: pair.id, projectID: link.projectID, actions: [action])
        )
        try await stateStore.saveOperation(operation)

        do {
            let linkURL = internalRoot.appendingPathComponent(link.linkRelativePath)
            guard !Self.hasUnsafeParent(for: link.linkRelativePath, under: internalRoot) else {
                throw DevManagedLinkError.collision(link.linkRelativePath)
            }
            if let kind = Self.entryKind(at: linkURL) {
                guard kind == .symlink else { throw DevManagedLinkError.collision(link.linkRelativePath) }
                try Self.removeSymlink(at: linkURL)
            }
            storedLinks.removeAll { $0.projectID == link.projectID }
            try await stateStore.saveLinks(storedLinks, pairID: pair.id)
            operation.state = .committed
            operation.updatedAt = Date()
            operation.completedAt = operation.updatedAt
            try await stateStore.saveOperation(operation)
        } catch {
            operation.state = .failed
            operation.updatedAt = Date()
            operation.completedAt = operation.updatedAt
            operation.errorSummary = String(describing: error)
            try? await stateStore.saveOperation(operation)
            throw error
        }
    }

    nonisolated static func readTarget(of linkURL: URL) -> String? {
        guard isSymlink(linkURL) else { return nil }
        var size = 256
        while size <= 1_048_576 {
            var buffer = [CChar](repeating: 0, count: size)
            let count = linkURL.withUnsafeFileSystemRepresentation { path in
                guard let path else { return -1 }
                return Darwin.readlink(path, &buffer, buffer.count)
            }
            guard count >= 0 else { return nil }
            if count < buffer.count {
                return String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            size *= 2
        }
        return nil
    }

    nonisolated static func isSymlink(_ url: URL) -> Bool {
        entryKind(at: url) == .symlink
    }

    private func validateProject(
        _ project: DevProject,
        externalRoot: URL,
        externalVolumeIdentifier: String
    ) throws {
        guard project.pairID == pair.id else { throw DevManagedLinkError.wrongSide }
        guard externalVolumeIdentifier == pair.externalRoot.volumeIdentifier else {
            throw DevManagedLinkError.volumeMismatch
        }
        guard DevRelativePath.isSafe(project.relativePath) else {
            throw DevManagedLinkError.targetNotBelowExternalRoot
        }
        try Self.validateRealDirectory(
            externalRoot.appendingPathComponent(project.relativePath).standardizedFileURL,
            below: externalRoot
        )
    }

    private func validateProjectNesting(
        _ relativePath: String,
        knownProjectPaths: Set<String>,
        allowInsideProject: Bool
    ) throws {
        guard !allowInsideProject else { return }
        let pathKey = DevRelativePath.normalizedKey(relativePath)
        for knownPath in knownProjectPaths where knownPath != relativePath {
            let knownKey = DevRelativePath.normalizedKey(knownPath)
            if pathKey.hasPrefix(knownKey + "/") {
                throw DevManagedLinkError.parentInsideProject(knownPath)
            }
        }
    }

    private func createSafeParents(for relativePath: String, under root: URL) throws {
        guard Self.entryKind(at: root) == .directory else {
            throw DevManagedLinkError.collision(root.path)
        }
        var current = root
        var currentRelativePath = ""
        for component in DevRelativePath.components(relativePath).dropLast() {
            currentRelativePath = currentRelativePath.isEmpty ? component : currentRelativePath + "/" + component
            try ensureNoCollision(for: component, in: current, relativePath: currentRelativePath)
            current.appendPathComponent(component, isDirectory: true)
            if let kind = Self.entryKind(at: current) {
                guard kind == .directory else { throw DevManagedLinkError.collision(currentRelativePath) }
            } else {
                try fileManager.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
    }

    private func ensureNoCollision(for name: String, in parent: URL, relativePath: String) throws {
        guard let children = try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { return }
        let key = DevRelativePath.normalizedKey(name)
        if let collision = children.first(where: {
            $0.lastPathComponent != name && DevRelativePath.normalizedKey($0.lastPathComponent) == key
        }) {
            throw DevManagedLinkError.collision(
                DevRelativePath.parent(relativePath).map { $0 + "/" + collision.lastPathComponent }
                    ?? collision.lastPathComponent
            )
        }
    }

    private func upsert(_ link: DevManagedLink, requireNewPath: Bool) async throws {
        var storedLinks = await links()
        let pathKey = DevRelativePath.normalizedKey(link.linkRelativePath)
        if requireNewPath, storedLinks.contains(where: {
            $0.projectID == link.projectID || DevRelativePath.normalizedKey($0.linkRelativePath) == pathKey
        }) {
            throw DevManagedLinkError.collision(link.linkRelativePath)
        }
        storedLinks.removeAll { $0.projectID == link.projectID }
        storedLinks.append(link)
        storedLinks.sort { $0.linkRelativePath.utf8.lexicographicallyPrecedes($1.linkRelativePath.utf8) }
        try await stateStore.saveLinks(storedLinks, pairID: pair.id)
    }

    private func preconditions(volumeIdentifier: String) -> DevActionPreconditions {
        DevActionPreconditions(
            expectedSourceSignature: nil,
            expectedDestinationSignature: nil,
            expectDestinationAbsent: false,
            expectedVolumeIdentifier: volumeIdentifier,
            expectedProjectFingerprint: nil,
            expectedParentKind: .directory,
            requiredFreeBytes: 0,
            policySchemaVersion: pair.configuration.policySchemaVersion
        )
    }

    private nonisolated static func validateRealDirectory(_ target: URL, below root: URL) throws {
        let root = root.standardizedFileURL
        let target = target.standardizedFileURL
        guard isBelow(target, root: root) else { throw DevManagedLinkError.targetNotBelowExternalRoot }
        guard entryKind(at: target) == .directory else { throw DevManagedLinkError.targetNotAProject }

        var current = root
        guard entryKind(at: current) == .directory else { throw DevManagedLinkError.targetNotAProject }
        let suffix = String(target.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for component in suffix.split(separator: "/") {
            current.appendPathComponent(String(component))
            guard entryKind(at: current) != .symlink else { throw DevManagedLinkError.targetNotBelowExternalRoot }
        }
    }

    private nonisolated static func createMarkedLink(at linkURL: URL, target: URL, marker: String) throws {
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: target.path)
        do {
            try setMarker(at: linkURL, value: marker)
        } catch {
            try? removeSymlink(at: linkURL)
            throw error
        }
    }

    private nonisolated static func replaceWithMarkedLink(at linkURL: URL, target: URL, marker: String) throws {
        if entryKind(at: linkURL) == nil {
            try createMarkedLink(at: linkURL, target: target, marker: marker)
            return
        }

        let temporaryURL = linkURL.deletingLastPathComponent()
            .appendingPathComponent(".\(linkURL.lastPathComponent).devsync-\(UUID().uuidString)")
        try createMarkedLink(at: temporaryURL, target: target, marker: marker)
        do {
            guard entryKind(at: linkURL) == .symlink else {
                throw DevManagedLinkError.collision(linkURL.path)
            }
            guard rename(temporaryURL.path, linkURL.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? removeSymlink(at: temporaryURL)
            throw error
        }
    }

    private nonisolated static func setMarker(at linkURL: URL, value: String) throws {
        let data = Data(value.utf8)
        let result = data.withUnsafeBytes { bytes in
            linkURL.path.withCString { path in
                DevSyncDefaults.managedLinkAttributeName.withCString { name in
                    setxattr(path, name, bytes.baseAddress, data.count, 0, XATTR_NOFOLLOW)
                }
            }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private nonisolated static func removeMarker(at linkURL: URL) {
        _ = linkURL.path.withCString { path in
            DevSyncDefaults.managedLinkAttributeName.withCString { name in
                removexattr(path, name, XATTR_NOFOLLOW)
            }
        }
    }

    private nonisolated static func removeSymlink(at url: URL) throws {
        guard entryKind(at: url) == .symlink else { throw DevManagedLinkError.collision(url.path) }
        guard unlink(url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private nonisolated static func resolvedTarget(_ targetText: String, linkURL: URL) -> URL? {
        guard !targetText.isEmpty, !targetText.contains("\0") else { return nil }
        if targetText.hasPrefix("/") {
            return URL(fileURLWithPath: targetText).standardizedFileURL
        }
        return URL(fileURLWithPath: targetText, relativeTo: linkURL.deletingLastPathComponent()).standardizedFileURL
    }

    private nonisolated static func isBelow(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return rootPath == "/" ? candidatePath != "/" && candidatePath.hasPrefix("/") : candidatePath.hasPrefix(rootPath + "/")
    }

    private nonisolated static func hasUnsafeParent(for relativePath: String, under root: URL) -> Bool {
        guard entryKind(at: root) == .directory else { return true }
        var current = root
        for component in DevRelativePath.components(relativePath).dropLast() {
            current.appendPathComponent(component, isDirectory: true)
            guard let kind = entryKind(at: current) else { continue }
            guard kind == .directory else { return true }
        }
        return false
    }

    private nonisolated static func entryKind(at url: URL) -> DevEntryKind? {
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return lstat(path, &info) == 0
        }) else { return nil }

        switch info.st_mode & S_IFMT {
        case S_IFREG: return .file
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .unsupported
        }
    }
}
