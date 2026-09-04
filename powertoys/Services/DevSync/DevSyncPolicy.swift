import CryptoKit
import Foundation

nonisolated struct DevPolicyInput: Sendable {
    var relativePath: String
    var kind: DevEntryKind
    var size: Int64
    var isInsideGitDirectory: Bool
}

nonisolated final class DevFilePolicyEngine: Sendable {
    private let policy: DevSyncConfiguration.Policy
    private let projectKind: DevProjectKind
    private let gitDirectoryRelativePath: String?
    private let gitTracked: Set<String>?
    private let gitIgnored: Set<String>?
    private let gitAvailable: Bool
    private let projectIgnoreRules: [String]

    init(
        policy: DevSyncConfiguration.Policy,
        projectKind: DevProjectKind,
        gitDirectoryRelativePath: String?,
        gitTracked: Set<String>?,
        gitIgnored: Set<String>?,
        gitAvailable: Bool,
        projectIgnoreRules: [String]
    ) {
        self.policy = policy
        self.projectKind = projectKind
        self.gitDirectoryRelativePath = gitDirectoryRelativePath
        self.gitTracked = gitTracked
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
        let requiresStableWindow = volatile || diskImage || input.size > 1_073_741_824

        guard input.kind != .unsupported else { return .exclude(.unsupportedObjectType) }
        guard !DevRelativePath.isCloudSyncSystemPath(path) else { return .exclude(.cloudSyncInternalPath) }

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

        if input.isInsideGitDirectory {
            let gitPath = pathInsideGitDirectory(path)
            if DevGit.isTransientGitPath(gitPath) {
                return .exclude(.transientGitLock)
            }
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

        let inCache = policy.skipCommonCaches && Self.isCommonCachePath(path)
        if sensitive && policy.includeIgnoredSensitiveFiles && !inCache {
            guard input.size <= policy.sensitiveSizeGuardBytes else {
                return .exclude(.sensitiveSizeGuard)
            }
            return .include(
                .sensitiveOverride,
                sensitive: true,
                volatile: volatile,
                requiresStableWindow: requiresStableWindow
            )
        }

        let tracked = gitAvailable && gitTracked?.contains(path) == true
        if tracked {
            return .include(
                .gitTracked,
                sensitive: sensitive,
                volatile: volatile,
                requiresStableWindow: requiresStableWindow
            )
        }

        let ignoredByGit = gitAvailable && policy.followGitIgnore && gitIgnored?.contains(path) == true
        let ignoredByProject = isIgnoredByProjectRules(path: path, name: name)
        if ignoredByGit || ignoredByProject {
            return .exclude(.gitIgnored)
        }

        if isHardExcluded(path: path, name: name) {
            return .exclude(.commonExclusion)
        }
        if name.hasSuffix(".icloud") {
            return .exclude(.datalessPlaceholder)
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
        let value = [
            projectKind.rawValue,
            gitDirectoryRelativePath ?? "-",
            gitAvailable ? "1" : "0",
            policy.followGitIgnore ? "1" : "0",
            policy.includeIgnoredSensitiveFiles ? "1" : "0",
            policy.sensitivePatterns.joined(separator: "\u{1f}"),
            String(policy.sensitiveSizeGuardBytes),
            policy.skipCommonCaches ? "1" : "0",
            policy.skipUnignoredBuildOutputs ? "1" : "0",
            policy.includeGitMetadata ? "1" : "0",
            policy.includeGitLFSObjects ? "1" : "0",
            policy.explicitIncludes.joined(separator: "\u{1f}"),
            policy.explicitExcludes.joined(separator: "\u{1f}"),
            (gitTracked ?? []).sorted().joined(separator: "\u{1f}"),
            (gitIgnored ?? []).sorted().joined(separator: "\u{1f}"),
            projectIgnoreRules.joined(separator: "\u{1f}")
        ].joined(separator: "\u{1e}")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
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

    private func normalizedPattern(_ pattern: String) -> String {
        var value = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("./") { value.removeFirst(2) }
        if value.hasPrefix("/") { value.removeFirst() }
        return value
    }
}
