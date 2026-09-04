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
        if let preferredPath, isExecutableFile(preferredPath) {
            return URL(fileURLWithPath: preferredPath)
        }
        return candidatePaths
            .map { URL(fileURLWithPath: $0) }
            .first { isExecutableFile($0.path) }
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var value = stat()
        return path.withCString { stat($0, &value) == 0 && value.st_mode & S_IFMT == S_IFREG && access($0, X_OK) == 0 }
    }
}

nonisolated enum DevRsyncProbeError: Error, Equatable, Sendable {
    case executableUnavailable(String)
    case commandFailed(String)
}

nonisolated enum DevRsyncProbe {
    private struct SelfTestResult {
        var passed = false
        var supportsFrom0 = false
        var supportsDoubleDash = false
        var supportsXattrs = false
        var supportsHardLinks = false
        var supportsCrtimes = false
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
        let supportsHardLinks = selfTest.supportsHardLinks
        let supportsCrtimes = selfTest.supportsCrtimes
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
        let fixtureCapabilities = try makeSelfTestTree(source: source)

        let hasXattrOption = supportedOptions.contains("--extended-attributes")
        let advertisesHardLinks = supportedOptions.contains("--hard-links") || shortOptionIsSupported("H", in: helpText)
        let hasHardLinks = advertisesHardLinks && fixtureCapabilities.canTestHardLinks
        let hasFrom0LongOption = supportedOptions.contains("--from0")
        let hasPartialDirectory = supportedOptions.contains("--partial-dir")
        let hasItemize = supportedOptions.contains("--itemize-changes")
        let hasExecutability = supportedOptions.contains("--executability")
        let hasPerms = supportedOptions.contains("--perms") || shortOptionIsSupported("p", in: helpText)
        let hasOmitDirTimes = supportedOptions.contains("--omit-dir-times") || shortOptionIsSupported("O", in: helpText)
        let hasBackup = supportedOptions.contains("--backup-dir")
        let hasCrtimes = supportedOptions.contains("--crtimes")
        var result = SelfTestResult()
        if advertisesHardLinks, !fixtureCapabilities.canTestHardLinks {
            result.notes.append("Hard-link self-test is unavailable on the probe volume")
        }
        if hasCrtimes, !fixtureCapabilities.canTestCreationTimes {
            result.notes.append("Creation-time self-test is unavailable on the probe volume")
        }
        var useFrom0 = true
        var useDoubleDash = true
        var useXattrs = hasXattrOption
        var useHardLinks = hasHardLinks
        var useCrtimes = hasCrtimes && fixtureCapabilities.canTestCreationTimes
        var copied = false
        var lastError = ""

        for _ in 0..<6 {
            try? fileManager.removeItem(at: destination)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let newlineURL = source.appendingPathComponent("newline\nname")
            let hasNewlineName = fileManager.fileExists(atPath: newlineURL.path)
            var manifest = selfTestManifest(hasNewlineName: hasNewlineName && useFrom0, hasHardLinks: useHardLinks)
            manifest = manifest.sorted { utf8LessThan($0, $1) }
            let arguments = selfTestArguments(
                source: source,
                destination: destination,
                partial: partial,
                useFrom0: useFrom0,
                useDoubleDash: useDoubleDash,
                useXattrs: useXattrs,
                useHardLinks: useHardLinks,
                useCrtimes: useCrtimes,
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
                let lowercasedError = lastError.lowercased()
                if useCrtimes, lowercasedError.contains("crtime") {
                    useCrtimes = false
                    result.notes.append("Creation-time option failed its self-test")
                } else if useHardLinks, lowercasedError.contains("option -- h") {
                    useHardLinks = false
                    result.notes.append("Hard-link option failed its self-test")
                } else if useXattrs {
                    useXattrs = false
                    result.notes.append("Extended attributes option failed its self-test")
                } else if useHardLinks {
                    useHardLinks = false
                    result.notes.append("Hard-link option failed its self-test")
                } else if useCrtimes {
                    useCrtimes = false
                    result.notes.append("Creation-time option failed its self-test")
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
            if useHardLinks && !sameInode(
                destination.appendingPathComponent("hard-source.txt").path,
                destination.appendingPathComponent("hard-copy.txt").path
            ) {
                useHardLinks = false
                result.notes.append("Hard links did not round-trip")
                continue
            }
            if useCrtimes && !verifyCreationTime(source: source, destination: destination) {
                useCrtimes = false
                result.notes.append("Creation times did not round-trip")
                continue
            }
            guard verifySelfTestCopy(
                source: source,
                destination: destination,
                hasNewlineName: fileManager.fileExists(atPath: newlineURL.path) && useFrom0,
                hasHardLinks: useHardLinks,
                checkExecutable: hasExecutability
            ) else {
                lastError = "Copied path matrix did not verify"
                break
            }
            copied = true
            result.supportsFrom0 = useFrom0
            result.supportsDoubleDash = useDoubleDash
            result.supportsXattrs = useXattrs
            result.supportsHardLinks = useHardLinks
            result.supportsCrtimes = useCrtimes
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
                useCrtimes: false,
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

    private static func makeSelfTestTree(source: URL) throws -> (canTestCreationTimes: Bool, canTestHardLinks: Bool) {
        let fileManager = FileManager.default
        let regularFile = source.appendingPathComponent("regular.txt")
        try Data("regular".utf8).write(to: regularFile)
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
        let canTestHardLinks = (try? fileManager.linkItem(
            at: source.appendingPathComponent("hard-source.txt"),
            to: source.appendingPathComponent("hard-copy.txt")
        )) != nil
        try? Data("newline".utf8).write(to: source.appendingPathComponent("newline\nname"))
        let xattrName = "com.surajmandal.macpowertoys.devsync-probe"
        _ = setXattr(Data("probe-xattr".utf8), name: xattrName, path: regularFile.path)
        return (
            canTestCreationTimes: setCreationDate(Date(timeIntervalSince1970: 1_600_000_000), for: regularFile),
            canTestHardLinks: canTestHardLinks
        )
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
        useCrtimes: Bool,
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
        if useCrtimes { arguments.append("--crtimes") }
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

    private static func verifyCreationTime(source: URL, destination: URL) -> Bool {
        guard let sourceStat = lstatValue(source.appendingPathComponent("regular.txt").path),
              let destinationStat = lstatValue(destination.appendingPathComponent("regular.txt").path) else {
            return false
        }
        let sourceCreation = Int64(sourceStat.st_birthtimespec.tv_sec) * 1_000_000_000 + Int64(sourceStat.st_birthtimespec.tv_nsec)
        let destinationCreation = Int64(destinationStat.st_birthtimespec.tv_sec) * 1_000_000_000 + Int64(destinationStat.st_birthtimespec.tv_nsec)
        return abs(sourceCreation - destinationCreation) <= 1_000_000_000
    }

    private static func setCreationDate(_ date: Date, for url: URL) -> Bool {
        var values = URLResourceValues()
        values.creationDate = date
        var mutableURL = url
        guard (try? mutableURL.setResourceValues(values)) != nil,
              let storedDate = try? mutableURL.resourceValues(forKeys: [.creationDateKey]).creationDate else {
            return false
        }
        return abs(storedDate.timeIntervalSince(date)) <= 1
    }

    private static func verifyXattr(source: URL, destination: URL) -> Bool {
        let name = "com.surajmandal.macpowertoys.devsync-probe"
        guard let sourceValue = readXattr(name: name, path: source.appendingPathComponent("regular.txt").path) else {
            return false
        }
        return sourceValue == readXattr(name: name, path: destination.appendingPathComponent("regular.txt").path)
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
    var preserveCreationTimes: Bool = false
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
            preserveCreationTimes: resolve(
                .auto,
                rsyncSupported: capabilities.supportsCrtimes,
                volumesSupported: supportsBoth { $0.supportsCreationTimes }
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
        if options.preserveCreationTimes && capabilities.supportsCrtimes { arguments.append("--crtimes") }
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
            guard DevRelativePath.isSafe(path), !isCloudSyncSystemPath(path) else {
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

    private static func isCloudSyncSystemPath(_ path: String) -> Bool {
        DevRelativePath.components(path).contains {
            DevSyncDefaults.systemDirectoryNames.contains($0.lowercased())
        }
    }

    func run(progress: @escaping @Sendable (DevRsyncProgress) -> Void) async throws -> DevRsyncResult {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) { [self] in
                try runSynchronously(progress: progress)
            }.value
        } onCancel: { [self] in
            cancel()
        }
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
        guard validation.rejected.isEmpty else {
            return failureResult(startedAt: start, deferredPaths: validation.deferred, message: "Manifest contains unsafe paths")
        }
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
        guard capabilities.selfTestPassed else {
            return failureResult(startedAt: start, deferredPaths: validation.deferred, message: "Rsync capability self-test did not pass")
        }
        guard capabilities.supportsFilesFrom, capabilities.supportsFrom0,
              arguments.contains("--files-from=-"),
              arguments.contains("-0") || arguments.contains("--from0") else {
            return failureResult(startedAt: start, deferredPaths: validation.deferred, message: "Rsync does not support NUL manifests")
        }
        guard capabilities.supportsPartialDir,
              arguments.contains("--partial"),
              arguments.contains(where: { $0.hasPrefix("--partial-dir=") }) else {
            return failureResult(startedAt: start, deferredPaths: validation.deferred, message: "Rsync does not support safe partial files")
        }
        guard let sourceRootURL, let destinationRootURL,
              isPlainDirectory(sourceRootURL), isPlainDirectory(destinationRootURL) else {
            return failureResult(startedAt: start, deferredPaths: validation.deferred, message: "Transfer roots must be real directories")
        }
        guard !validation.accepted.contains(where: { pathTraversesSymbolicLink($0, sourceRoot: sourceRootURL) }) else {
            return failureResult(startedAt: start, deferredPaths: validation.deferred, message: "Manifest path traverses a symbolic link")
        }
        let sortedManifest = validation.accepted.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let itemizeCapture = DevRsyncItemizeCapture(manifest: Set(sortedManifest), progress: progress)
        logCommand()
        let output: DevRsyncProcessOutput
        do {
            output = try DevRsyncProcessRunner.run(
                executable: executable,
                arguments: arguments,
                stdinWriter: { try Self.writeManifest(sortedManifest, to: $0) },
                currentDirectoryURL: sourceRootURL,
                stdoutLimit: 0,
                stderrLimit: 8_192,
                stdoutChunk: { itemizeCapture.append($0) },
                configure: { [self] process in register(process) },
                didStart: { [self] process in processDidStart(process) }
            )
        } catch {
            clearProcess()
            throw error
        }
        clearProcess()
        itemizeCapture.finish()
        let itemizedPaths = itemizeCapture.paths
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

    private var destinationRootURL: URL? {
        guard let destination = arguments.last else { return nil }
        let path = destination.hasSuffix("/") && destination.count > 1 ? String(destination.dropLast()) : destination
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func isPlainDirectory(_ url: URL) -> Bool {
        guard let value = lstatValue(url.path) else { return false }
        return value.st_mode & S_IFMT == S_IFDIR
    }

    private func pathTraversesSymbolicLink(_ path: String, sourceRoot: URL) -> Bool {
        var current = sourceRoot
        for component in DevRelativePath.components(path).dropLast() {
            current.appendPathComponent(component, isDirectory: true)
            guard let value = lstatValue(current.path) else { continue }
            if value.st_mode & S_IFMT == S_IFLNK { return true }
        }
        return false
    }

    private func failureResult(startedAt start: Date, deferredPaths: [String], message: String) -> DevRsyncResult {
        DevRsyncResult(
            exitCode: 1,
            exitClass: .failure,
            itemizedPaths: [],
            stderrTail: message,
            deferredPaths: deferredPaths,
            duration: Date().timeIntervalSince(start)
        )
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

    private static func writeManifest(_ paths: [String], to handle: FileHandle) throws {
        var data = Data(capacity: 64 * 1_024)
        for path in paths {
            if data.count + path.utf8.count + 1 > 64 * 1_024, !data.isEmpty {
                try handle.write(contentsOf: data)
                data.removeAll(keepingCapacity: true)
            }
            data.append(contentsOf: path.utf8)
            data.append(0)
        }
        if !data.isEmpty { try handle.write(contentsOf: data) }
    }

    private func lstatValue(_ path: String) -> stat? {
        var value = stat()
        guard path.withCString({ lstat($0, &value) == 0 }) else { return nil }
        return value
    }

    private func logCommand() {
        let command = ([executable.path] + arguments).map(redactedArgument).joined(separator: " ")
        Task { @MainActor in
            LogManager.shared.debug(command, source: "DevSync")
        }
    }

    private func redactedArgument(_ argument: String) -> String {
        let redacted: String
        if argument.hasPrefix("--partial-dir=") || argument.hasPrefix("--backup-dir=") {
            if let separator = argument.firstIndex(of: "=") {
                let prefix = argument[..<separator]
                let value = String(argument[argument.index(after: separator)...])
                redacted = "\(prefix)=…/\(URL(fileURLWithPath: value).lastPathComponent)"
            } else {
                redacted = argument
            }
        } else if argument.hasPrefix("/") {
            redacted = "…/\(URL(fileURLWithPath: argument).lastPathComponent)"
        } else {
            redacted = argument
        }
        return redacted.unicodeScalars.reduce(into: "") { result, scalar in
            if scalar.value < 32 || scalar.value == 127 {
                result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
    }
}

private nonisolated final class DevRsyncItemizeCapture: @unchecked Sendable {
    private let manifest: Set<String>
    private let progress: @Sendable (DevRsyncProgress) -> Void
    private let lock = NSLock()
    private var pending = Data()
    private var capturedPaths: [String] = []

    init(manifest: Set<String>, progress: @escaping @Sendable (DevRsyncProgress) -> Void) {
        self.manifest = manifest
        self.progress = progress
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedPaths
    }

    func append(_ chunk: Data) {
        process(chunk, includesTrailingLine: false)
    }

    func finish() {
        process(Data(), includesTrailingLine: true)
    }

    private func process(_ chunk: Data, includesTrailingLine: Bool) {
        lock.lock()
        var buffer = pending
        buffer.append(chunk)
        var lineStart = buffer.startIndex
        var newPaths: [String] = []
        for index in buffer.indices where buffer[index] == 10 {
            if let path = parseLine(buffer[lineStart..<index]) {
                capturedPaths.append(path)
                newPaths.append(path)
            }
            lineStart = buffer.index(after: index)
        }
        if includesTrailingLine, lineStart < buffer.endIndex {
            if let path = parseLine(buffer[lineStart..<buffer.endIndex]) {
                capturedPaths.append(path)
                newPaths.append(path)
            }
            pending.removeAll(keepingCapacity: true)
        } else {
            pending = Data(buffer[lineStart..<buffer.endIndex])
        }
        let total = capturedPaths.count
        lock.unlock()

        let firstCount = total - newPaths.count + 1
        for (offset, path) in newPaths.enumerated() {
            progress(DevRsyncProgress(itemizedLines: firstCount + offset, lastRelativePath: path))
        }
    }

    private func parseLine(_ line: Data.SubSequence) -> String? {
        guard let separator = line.firstIndex(of: 32) else { return nil }
        let itemCode = line[..<separator]
        guard itemCode.count >= 2 else { return nil }
        let encodedPath = line[line.index(after: separator)...]
        let outputPath = String(decoding: unescapeRsyncPath(encodedPath), as: UTF8.self)
        guard !outputPath.isEmpty else { return nil }
        if manifest.contains(outputPath) { return outputPath }
        if outputPath.last == "/" {
            let directoryPath = String(outputPath.dropLast())
            if manifest.contains(directoryPath) { return directoryPath }
        }
        guard itemCode[itemCode.index(after: itemCode.startIndex)] == 76 else { return nil }

        var searchRange = outputPath.startIndex..<outputPath.endIndex
        while let marker = outputPath.range(of: " -> ", range: searchRange) {
            let candidate = String(outputPath[..<marker.lowerBound])
            if manifest.contains(candidate) { return candidate }
            searchRange = marker.upperBound..<outputPath.endIndex
        }
        return nil
    }

    private func unescapeRsyncPath(_ bytes: Data.SubSequence) -> [UInt8] {
        let input = Array(bytes)
        var result: [UInt8] = []
        result.reserveCapacity(input.count)
        var index = 0
        while index < input.count {
            guard input[index] == 92, index + 4 < input.count, input[index + 1] == 35 else {
                result.append(input[index])
                index += 1
                continue
            }
            let octal = input[(index + 2)...(index + 4)]
            guard octal.allSatisfy({ $0 >= 48 && $0 <= 55 }) else {
                result.append(input[index])
                index += 1
                continue
            }
            result.append(
                ((octal[octal.startIndex] - 48) << 6)
                    | ((octal[octal.startIndex + 1] - 48) << 3)
                    | (octal[octal.startIndex + 2] - 48)
            )
            index += 5
        }
        return result
    }
}

private nonisolated struct DevRsyncProcessOutput: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data
}

private nonisolated final class DevRsyncDataCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private let keepSuffix: Bool
    private var value = Data()

    init(limit: Int, keepSuffix: Bool = false) {
        self.limit = limit
        self.keepSuffix = keepSuffix
    }

    func append(_ data: Data) {
        lock.lock()
        if keepSuffix {
            value.append(data)
            if value.count > limit {
                value = Data(value.suffix(limit))
            }
        } else if value.count < limit {
            value.append(contentsOf: data.prefix(limit - value.count))
        }
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
        stdinWriter: (@Sendable (FileHandle) throws -> Void)? = nil,
        currentDirectoryURL: URL? = nil,
        stdoutLimit: Int = 1_048_576,
        stderrLimit: Int = 65_536,
        stdoutChunk: (@Sendable (Data) -> Void)? = nil,
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

        let outputCapture = DevRsyncDataCapture(limit: stdoutLimit)
        let errorCapture = DevRsyncDataCapture(limit: stderrLimit, keepSuffix: true)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            readChunks(from: outputPipe.fileHandleForReading) {
                outputCapture.append($0)
                stdoutChunk?($0)
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            readChunks(from: errorPipe.fileHandleForReading) { errorCapture.append($0) }
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
        if stdin != nil || stdinWriter != nil {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                if let stdin {
                    try? inputPipe.fileHandleForWriting.write(contentsOf: stdin)
                } else {
                    try? stdinWriter?(inputPipe.fileHandleForWriting)
                }
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

    private static func readChunks(from handle: FileHandle, receive: (Data) -> Void) {
        while true {
            let data = handle.readData(ofLength: 64 * 1_024)
            guard !data.isEmpty else { return }
            receive(data)
        }
    }
}
