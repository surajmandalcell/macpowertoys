//
//  FileWatcher.swift
//  powertoys
//

import Foundation
import CoreServices

final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: @Sendable ([String]) -> Void
    private let latency: CFTimeInterval
    private var isRunning = false
    private let lock = NSLock()

    init(path: String, latency: CFTimeInterval = 0.5, callback: @escaping @Sendable ([String]) -> Void) {
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
            { _, info, numEvents, eventPaths, _, _ in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let changedPaths = Array(paths.prefix(numEvents))

                Task { @MainActor in
                    watcher.callback(changedPaths)
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
