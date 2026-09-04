import CoreServices
import Foundation

nonisolated struct DevFileEvent: Equatable, Sendable {
    var path: String
    var flags: UInt32
    var eventID: UInt64
}

nonisolated struct DevEventBatch: Equatable, Sendable {
    var events: [DevFileEvent]
    var lastEventID: UInt64
    var mustRescanRoot: Bool
    var rescanSubtrees: [String]
    var mountChanged: Bool
}

nonisolated final class DevEventStream: @unchecked Sendable {
    private let rootURL: URL
    private let sinceEventID: FSEventStreamEventId
    private let isReplay: Bool
    private let latencySeconds: Double
    private let queue: DispatchQueue
    private let handler: @Sendable (DevEventBatch) -> Void
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var running = false

    init(
        rootURL: URL,
        sinceEventID: UInt64?,
        latencySeconds: Double,
        queue: DispatchQueue,
        handler: @escaping @Sendable (DevEventBatch) -> Void
    ) {
        self.rootURL = rootURL
        self.sinceEventID = sinceEventID.map { FSEventStreamEventId($0) } ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        self.isReplay = sinceEventID != nil
        self.latencySeconds = max(0, latencySeconds)
        self.queue = queue
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !running else { return true }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let createdStream = FSEventStreamCreate(
            nil,
            { _, info, eventCount, eventPaths, eventFlags, eventIDs in
                guard let info else { return }
                let stream = Unmanaged<DevEventStream>.fromOpaque(info).takeUnretainedValue()
                stream.handle(
                    eventCount: eventCount,
                    eventPaths: eventPaths,
                    eventFlags: eventFlags,
                    eventIDs: eventIDs
                )
            },
            &context,
            [rootURL.path] as CFArray,
            sinceEventID,
            latencySeconds,
            flags
        ) else {
            Task { @MainActor in
                LogManager.shared.error("Failed to create FSEvents stream", source: "DevSync")
            }
            return false
        }

        FSEventStreamSetDispatchQueue(createdStream, queue)
        stream = createdStream
        running = true
        guard FSEventStreamStart(createdStream) else {
            stream = nil
            running = false
            FSEventStreamInvalidate(createdStream)
            FSEventStreamRelease(createdStream)
            Task { @MainActor in
                LogManager.shared.error("Failed to start FSEvents stream", source: "DevSync")
            }
            return false
        }

        return true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard running, let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        running = false
    }

    static func currentEventID(forDeviceOf url: URL) -> UInt64 {
        var fileStatus = Darwin.stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &fileStatus)
        }
        guard result == 0 else {
            return UInt64(FSEventsGetCurrentEventId())
        }
        return UInt64(FSEventsGetLastEventIdForDeviceBeforeTime(fileStatus.st_dev, CFAbsoluteTimeGetCurrent()))
    }

    private func handle(
        eventCount: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>,
        eventIDs: UnsafePointer<FSEventStreamEventId>
    ) {
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
        let count = min(eventCount, paths.count)
        guard count > 0 else { return }

        let rootPaths = Set([
            eventComparablePath(rootURL.standardizedFileURL.path)
        ])
        var events: [DevFileEvent] = []
        var rescanSubtrees: [String] = []
        var rescanSubtreePaths = Set<String>()
        var mustRescanRoot = false
        var mountChanged = false

        for index in 0..<count {
            let path = paths[index]
            let flags = UInt32(eventFlags[index])
            let eventID = UInt64(eventIDs[index])
            events.append(DevFileEvent(path: path, flags: flags, eventID: eventID))

            let eventPath = eventComparablePath(URL(fileURLWithPath: path).standardizedFileURL.path)
            let isRoot = rootPaths.contains(eventPath)
            let mustScan = flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0
            let dropped = flags & UInt32(kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0
            let wrapped = flags & UInt32(kFSEventStreamEventFlagEventIdsWrapped) != 0
            let rootChanged = flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0
            let historyDone = isReplay && flags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0

            if dropped || wrapped || rootChanged || historyDone || (mustScan && isRoot) {
                mustRescanRoot = true
            } else if mustScan {
                if rescanSubtreePaths.insert(path).inserted {
                    rescanSubtrees.append(path)
                }
            }

            if flags & UInt32(kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount) != 0 {
                mountChanged = true
            }
        }

        let lastEventID = events.map { $0.eventID }.max() ?? 0
        handler(
            DevEventBatch(
                events: events,
                lastEventID: lastEventID,
                mustRescanRoot: mustRescanRoot,
                rescanSubtrees: rescanSubtrees,
                mountChanged: mountChanged
            )
        )
    }

    private func eventComparablePath(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }
}

