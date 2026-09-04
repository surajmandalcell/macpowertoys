import Darwin
import Foundation

nonisolated enum DevGitError: Error, Equatable {
    case unavailable
    case failed(exitCode: Int32, stderr: String)
}

private nonisolated final class DevGitProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func install(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        return true
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

nonisolated enum DevGit {
    private static let maximumTextBytes = 1_048_576
    private static let textReadChunkBytes = 64 * 1_024

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
        guard !directory.path.contains("\0"), arguments.allSatisfy({ !$0.contains("\0") }) else {
            throw DevGitError.failed(exitCode: -1, stderr: "Invalid Git path or argument")
        }
        let environment = ProcessInfo.processInfo.environment.merging(
            [
                "GIT_OPTIONAL_LOCKS": "0",
                "GIT_TERMINAL_PROMPT": "0",
                "PATH": "/usr/bin:/bin"
            ],
            uniquingKeysWith: { _, new in new }
        )
        let processHandle = DevGitProcessHandle()
        let operation = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard let executable, fileType(at: executable) == .regular else {
                throw DevGitError.unavailable
            }
            guard fileType(at: directory) == .directory else {
                throw DevGitError.failed(exitCode: -1, stderr: "Invalid Git working directory")
            }
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
            process.standardInput = inputPipe ?? FileHandle.nullDevice

            guard processHandle.install(process) else { throw CancellationError() }
            defer { processHandle.clear() }

            let outputReader = Task.detached(priority: .utility) {
                (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
            }
            let errorReader = Task.detached(priority: .utility) {
                (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
            }

            do {
                try process.run()
                if Task.isCancelled {
                    process.terminate()
                }
                if let input, let inputPipe {
                    try inputPipe.fileHandleForWriting.write(contentsOf: input)
                    try inputPipe.fileHandleForWriting.close()
                }
                process.waitUntilExit()
            } catch {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                try? outputPipe.fileHandleForWriting.close()
                try? errorPipe.fileHandleForWriting.close()
                _ = await outputReader.value
                _ = await errorReader.value
                throw DevGitError.failed(exitCode: -1, stderr: error.localizedDescription)
            }

            let output = await outputReader.value
            let error = await errorReader.value
            try Task.checkCancellation()
            guard process.terminationStatus == 0 else {
                throw DevGitError.failed(
                    exitCode: process.terminationStatus,
                    stderr: String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return output
        }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
            processHandle.cancel()
        }
    }

    static func workingTreeManifest(projectURL: URL) async throws -> [String] {
        let operation = Task.detached(priority: .utility) {
            try await workingTreeManifest(projectURL: projectURL, visited: [])
        }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
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
        var manifest = nulSeparatedStrings(data).filter(DevRelativePath.isSafe)

        for submodulePath in await configuredSubmodulePaths(projectURL: projectURL) {
            guard isInitializedSubmodule(submodulePath, in: projectURL) else { continue }
            let submoduleURL = projectURL.appendingPathComponent(submodulePath, isDirectory: true)
            let nested = try await workingTreeManifest(projectURL: submoduleURL, visited: visited)
            manifest.append(contentsOf: nested.compactMap { nestedPath in
                guard DevRelativePath.isSafe(nestedPath) else { return nil }
                return "\(submodulePath)/\(nestedPath)"
            })
        }
        return Array(Set(manifest)).sorted()
    }

    static func ignoredPaths(projectURL: URL, candidates: [String]) async throws -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        guard candidates.allSatisfy(DevRelativePath.isSafe) else {
            throw DevGitError.failed(exitCode: -1, stderr: "Invalid Git ignore candidate")
        }
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
        let operation = Task.detached(priority: .utility) {
            await topologyOffMain(projectURL: projectURL, internalRoot: internalRoot, externalRoot: externalRoot)
        }
        return await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private static func topologyOffMain(projectURL: URL, internalRoot: URL, externalRoot: URL) async -> DevGitTopology {
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

        var actualGitDirectory = isBare ? projectURL : (hasGitDirectory ? gitURL : validGitFile)
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
        let operation = Task.detached(priority: .utility) {
            await globalIgnoreIdentityOffMain()
        }
        return await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private static func globalIgnoreIdentityOffMain() async -> (path: String, modificationDate: Date)? {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        guard let output = try? await run(["config", "--path", "--get", "core.excludesFile"], in: directory),
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
        do {
            while let chunk = try handle.read(upToCount: min(textReadChunkBytes, maximumTextBytes - data.count + 1)) {
                guard !chunk.isEmpty else { break }
                data.append(chunk)
                guard data.count <= maximumTextBytes else { return nil }
            }
        } catch {
            return nil
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

    private static func submodulePaths(projectURL: URL) async -> [String] {
        await submodulePaths(projectURL: projectURL, visited: [])
    }

    private static func submodulePaths(projectURL: URL, visited: Set<String>) async -> [String] {
        let canonicalProjectPath = canonicalPath(projectURL)
        guard !visited.contains(canonicalProjectPath) else { return [] }
        var visited = visited
        visited.insert(canonicalProjectPath)
        let directPaths = await configuredSubmodulePaths(projectURL: projectURL)
        var paths = directPaths
        for directPath in directPaths where isInitializedSubmodule(directPath, in: projectURL) {
            let submoduleURL = projectURL.appendingPathComponent(directPath, isDirectory: true)
            let nestedPaths = await submodulePaths(projectURL: submoduleURL, visited: visited)
            paths.append(contentsOf: nestedPaths.map { "\(directPath)/\($0)" })
        }
        return Array(Set(paths)).sorted()
    }

    private static func configuredSubmodulePaths(projectURL: URL) async -> [String] {
        let configurationURL = projectURL.appendingPathComponent(".gitmodules")
        guard fileType(at: configurationURL) == .regular,
              let output = try? await run(
                ["config", "--null", "--no-includes", "--file", ".gitmodules", "--get-regexp", "^submodule\\..*\\.path$"],
                in: projectURL
              )
        else { return [] }
        let paths = output.split(separator: 0).compactMap { record -> String? in
            guard let separator = record.firstIndex(of: 10) else { return nil }
            let value = String(decoding: record[record.index(after: separator)...], as: UTF8.self)
            return DevRelativePath.isSafe(value) ? value : nil
        }
        return Array(Set(paths)).sorted()
    }

    private static func isInitializedSubmodule(_ path: String, in projectURL: URL) -> Bool {
        guard DevRelativePath.isSafe(path),
              fileType(at: projectURL.appendingPathComponent(path, isDirectory: true)) == .directory
        else { return false }
        let markerType = fileType(at: projectURL.appendingPathComponent(path).appendingPathComponent(".git"))
        return markerType == .directory || markerType == .regular
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
        var values = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let value = String(line)
            guard let tab = value.firstIndex(of: "\t") else { continue }
            let remainder = value[value.index(after: tab)...]
            guard let suffix = remainder.range(of: " (") else { continue }
            let url = String(remainder[..<suffix.lowerBound])
            let stripped = stripCredentials(from: url)
            if !stripped.isEmpty { values.insert(stripped) }
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
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
