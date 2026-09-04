import AppKit
import Darwin
import Foundation

nonisolated enum DevRootResolution: Equatable, Sendable {
    case available(URL)
    case offline
    case identityMismatch(foundIdentifier: String, foundName: String)
    case staleBookmark
}

nonisolated enum DevSyncRoots {
    private static let managedLinkAttribute = DevSyncDefaults.managedLinkAttributeName

    static func canonicalURL(_ url: URL) throws -> URL {
        let path = normalizedPath(url.path)
        guard let resolvedPointer = path.withCString({ realpath($0, nil) }) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        defer { free(resolvedPointer) }
        let resolvedPath = normalizedPath(String(cString: resolvedPointer))
        return URL(fileURLWithPath: resolvedPath, isDirectory: true)
    }

    static func makeRoot(url: URL) throws -> DevSyncRoot {
        let canonical = try canonicalURL(url)
        guard let stat = lstatValue(canonical.path), (stat.st_mode & S_IFMT) == S_IFDIR else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: canonical.path])
        }

        let values = try resourceValues(for: canonical, keys: [
            .volumeUUIDStringKey,
            .volumeNameKey,
            .volumeTypeNameKey,
            .volumeTotalCapacityKey
        ])
        let volumeName = values.volumeName ?? canonical.lastPathComponent
        let capacity = Int64(values.volumeTotalCapacity ?? 0)
        let volumeIdentifier = volumeIdentifier(from: values, volumeName: volumeName, capacity: capacity)
        let fileSystemType = values.volumeTypeName ?? fileSystemType(for: canonical.path)
        let bookmark = try canonical.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)

        return DevSyncRoot(
            bookmark: bookmark,
            path: canonical.path,
            volumeIdentifier: volumeIdentifier,
            volumeName: volumeName,
            fileSystemType: fileSystemType
        )
    }

    static func validatePair(internal internalURL: URL, external externalURL: URL, existingPairs: [DevSyncPair]) -> [DevRootIssue] {
        let internalResult = validateRoot(internalURL)
        let externalResult = validateRoot(externalURL)
        var issues = internalResult.issues + externalResult.issues

        if let internalURL = internalResult.canonical, let externalURL = externalResult.canonical {
            if internalURL.path == externalURL.path {
                appendIfMissing(.sameDirectory, to: &issues)
            } else if isDescendant(internalURL.path, of: externalURL.path) {
                appendIfMissing(.nested(outer: externalURL.path, inner: internalURL.path), to: &issues)
            } else if isDescendant(externalURL.path, of: internalURL.path) {
                appendIfMissing(.nested(outer: internalURL.path, inner: externalURL.path), to: &issues)
            }

            let candidateRoots = [internalURL, externalURL]
            for pair in existingPairs {
                let existingRoots = [pair.internalRoot.url, pair.externalRoot.url]
                for candidate in candidateRoots {
                    for existing in existingRoots {
                        guard let existingCanonical = try? canonicalURL(existing) else { continue }
                        guard pathsOverlap(candidate.path, existingCanonical.path) else { continue }
                        let offendingPath = isDescendant(candidate.path, of: existingCanonical.path) || candidate.path == existingCanonical.path
                            ? candidate.path
                            : existingCanonical.path
                        appendIfMissing(
                            .overlapsExistingPair(pairName: pair.displayName, path: offendingPath),
                            to: &issues
                        )
                    }
                }
            }
        }

        return issues
    }

    static func resolve(_ root: DevSyncRoot) -> DevRootResolution {
        var bookmarkWasStale = false
        if let bookmark = root.bookmark {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                bookmarkWasStale = isStale
                if !isStale, let resolution = resolution(for: resolved, expected: root) {
                    return resolution
                }
            } else {
                bookmarkWasStale = true
            }
        }

        let pathURL = URL(fileURLWithPath: root.path, isDirectory: true)
        if let resolution = resolution(for: pathURL, expected: root) {
            return resolution
        }
        return bookmarkWasStale ? .staleBookmark : .offline
    }

    static func volumeIdentifier(for url: URL) -> String? {
        guard lstatValue(normalizedPath(url.path)) != nil else { return nil }
        let canonical = (try? canonicalURL(url)) ?? URL(fileURLWithPath: normalizedPath(url.path))
        guard let values = try? resourceValues(for: canonical, keys: [
            .volumeUUIDStringKey,
            .volumeNameKey,
            .volumeTotalCapacityKey
        ]) else {
            return nil
        }
        let name = values.volumeName ?? canonical.deletingLastPathComponent().lastPathComponent
        let capacity = Int64(values.volumeTotalCapacity ?? 0)
        return volumeIdentifier(from: values, volumeName: name, capacity: capacity)
    }

    private static func validateRoot(_ url: URL) -> (canonical: URL?, issues: [DevRootIssue]) {
        let path = normalizedPath(url.path)
        guard let stat = lstatValue(path) else {
            return (nil, [.notADirectory(path)])
        }

        if (stat.st_mode & S_IFMT) == S_IFLNK, hasManagedLinkAttribute(at: path) {
            return (nil, [.isManagedLink(path)])
        }

        guard let canonical = try? canonicalURL(url),
              let canonicalStat = lstatValue(canonical.path),
              (canonicalStat.st_mode & S_IFMT) == S_IFDIR else {
            return (nil, [.notADirectory(path)])
        }
        guard access(canonical.path, R_OK | X_OK) == 0 else {
            return (canonical, [.unreadable(canonical.path)])
        }
        return (canonical, [])
    }

    private static func resolution(for url: URL, expected root: DevSyncRoot) -> DevRootResolution? {
        guard lstatValue(normalizedPath(url.path)) != nil,
              let canonical = try? canonicalURL(url),
              let stat = lstatValue(canonical.path),
              (stat.st_mode & S_IFMT) == S_IFDIR else {
            return nil
        }
        guard let identifier = volumeIdentifier(for: canonical) else { return .offline }
        guard identifier == root.volumeIdentifier else {
            let name = (try? resourceValues(for: canonical, keys: [.volumeNameKey])).flatMap(\.volumeName) ?? canonical.lastPathComponent
            return .identityMismatch(foundIdentifier: identifier, foundName: name)
        }
        return .available(canonical)
    }

    private static func volumeIdentifier(
        from values: URLResourceValues?,
        volumeName: String,
        capacity: Int64
    ) -> String {
        if let uuid = values?.volumeUUIDString, !uuid.isEmpty {
            return "uuid:\(uuid)"
        }
        return "vol:\(volumeName):\(capacity)"
    }

    private static func resourceValues(for url: URL, keys: Set<URLResourceKey>) throws -> URLResourceValues {
        guard let linkValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), linkValues.isSymbolicLink != true else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
        return try url.resourceValues(forKeys: keys)
    }

    private static func fileSystemType(for path: String) -> String {
        var info = statfs()
        guard path.withCString({ statfs($0, &info) == 0 }) else { return "" }
        return withUnsafeBytes(of: &info.f_fstypename) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard path.count > 1 else { return "/" }
        var result = path
        while result.last == "/" && result.count > 1 {
            result.removeLast()
        }
        return result
    }

    private static func lstatValue(_ path: String) -> stat? {
        var value = stat()
        guard path.withCString({ lstat($0, &value) == 0 }) else { return nil }
        return value
    }

    private static func hasManagedLinkAttribute(at path: String) -> Bool {
        var result = false
        path.withCString { pathPointer in
            managedLinkAttribute.withCString { namePointer in
                result = getxattr(pathPointer, namePointer, nil, 0, 0, XATTR_NOFOLLOW) >= 0
            }
        }
        return result
    }

    private static func isDescendant(_ path: String, of parent: String) -> Bool {
        guard path != parent else { return false }
        return parent == "/" ? path.hasPrefix("/") : path.hasPrefix(parent + "/")
    }

    private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || isDescendant(lhs, of: rhs) || isDescendant(rhs, of: lhs)
    }

    private static func appendIfMissing(_ issue: DevRootIssue, to issues: inout [DevRootIssue]) {
        guard !issues.contains(issue) else { return }
        issues.append(issue)
    }
}

