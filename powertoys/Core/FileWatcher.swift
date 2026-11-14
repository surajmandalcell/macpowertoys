//
//  FileWatcher.swift
//  powertoys
//

import Foundation
import CoreServices

nonisolated enum FileChangeKind: String, Codable, Sendable, CaseIterable {
    case created
    case modified
    case removed
    case renamed

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .created: return "plus.circle"
        case .modified: return "pencil.circle"
        case .removed: return "minus.circle"
        case .renamed: return "arrow.left.arrow.right.circle"
        }
    }

    static func resolve(_ flags: FSEventStreamEventFlags) -> FileChangeKind {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 { return .removed }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 { return .renamed }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 { return .created }
        return .modified
    }
}

nonisolated struct FileChangeEvent: Sendable, Hashable {
    let path: String
    let kind: FileChangeKind
}

nonisolated struct RelativeFileChange: Sendable, Hashable {
    let relativePath: String
    let name: String
    let isDirectory: Bool
    let kind: FileChangeKind
}

/// Delivers coalesced FSEvents batches on a private serial queue, never on main.
nonisolated final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: @Sendable ([FileChangeEvent]) -> Void
    private let latency: CFTimeInterval
    private let queue = DispatchQueue(label: "MacPowerToys.FileWatcher", qos: .utility)
    private let lock = NSLock()

    init(path: String, latency: CFTimeInterval = 0.5, callback: @escaping @Sendable ([FileChangeEvent]) -> Void) {
        self.path = path
        self.latency = latency
        self.callback = callback
    }

    deinit {
        stop()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return }

        // The stream retains self until FSEventStreamRelease, so a late callback never sees a freed object.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<FileWatcher>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<FileWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        let watchedPath = path
        guard let created = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, eventFlags, _ in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                var seen: Set<FileChangeEvent> = []
                let changes = paths.prefix(numEvents).enumerated().compactMap { index, path -> FileChangeEvent? in
                    let change = FileChangeEvent(path: path, kind: FileChangeKind.resolve(eventFlags[index]))
                    return seen.insert(change).inserted ? change : nil
                }
                watcher.callback(changes)
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
        ) else {
            Task { @MainActor in
                LogManager.shared.error("Failed to create FSEvent stream for: \(watchedPath)", source: "FileWatcher")
            }
            return
        }

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            Task { @MainActor in
                LogManager.shared.error("Failed to start FSEvent stream for: \(watchedPath)", source: "FileWatcher")
            }
            return
        }
        stream = created

        Task { @MainActor in
            LogManager.shared.debug("FileWatcher started for: \(watchedPath)", source: "FileWatcher")
        }
    }

    func stop() {
        lock.lock()
        let stopped = stream
        stream = nil
        lock.unlock()

        // Released outside the lock: the release callback can drop the last reference and run deinit.
        guard let stopped else { return }
        FSEventStreamStop(stopped)
        FSEventStreamInvalidate(stopped)
        FSEventStreamRelease(stopped)
    }

    /// Maps events to paths relative to `rootPath` and stats each one; call it on the watcher queue, not main.
    static func relativeChanges(_ changes: [FileChangeEvent], under rootPath: String) -> [RelativeFileChange] {
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return changes.compactMap { change in
            let path = URL(fileURLWithPath: change.path).standardizedFileURL.path
            guard path.hasPrefix(prefix) else { return nil }
            let relativePath = String(path.dropFirst(prefix.count))
            guard !relativePath.isEmpty else { return nil }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return RelativeFileChange(
                relativePath: relativePath,
                name: (relativePath as NSString).lastPathComponent,
                isDirectory: exists && isDirectory.boolValue,
                kind: change.kind
            )
        }
    }
}
