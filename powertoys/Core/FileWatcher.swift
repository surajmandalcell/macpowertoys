//
//  FileWatcher.swift
//  powertoys
//

import Foundation
import CoreServices

enum FileChangeKind: String, Codable, Sendable, CaseIterable {
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

struct FileChangeEvent: Sendable, Hashable {
    let path: String
    let kind: FileChangeKind
}

final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: @Sendable ([FileChangeEvent]) -> Void
    private let latency: CFTimeInterval
    private var isRunning = false
    private let lock = NSLock()

    init(path: String, latency: CFTimeInterval = 0.5, callback: @escaping @Sendable ([FileChangeEvent]) -> Void) {
        self.path = path
        self.latency = latency
        self.callback = callback
    }

    deinit {
        stopSync()
    }

    @MainActor
    func start() {
        guard !isRunning else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
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

                Task { @MainActor in
                    watcher.callback(changes)
                }
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
        ) else {
            LogManager.shared.error("Failed to create FSEvent stream for: \(path)", source: "FileWatcher")
            return
        }

        self.stream = stream

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        isRunning = true

        LogManager.shared.debug("FileWatcher started for: \(path)", source: "FileWatcher")
    }

    @MainActor
    func stop() {
        stopSync()
    }

    private func stopSync() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning, let stream = stream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        self.stream = nil
        isRunning = false
    }
}
