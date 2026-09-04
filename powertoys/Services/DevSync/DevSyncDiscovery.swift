import Darwin
import Foundation

nonisolated struct DevDiscoveredProject: Equatable, Sendable {
    var relativePath: String
    var side: DevSyncSide
    var kind: DevProjectKind
    var url: URL
    var resourceIdentifier: Data?
}

nonisolated struct DevDiscoveryResult: Equatable, Sendable {
    var projects: [DevDiscoveredProject]
    var candidates: [DevProjectCandidate]
    var unreadablePaths: [String]
    var complete: Bool
    var symlinksToExternal: [String: String]
}

nonisolated struct DevRenameCandidate: Equatable, Sendable {
    var previous: DevProject
    var current: DevDiscoveredProject
    var confidence: Double
    var evidence: String
}

nonisolated enum DevProjectDiscovery {
    static func discover(
        root: URL,
        side: DevSyncSide,
        configuration: DevSyncConfiguration.Discovery,
        managedLinkPaths: Set<String>,
        otherRoot: URL?
    ) async -> DevDiscoveryResult {
        let scanTask = Task.detached(priority: .utility) {
            var scanner = DevDiscoveryScanner(
                root: root.standardizedFileURL,
                side: side,
                configuration: configuration,
                managedLinkPaths: managedLinkPaths,
                otherRoot: otherRoot?.standardizedFileURL
            )
            return scanner.scan()
        }
        var scan = await withTaskCancellationHandler {
            await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }
        if Task.isCancelled {
            scan.complete = false
        }

        let internalRoot = side == .internal ? root : (otherRoot ?? root)
        let externalRoot = side == .external ? root : (otherRoot ?? root)
        var projects: [DevDiscoveredProject] = []
        var submoduleRoots = Set<String>()
        for found in scan.projects {
            guard !Task.isCancelled else {
                scan.complete = false
                break
            }
            let topology = await DevGit.topology(
                projectURL: found.url,
                internalRoot: internalRoot,
                externalRoot: externalRoot
            )
            for submodulePath in topology.submodulePaths where DevRelativePath.isSafe(submodulePath) {
                let relativePath = found.relativePath.isEmpty
                    ? submodulePath
                    : "\(found.relativePath)/\(submodulePath)"
                submoduleRoots.insert(relativePath)
            }
            projects.append(
                DevDiscoveredProject(
                    relativePath: found.relativePath,
                    side: side,
                    kind: topology.kind,
                    url: found.url,
                    resourceIdentifier: found.resourceIdentifier
                )
            )
        }
        return DevDiscoveryResult(
            projects: projects.sorted { $0.relativePath < $1.relativePath },
            candidates: scan.candidates.filter { candidate in
                !isInsideSubmodule(candidate.relativePath, submoduleRoots: submoduleRoots)
            }.sorted { $0.id < $1.id },
            unreadablePaths: scan.unreadablePaths.sorted(),
            complete: scan.complete,
            symlinksToExternal: scan.symlinksToExternal
        )
    }

    static func matchRenames(
        previous: [DevProject],
        current: [DevDiscoveredProject],
        side: DevSyncSide,
        identitiesByRelativePath: [String: DevProjectIdentity]? = nil
    ) -> [DevRenameCandidate] {
        let currentPaths = Set(current.filter { $0.side == side }.map(\.relativePath))
        let previousOnSide = previous.filter { wasPresent($0, on: side) }
        let previousPaths = Set(previousOnSide.map(\.relativePath))
        let missing = previousOnSide.filter { !currentPaths.contains($0.relativePath) }
        let additions = current.filter { $0.side == side && !previousPaths.contains($0.relativePath) }
        var missingByResourceIdentifier: [Data: [DevProject]] = [:]
        var missingByFingerprint: [String: [DevProject]] = [:]
        var missingByKindAndName: [String: [DevProject]] = [:]
        for project in missing {
            let resourceIdentifier = side == .internal
                ? project.internalResourceIdentifier
                : project.externalResourceIdentifier
            if let resourceIdentifier {
                missingByResourceIdentifier[resourceIdentifier, default: []].append(project)
            }
            if let fingerprint = project.identity?.fingerprint {
                missingByFingerprint[fingerprint, default: []].append(project)
            }
            missingByKindAndName["\(project.kind.rawValue)\0\(project.name)", default: []].append(project)
        }
        var usedPrevious = Set<UUID>()
        var matches: [DevRenameCandidate] = []

        for candidate in additions.sorted(by: { $0.relativePath < $1.relativePath }) {
            if let resourceIdentifier = candidate.resourceIdentifier,
               let resourceMatches = missingByResourceIdentifier[resourceIdentifier],
               resourceMatches.count == 1,
               let previousProject = resourceMatches.first,
               !usedPrevious.contains(previousProject.id) {
                usedPrevious.insert(previousProject.id)
                matches.append(
                    DevRenameCandidate(
                        previous: previousProject,
                        current: candidate,
                        confidence: 1.0,
                        evidence: "Matching file resource identifier"
                    )
                )
                continue
            }

            if let fingerprint = identitiesByRelativePath?[candidate.relativePath]?.fingerprint {
                if let identityMatches = missingByFingerprint[fingerprint],
                   identityMatches.count == 1,
                   let previousProject = identityMatches.first,
                   !usedPrevious.contains(previousProject.id) {
                    usedPrevious.insert(previousProject.id)
                    matches.append(
                        DevRenameCandidate(
                            previous: previousProject,
                            current: candidate,
                            confidence: 0.9,
                            evidence: "Matching project identity"
                        )
                    )
                    continue
                }
            }

            guard let name = candidate.relativePath.split(separator: "/").last.map(String.init),
                  let nameMatches = missingByKindAndName["\(candidate.kind.rawValue)\0\(name)"],
                  nameMatches.count == 1,
                  let previousProject = nameMatches.first,
                  !usedPrevious.contains(previousProject.id)
            else { continue }
            usedPrevious.insert(previousProject.id)
            matches.append(
                DevRenameCandidate(
                    previous: previousProject,
                    current: candidate,
                    confidence: 0.5,
                    evidence: "Matching kind and name"
                )
            )
        }
        return matches.sorted { $0.current.relativePath < $1.current.relativePath }
    }

    private static func wasPresent(_ project: DevProject, on side: DevSyncSide) -> Bool {
        let resourceIdentifier = side == .internal
            ? project.internalResourceIdentifier
            : project.externalResourceIdentifier
        let lastSeenAt = side == .internal ? project.lastSeenInternalAt : project.lastSeenExternalAt
        if resourceIdentifier != nil || lastSeenAt != nil { return true }
        switch (project.residency, side) {
        case (.mirrored, _), (.internalOnlyPendingMirror, .internal), (.externalResident, .external), (.externalOnlyPendingLink, .external):
            return true
        default:
            return false
        }
    }

    private static func isInsideSubmodule(_ path: String, submoduleRoots: Set<String>) -> Bool {
        var current: String? = path
        while let value = current {
            if submoduleRoots.contains(value) { return true }
            current = DevRelativePath.parent(value)
        }
        return false
    }
}

