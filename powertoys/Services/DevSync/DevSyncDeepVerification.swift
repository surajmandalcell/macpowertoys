import Foundation

nonisolated enum DevDeepVerificationDifferenceKind: String, Sendable {
    case missingInternal
    case missingExternal
    case type
    case content
    case modificationTime
    case permissions
    case symlinkTarget
    case extendedAttributes
    case nameCollision
}

nonisolated struct DevDeepVerificationDifference: Hashable, Sendable {
    var relativePath: String
    var kind: DevDeepVerificationDifferenceKind
}

nonisolated struct DevDeepVerificationReport: Equatable, Sendable {
    var pairID: UUID
    var projectID: UUID
    var verifiedFileCount: Int
    var differences: [DevDeepVerificationDifference]
    var incompletePaths: [String]
    var complete: Bool
    var duration: TimeInterval
}

nonisolated enum DevDeepVerificationError: Error, Equatable, Sendable {
    case pairMismatch
    case projectNotFound
    case rootUnavailable
}

actor DevDeepVerifier {
    private let pair: DevSyncPair
    private let projects: [DevProject]
    private let internalRoot: URL
    private let externalRoot: URL
    private let capabilities: DevPairCapabilities

    init(
        pair: DevSyncPair,
        projects: [DevProject],
        internalRoot: URL,
        externalRoot: URL,
        capabilities: DevPairCapabilities
    ) {
        self.pair = pair
        self.projects = projects
        self.internalRoot = internalRoot
        self.externalRoot = externalRoot
        self.capabilities = capabilities
    }

    func verify(pairID: UUID, projectID: UUID) async throws -> DevDeepVerificationReport {
        guard pairID == pair.id else { throw DevDeepVerificationError.pairMismatch }
        guard let project = projects.first(where: { $0.id == projectID }) else {
            throw DevDeepVerificationError.projectNotFound
        }
        try Task.checkCancellation()
        let startedAt = Date()
        let internalProject = internalRoot.appendingPathComponent(project.relativePath, isDirectory: true)
        let externalProject = externalRoot.appendingPathComponent(project.relativePath, isDirectory: true)
        guard (try? DevSnapshotScanner.signature(of: internalProject, includeHash: false).kind) == .directory,
              (try? DevSnapshotScanner.signature(of: externalProject, includeHash: false).kind) == .directory
        else { throw DevDeepVerificationError.rootUnavailable }

        let policy = await makePolicy(project: project, projectURL: internalProject)
        async let quickInternal = scan(projectURL: internalProject, project: project, policy: policy, hashPaths: [])
        async let quickExternal = scan(projectURL: externalProject, project: project, policy: policy, hashPaths: [])
        let initialInternal = await quickInternal
        let initialExternal = await quickExternal
        try Task.checkCancellation()
        let filePaths = Set(initialInternal.entries.compactMap { $0.value.kind == .file ? $0.key : nil })
            .union(initialExternal.entries.compactMap { $0.value.kind == .file ? $0.key : nil })

        async let hashedInternal = scan(projectURL: internalProject, project: project, policy: policy, hashPaths: filePaths)
        async let hashedExternal = scan(projectURL: externalProject, project: project, policy: policy, hashPaths: filePaths)
        let internalSnapshot = await hashedInternal
        let externalSnapshot = await hashedExternal
        try Task.checkCancellation()

        var differences = compare(internalSnapshot: internalSnapshot, externalSnapshot: externalSnapshot)
        for group in internalSnapshot.collisions + externalSnapshot.collisions {
            differences.append(contentsOf: group.map { DevDeepVerificationDifference(relativePath: $0, kind: .nameCollision) })
        }
        differences = Array(Set(differences))
            .sorted { lhs, rhs in
                lhs.relativePath == rhs.relativePath
                    ? lhs.kind.rawValue < rhs.kind.rawValue
                    : lhs.relativePath.utf8.lexicographicallyPrecedes(rhs.relativePath.utf8)
            }
        let incompletePaths = Array(Set(internalSnapshot.unreadablePaths + externalSnapshot.unreadablePaths)).sorted()
        return DevDeepVerificationReport(
            pairID: pairID,
            projectID: projectID,
            verifiedFileCount: filePaths.count,
            differences: differences,
            incompletePaths: incompletePaths,
            complete: internalSnapshot.complete && externalSnapshot.complete,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private func makePolicy(project: DevProject, projectURL: URL) async -> DevFilePolicyEngine {
        let tracked = project.kind == .nonGit ? nil : try? await DevGit.workingTreeManifest(projectURL: projectURL)
        return DevFilePolicyEngine(
            policy: pair.configuration.policy,
            projectKind: project.kind,
            gitDirectoryRelativePath: project.topology?.gitDirectory,
            gitTracked: tracked.map(Set.init),
            gitIgnored: nil,
            gitAvailable: tracked != nil,
            projectIgnoreRules: []
        )
    }

    private func scan(
        projectURL: URL,
        project: DevProject,
        policy: DevFilePolicyEngine,
        hashPaths: Set<String>
    ) async -> DevSnapshot {
        await DevSnapshotScanner.scan(
            projectURL: projectURL,
            policy: policy,
            gitDirectoryRelativePath: project.topology?.gitDirectory,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: capabilities.externalVolume?.isCaseSensitive == false,
            hashPaths: hashPaths
        )
    }

    private func compare(
        internalSnapshot: DevSnapshot,
        externalSnapshot: DevSnapshot
    ) -> [DevDeepVerificationDifference] {
        let paths = Set(internalSnapshot.entries.keys).union(externalSnapshot.entries.keys)
        var differences: [DevDeepVerificationDifference] = []
        for path in paths {
            guard let internalEntry = internalSnapshot.entries[path] else {
                differences.append(.init(relativePath: path, kind: .missingInternal))
                continue
            }
            guard let externalEntry = externalSnapshot.entries[path] else {
                differences.append(.init(relativePath: path, kind: .missingExternal))
                continue
            }
            guard internalEntry.kind == externalEntry.kind else {
                differences.append(.init(relativePath: path, kind: .type))
                continue
            }
            if internalEntry.kind == .file, internalEntry.contentHash != externalEntry.contentHash {
                differences.append(.init(relativePath: path, kind: .content))
            }
            if internalEntry.kind == .symlink, internalEntry.symlinkTarget != externalEntry.symlinkTarget {
                differences.append(.init(relativePath: path, kind: .symlinkTarget))
            }
            if !timesMatch(internalEntry.modificationTimeNanoseconds, externalEntry.modificationTimeNanoseconds) {
                differences.append(.init(relativePath: path, kind: .modificationTime))
            }
            if comparesPermissions, internalEntry.mode != externalEntry.mode {
                differences.append(.init(relativePath: path, kind: .permissions))
            }
            if comparesExtendedAttributes, internalEntry.xattrDigest != externalEntry.xattrDigest {
                differences.append(.init(relativePath: path, kind: .extendedAttributes))
            }
        }
        return differences
    }

    private var comparesPermissions: Bool {
        pair.configuration.metadata.permissions != .off
            && capabilities.internalVolume?.supportsUnixPermissions == true
            && capabilities.externalVolume?.supportsUnixPermissions == true
    }

    private var comparesExtendedAttributes: Bool {
        pair.configuration.metadata.xattrs != .off
            && capabilities.internalVolume?.supportsExtendedAttributes == true
            && capabilities.externalVolume?.supportsExtendedAttributes == true
    }

    private func timesMatch(_ lhs: Int64?, _ rhs: Int64?) -> Bool {
        guard let lhs, let rhs else { return lhs == rhs }
        let difference = lhs.subtractingReportingOverflow(rhs)
        guard !difference.overflow else { return false }
        let tolerance = max(0, capabilities.timestampToleranceNanoseconds)
        return difference.partialValue >= -tolerance && difference.partialValue <= tolerance
    }
}
