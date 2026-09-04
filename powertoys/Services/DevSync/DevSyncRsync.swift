import CryptoKit
import Darwin
import Foundation

nonisolated enum DevRsyncLocator {
    static let candidatePaths = [
        "/opt/homebrew/bin/rsync",
        "/usr/local/bin/rsync",
        "/usr/bin/rsync"
    ]

    static func locate(preferredPath: String?) -> URL? {
        let fileManager = FileManager.default
        if let preferredPath, fileManager.isExecutableFile(atPath: preferredPath) {
            return URL(fileURLWithPath: preferredPath)
        }
        return candidatePaths
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

nonisolated enum DevRsyncProbeError: Error, Equatable, Sendable {
    case executableUnavailable(String)
    case commandFailed(String)
    case selfTestFailed(String)
}

nonisolated enum DevRsyncProbe {
    private struct SelfTestResult {
        var passed = false
        var supportsFrom0 = false
        var supportsDoubleDash = false
        var supportsXattrs = false
        var notes: [String] = []
    }

    static func parseHelp(_ helpText: String) -> Set<String> {
        let bytes = Array(helpText.utf8)
        var options: Set<String> = []
        var index = 0
        while index + 2 < bytes.count {
            guard bytes[index] == 45, bytes[index + 1] == 45 else {
                index += 1
                continue
            }
            let start = index
            index += 2
            guard isLongOptionByte(bytes[index]) else { continue }
            while index < bytes.count, isLongOptionByte(bytes[index]) {
                index += 1
            }
            options.insert(String(decoding: bytes[start..<index], as: UTF8.self))
        }
        return options
    }

    static func parseVersion(_ versionText: String) -> (version: String, protocolVersion: Int?, isOpenrsync: Bool) {
        let lowercased = versionText.lowercased()
        var version = ""
        if let versionRange = lowercased.range(of: "rsync version") {
            let suffix = lowercased[versionRange.upperBound...]
            version = firstVersion(in: String(suffix))
        }
        if version.isEmpty {
            version = firstVersion(in: versionText)
        }
        let protocolVersion: Int?
        if let protocolRange = lowercased.range(of: "protocol version") {
            protocolVersion = firstInteger(in: String(lowercased[protocolRange.upperBound...]))
        } else {
            protocolVersion = nil
        }
        return (version: version, protocolVersion: protocolVersion, isOpenrsync: lowercased.contains("openrsync"))
    }

    static func probe(executable: URL, selfTestDirectory: URL? = nil) async throws -> DevRsyncCapabilities {
        try await Task.detached(priority: .utility) {
            try probeSynchronously(executable: executable, selfTestDirectory: selfTestDirectory)
        }.value
    }

    private static func probeSynchronously(executable: URL, selfTestDirectory: URL?) throws -> DevRsyncCapabilities {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DevRsyncProbeError.executableUnavailable(executable.path)
        }
        let versionOutput = try DevRsyncProcessRunner.run(executable: executable, arguments: ["--version"])
        guard versionOutput.status == 0 else {
            throw DevRsyncProbeError.commandFailed(String(decoding: versionOutput.stderr, as: UTF8.self))
        }
        let helpOutput = try DevRsyncProcessRunner.run(executable: executable, arguments: ["--help"])
        guard helpOutput.status == 0 else {
            throw DevRsyncProbeError.commandFailed(String(decoding: helpOutput.stderr, as: UTF8.self))
        }

        let versionText = String(decoding: versionOutput.stdout + versionOutput.stderr, as: UTF8.self)
        let helpText = String(decoding: helpOutput.stdout + helpOutput.stderr, as: UTF8.self)
        let version = parseVersion(versionText)
        let options = parseHelp(helpText)
        let selfTest = try runSelfTest(
            executable: executable,
            helpText: helpText,
            supportedOptions: options,
            selfTestDirectory: selfTestDirectory
        )
        var notes = selfTest.notes
        let supportsFilesFrom = options.contains("--files-from")
        let supportsPartialDir = options.contains("--partial-dir")
        let supportsBackupDir = options.contains("--backup-dir")
        let supportsItemizeChanges = options.contains("--itemize-changes")
        let supportsExecutability = options.contains("--executability")
        let supportsPerms = options.contains("--perms") || shortOptionIsSupported("p", in: helpText)
        let supportsHardLinks = options.contains("--hard-links") || shortOptionIsSupported("H", in: helpText)
        let supportsCrtimes = options.contains("--crtimes")
        let supportsOmitDirTimes = options.contains("--omit-dir-times") || shortOptionIsSupported("O", in: helpText)
        let supportsModifyWindow = options.contains("--modify-window")
        let supportsXattrs = selfTest.supportsXattrs && options.contains("--extended-attributes")
        if !supportsFilesFrom { notes.append("NUL manifests are unavailable") }
        if !supportsPartialDir { notes.append("Partial files are not isolated") }
        if !supportsBackupDir { notes.append("Backup history is unavailable") }
        if !supportsItemizeChanges { notes.append("Itemized progress is unavailable") }
        if !supportsExecutability { notes.append("Executable bits are not preserved") }
        if !supportsPerms { notes.append("Unix permissions are not preserved") }
        if !supportsXattrs { notes.append("Extended attributes are not preserved") }
        if !supportsHardLinks { notes.append("Hard links are copied as separate files") }
        if !supportsCrtimes { notes.append("Creation times are not preserved") }
        if !selfTest.supportsFrom0 { notes.append("Names with newlines are deferred") }
        if !selfTest.supportsDoubleDash { notes.append("Path separator is unavailable") }

        let fingerprint = fingerprint(executable: executable, versionText: versionText)
        return DevRsyncCapabilities(
            executablePath: executable.path,
            versionText: versionText,
            protocolVersion: version.protocolVersion,
            isOpenrsync: version.isOpenrsync,
            supportedLongOptions: options,
            supportsFilesFrom: supportsFilesFrom,
            supportsFrom0: selfTest.supportsFrom0,
            supportsPartialDir: supportsPartialDir,
            supportsBackupDir: supportsBackupDir,
            supportsItemizeChanges: supportsItemizeChanges,
            supportsExecutability: supportsExecutability,
            supportsPerms: supportsPerms,
            supportsXattrs: supportsXattrs,
            supportsACLs: options.contains("--acls"),
            supportsHardLinks: supportsHardLinks,
            supportsCrtimes: supportsCrtimes,
            supportsOmitDirTimes: supportsOmitDirTimes,
            supportsModifyWindow: supportsModifyWindow,
            supportsDoubleDash: selfTest.supportsDoubleDash,
            selfTestPassed: selfTest.passed,
            selfTestNotes: notes,
            fingerprint: fingerprint,
            probedAt: Date()
        )
    }

    private static func runSelfTest(
        executable: URL,
        helpText: String,
        supportedOptions: Set<String>,
        selfTestDirectory: URL?
    ) throws -> SelfTestResult {
        let fileManager = FileManager.default
        let parent = selfTestDirectory ?? FileManager.default.temporaryDirectory
        let testRoot = parent.appendingPathComponent("devsync-rsync-\(UUID().uuidString)", isDirectory: true)
        let source = testRoot.appendingPathComponent("source", isDirectory: true)
        let destination = testRoot.appendingPathComponent("destination", isDirectory: true)
        let partial = testRoot.appendingPathComponent("partial", isDirectory: true)
        let backup = testRoot.appendingPathComponent("backup", isDirectory: true)
        defer { try? fileManager.removeItem(at: testRoot) }
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        try makeSelfTestTree(source: source)

        let hasXattrOption = supportedOptions.contains("--extended-attributes")
        let hasHardLinks = supportedOptions.contains("--hard-links") || shortOptionIsSupported("H", in: helpText)
        let hasFrom0LongOption = supportedOptions.contains("--from0")
        let hasPartialDirectory = supportedOptions.contains("--partial-dir")
        let hasItemize = supportedOptions.contains("--itemize-changes")
        let hasExecutability = supportedOptions.contains("--executability")
        let hasPerms = supportedOptions.contains("--perms") || shortOptionIsSupported("p", in: helpText)
        let hasOmitDirTimes = supportedOptions.contains("--omit-dir-times") || shortOptionIsSupported("O", in: helpText)
        let hasBackup = supportedOptions.contains("--backup-dir")
        var result = SelfTestResult()
        var useFrom0 = true
        var useDoubleDash = true
        var useXattrs = hasXattrOption
        var copied = false
        var lastError = ""

        for _ in 0..<4 {
            try? fileManager.removeItem(at: destination)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let newlineURL = source.appendingPathComponent("newline\nname")
            let hasNewlineName = fileManager.fileExists(atPath: newlineURL.path)
            var manifest = selfTestManifest(hasNewlineName: hasNewlineName && useFrom0, hasHardLinks: hasHardLinks)
            manifest = manifest.sorted { utf8LessThan($0, $1) }
            let arguments = selfTestArguments(
                source: source,
                destination: destination,
                partial: partial,
                useFrom0: useFrom0,
                useDoubleDash: useDoubleDash,
                useXattrs: useXattrs,
                useHardLinks: hasHardLinks,
                usePartialDirectory: hasPartialDirectory,
                useItemize: hasItemize,
                useExecutability: hasExecutability,
                usePerms: hasPerms,
                useOmitDirTimes: hasOmitDirTimes,
                from0LongOption: hasFrom0LongOption
            )
            let output = try DevRsyncProcessRunner.run(
                executable: executable,
                arguments: arguments,
                stdin: manifestData(manifest, nulSeparated: useFrom0),
                currentDirectoryURL: source
            )
            guard output.status == 0 else {
                lastError = String(decoding: output.stderr, as: UTF8.self)
                if useXattrs {
                    useXattrs = false
                    result.notes.append("Extended attributes option failed its self-test")
                } else if useDoubleDash {
                    useDoubleDash = false
                    result.notes.append("Double-dash path separator failed its self-test")
                } else if useFrom0 {
                    useFrom0 = false
                    result.notes.append("NUL manifest input is unavailable")
                } else {
                    break
                }
                continue
            }
            if useXattrs && !verifyXattr(source: source, destination: destination) {
                useXattrs = false
                result.notes.append("Extended attributes did not round-trip")
                continue
            }
            guard verifySelfTestCopy(
                source: source,
                destination: destination,
                hasNewlineName: fileManager.fileExists(atPath: newlineURL.path) && useFrom0,
                hasHardLinks: hasHardLinks,
                checkExecutable: hasExecutability
            ) else {
                lastError = "Copied path matrix did not verify"
                break
            }
            copied = true
            result.supportsFrom0 = useFrom0
            result.supportsDoubleDash = useDoubleDash
            result.supportsXattrs = useXattrs
            if fileManager.fileExists(atPath: newlineURL.path) && !useFrom0 {
                result.notes.append("Names with newlines are deferred")
            } else if !fileManager.fileExists(atPath: newlineURL.path) {
                result.notes.append("Newline names are unavailable on this file system")
            }
            break
        }

        guard copied else {
            result.notes.append(lastError.isEmpty ? "Rsync self-test failed" : "Rsync self-test failed: \(lastError.prefix(160))")
            return result
        }
        if hasBackup {
            let destinationFile = destination.appendingPathComponent("regular.txt")
            try Data("old destination".utf8).write(to: destinationFile)
            let backupArguments = selfTestArguments(
                source: source,
                destination: destination,
                partial: partial,
                useFrom0: result.supportsFrom0,
                useDoubleDash: result.supportsDoubleDash,
                useXattrs: false,
                useHardLinks: false,
                usePartialDirectory: hasPartialDirectory,
                useItemize: false,
                useExecutability: false,
                usePerms: false,
                useOmitDirTimes: hasOmitDirTimes,
                from0LongOption: hasFrom0LongOption,
                backupDirectory: backup
            )
            let output = try DevRsyncProcessRunner.run(
                executable: executable,
                arguments: backupArguments,
                stdin: manifestData(["regular.txt"], nulSeparated: result.supportsFrom0),
                currentDirectoryURL: source
            )
            let backupFile = backup.appendingPathComponent("regular.txt")
            if output.status != 0 || String(decoding: (try? Data(contentsOf: backupFile)) ?? Data(), as: UTF8.self) != "old destination" {
                result.notes.append("Backup-directory behavior failed its self-test")
                result.passed = false
                return result
            }
        }
        result.passed = true
        return result
    }

    private static func makeSelfTestTree(source: URL) throws {
        let fileManager = FileManager.default
        try Data("regular".utf8).write(to: source.appendingPathComponent("regular.txt"))
        try Data("#!/bin/sh\necho devsync\n".utf8).write(to: source.appendingPathComponent("script.sh"))
        chmod(source.appendingPathComponent("script.sh").path, mode_t(0o755))
        try fileManager.createDirectory(at: source.appendingPathComponent("empty directory"), withIntermediateDirectories: true)
        let spaceDirectory = source.appendingPathComponent("space directory", isDirectory: true)
        try fileManager.createDirectory(at: spaceDirectory, withIntermediateDirectories: true)
        try Data("unicode".utf8).write(to: spaceDirectory.appendingPathComponent("emoji 🚀.txt"))
        try Data("combining".utf8).write(to: source.appendingPathComponent("e\u{301}.txt"))
        try Data("link target".utf8).write(to: source.appendingPathComponent("link-target.txt"))
        try fileManager.createSymbolicLink(
            atPath: source.appendingPathComponent("link.txt").path,
            withDestinationPath: "link-target.txt"
        )
        try Data("hard link".utf8).write(to: source.appendingPathComponent("hard-source.txt"))
        try fileManager.linkItem(
            at: source.appendingPathComponent("hard-source.txt"),
            to: source.appendingPathComponent("hard-copy.txt")
        )
        try? Data("newline".utf8).write(to: source.appendingPathComponent("newline\nname"))
        let xattrName = "com.surajmandal.macpowertoys.devsync-probe"
        _ = setXattr(Data("probe-xattr".utf8), name: xattrName, path: source.appendingPathComponent("regular.txt").path)
    }

    private static func selfTestManifest(hasNewlineName: Bool, hasHardLinks: Bool) -> [String] {
        var paths = [
            "regular.txt",
            "script.sh",
            "empty directory",
            "space directory",
            "space directory/emoji 🚀.txt",
            "e\u{301}.txt",
            "link-target.txt",
            "link.txt"
        ]
        if hasHardLinks { paths += ["hard-source.txt", "hard-copy.txt"] }
        if hasNewlineName { paths.append("newline\nname") }
        return paths
    }

    private static func selfTestArguments(
        source: URL,
        destination: URL,
        partial: URL,
        useFrom0: Bool,
        useDoubleDash: Bool,
        useXattrs: Bool,
        useHardLinks: Bool,
        usePartialDirectory: Bool,
        useItemize: Bool,
        useExecutability: Bool,
        usePerms: Bool,
        useOmitDirTimes: Bool,
        from0LongOption: Bool,
        backupDirectory: URL? = nil
    ) -> [String] {
        var arguments = ["-l", "-t"]
        if useOmitDirTimes { arguments.append("-O") }
        if useExecutability { arguments.append("--executability") }
        if usePartialDirectory {
            arguments.append("--partial")
            arguments.append("--partial-dir=\(partial.path)")
        }
        if useItemize { arguments.append("--itemize-changes") }
        arguments.append("--files-from=-")
        if useFrom0 { arguments.append(from0LongOption ? "--from0" : "-0") }
        if let backupDirectory {
            arguments.append("--backup")
            arguments.append("--backup-dir=\(backupDirectory.path)")
        }
        if usePerms { arguments.append("-p") }
        if useXattrs { arguments.append("-X") }
        if useHardLinks { arguments.append("-H") }
        if useDoubleDash { arguments.append("--") }
        arguments.append(directoryArgument(source))
        arguments.append(directoryArgument(destination))
        return arguments
    }

    private static func verifySelfTestCopy(
        source: URL,
        destination: URL,
        hasNewlineName: Bool,
        hasHardLinks: Bool,
        checkExecutable: Bool
    ) -> Bool {
        let fileManager = FileManager.default
        let paths = selfTestManifest(hasNewlineName: hasNewlineName, hasHardLinks: hasHardLinks)
        guard paths.allSatisfy({ fileManager.fileExists(atPath: destination.appendingPathComponent($0).path) }) else { return false }
        let sourceLink = source.appendingPathComponent("link.txt").path
        let destinationLink = destination.appendingPathComponent("link.txt").path
        guard let linkStat = lstatValue(destinationLink), (linkStat.st_mode & S_IFMT) == S_IFLNK else { return false }
        guard readLink(destinationLink) == readLink(sourceLink) else { return false }
        if checkExecutable {
            guard let scriptStat = lstatValue(destination.appendingPathComponent("script.sh").path), scriptStat.st_mode & 0o111 != 0 else {
                return false
            }
        }
        if hasHardLinks && !sameInode(
            destination.appendingPathComponent("hard-source.txt").path,
            destination.appendingPathComponent("hard-copy.txt").path
        ) {
            return false
        }
        guard let sourceStat = lstatValue(source.appendingPathComponent("regular.txt").path),
              let destinationStat = lstatValue(destination.appendingPathComponent("regular.txt").path) else { return false }
        let sourceTime = Int64(sourceStat.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(sourceStat.st_mtimespec.tv_nsec)
        let destinationTime = Int64(destinationStat.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(destinationStat.st_mtimespec.tv_nsec)
        return abs(sourceTime - destinationTime) <= 1_000_000_000
    }

    private static func verifyXattr(source: URL, destination: URL) -> Bool {
        let name = "com.surajmandal.macpowertoys.devsync-probe"
        return readXattr(name: name, path: source.appendingPathComponent("regular.txt").path)
            == readXattr(name: name, path: destination.appendingPathComponent("regular.txt").path)
    }

    private static func manifestData(_ paths: [String], nulSeparated: Bool) -> Data {
        var data = Data()
        for path in paths {
            data.append(contentsOf: path.utf8)
            data.append(nulSeparated ? 0 : 10)
        }
        return data
    }

    private static func directoryArgument(_ url: URL) -> String {
        url.path.hasSuffix("/") ? url.path : url.path + "/"
    }

    private static func isLongOptionByte(_ byte: UInt8) -> Bool {
        byte == 45 || byte == 95
            || byte >= 48 && byte <= 57
            || byte >= 65 && byte <= 90
            || byte >= 97 && byte <= 122
    }

    private static func shortOptionIsSupported(_ option: Character, in helpText: String) -> Bool {
        guard let usageStart = helpText.range(of: "rsync [") else { return false }
        guard let usageEnd = helpText[usageStart.upperBound...].firstIndex(of: "]") else { return false }
        return helpText[usageStart.upperBound..<usageEnd].contains(option)
    }

    private static func firstVersion(in text: String) -> String {
        let bytes = Array(text.utf8)
        for start in bytes.indices where bytes[start] >= 48 && bytes[start] <= 57 {
            var end = start
            var dots = 0
            while end < bytes.count {
                let byte = bytes[end]
                if byte >= 48 && byte <= 57 {
                    end += 1
                } else if byte == 46 && end + 1 < bytes.count && bytes[end + 1] >= 48 && bytes[end + 1] <= 57 {
                    dots += 1
                    end += 1
                } else {
                    break
                }
            }
            if dots >= 1 {
                return String(decoding: bytes[start..<end], as: UTF8.self)
            }
        }
        return ""
    }

    private static func firstInteger(in text: String) -> Int? {
        let bytes = Array(text.utf8)
        guard let start = bytes.firstIndex(where: { $0 >= 48 && $0 <= 57 }) else { return nil }
        var end = start
        while end < bytes.count, bytes[end] >= 48 && bytes[end] <= 57 { end += 1 }
        return Int(String(decoding: bytes[start..<end], as: UTF8.self))
    }

    private static func fingerprint(executable: URL, versionText: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: executable.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let payload = "\(executable.path)\n\(size)\n\(modificationDate)\n\(versionText)"
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func utf8LessThan(_ lhs: String, _ rhs: String) -> Bool {
        Array(lhs.utf8).lexicographicallyPrecedes(Array(rhs.utf8))
    }

    private static func sameInode(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = lstatValue(lhs), let right = lstatValue(rhs) else { return false }
        return left.st_dev == right.st_dev && left.st_ino == right.st_ino
    }

    private static func lstatValue(_ path: String) -> stat? {
        var value = stat()
        guard path.withCString({ lstat($0, &value) == 0 }) else { return nil }
        return value
    }

    private static func readLink(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let count = path.withCString { readlink($0, &buffer, buffer.count) }
        guard count >= 0 else { return nil }
        return String(decoding: buffer.prefix(Int(count)).map(UInt8.init), as: UTF8.self)
    }

    private static func setXattr(_ data: Data, name: String, path: String) -> Bool {
        data.withUnsafeBytes { bytes in
            path.withCString { pathPointer in
                name.withCString { namePointer in
                    setxattr(pathPointer, namePointer, bytes.baseAddress, data.count, 0, XATTR_NOFOLLOW) == 0
                }
            }
        }
    }

    private static func readXattr(name: String, path: String) -> Data? {
        let size = path.withCString { pathPointer in
            name.withCString { namePointer in
                getxattr(pathPointer, namePointer, nil, 0, 0, XATTR_NOFOLLOW)
            }
        }
        guard size >= 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { bytes in
            path.withCString { pathPointer in
                name.withCString { namePointer in
                    getxattr(pathPointer, namePointer, bytes.baseAddress, size, 0, XATTR_NOFOLLOW)
                }
            }
        }
        guard read == size else { return nil }
        return data
    }
}

nonisolated struct DevRsyncOptions: Equatable, Sendable {
    var preservePermissions: Bool
    var preserveXattrs: Bool
    var preserveHardLinks: Bool
    var modifyWindowSeconds: Int?
    var partialDirectory: URL
    var backupDirectory: URL?

    static func resolve(
        capabilities: DevRsyncCapabilities,
        pairCapabilities: DevPairCapabilities,
        metadata: DevSyncConfiguration.Metadata,
        partialDirectory: URL,
        backupDirectory: URL?
    ) -> DevRsyncOptions {
        let internalVolume = pairCapabilities.internalVolume
        let externalVolume = pairCapabilities.externalVolume
        func supportsBoth(_ predicate: (DevVolumeCapabilities) -> Bool) -> Bool {
            guard let internalVolume, let externalVolume else { return false }
            return predicate(internalVolume) && predicate(externalVolume)
        }
        func resolve(_ option: DevMetadataOption, rsyncSupported: Bool, volumesSupported: Bool) -> Bool {
            switch option {
            case .off: return false
            case .on: return rsyncSupported
            case .auto: return rsyncSupported && volumesSupported
            }
        }
        let tolerance = pairCapabilities.timestampToleranceNanoseconds
        let modifyWindow: Int? = capabilities.supportsModifyWindow && tolerance > 1_000_000_000
            ? Int(ceil(Double(tolerance) / 1_000_000_000))
            : nil
        return DevRsyncOptions(
            preservePermissions: resolve(
                metadata.permissions,
                rsyncSupported: capabilities.supportsPerms,
                volumesSupported: supportsBoth { $0.supportsUnixPermissions }
            ),
            preserveXattrs: resolve(
                metadata.xattrs,
                rsyncSupported: capabilities.supportsXattrs,
                volumesSupported: supportsBoth { $0.supportsExtendedAttributes }
            ),
            preserveHardLinks: resolve(
                metadata.hardLinks,
                rsyncSupported: capabilities.supportsHardLinks,
                volumesSupported: supportsBoth { $0.supportsHardLinks }
            ),
            modifyWindowSeconds: modifyWindow,
            partialDirectory: partialDirectory,
            backupDirectory: backupDirectory
        )
    }
}

nonisolated enum DevRsyncCommand {
    static func arguments(
        capabilities: DevRsyncCapabilities,
        options: DevRsyncOptions,
        sourceRoot: URL,
        destinationRoot: URL
    ) -> [String] {
        var arguments = ["-l", "-t"]
        if capabilities.supportsOmitDirTimes { arguments.append("-O") }
        if capabilities.supportsExecutability { arguments.append("--executability") }
        if capabilities.supportsPartialDir {
            arguments.append("--partial")
            arguments.append("--partial-dir=\(options.partialDirectory.path)")
        }
        if capabilities.supportsItemizeChanges { arguments.append("--itemize-changes") }
        if capabilities.supportsFilesFrom { arguments.append("--files-from=-") }
        if capabilities.supportsFrom0 {
            arguments.append(capabilities.supportedLongOptions.contains("--from0") ? "--from0" : "-0")
        }
        if let backupDirectory = options.backupDirectory, capabilities.supportsBackupDir {
            arguments.append("--backup")
            arguments.append("--backup-dir=\(backupDirectory.path)")
        }
        if options.preservePermissions && capabilities.supportsPerms { arguments.append("-p") }
        if options.preserveXattrs && capabilities.supportsXattrs { arguments.append("-X") }
        if options.preserveHardLinks && capabilities.supportsHardLinks { arguments.append("-H") }
        if let modifyWindowSeconds = options.modifyWindowSeconds, capabilities.supportsModifyWindow {
            arguments.append("--modify-window=\(modifyWindowSeconds)")
        }
        if capabilities.supportsDoubleDash { arguments.append("--") }
        arguments.append(directoryArgument(sourceRoot))
        arguments.append(directoryArgument(destinationRoot))
        return arguments
    }

    private static func directoryArgument(_ url: URL) -> String {
        url.path.hasSuffix("/") ? url.path : url.path + "/"
    }
}

nonisolated struct DevRsyncProgress: Equatable, Sendable {
    var itemizedLines: Int
    var lastRelativePath: String?
}

nonisolated struct DevRsyncResult: Equatable, Sendable {
    var exitCode: Int32
    var exitClass: DevRsyncExitClass
    var itemizedPaths: [String]
    var stderrTail: String
    var deferredPaths: [String]
    var duration: TimeInterval
}

nonisolated enum DevRsyncManifestError: Error, Equatable, Sendable {
    case unsafePath(String)
    case newlineUnsupported(String)
    case empty
}

nonisolated final class DevRsyncTransfer: @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let manifest: [String]
    private let capabilities: DevRsyncCapabilities
    private let processLock = NSLock()
    private var activeProcess: Process?
    private var cancellationRequested = false

    init(executable: URL, arguments: [String], manifest: [String], capabilities: DevRsyncCapabilities) {
        self.executable = executable
        self.arguments = arguments
        self.manifest = manifest
        self.capabilities = capabilities
    }

    static func validateManifest(
        _ manifest: [String],
        capabilities: DevRsyncCapabilities
    ) -> (accepted: [String], deferred: [String], rejected: [(String, DevRsyncManifestError)]) {
        guard !manifest.isEmpty else { return ([], [], [("", .empty)]) }
        var accepted: [String] = []
        var deferred: [String] = []
        var rejected: [(String, DevRsyncManifestError)] = []
        var seen: Set<String> = []
        for path in manifest where seen.insert(path).inserted {
            guard DevRelativePath.isSafe(path), !DevRelativePath.isCloudSyncSystemPath(path) else {
                rejected.append((path, .unsafePath(path)))
                continue
            }
            if path.contains("\n") || path.contains("\r"), !capabilities.supportsFrom0 {
                deferred.append(path)
            } else {
                accepted.append(path)
            }
        }
        return (accepted, deferred, rejected)
    }

    func run(progress: @escaping @Sendable (DevRsyncProgress) -> Void) async throws -> DevRsyncResult {
        try await Task.detached(priority: .utility) { [self] in
            try runSynchronously(progress: progress)
        }.value
    }

    func cancel() {
        processLock.lock()
        cancellationRequested = true
        let process = activeProcess
        processLock.unlock()
        if let process { terminate(process) }
    }

    private func runSynchronously(progress: @escaping @Sendable (DevRsyncProgress) -> Void) throws -> DevRsyncResult {
        let start = Date()
        let validation = Self.validateManifest(manifest, capabilities: capabilities)
        guard !validation.accepted.isEmpty else {
            return DevRsyncResult(
                exitCode: validation.rejected.isEmpty ? 0 : 1,
                exitClass: validation.rejected.isEmpty ? .success : .failure,
                itemizedPaths: [],
                stderrTail: validation.rejected.isEmpty ? "" : "No safe paths to transfer",
                deferredPaths: validation.deferred,
                duration: Date().timeIntervalSince(start)
            )
        }
        guard capabilities.supportsFilesFrom else {
            return DevRsyncResult(
                exitCode: 1,
                exitClass: .failure,
                itemizedPaths: [],
                stderrTail: "Rsync does not support --files-from",
                deferredPaths: validation.deferred,
                duration: Date().timeIntervalSince(start)
            )
        }
        let sortedManifest = validation.accepted.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        let input = manifestData(sortedManifest, nulSeparated: capabilities.supportsFrom0)
        logCommand()
        let output: DevRsyncProcessOutput
        do {
            output = try DevRsyncProcessRunner.run(
                executable: executable,
                arguments: arguments,
                stdin: input,
                currentDirectoryURL: sourceRootURL,
                configure: { [self] process in register(process) },
                didStart: { [self] process in processDidStart(process) }
            )
        } catch {
            clearProcess()
            throw error
        }
        clearProcess()
        let itemizedPaths = parseItemizedPaths(output.stdout, progress: progress)
        processLock.lock()
        let wasCancelled = cancellationRequested
        processLock.unlock()
        let exitClass = wasCancelled ? .cancelled : DevRsyncExitClass.classify(exitCode: output.status)
        return DevRsyncResult(
            exitCode: output.status,
            exitClass: exitClass,
            itemizedPaths: itemizedPaths,
            stderrTail: String(decoding: output.stderr.suffix(8_192), as: UTF8.self),
            deferredPaths: validation.deferred,
            duration: Date().timeIntervalSince(start)
        )
    }

    private var sourceRootURL: URL? {
        guard arguments.count >= 2 else { return nil }
        let source = arguments[arguments.count - 2]
        let path = source.hasSuffix("/") && source.count > 1 ? String(source.dropLast()) : source
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func register(_ process: Process) {
        processLock.lock()
        activeProcess = process
        let shouldCancel = cancellationRequested
        processLock.unlock()
        if shouldCancel { terminate(process) }
    }

    private func processDidStart(_ process: Process) {
        processLock.lock()
        let shouldCancel = cancellationRequested
        processLock.unlock()
        if shouldCancel { terminate(process) }
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            guard process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func clearProcess() {
        processLock.lock()
        activeProcess = nil
        processLock.unlock()
    }

    private func parseItemizedPaths(
        _ data: Data,
        progress: @escaping @Sendable (DevRsyncProgress) -> Void
    ) -> [String] {
        let bytes = Array(data)
        var paths: [String] = []
        var lineStart = 0
        for index in 0...bytes.count {
            guard index == bytes.count || bytes[index] == 10 else { continue }
            let line = bytes[lineStart..<index]
            lineStart = index + 1
            guard let separator = line.firstIndex(of: 32) else { continue }
            let encodedPath = line[line.index(after: separator)...]
            let path = String(decoding: unescapeRsyncPath(Array(encodedPath)), as: UTF8.self)
            guard !path.isEmpty else { continue }
            paths.append(path)
            progress(DevRsyncProgress(itemizedLines: paths.count, lastRelativePath: path))
        }
        return paths
    }

    private func unescapeRsyncPath(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        var index = 0
        while index < bytes.count {
            guard bytes[index] == 92, index + 4 < bytes.count, bytes[index + 1] == 35 else {
                result.append(bytes[index])
                index += 1
                continue
            }
            let octal = bytes[(index + 2)...(index + 4)]
            guard octal.allSatisfy({ $0 >= 48 && $0 <= 55 }) else {
                result.append(bytes[index])
                index += 1
                continue
            }
            let value = ((octal[octal.startIndex] - 48) << 6)
                | ((octal[octal.startIndex + 1] - 48) << 3)
                | (octal[octal.startIndex + 2] - 48)
            result.append(value)
            index += 5
        }
        return result
    }

    private func manifestData(_ paths: [String], nulSeparated: Bool) -> Data {
        var data = Data()
        for path in paths {
            data.append(contentsOf: path.utf8)
            data.append(nulSeparated ? 0 : 10)
        }
        return data
    }

    private func logCommand() {
        let command = ([executable.path] + arguments).map(redactedArgument).joined(separator: " ")
        Task { @MainActor in
            LogManager.shared.debug(command, source: "DevSync")
        }
    }

    private func redactedArgument(_ argument: String) -> String {
        if argument.hasPrefix("--partial-dir=") || argument.hasPrefix("--backup-dir=") {
            guard let separator = argument.firstIndex(of: "=") else { return argument }
            let prefix = argument[..<separator]
            let value = String(argument[argument.index(after: separator)...])
            return "\(prefix)=…/\(URL(fileURLWithPath: value).lastPathComponent)"
        }
        if argument.hasPrefix("/") {
            return "…/\(URL(fileURLWithPath: argument).lastPathComponent)"
        }
        return argument
    }
}

private nonisolated struct DevRsyncProcessOutput: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data
}

private nonisolated final class DevRsyncDataCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

nonisolated private enum DevRsyncProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        stdin: Data? = nil,
        currentDirectoryURL: URL? = nil,
        configure: ((Process) -> Void)? = nil,
        didStart: ((Process) -> Void)? = nil
    ) throws -> DevRsyncProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.qualityOfService = .utility
        process.currentDirectoryURL = currentDirectoryURL
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        _ = fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        configure?(process)

        let outputCapture = DevRsyncDataCapture()
        let errorCapture = DevRsyncDataCapture()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputCapture.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorCapture.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        do {
            try process.run()
            didStart?(process)
        } catch {
            try? inputPipe.fileHandleForWriting.close()
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            group.wait()
            throw error
        }
        if let stdin {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                try? inputPipe.fileHandleForWriting.write(contentsOf: stdin)
                try? inputPipe.fileHandleForWriting.close()
                group.leave()
            }
        } else {
            try? inputPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        group.wait()
        return DevRsyncProcessOutput(status: process.terminationStatus, stdout: outputCapture.get(), stderr: errorCapture.get())
    }
}
