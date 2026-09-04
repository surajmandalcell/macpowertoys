import Darwin
import Foundation

nonisolated enum DevGitError: Error, Equatable {
    case unavailable
    case failed(exitCode: Int32, stderr: String)
}

nonisolated enum DevGit {
    private static let developerDirectoryPath: URL? = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        } catch {
            return nil
        }
    }()

    static func developerDirectory() -> URL? {
        developerDirectoryPath
    }

    static var isAvailable: Bool {
        guard let executable else { return false }
        return fileType(at: executable) == .regular
    }

    static var executable: URL? {
        developerDirectoryPath?.appendingPathComponent("usr/bin/git")
    }

    static func run(_ arguments: [String], in directory: URL, input: Data? = nil) async throws -> Data {
        guard isAvailable, let executable else { throw DevGitError.unavailable }
        let environment = ProcessInfo.processInfo.environment.merging(
            [
                "GIT_OPTIONAL_LOCKS": "0",
                "GIT_TERMINAL_PROMPT": "0",
                "PATH": "/usr/bin:/bin"
            ],
            uniquingKeysWith: { _, new in new }
        )
        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let inputPipe = input.map { _ in Pipe() }
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = inputPipe

            let outputReader = Task.detached(priority: .utility) {
                (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
            }
            let errorReader = Task.detached(priority: .utility) {
                (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
            }

            do {
                try process.run()
                if let input, let inputPipe {
                    try inputPipe.fileHandleForWriting.write(contentsOf: input)
                    try inputPipe.fileHandleForWriting.close()
                }
                process.waitUntilExit()
            } catch {
                try? outputPipe.fileHandleForReading.close()
                try? errorPipe.fileHandleForReading.close()
                _ = await outputReader.value
                _ = await errorReader.value
                throw DevGitError.failed(exitCode: -1, stderr: error.localizedDescription)
            }

            let output = await outputReader.value
            let error = await errorReader.value
            guard process.terminationStatus == 0 else {
                throw DevGitError.failed(
                    exitCode: process.terminationStatus,
                    stderr: String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return output
        }.value
    }

    static func workingTreeManifest(projectURL: URL) async throws -> [String] {
        try await workingTreeManifest(projectURL: projectURL, visited: [])
    }

    private static func workingTreeManifest(projectURL: URL, visited: Set<String>) async throws -> [String] {
        let canonicalProjectPath = projectURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard !visited.contains(canonicalProjectPath) else { return [] }
        var visited = visited
        visited.insert(canonicalProjectPath)

        let data = try await run(
            ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            in: projectURL
        )
        var manifest = nulSeparatedStrings(data)

        let submoduleData = try? await run(["submodule", "status", "--recursive"], in: projectURL)
        var submodules = submoduleData.map { initializedSubmodules(from: String(decoding: $0, as: UTF8.self)) } ?? []
        if submodules.isEmpty,
           let text = readText(at: projectURL.appendingPathComponent(".gitmodules")) {
            submodules = parseGitModulePaths(text).compactMap { path in
                let url = projectURL.appendingPathComponent(path)
                guard let mode = lstatMode(at: url.appendingPathComponent(".git")),
                      mode & S_IFMT != S_IFLNK
                else { return nil }
                return (path, Character(" "))
            }
        }
        for submodule in submodules where submodule.state != "-" {
            guard DevRelativePath.isSafe(submodule.path),
                  let mode = lstatMode(at: projectURL.appendingPathComponent(submodule.path)),
                  mode & S_IFMT != S_IFLNK,
                  mode & S_IFMT == S_IFDIR
            else { continue }
            let submoduleURL = projectURL.appendingPathComponent(submodule.path, isDirectory: true)
            let nested = try await workingTreeManifest(projectURL: submoduleURL, visited: visited)
            manifest.append(contentsOf: nested.compactMap { nestedPath in
                guard DevRelativePath.isSafe(nestedPath) else { return nil }
                return "\(submodule.path)/\(nestedPath)"
            })
        }
        return manifest
    }

    static func ignoredPaths(projectURL: URL, candidates: [String]) async throws -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        let input = candidates.reduce(into: Data()) { result, candidate in
            result.append(contentsOf: candidate.utf8)
            result.append(0)
        }
        do {
            let output = try await run(["check-ignore", "--stdin", "-z"], in: projectURL, input: input)
            return Set(nulSeparatedStrings(output))
        } catch let error as DevGitError {
            guard case .failed(let exitCode, _) = error, exitCode == 1 else { throw error }
            return []
        }
    }

    static func topology(projectURL: URL, internalRoot: URL, externalRoot: URL) async -> DevGitTopology {
        let gitURL = projectURL.appendingPathComponent(".git", isDirectory: true)
        let gitMode = lstatMode(at: gitURL)
        let validGitFile = gitMode.map { $0 & S_IFMT == S_IFREG } == true ? gitDirectoryFromPointer(at: gitURL, projectURL: projectURL) : nil
        let hasGitDirectory = gitMode.map { $0 & S_IFMT == S_IFDIR } == true
        let isBare = !hasGitDirectory && validGitFile == nil && isBareRepository(at: projectURL)
        let localKind: DevProjectKind = isBare ? .gitBareRepository : (hasGitDirectory || validGitFile != nil ? .gitRepository : .nonGit)
        guard isAvailable else {
            return DevGitTopology(kind: .nonGit)
        }
        guard localKind != .nonGit else { return DevGitTopology(kind: .nonGit) }

        var actualGitDirectory = hasGitDirectory ? gitURL : validGitFile
        var commonDirectory = actualGitDirectory
        if localKind != .gitBareRepository {
            if let output = try? await run(["rev-parse", "--git-dir"], in: projectURL),
               let value = firstLine(output), !value.isEmpty {
                actualGitDirectory = resolvePath(value, relativeTo: projectURL)
            }
            if let output = try? await run(["rev-parse", "--git-common-dir"], in: projectURL),
               let value = firstLine(output), !value.isEmpty {
                commonDirectory = resolvePath(value, relativeTo: projectURL)
            }
        }

        var kind = localKind
        if isBare,
           let output = try? await run(["rev-parse", "--is-bare-repository"], in: projectURL),
           firstLine(output) == "true" {
            kind = .gitBareRepository
        } else if let actualGitDirectory, let commonDirectory,
                  isLinkedWorktree(gitDirectory: actualGitDirectory, commonDirectory: commonDirectory) {
            kind = .gitLinkedWorktree
        } else if hasGitDirectory || validGitFile != nil {
            kind = .gitRepository
        }

        let resolvedGitDirectory = actualGitDirectory ?? (kind == .gitBareRepository ? nil : gitURL)
        let resolvedCommonDirectory = commonDirectory ?? actualGitDirectory ?? (kind == .gitBareRepository ? nil : gitURL)
        let submodulePaths = await submodulePaths(projectURL: projectURL)
        let metadataDirectories = [resolvedGitDirectory, resolvedCommonDirectory].compactMap { $0 }
        let alternates = Array(Set(metadataDirectories.flatMap(alternatePaths)))
        let roots = [internalRoot, externalRoot].map(canonicalPath)

        return DevGitTopology(
            kind: kind,
            gitDirectory: resolvedGitDirectory.map { relativePath($0, to: projectURL) },
            commonDirectory: resolvedCommonDirectory.map { relativePath($0, to: projectURL) },
            submodulePaths: submodulePaths,
            hasAlternates: !alternates.isEmpty,
            alternateOutsidePair: alternates.contains { !isInside($0, roots: roots) },
            commonDirectoryOutsidePair: resolvedCommonDirectory.map { !isInside($0, roots: roots) } ?? false,
            isShallow: metadataDirectories.contains { isRegularFile(at: $0.appendingPathComponent("shallow")) },
            hasLFS: metadataDirectories.contains { isDirectory(at: $0.appendingPathComponent("lfs")) } || hasLFSAttributes(at: projectURL)
        )
    }

    static func identity(projectURL: URL) async -> DevProjectIdentity? {
        guard isAvailable else { return nil }
        let topology = await topology(projectURL: projectURL, internalRoot: projectURL, externalRoot: projectURL)
        guard topology.kind != .nonGit, topology.kind != .gitBareRepository else {
            return topology.kind == .gitBareRepository ? await bareIdentity(projectURL: projectURL, topology: topology) : nil
        }

        let remoteHints: [String]
        do {
            let output = try await run(["remote", "-v"], in: projectURL)
            remoteHints = remoteURLs(from: String(decoding: output, as: UTF8.self))
        } catch {
            return nil
        }
        let head = (try? await run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: projectURL)).flatMap(firstLine)
        let commit = (try? await run(["rev-list", "--max-parents=0", "HEAD"], in: projectURL)).flatMap(firstLine)
        return DevProjectIdentity(
            remoteURLHints: remoteHints,
            headReference: head,
            firstCommit: commit,
            topologyKind: topology.kind,
            fingerprint: DevProjectIdentity.fingerprint(
                remoteURLHints: remoteHints,
                firstCommit: commit,
                topologyKind: topology.kind
            )
        )
    }

    private static func bareIdentity(projectURL: URL, topology: DevGitTopology) async -> DevProjectIdentity? {
        let remoteHints = (try? await run(["remote", "-v"], in: projectURL)).map {
            remoteURLs(from: String(decoding: $0, as: UTF8.self))
        } ?? []
        let head = (try? await run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: projectURL)).flatMap(firstLine)
        let commit = (try? await run(["rev-list", "--max-parents=0", "HEAD"], in: projectURL)).flatMap(firstLine)
        return DevProjectIdentity(
            remoteURLHints: remoteHints,
            headReference: head,
            firstCommit: commit,
            topologyKind: topology.kind,
            fingerprint: DevProjectIdentity.fingerprint(
                remoteURLHints: remoteHints,
                firstCommit: commit,
                topologyKind: topology.kind
            )
        )
    }

    static func activeLocks(projectURL: URL, gitDirectory: URL) -> [String] {
        let resolvedGitDirectory: URL
        if fileType(at: gitDirectory) == .regular,
           let pointer = gitDirectoryFromPointer(at: gitDirectory, projectURL: projectURL) {
            resolvedGitDirectory = pointer
        } else {
            resolvedGitDirectory = gitDirectory
        }
        guard fileType(at: resolvedGitDirectory) == .directory else { return [] }
        var paths: [String] = []
        for name in ["index.lock", "HEAD.lock", "config.lock", "packed-refs.lock", "shallow.lock"] {
            let url = resolvedGitDirectory.appendingPathComponent(name)
            if isRegularFile(at: url) { paths.append(relativePath(url, to: projectURL)) }
        }
        let refsURL = resolvedGitDirectory.appendingPathComponent("refs", isDirectory: true)
        collectLockFiles(in: refsURL, projectURL: projectURL, into: &paths)
        let packURL = resolvedGitDirectory.appendingPathComponent("objects/pack", isDirectory: true)
        if let entries = directoryContents(packURL) {
            for entry in entries where entry.lastPathComponent.hasPrefix("tmp_") && isRegularFile(at: entry) {
                paths.append(relativePath(entry, to: projectURL))
            }
        }
        return paths.sorted()
    }

    static func globalIgnoreIdentity() async -> (path: String, modificationDate: Date)? {
        guard isAvailable else { return nil }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        guard let output = try? await run(["config", "--global", "--path", "--get", "core.excludesFile"], in: directory),
              let path = firstLine(output), !path.isEmpty
        else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        guard let date = modificationDate(at: url) else { return nil }
        return (url.path, date)
    }

    static func isTransientGitPath(_ relativePathInsideGitDirectory: String) -> Bool {
        let components = relativePathInsideGitDirectory.split(separator: "/").map(String.init)
        guard let last = components.last else { return false }
        if last.hasSuffix(".lock") { return true }
        return components.count == 3 && components[0] == "objects" && components[1] == "pack" && last.hasPrefix("tmp_")
    }

    private static func readText(at url: URL) -> String? {
        guard fileType(at: url) == .regular, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            data.append(chunk)
        }
        return String(data: data, encoding: .utf8)
    }

    private static func gitDirectoryFromPointer(at url: URL, projectURL: URL) -> URL? {
        guard let line = readText(at: url)?.split(whereSeparator: \.isNewline).first,
              line.hasPrefix("gitdir:"),
              let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces).nilIfEmpty,
              !path.contains("\0")
        else { return nil }
        return resolvePath(path, relativeTo: projectURL)
    }

    private static func isBareRepository(at url: URL) -> Bool {
        isRegularFile(at: url.appendingPathComponent("HEAD")) &&
            isDirectory(at: url.appendingPathComponent("objects")) &&
            isDirectory(at: url.appendingPathComponent("refs"))
    }

    private static func resolvePath(_ value: String, relativeTo base: URL) -> URL {
        if value.hasPrefix("/") { return URL(fileURLWithPath: value).standardizedFileURL }
        return URL(fileURLWithPath: value, relativeTo: base).standardizedFileURL
    }

    private static func firstLine(_ data: Data) -> String? {
        firstLine(String(decoding: data, as: UTF8.self))
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    private static func initializedSubmodules(from text: String) -> [(path: String, state: Character)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.count > 42 else { return nil }
            let state = line.first!
            let withoutState = line.dropFirst()
            guard let hashEnd = withoutState.firstIndex(of: " ") else { return nil }
            let remainder = withoutState[hashEnd...].drop(while: { $0 == " " || $0 == "\t" })
            guard !remainder.isEmpty else { return nil }
            let path = remainder.split(separator: " (").first.map(String.init) ?? String(remainder)
            guard !path.isEmpty else { return nil }
            return (path, state)
        }
    }

    private static func submodulePaths(projectURL: URL) async -> [String] {
        if let output = try? await run(["submodule", "status", "--recursive"], in: projectURL) {
            let paths = initializedSubmodules(from: String(decoding: output, as: UTF8.self)).map(\.path)
            if !paths.isEmpty { return Array(Set(paths)).sorted() }
        }
        guard let text = readText(at: projectURL.appendingPathComponent(".gitmodules")) else { return [] }
        return parseGitModulePaths(text)
    }

    private static func parseGitModulePaths(_ text: String) -> [String] {
        var paths: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "path", DevRelativePath.isSafe(String(parts[1])) else { continue }
            paths.append(String(parts[1]))
        }
        return Array(Set(paths)).sorted()
    }

    private static func isLinkedWorktree(gitDirectory: URL, commonDirectory: URL) -> Bool {
        let common = canonicalPath(commonDirectory)
        let git = canonicalPath(gitDirectory)
        return git.hasPrefix(common + "/worktrees/")
    }

    private static func alternatePaths(gitDirectory: URL) -> [URL] {
        let alternatesURL = gitDirectory.appendingPathComponent("objects/info/alternates")
        guard let text = readText(at: alternatesURL) else { return [] }
        let objectsURL = gitDirectory.appendingPathComponent("objects", isDirectory: true)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return resolvePath(value, relativeTo: objectsURL).resolvingSymlinksInPath().standardizedFileURL
        }
    }

    private static func hasLFSAttributes(at projectURL: URL) -> Bool {
        guard let text = readText(at: projectURL.appendingPathComponent(".gitattributes")) else { return false }
        return text.split(whereSeparator: \.isNewline).contains { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return !value.hasPrefix("#") && value.localizedCaseInsensitiveContains("filter=lfs")
        }
    }

    private static func relativePath(_ url: URL, to base: URL) -> String {
        let path = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path
        guard path != basePath else { return "" }
        guard path.hasPrefix(basePath + "/") else { return path }
        return String(path.dropFirst(basePath.count + 1))
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func isInside(_ url: URL, roots: [String]) -> Bool {
        let path = canonicalPath(url)
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private static func collectLockFiles(in directory: URL, projectURL: URL, into paths: inout [String]) {
        guard isDirectory(at: directory), let entries = directoryContents(directory) else { return }
        for entry in entries {
            guard fileType(at: entry) != .symlink else { continue }
            if isDirectory(at: entry) {
                collectLockFiles(in: entry, projectURL: projectURL, into: &paths)
            } else if entry.lastPathComponent.hasSuffix(".lock") {
                paths.append(relativePath(entry, to: projectURL))
            }
        }
    }

    private static func directoryContents(_ url: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
    }

    private static func isDirectory(at url: URL) -> Bool {
        fileType(at: url) == .directory
    }

    private static func isRegularFile(at url: URL) -> Bool {
        fileType(at: url) == .regular
    }

    private static func modificationDate(at url: URL) -> Date? {
        guard let value = lstatValue(at: url) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value.st_mtimespec.tv_sec) + TimeInterval(value.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    private nonisolated enum FileType {
        case regular
        case directory
        case symlink
        case other
    }

    private static func fileType(at url: URL) -> FileType {
        guard let mode = lstatMode(at: url) else { return .other }
        switch mode & S_IFMT {
        case S_IFREG: return .regular
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    private static func lstatMode(at url: URL) -> UInt16? {
        guard let value = lstatValue(at: url) else { return nil }
        return value.st_mode
    }

    private static func lstatValue(at url: URL) -> stat? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var value = stat()
            guard lstat(path, &value) == 0 else { return nil }
            return value
        }
    }

    private static func nulSeparatedStrings(_ data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func remoteURLs(from text: String) -> [String] {
        var values: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let value = String(line)
            guard let tab = value.firstIndex(of: "\t") else { continue }
            let remainder = value[value.index(after: tab)...]
            guard let suffix = remainder.range(of: " (") else { continue }
            let url = String(remainder[..<suffix.lowerBound])
            let stripped = stripCredentials(from: url)
            if !stripped.isEmpty, !values.contains(stripped) { values.append(stripped) }
        }
        return values.sorted()
    }

    private static func stripCredentials(from value: String) -> String {
        if var components = URLComponents(string: value), components.host != nil {
            components.user = nil
            components.password = nil
            return components.string ?? value
        }
        guard let at = value.firstIndex(of: "@"), value[..<at].contains(":"),
              let colon = value[..<at].firstIndex(of: ":"), colon > value.startIndex
        else { return value }
        return String(value[value.index(after: at)...])
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