nonisolated struct DevDirtyGeneration: Equatable, Sendable {
    var projectID: UUID
    var side: DevSyncSide
    var paths: Set<String>?
    var firstEventAt: Date
    var lastEventAt: Date
    var reason: DevDirtyReason
    var requiresFullScan: Bool
}

actor DevDirtyScheduler {
    static let discoveryProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private struct Pending: Sendable {
        var generation: DevDirtyGeneration
        var eventTimes: [Date]
        var dueNow: Bool
    }

    private let timing: DevSyncConfiguration.Timing
    private let performance: DevSyncConfiguration.Performance
    private let now: @Sendable () -> Date
    private var pending: [UUID: Pending] = [:]
    private var lastCompletion: [UUID: Date] = [:]
    private var attemptCounts: [UUID: Int] = [:]

    init(
        timing: DevSyncConfiguration.Timing,
        performance: DevSyncConfiguration.Performance,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.timing = timing
        self.performance = performance
        self.now = now
    }

    func noteEvents(
        side: DevSyncSide,
        relativePaths: [String],
        projectResolver: @Sendable (String) -> UUID?,
        at date: Date? = nil
    ) {
        guard !relativePaths.isEmpty else { return }
        let eventDate = date ?? now()

        for relativePath in relativePaths {
            let resolvedProject = projectResolver(relativePath)
            let projectID = resolvedProject ?? Self.discoveryProjectID
            let reason: DevDirtyReason = resolvedProject == nil ? .unknownPath : .fileEvent
            var item = pending[projectID] ?? Pending(
                generation: DevDirtyGeneration(
                    projectID: projectID,
                    side: side,
                    paths: [],
                    firstEventAt: eventDate,
                    lastEventAt: eventDate,
                    reason: reason,
                    requiresFullScan: resolvedProject == nil
                ),
                eventTimes: [],
                dueNow: false
            )

            item.generation.firstEventAt = min(item.generation.firstEventAt, eventDate)
            item.generation.lastEventAt = max(item.generation.lastEventAt, eventDate)
            if item.generation.side != side {
                item.generation.paths = nil
                item.generation.requiresFullScan = true
            }
            if item.generation.paths != nil, resolvedProject != nil {
                item.generation.paths?.insert(relativePath)
            }
            if resolvedProject == nil {
                item.generation.paths = nil
                item.generation.requiresFullScan = true
            }
            if reason == .unknownPath || item.generation.reason == .unknownPath {
                item.generation.reason = reason
            }
            item.eventTimes.append(eventDate)
            item.eventTimes = recentEventTimes(item.eventTimes, relativeTo: eventDate)
            if item.eventTimes.count > performance.eventStormThreshold {
                item.generation.paths = nil
                item.generation.requiresFullScan = true
            }
            if let paths = item.generation.paths, paths.count > performance.pathCollapseThreshold {
                item.generation.paths = nil
                item.generation.requiresFullScan = true
            }
            pending[projectID] = item
        }
    }

    func noteFullRescan(side: DevSyncSide, projectID: UUID?, reason: DevDirtyReason) {
        let projectID = projectID ?? Self.discoveryProjectID
        let eventDate = now()
        var item = pending[projectID] ?? Pending(
            generation: DevDirtyGeneration(
                projectID: projectID,
                side: side,
                paths: nil,
                firstEventAt: eventDate,
                lastEventAt: eventDate,
                reason: reason,
                requiresFullScan: true
            ),
            eventTimes: [],
            dueNow: false
        )
        item.generation.firstEventAt = min(item.generation.firstEventAt, eventDate)
        item.generation.lastEventAt = max(item.generation.lastEventAt, eventDate)
        item.generation.paths = nil
        item.generation.reason = reason
        item.generation.requiresFullScan = true
        item.eventTimes.append(eventDate)
        item.eventTimes = recentEventTimes(item.eventTimes, relativeTo: eventDate)
        pending[projectID] = item
    }

    func requestNow(projectID: UUID, reason: DevDirtyReason) {
        let eventDate = now()
        var item = pending[projectID] ?? Pending(
            generation: DevDirtyGeneration(
                projectID: projectID,
                side: .internal,
                paths: nil,
                firstEventAt: eventDate,
                lastEventAt: eventDate,
                reason: reason,
                requiresFullScan: true
            ),
            eventTimes: [],
            dueNow: true
        )
        item.generation.lastEventAt = max(item.generation.lastEventAt, eventDate)
        item.generation.reason = reason
        if item.generation.paths == nil {
            item.generation.requiresFullScan = true
        }
        item.dueNow = true
        pending[projectID] = item
    }

    func due(at date: Date? = nil) -> [DevDirtyGeneration] {
        let currentDate = date ?? now()
        return pending.values
            .filter { isDue($0, at: currentDate) }
            .map { $0.generation }
            .sorted(by: generationPrecedes)
    }

    func nextDueDate() -> Date? {
        let currentDate = now()
        return pending.values.compactMap { nextDueDate(for: $0, now: currentDate) }.min()
    }

    func begin(projectID: UUID) -> DevDirtyGeneration? {
        guard let item = pending.removeValue(forKey: projectID) else { return nil }
        return item.generation
    }

    func complete(projectID: UUID, at date: Date? = nil) {
        lastCompletion[projectID] = date ?? now()
        attemptCounts[projectID] = nil
    }

    func requeue(_ generation: DevDirtyGeneration) {
        let projectID = generation.projectID
        attemptCounts[projectID, default: 0] += 1
        guard var item = pending[projectID] else {
            var generation = generation
            if generation.paths == nil {
                generation.requiresFullScan = true
            }
            pending[projectID] = Pending(generation: generation, eventTimes: [generation.firstEventAt, generation.lastEventAt], dueNow: false)
            return
        }

        item.generation.firstEventAt = min(item.generation.firstEventAt, generation.firstEventAt)
        item.generation.lastEventAt = max(item.generation.lastEventAt, generation.lastEventAt)
        item.generation.reason = generation.reason
        item.generation.requiresFullScan = item.generation.requiresFullScan || generation.requiresFullScan
        if item.generation.side != generation.side {
            item.generation.paths = nil
            item.generation.requiresFullScan = true
        } else if item.generation.paths == nil || generation.paths == nil {
            item.generation.paths = nil
            item.generation.requiresFullScan = true
        } else if let paths = generation.paths {
            item.generation.paths = (item.generation.paths ?? []).union(paths)
        } else {
            item.generation.paths = nil
        }
        item.eventTimes.append(contentsOf: [generation.firstEventAt, generation.lastEventAt])
        item.eventTimes = recentEventTimes(item.eventTimes, relativeTo: item.generation.lastEventAt)
        pending[projectID] = item
    }

    func exportEntries() -> [DevDirtyEntry] {
        pending.values
            .flatMap { item -> [DevDirtyEntry] in
                let paths: [String?] = item.generation.paths.map { $0.sorted(by: bytewisePrecedes).map(Optional.some) } ?? [nil]
                return paths.map {
                    DevDirtyEntry(
                        projectID: item.generation.projectID,
                        side: item.generation.side,
                        relativePath: $0,
                        firstEventAt: item.generation.firstEventAt,
                        lastEventAt: item.generation.lastEventAt,
                        reason: item.generation.reason,
                        requiresFullScan: item.generation.requiresFullScan,
                        attemptCount: attemptCounts[item.generation.projectID, default: 0]
                    )
                }
            }
            .sorted { lhs, rhs in
                let leftProject = lhs.projectID?.uuidString ?? ""
                let rightProject = rhs.projectID?.uuidString ?? ""
                if leftProject != rightProject { return leftProject < rightProject }
                if lhs.side != rhs.side { return lhs.side.rawValue < rhs.side.rawValue }
                return bytewisePrecedes(lhs.relativePath ?? "", rhs.relativePath ?? "")
            }
    }

    func importEntries(_ entries: [DevDirtyEntry]) {
        for entry in entries {
            let projectID = entry.projectID ?? Self.discoveryProjectID
            var item = pending[projectID] ?? Pending(
                generation: DevDirtyGeneration(
                    projectID: projectID,
                    side: entry.side,
                    paths: entry.relativePath.map { [$0] },
                    firstEventAt: entry.firstEventAt,
                    lastEventAt: entry.lastEventAt,
                    reason: entry.reason,
                    requiresFullScan: entry.requiresFullScan
                ),
                eventTimes: [entry.firstEventAt, entry.lastEventAt],
                dueNow: entry.reason == .userRequested
            )
            item.generation.firstEventAt = min(item.generation.firstEventAt, entry.firstEventAt)
            item.generation.lastEventAt = max(item.generation.lastEventAt, entry.lastEventAt)
            item.generation.reason = entry.reason
            item.generation.requiresFullScan = item.generation.requiresFullScan || entry.requiresFullScan
            if item.generation.side != entry.side || entry.relativePath == nil {
                item.generation.paths = nil
                item.generation.requiresFullScan = true
            } else {
                item.generation.paths?.insert(entry.relativePath!)
            }
            item.eventTimes.append(contentsOf: [entry.firstEventAt, entry.lastEventAt])
            item.eventTimes = recentEventTimes(item.eventTimes, relativeTo: item.generation.lastEventAt)
            item.dueNow = item.dueNow || entry.reason == .userRequested
            attemptCounts[projectID] = max(attemptCounts[projectID, default: 0], entry.attemptCount)
            pending[projectID] = item
        }
    }

    private func isDue(_ item: Pending, at date: Date) -> Bool {
        if item.dueNow { return true }
        guard !timing.isManualOnly else { return false }
        guard let dueDate = nextDueDate(for: item, now: date), dueDate <= date else { return false }
        if let completedAt = lastCompletion[item.generation.projectID], timing.minimumProjectIntervalSeconds > 0 {
            return completedAt.addingTimeInterval(timing.minimumProjectIntervalSeconds) <= date
        }
        return true
    }

    private func nextDueDate(for item: Pending, now date: Date) -> Date? {
        if item.dueNow { return date }
        guard !timing.isManualOnly else { return nil }

        var dueDates: [Date] = []
        if timing.quietPeriodSeconds > 0 {
            dueDates.append(item.generation.lastEventAt.addingTimeInterval(timing.quietPeriodSeconds))
        }
        if timing.continuousCheckpointSeconds > 0 {
            dueDates.append(item.generation.firstEventAt.addingTimeInterval(timing.continuousCheckpointSeconds))
        }
        guard var dueDate = dueDates.min() else { return nil }
        if let completedAt = lastCompletion[item.generation.projectID], timing.minimumProjectIntervalSeconds > 0 {
            dueDate = max(dueDate, completedAt.addingTimeInterval(timing.minimumProjectIntervalSeconds))
        }
        return dueDate
    }

    private func recentEventTimes(_ dates: [Date], relativeTo date: Date) -> [Date] {
        guard performance.eventStormWindowSeconds >= 0 else { return [] }
        return dates.filter { abs($0.timeIntervalSince(date)) <= performance.eventStormWindowSeconds }
    }

    private func generationPrecedes(_ lhs: DevDirtyGeneration, _ rhs: DevDirtyGeneration) -> Bool {
        if lhs.firstEventAt != rhs.firstEventAt { return lhs.firstEventAt < rhs.firstEventAt }
        return lhs.projectID.uuidString < rhs.projectID.uuidString
    }

    private func bytewisePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}

actor DevSelfEventLedger {
    private struct Expectation: Sendable {
        var signature: DevFileSignature
        var operationID: UUID
        var until: Date
    }

    private struct Key: Hashable, Sendable {
        var side: DevSyncSide
        var relativePath: String
    }

    private var expectations: [Key: Expectation] = [:]

    func expect(side: DevSyncSide, relativePath: String, signature: DevFileSignature, operationID: UUID, until: Date) {
        expectations[Key(side: side, relativePath: relativePath)] = Expectation(
            signature: signature,
            operationID: operationID,
            until: until
        )
    }

    func consume(
        side: DevSyncSide,
        relativePath: String,
        actual: DevFileSignature?,
        toleranceNanoseconds: Int64,
        now: Date = Date()
    ) -> Bool {
        let key = Key(side: side, relativePath: relativePath)
        guard let expectation = expectations.removeValue(forKey: key), expectation.until > now else {
            return false
        }
        guard let actual, expectation.signature.quickMatches(actual, toleranceNanoseconds: toleranceNanoseconds, compareMode: true) else {
            return false
        }
        return true
    }

    func expire(now: Date) {
        expectations = expectations.filter { $0.value.until > now }
    }
}
