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

    convenience init() {
        self.init(storageURL: AppDataLocation.localChangesURL)
    }

    init(storageURL: URL, limit: Int = 100) {
        self.storageURL = storageURL
        self.limit = limit
    }

    func restore() async {
        let url = storageURL
        let restored: [LocalChangeRecord] = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let records = try? JSONDecoder().decode([LocalChangeRecord].self, from: data) else {
                return [LocalChangeRecord]()
            }
            return records
        }.value
        entries = Array(restored.prefix(limit))
    }

    func record(_ records: [LocalChangeRecord]) {
        guard !records.isEmpty else { return }
        entries.insert(contentsOf: records.reversed(), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        schedulePersist()
    }

    func flush() async {
        persistTask?.cancel()
        persistTask = nil
        await persist(entries)
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.persistTask = nil
            await self.persist(self.entries)
        }
    }

    private func persist(_ records: [LocalChangeRecord]) async {
        let url = storageURL
        await Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(records) else { return }
            try? data.write(to: url, options: .atomic)
        }.value
    }
}