private nonisolated struct DevDiscoveryFoundProject: Sendable {
    var relativePath: String
    var url: URL
    var resourceIdentifier: Data?
}

private nonisolated struct DevDiscoveryScan: Sendable {
    var projects: [DevDiscoveryFoundProject] = []
    var candidates: [DevProjectCandidate] = []
    var unreadablePaths: [String] = []
    var complete = true
    var symlinksToExternal: [String: String] = [:]
}

private nonisolated struct DevDiscoveryScanner {
    private static let maximumDepth = 32
    private static let maximumDirectoryCount = 50_000
    private static let maximumMarkerBytes = 1_048_576
    private static let markerReadChunkBytes = 64 * 1_024

    let root: URL
    let side: DevSyncSide
    let configuration: DevSyncConfiguration.Discovery
    let managedLinkPaths: Set<String>
    let otherRootPath: String?
    var result = DevDiscoveryScan()
    var visitedDirectories = 0

    init(
        root: URL,
        side: DevSyncSide,
        configuration: DevSyncConfiguration.Discovery,
        managedLinkPaths: Set<String>,
        otherRoot: URL?
    ) {
        self.root = root
        self.side = side
        self.configuration = configuration
        self.managedLinkPaths = Set(managedLinkPaths.map(DevDiscoveryScanner.normalizedPath))
        self.otherRootPath = otherRoot.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
    }

    mutating func scan() -> DevDiscoveryScan {
        guard let mode = lstatMode(at: root), mode & S_IFMT == S_IFDIR else {
            result.complete = false
            result.unreadablePaths.append("")
            return result
        }
        visit(directory: root, relativePath: "", depth: 0)
        return result
    }

    private mutating func visit(directory: URL, relativePath: String, depth: Int) {
        guard enterDirectory(directory, relativePath: relativePath, depth: depth) else { return }

        if hasGitProjectMarker(at: directory) {
            result.projects.append(
                DevDiscoveryFoundProject(
                    relativePath: relativePath,
                    url: directory,
                    resourceIdentifier: resourceIdentifier(at: directory)
                )
            )
            scanNestedRepositories(
                in: directory,
                outerRelativePath: relativePath,
                projectRootRelativePath: relativePath,
                submodulePaths: parseSubmodulePaths(at: directory),
                depth: depth
            )
            return
        }

        if isBareRepository(at: directory) {
            addCandidate(relativePath: relativePath, kind: .bareRepository)
            return
        }

        if configuration.showMarkerCandidates, let marker = markerName(in: directory) {
            addCandidate(relativePath: relativePath, kind: .marker, markerName: marker)
        }
        guard let entries = directoryContents(directory) else {
            result.complete = false
            result.unreadablePaths.append(relativePath)
            return
        }
        for entry in entries {
            let childRelativePath = relativePath.isEmpty ? entry.lastPathComponent : "\(relativePath)/\(entry.lastPathComponent)"
            guard entry.lastPathComponent != ".git",
                  !isManagedLink(childRelativePath),
                  !DevRelativePath.isCloudSyncSystemPath(childRelativePath)
            else { continue }
            guard let mode = lstatMode(at: entry) else {
                result.complete = false
                result.unreadablePaths.append(childRelativePath)
                continue
            }
            if mode & S_IFMT == S_IFLNK {
                recordExternalSymlink(at: entry, relativePath: childRelativePath)
                continue
            }
            guard mode & S_IFMT == S_IFDIR else { continue }
            if DevFilePolicyEngine.isCommonCachePath(childRelativePath) { continue }
            visit(directory: entry, relativePath: childRelativePath, depth: depth + 1)
        }
    }

    private mutating func scanNestedRepositories(
        in directory: URL,
        outerRelativePath: String,
        projectRootRelativePath: String,
        submodulePaths: Set<String>,
        depth: Int
    ) {
        guard let entries = directoryContents(directory) else {
            result.complete = false
            result.unreadablePaths.append(outerRelativePath)
            return
        }
        for entry in entries {
            let childRelativePath = outerRelativePath.isEmpty ? entry.lastPathComponent : "\(outerRelativePath)/\(entry.lastPathComponent)"
            guard entry.lastPathComponent != ".git",
                  !isManagedLink(childRelativePath),
                  !DevRelativePath.isCloudSyncSystemPath(childRelativePath)
            else { continue }
            guard let mode = lstatMode(at: entry) else {
                result.complete = false
                result.unreadablePaths.append(childRelativePath)
                continue
            }
            if mode & S_IFMT == S_IFLNK {
                recordExternalSymlink(at: entry, relativePath: childRelativePath)
                continue
            }
            guard mode & S_IFMT == S_IFDIR else { continue }
            if DevFilePolicyEngine.isCommonCachePath(childRelativePath) { continue }
            guard enterDirectory(entry, relativePath: childRelativePath, depth: depth + 1) else { continue }

            let relativeToOuter = projectRootRelativePath.isEmpty
                ? childRelativePath
                : String(childRelativePath.dropFirst(projectRootRelativePath.count + 1))
            let isSubmodule = submodulePaths.contains { relativeToOuter == $0 || relativeToOuter.hasPrefix($0 + "/") }
            if submodulePaths.contains(relativeToOuter) { continue }
            if hasGitProjectMarker(at: entry), !isSubmodule {
                addCandidate(relativePath: childRelativePath, kind: .nestedRepository)
                continue
            } else if isBareRepository(at: entry), !isSubmodule {
                addCandidate(relativePath: childRelativePath, kind: .bareRepository)
                continue
            }
            scanNestedRepositories(
                in: entry,
                outerRelativePath: childRelativePath,
                projectRootRelativePath: projectRootRelativePath,
                submodulePaths: submodulePaths,
                depth: depth + 1
            )
        }
    }

    private mutating func enterDirectory(_ directory: URL, relativePath: String, depth: Int) -> Bool {
        guard !Task.isCancelled else {
            result.complete = false
            return false
        }
        guard depth <= Self.maximumDepth else {
            result.complete = false
            result.unreadablePaths.append(relativePath)
            return false
        }
        guard visitedDirectories < Self.maximumDirectoryCount else {
            result.complete = false
            return false
        }
        visitedDirectories += 1
        guard isReadableDirectory(at: directory) else {
            result.complete = false
            result.unreadablePaths.append(relativePath)
            return false
        }
        return true
    }

    private mutating func addCandidate(relativePath: String, kind: DevCandidateKind, markerName: String? = nil) {
        result.candidates.append(
            DevProjectCandidate(relativePath: relativePath, side: side, kind: kind, markerName: markerName)
        )
    }

    private func markerName(in directory: URL) -> String? {
        let entries = directoryContents(directory) ?? []
        return DevSyncDefaults.projectMarkers.first { marker in
            entries.contains {
                guard let mode = lstatMode(at: $0), mode & S_IFMT != S_IFLNK else { return false }
                return $0.lastPathComponent == marker
            }
        }
    }

    private func hasGitProjectMarker(at directory: URL) -> Bool {
        let gitURL = directory.appendingPathComponent(".git", isDirectory: true)
        guard let mode = lstatMode(at: gitURL) else { return false }
        if mode & S_IFMT == S_IFDIR { return true }
        guard mode & S_IFMT == S_IFREG, let text = readText(at: gitURL),
              let firstLine = text.split(whereSeparator: \.isNewline).first,
              firstLine.hasPrefix("gitdir:"),
              let pointer = firstLine.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces).nilIfEmpty
        else { return false }
        return !pointer.contains("\0")
    }

    private func parseSubmodulePaths(at directory: URL) -> Set<String> {
        guard let text = readText(at: directory.appendingPathComponent(".gitmodules")) else { return [] }
        var paths = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "path", DevRelativePath.isSafe(String(parts[1])) else { continue }
            paths.insert(String(parts[1]))
        }
        return paths
    }

    private func isBareRepository(at directory: URL) -> Bool {
        isRegularFile(at: directory.appendingPathComponent("HEAD")) &&
            isDirectory(at: directory.appendingPathComponent("objects")) &&
            isDirectory(at: directory.appendingPathComponent("refs"))
    }

    private mutating func recordExternalSymlink(at url: URL, relativePath: String) {
        guard let otherRootPath else { return }
        let target = canonicalPath(url)
        guard target == otherRootPath || target.hasPrefix(otherRootPath + "/") else { return }
        result.symlinksToExternal[relativePath] = target
    }

    private func isManagedLink(_ path: String) -> Bool {
        managedLinkPaths.contains(Self.normalizedPath(path))
    }

    private func isReadableDirectory(at url: URL) -> Bool {
        guard let mode = lstatMode(at: url), mode & S_IFMT == S_IFDIR else { return false }
        return mode & 0o444 != 0 && mode & 0o111 != 0
    }

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .joined(separator: "/")
            .precomposedStringWithCanonicalMapping
    }

    private func directoryContents(_ url: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
    }

    private func readText(at url: URL) -> String? {
        guard isRegularFile(at: url), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        do {
            while let chunk = try handle.read(upToCount: min(Self.markerReadChunkBytes, Self.maximumMarkerBytes - data.count + 1)) {
                guard !chunk.isEmpty else { break }
                data.append(chunk)
                guard data.count <= Self.maximumMarkerBytes else { return nil }
            }
        } catch {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func resourceIdentifier(at url: URL) -> Data? {
        guard let value = lstatValue(at: url), value.st_mode & S_IFMT != S_IFLNK else { return nil }
        var device = UInt64(truncatingIfNeeded: value.st_dev).bigEndian
        var inode = UInt64(truncatingIfNeeded: value.st_ino).bigEndian
        var identifier = Data()
        withUnsafeBytes(of: &device) { identifier.append(contentsOf: $0) }
        withUnsafeBytes(of: &inode) { identifier.append(contentsOf: $0) }
        return identifier
    }

    private nonisolated enum FileType {
        case regular
        case directory
        case symlink
        case other
    }

    private func fileType(at url: URL) -> FileType {
        guard let mode = lstatMode(at: url) else { return .other }
        switch mode & S_IFMT {
        case S_IFREG: return .regular
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    private func isRegularFile(at url: URL) -> Bool {
        fileType(at: url) == .regular
    }

    private func isDirectory(at url: URL) -> Bool {
        fileType(at: url) == .directory
    }

    private func lstatMode(at url: URL) -> UInt16? {
        lstatValue(at: url)?.st_mode
    }

    private func lstatValue(at url: URL) -> stat? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var value = stat()
            guard lstat(path, &value) == 0 else { return nil }
            return value
        }
    }

    private func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
