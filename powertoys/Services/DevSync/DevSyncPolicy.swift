import CryptoKit
import Foundation

nonisolated struct DevPolicyInput: Sendable {
    var relativePath: String
    var kind: DevEntryKind
    var size: Int64
    var isInsideGitDirectory: Bool
}

nonisolated final class DevFilePolicyEngine: Sendable {
    private static let largeFileThresholdBytes: Int64 = 1_073_741_824

    private let policy: DevSyncConfiguration.Policy
    private let projectKind: DevProjectKind
    private let gitDirectoryRelativePath: String?
    private let gitTracked: Set<String>?
    private let gitManifest: Set<String>?
    private let gitManifestDirectories: Set<String>?
    private let gitIgnored: Set<String>?
    private let gitAvailable: Bool
    private let projectIgnoreRules: [String]

    init(
        policy: DevSyncConfiguration.Policy,
        projectKind: DevProjectKind,
        gitDirectoryRelativePath: String?,
        gitTracked: Set<String>?,
        gitManifest: Set<String>? = nil,
        gitIgnored: Set<String>?,
        gitAvailable: Bool,
        projectIgnoreRules: [String]
    ) {
        self.policy = policy
        self.projectKind = projectKind
        self.gitDirectoryRelativePath = gitDirectoryRelativePath
        self.gitTracked = gitTracked
        self.gitManifest = gitManifest
        self.gitManifestDirectories = gitManifest.map { manifest in
            var directories = Set<String>()
            for path in manifest {
                var current = path
                while let parent = DevRelativePath.parent(current) {
                    directories.insert(parent)
                    current = parent
                }
            }
            return directories
        }
        self.gitIgnored = gitIgnored
        self.gitAvailable = gitAvailable
        self.projectIgnoreRules = projectIgnoreRules
    }

    func decide(_ input: DevPolicyInput) -> DevFilePolicyDecision {
        let path = input.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let sensitive = policy.sensitivePatterns.contains { DevRelativePath.matchesGlob($0, name: name) }
        let diskImage = DevSyncDefaults.diskImagePatterns.contains { DevRelativePath.matchesGlob($0, name: name) }
        let volatile = diskImage || DevSyncDefaults.volatileFilePatterns.contains { DevRelativePath.matchesGlob($0, name: name) }
        let requiresStableWindow = volatile || input.size > Self.largeFileThresholdBytes
        let insideGitDirectory = input.isInsideGitDirectory || isGitDirectoryPath(path)

        guard input.kind != .unsupported else { return .exclude(.unsupportedObjectType) }
        guard !DevRelativePath.isCloudSyncSystemPath(path) else { return .exclude(.cloudSyncInternalPath) }
        guard !name.hasSuffix(".icloud") else { return .exclude(.datalessPlaceholder) }

        let gitPath = insideGitDirectory ? pathInsideGitDirectory(path) : ""
        if insideGitDirectory, DevGit.isTransientGitPath(gitPath) {
            return .exclude(.transientGitLock)
        }

        let explicitInclude = policy.explicitIncludes.contains { matches($0, path: path, name: name) }
        let explicitExclude = policy.explicitExcludes.contains { matches($0, path: path, name: name) }
        if explicitExclude {
            return .exclude(.explicitUserExclude)
        }
        if explicitInclude {
            return .include(
                .explicitUserInclude,
                sensitive: sensitive,
                volatile: volatile,
                requiresStableWindow: requiresStableWindow
            )
        }

        let inCache = policy.skipCommonCaches && Self.isCommonCachePath(path)
        if sensitive && !inCache {
            guard input.size <= policy.sensitiveSizeGuardBytes else {
                return .exclude(.sensitiveSizeGuard)
            }
            if policy.includeIgnoredSensitiveFiles {
                return .include(
                    .sensitiveOverride,
                    sensitive: true,
                    volatile: volatile,
                    requiresStableWindow: requiresStableWindow
                )
            }
        }

        if insideGitDirectory {
            if !policy.includeGitMetadata || (!policy.includeGitLFSObjects && isGitLFSPath(gitPath)) {
                return .exclude(.commonExclusion)
            }
            return .include(
                .requiredGitMetadata,
                sensitive: sensitive,
                volatile: volatile,
                requiresStableWindow: requiresStableWindow
            )
        }

        let manifestMember = gitAvailable && (
            gitManifest?.contains(path) == true
                || input.kind == .directory && gitManifestDirectories?.contains(path) == true
        )
        let tracked = gitAvailable && gitTracked?.contains(path) == true
        if tracked || manifestMember {
            return .include(
                .gitTracked,
                sensitive: sensitive,
                volatile: volatile,
                requiresStableWindow: requiresStableWindow
            )
        }

        let ignoredByGit = gitAvailable && policy.followGitIgnore && (
            gitIgnored?.contains(path) == true
                || gitManifest != nil && !manifestMember
        )
        let ignoredByProject = isIgnoredByProjectRules(path: path, name: name)
        if ignoredByGit || ignoredByProject {
            return .exclude(.gitIgnored)
        }

        if isHardExcluded(path: path, name: name) {
            return .exclude(.commonExclusion)
        }
        if policy.skipCommonCaches && Self.isCommonCachePath(path) {
            return .exclude(.commonExclusion)
        }
        if policy.skipUnignoredBuildOutputs && Self.isBuildOutputPath(path) {
            return .exclude(.buildOutputExclusion)
        }
        return .include(
            .defaultInclusion,
            sensitive: sensitive,
            volatile: volatile,
            requiresStableWindow: requiresStableWindow
        )
    }

    func fingerprint() -> String {
        var hasher = SHA256()
        let values = [
            projectKind.rawValue,
            gitDirectoryRelativePath.map { "gitdir:\($0)" } ?? "gitdir:nil",
            gitAvailable ? "1" : "0",
            policy.followGitIgnore ? "1" : "0",
            policy.includeIgnoredSensitiveFiles ? "1" : "0",
            String(policy.sensitiveSizeGuardBytes),
            policy.skipCommonCaches ? "1" : "0",
            policy.skipUnignoredBuildOutputs ? "1" : "0",
            policy.includeGitMetadata ? "1" : "0",
            policy.includeGitLFSObjects ? "1" : "0"
        ]
        for value in values {
            Self.updateFingerprint(&hasher, with: value)
        }
        for pattern in policy.sensitivePatterns.sorted() {
            Self.updateFingerprint(&hasher, with: "sensitive:\(pattern)")
        }
        for pattern in policy.explicitIncludes.sorted() {
            Self.updateFingerprint(&hasher, with: "include:\(pattern)")
        }
        for pattern in policy.explicitExcludes.sorted() {
            Self.updateFingerprint(&hasher, with: "exclude:\(pattern)")
        }
        for rule in projectIgnoreRules {
            Self.updateFingerprint(&hasher, with: "project:\(rule)")
        }
        Self.updateFingerprint(&hasher, with: gitTracked == nil ? "tracked:nil" : "tracked:set")
        for path in (gitTracked ?? []).sorted() {
            Self.updateFingerprint(&hasher, with: path)
        }
        Self.updateFingerprint(&hasher, with: gitManifest == nil ? "manifest:nil" : "manifest:set")
        for path in (gitManifest ?? []).sorted() {
            Self.updateFingerprint(&hasher, with: path)
        }
        Self.updateFingerprint(&hasher, with: gitIgnored == nil ? "ignored:nil" : "ignored:set")
        for path in (gitIgnored ?? []).sorted() {
            Self.updateFingerprint(&hasher, with: path)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func parseProjectIgnoreRules(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.hasPrefix("#") else { return nil }
            return value
        }
    }

    static func isCommonCachePath(_ relativePath: String) -> Bool {
        let path = normalizedPath(relativePath)
        return DevSyncDefaults.commonCacheDirectories.contains { pattern in
            path == pattern || path.hasSuffix("/\(pattern)") ||
                containsPathPattern(pattern, in: path) ||
                path.split(separator: "/").contains { DevRelativePath.matchesGlob(pattern, name: String($0)) }
        }
    }

    static func isBuildOutputPath(_ relativePath: String) -> Bool {
        let path = normalizedPath(relativePath)
        return DevSyncDefaults.buildOutputDirectories.contains { pattern in
            path == pattern || path.hasSuffix("/\(pattern)") ||
                containsPathPattern(pattern, in: path) ||
                path.split(separator: "/").contains { DevRelativePath.matchesGlob(pattern, name: String($0)) }
        }
    }

    private func matches(_ pattern: String, path: String, name: String) -> Bool {
        let pattern = normalizedPattern(pattern)
        guard !pattern.isEmpty else { return false }
        if pattern.hasSuffix("/") {
            let directory = String(pattern.dropLast())
            return path == directory || path.hasPrefix(directory + "/")
        }
        return DevRelativePath.matchesGlob(pattern, name: path) || DevRelativePath.matchesGlob(pattern, name: name)
    }

    private func isIgnoredByProjectRules(path: String, name: String) -> Bool {
        var ignored = false
        for rule in projectIgnoreRules {
            let negated = rule.hasPrefix("!")
            let pattern = negated ? String(rule.dropFirst()) : rule
            guard matches(pattern, path: path, name: name) else { continue }
            ignored = !negated
        }
        return ignored
    }

    private func isHardExcluded(path: String, name: String) -> Bool {
        DevSyncDefaults.hardExclusions.contains { pattern in
            DevRelativePath.matchesGlob(pattern, name: name) ||
                path.split(separator: "/").dropLast().contains {
                    DevRelativePath.matchesGlob(pattern, name: String($0))
                }
        }
    }

    private func pathInsideGitDirectory(_ path: String) -> String {
        guard let gitDirectoryRelativePath,
              path == gitDirectoryRelativePath || path.hasPrefix(gitDirectoryRelativePath + "/")
        else { return path }
        return String(path.dropFirst(gitDirectoryRelativePath.count).drop(while: { $0 == "/" }))
    }

    private func isGitDirectoryPath(_ path: String) -> Bool {
        guard projectKind != .nonGit else { return false }
        if path == ".git" || path.hasPrefix(".git/") { return true }
        guard let gitDirectoryRelativePath else { return false }
        return path == gitDirectoryRelativePath || path.hasPrefix(gitDirectoryRelativePath + "/")
    }

    private func isGitLFSPath(_ path: String) -> Bool {
        path == "lfs" || path.hasPrefix("lfs/")
    }

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").joined(separator: "/")
    }

    private static func containsPathPattern(_ pattern: String, in path: String) -> Bool {
        let patternComponents = pattern.split(separator: "/").map(String.init)
        let pathComponents = path.split(separator: "/").map(String.init)
        guard !patternComponents.isEmpty, patternComponents.count <= pathComponents.count else { return false }
        for start in 0...(pathComponents.count - patternComponents.count) {
            if zip(patternComponents, pathComponents[start...]).allSatisfy({ pattern, component in
                DevRelativePath.matchesGlob(pattern, name: component)
            }) {
                return true
            }
        }
        return false
    }

    private static func updateFingerprint(_ hasher: inout SHA256, with value: String) {
        let data = Data(value.utf8)
        var byteCount = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &byteCount) { hasher.update(data: Data($0)) }
        hasher.update(data: data)
    }

    private func normalizedPattern(_ pattern: String) -> String {
        var value = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("./") { value.removeFirst(2) }
        if value.hasPrefix("/") { value.removeFirst() }
        return value
    }
}
