//
//  LocalChangeHistory.swift
//  powertoys
//

import Foundation

struct LocalChangeRecord: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let timestamp: Date
    let jobID: UUID
    let operation: RcloneOperation
    let sourceDisplay: String
    let relativePath: String
    let kind: FileChangeKind

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        jobID: UUID,
        operation: RcloneOperation,
        sourceDisplay: String,
        relativePath: String,
        kind: FileChangeKind
    ) {
        self.id = id
        self.timestamp = timestamp
        self.jobID = jobID
        self.operation = operation
        self.sourceDisplay = sourceDisplay
        self.relativePath = relativePath
        self.kind = kind
    }
}

@Observable
@MainActor
final class LocalChangeHistory {
    static let shared = LocalChangeHistory()

    private(set) var entries: [LocalChangeRecord] = []
    private let storageURL: URL
    private let limit: Int
    private var persistTask: Task<Void, Never>?
    private let writer = OrderedAtomicFileWriter()
    private var revision = 0
    private var needsSave = false
    private var didRestore = false
    private var restoreTask: Task<[LocalChangeRecord], Never>?

    convenience init() {
        self.init(storageURL: AppDataLocation.localChangesURL)
    }

    init(storageURL: URL, limit: Int = 100) {
        self.storageURL = storageURL
        self.limit = limit
    }

    func restore() async {
        guard !didRestore else { return }
        let url = storageURL
        let task = restoreTask ?? Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let records = try? JSONDecoder().decode([LocalChangeRecord].self, from: data) else {
                return [LocalChangeRecord]()
            }
            return records
        }
        restoreTask = task
        let restored = await task.value
        guard !didRestore else { return }
        let current = entries
        let currentIDs = Set(current.map(\.id))
        entries = limited(current + restored.filter { !currentIDs.contains($0.id) })
        didRestore = true
        restoreTask = nil
        if !current.isEmpty { schedulePersist() }
    }

    func record(_ records: [LocalChangeRecord]) {
        guard !records.isEmpty else { return }
        entries.insert(contentsOf: records.reversed(), at: 0)
        entries = limited(entries)
        schedulePersist()
    }

    func removeEntries(for jobIDs: Set<UUID>) {
        guard !jobIDs.isEmpty else { return }
        let previousCount = entries.count
        entries.removeAll { jobIDs.contains($0.jobID) }
        if entries.count != previousCount {
            schedulePersist()
        }
    }

    func flush() async {
        do {
            try await flushReportingErrors()
        } catch {
            LogManager.shared.error("Unable to save local change history: \(error.localizedDescription)", source: "LocalChangeHistory")
        }
    }

    func flushReportingErrors() async throws {
        if needsSave, !didRestore { await restore() }
        persistTask?.cancel()
        persistTask = nil
        guard needsSave else { return }
        try await persist(entries)
    }

    private func schedulePersist() {
        needsSave = true
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.persistTask = nil
            await self.flush()
        }
    }

    private func limited(_ records: [LocalChangeRecord]) -> [LocalChangeRecord] {
        var counts: [UUID: Int] = [:]
        return records.filter { record in
            let count = counts[record.jobID, default: 0]
            guard count < limit else { return false }
            counts[record.jobID] = count + 1
            return true
        }
    }

    private func persist(_ records: [LocalChangeRecord]) async throws {
        let url = storageURL
        revision += 1
        let currentRevision = revision
        let writer = self.writer
        try await Task.detached(priority: .utility) {
            let data = try JSONEncoder().encode(records)
            try await writer.write(data, revision: currentRevision, to: url)
        }.value
        if entries == records { needsSave = false }
    }
}