nonisolated enum DevVolumeProbe {
    private struct ProbeResult {
        var supportsSymbolicLinks = false
        var supportsHardLinks = false
        var supportsUnixPermissions = false
        var supportsExtendedAttributes = false
        var isCaseSensitive = true
        var isCasePreserving = true
        var timestampResolutionNanoseconds: Int64 = 1_000_000_000
        var maximumPathComponentLength = 0
    }

    static func probe(rootURL: URL, probeDirectory: URL? = nil) -> DevVolumeCapabilities {
        let root = (try? DevSyncRoots.canonicalURL(rootURL)) ?? rootURL.standardizedFileURL
        let values = (try? resourceValues(for: root, keys: [
            .volumeUUIDStringKey,
            .volumeNameKey,
            .volumeTypeNameKey,
            .volumeSupportsSymbolicLinksKey,
            .volumeSupportsHardLinksKey,
            .volumeSupportsCaseSensitiveNamesKey,
            .volumeSupportsCasePreservedNamesKey,
            .volumeSupportsExtendedSecurityKey,
            .volumeSupportsPersistentIDsKey,
            .volumeIsReadOnlyKey,
            .volumeIsRemovableKey,
            .volumeIsLocalKey,
            .volumeIsEncryptedKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
            .volumeMaximumFileSizeKey,
            .volumeSupportsFileCloningKey,
            .volumeSupportsExclusiveRenamingKey,
            .volumeSupportsSwapRenamingKey,
            .creationDateKey
        ]))

        let volumeName = values?.volumeName ?? root.lastPathComponent
        let totalCapacity = Int64(values?.volumeTotalCapacity ?? 0)
        let volumeIdentifier = DevSyncRoots.volumeIdentifier(for: root) ?? "vol:\(volumeName):\(totalCapacity)"
        let initialReadOnly = values?.volumeIsReadOnly ?? false
        let initialCaseSensitive = values?.volumeSupportsCaseSensitiveNames ?? true
        let initialCasePreserving = values?.volumeSupportsCasePreservedNames ?? true
        let initialSymlinks = values?.volumeSupportsSymbolicLinks ?? true
        let initialHardLinks = values?.volumeSupportsHardLinks ?? true
        let initialPermissions = values?.volumeSupportsExtendedSecurity ?? true
        let initialPersistentIDs = values?.volumeSupportsPersistentIDs ?? false
        let initialAvailable = Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        var notes: [String] = []
        var probeResult = ProbeResult(
            supportsSymbolicLinks: initialSymlinks,
            supportsHardLinks: initialHardLinks,
            supportsUnixPermissions: initialPermissions,
            isCaseSensitive: initialCaseSensitive,
            isCasePreserving: initialCasePreserving
        )
        var probeSucceeded = false
        let temporaryProbe = (probeDirectory ?? root.appendingPathComponent(".cloudsync-system", isDirectory: true))
            .appendingPathComponent("probe-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: temporaryProbe)
        }

        if !initialReadOnly, access(root.path, W_OK | X_OK) == 0 {
            do {
                try FileManager.default.createDirectory(at: temporaryProbe, withIntermediateDirectories: true)
                chmod(temporaryProbe.path, mode_t(0o700))
                probeResult = runProbe(in: temporaryProbe, initial: probeResult)
                probeSucceeded = true
            } catch {
                notes.append("Temporary volume probe failed")
            }
        }

        if initialReadOnly {
            notes.append("Volume is read-only")
        } else if !probeSucceeded {
            notes.append("Volume is not writable")
        }
        if !probeResult.supportsSymbolicLinks { notes.append("Symbolic links are not preserved") }
        if !probeResult.supportsUnixPermissions { notes.append("Executable bits are not preserved") }
        if !probeResult.supportsExtendedAttributes { notes.append("Extended attributes are not preserved") }
        if !probeResult.supportsHardLinks { notes.append("Hard links are copied as separate files") }
        if probeResult.timestampResolutionNanoseconds > 1 {
            let seconds = Double(probeResult.timestampResolutionNanoseconds) / 1_000_000_000
            notes.append("Timestamps use a \(seconds.formatted(.number.precision(.fractionLength(0...3)))) s modify window")
        }

        let blocked = initialReadOnly || !probeSucceeded
        let fidelity: DevFileSystemFidelity = blocked ? .blocked : (notes.isEmpty ? .full : .portable)
        return DevVolumeCapabilities(
            volumeIdentifier: volumeIdentifier,
            volumeName: volumeName,
            mountPath: root.path,
            fileSystemType: values?.volumeTypeName ?? fileSystemType(for: root.path),
            isReadOnly: initialReadOnly,
            isRemovable: values?.volumeIsRemovable ?? false,
            isLocal: values?.volumeIsLocal ?? true,
            isEncrypted: values?.volumeIsEncrypted,
            availableCapacity: initialAvailable,
            totalCapacity: totalCapacity,
            isCaseSensitive: probeResult.isCaseSensitive,
            isCasePreserving: probeResult.isCasePreserving,
            supportsSymbolicLinks: probeResult.supportsSymbolicLinks,
            supportsHardLinks: probeResult.supportsHardLinks,
            supportsUnixPermissions: probeResult.supportsUnixPermissions,
            supportsExtendedAttributes: probeResult.supportsExtendedAttributes,
            supportsCreationTimes: values?.creationDate != nil,
            supportsPersistentIdentifiers: initialPersistentIDs,
            timestampResolutionNanoseconds: probeResult.timestampResolutionNanoseconds,
            maximumPathComponentLength: probeResult.maximumPathComponentLength,
            probedAt: Date(),
            fidelity: fidelity,
            fidelityNotes: notes
        )
    }

    private static func runProbe(in directory: URL, initial: ProbeResult) -> ProbeResult {
        let fileManager = FileManager.default
        var result = initial
        let file = directory.appendingPathComponent("probe-file")
        let target = directory.appendingPathComponent("probe-target")
        let symlinkURL = directory.appendingPathComponent("probe-link")
        let hardLink = directory.appendingPathComponent("probe-hard-link")
        let upper = directory.appendingPathComponent("CaseProbe")
        let lower = directory.appendingPathComponent("caseprobe")

        guard fileManager.createFile(atPath: file.path, contents: Data("probe".utf8)) else { return result }
        chmod(file.path, mode_t(0o755))
        if let fileStat = lstatValue(file.path) {
            result.supportsUnixPermissions = (fileStat.st_mode & 0o111) != 0
        } else {
            result.supportsUnixPermissions = false
        }

        result.supportsSymbolicLinks = false
        if fileManager.createFile(atPath: target.path, contents: Data("target".utf8)),
           symlink("probe-target", symlinkURL.path) == 0,
           let linkStat = lstatValue(symlinkURL.path) {
            result.supportsSymbolicLinks = (linkStat.st_mode & S_IFMT) == S_IFLNK
        }

        let xattrName = "com.surajmandal.macpowertoys.devsync-probe"
        let xattrValue = Data("devsync".utf8)
        result.supportsExtendedAttributes = setXattr(xattrValue, name: xattrName, path: file.path)
            && readXattr(name: xattrName, path: file.path) == xattrValue

        result.supportsHardLinks = link(file.path, hardLink.path) == 0
            && sameInode(file.path, hardLink.path)

        _ = fileManager.createFile(atPath: upper.path, contents: Data("upper".utf8))
        let lowerCreated = fileManager.createFile(atPath: lower.path, contents: Data("lower".utf8))
        result.isCaseSensitive = lowerCreated
        if !lowerCreated {
            result.isCaseSensitive = !sameInode(upper.path, lower.path)
        }
        result.isCasePreserving = fileManager.fileExists(atPath: upper.path)

        result.timestampResolutionNanoseconds = timestampResolution(for: file)
        let component = String(repeating: "a", count: 255)
        let longName = directory.appendingPathComponent(component)
        if fileManager.createFile(atPath: longName.path, contents: Data()) {
            result.maximumPathComponentLength = 255
        }
        return result
    }

    private static func timestampResolution(for url: URL) -> Int64 {
        let baseSeconds: Int64 = 1_700_000_000
        let offsets: [Int64] = [0, 1, 1_000_000_000, 2_000_000_000, 4_000_000_000]
        var observed: [Int64] = []
        for offset in offsets {
            let total = baseSeconds * 1_000_000_000 + offset
            let seconds = total / 1_000_000_000
            let nanoseconds = total % 1_000_000_000
            guard setModificationTime(url, seconds: seconds, nanoseconds: nanoseconds),
                  let stat = lstatValue(url.path) else { continue }
            observed.append(Int64(stat.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(stat.st_mtimespec.tv_nsec))
        }
        let differences = zip(observed, observed.dropFirst()).compactMap { lhs, rhs -> Int64? in
            let difference = abs(rhs - lhs)
            return difference > 0 ? difference : nil
        }
        return differences.min() ?? 1_000_000_000
    }

    private static func setModificationTime(_ url: URL, seconds: Int64, nanoseconds: Int64) -> Bool {
        let times = [
            timespec(tv_sec: Int(seconds), tv_nsec: Int(nanoseconds)),
            timespec(tv_sec: Int(seconds), tv_nsec: Int(nanoseconds))
        ]
        return url.path.withCString { path in
            times.withUnsafeBufferPointer { buffer in
                utimensat(AT_FDCWD, path, buffer.baseAddress, 0) == 0
            }
        }
    }

    private static func sameInode(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = lstatValue(lhs), let right = lstatValue(rhs) else { return false }
        return left.st_dev == right.st_dev && left.st_ino == right.st_ino
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

    private static func resourceValues(for url: URL, keys: Set<URLResourceKey>) throws -> URLResourceValues {
        guard let linkValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), linkValues.isSymbolicLink != true else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
        return try url.resourceValues(forKeys: keys)
    }

    private static func fileSystemType(for path: String) -> String {
        var info = statfs()
        guard path.withCString({ statfs($0, &info) == 0 }) else { return "" }
        return withUnsafeBytes(of: &info.f_fstypename) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func lstatValue(_ path: String) -> stat? {
        var value = stat()
        guard path.withCString({ lstat($0, &value) == 0 }) else { return nil }
        return value
    }
}

@MainActor
final class DevVolumeMonitor {
    private let handler: @MainActor (DevVolumeEvent) -> Void
    private var observers: [NSObjectProtocol] = []

    init(handler: @escaping @MainActor (DevVolumeEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main) { [weak self] notification in
                let event = Self.event(for: notification, kind: .willUnmount)
                Task { @MainActor [weak self] in
                    if let event { self?.handler(event) }
                }
            },
            center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] notification in
                let event = Self.event(for: notification, kind: .didUnmount)
                Task { @MainActor [weak self] in
                    if let event { self?.handler(event) }
                }
            },
            center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] notification in
                let event = Self.event(for: notification, kind: .didMount)
                Task { @MainActor [weak self] in
                    if let event { self?.handler(event) }
                }
            }
        ]
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private nonisolated static func event(for notification: Notification, kind: DevVolumeEvent.Kind) -> DevVolumeEvent? {
        guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL ?? notification.object as? URL else { return nil }
        return kind.event(for: url)
    }
}

nonisolated enum DevVolumeEvent: Equatable, Sendable {
    case willUnmount(URL)
    case didUnmount(URL)
    case didMount(URL)

    fileprivate enum Kind {
        case willUnmount
        case didUnmount
        case didMount

        func event(for url: URL) -> DevVolumeEvent {
            switch self {
            case .willUnmount: return .willUnmount(url)
            case .didUnmount: return .didUnmount(url)
            case .didMount: return .didMount(url)
            }
        }
    }
}
