//
//  LogPersistence.swift
//  powertoys
//

import Foundation
import SwiftData

@ModelActor
actor LogPersistence {
    func persist(_ entries: [LogEntryData]) {
        for entry in entries {
            modelContext.insert(LogEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                level: entry.level.rawValue,
                source: entry.source,
                message: entry.message
            ))
        }
        try? modelContext.save()
    }

    func prune(before date: Date) {
        try? modelContext.delete(model: LogEntry.self, where: #Predicate { $0.timestamp < date })
        try? modelContext.save()
    }

    func load(since date: Date, limit: Int) -> [LogEntryData] {
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.timestamp >= date },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.reversed().compactMap { row in
            guard let level = LogLevel(rawValue: row.level) else { return nil }
            return LogEntryData(id: row.id, timestamp: row.timestamp, level: level, source: row.source, message: row.message)
        }
    }
}
