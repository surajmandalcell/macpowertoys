//
//  LogManager.swift
//  powertoys
//

import Foundation
import SwiftData

// MARK: - Log Level

enum LogLevel: Int, Codable, CaseIterable, Comparable, Sendable {
    case error = 0
    case warning = 1
    case info = 2
    case debug = 3

    var name: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }

    var icon: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .debug: return "ant.fill"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log Entry (In-Memory)

struct LogEntryData: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let source: String
    let message: String

    init(level: LogLevel, source: String, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.source = source
        self.message = message
    }
}

// MARK: - Log Manager

@Observable
@MainActor
final class LogManager {
    static let shared = LogManager()

    private(set) var logs: [LogEntryData] = []
    private let maxMemoryEntries = 1000
    private let retentionDays = 2

    var modelContext: ModelContext?

    private init() {}

    func log(_ message: String, level: LogLevel, source: String) {
        let entry = LogEntryData(level: level, source: source, message: message)

        logs.append(entry)

        if logs.count > maxMemoryEntries {
            logs.removeFirst(logs.count - maxMemoryEntries)
        }

        persistEntry(entry)

        #if DEBUG
        let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
        print("[\(level.name.uppercased())] [\(source)] \(timestamp): \(message)")
        #endif
    }

    func error(_ message: String, source: String = "App") {
        log(message, level: .error, source: source)
    }

    func warning(_ message: String, source: String = "App") {
        log(message, level: .warning, source: source)
    }

    func info(_ message: String, source: String = "App") {
        log(message, level: .info, source: source)
    }

    func debug(_ message: String, source: String = "App") {
        log(message, level: .debug, source: source)
    }

    func getLogs(since date: Date? = nil, level: LogLevel? = nil, source: String? = nil) -> [LogEntryData] {
        var result = logs

        if let date {
            result = result.filter { $0.timestamp >= date }
        }

        if let level {
            result = result.filter { $0.level.rawValue <= level.rawValue }
        }

        if let source {
            result = result.filter { $0.source == source }
        }

        return result
    }

    func clearMemoryLogs() {
        logs.removeAll()
    }

    func pruneOldLogs() async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

        logs.removeAll { $0.timestamp < cutoffDate }

        await prunePersistedLogs(before: cutoffDate)

        info("Pruned logs older than \(retentionDays) days", source: "LogManager")
    }

    private func persistEntry(_ entry: LogEntryData) {
        guard let context = modelContext else { return }

        let persistedEntry = LogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level.rawValue,
            source: entry.source,
            message: entry.message
        )

        context.insert(persistedEntry)

        do {
            try context.save()
        } catch {
            print("Failed to persist log entry: \(error)")
        }
    }

    private func prunePersistedLogs(before date: Date) async {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.timestamp < date }
            )
            let oldLogs = try context.fetch(descriptor)

            for log in oldLogs {
                context.delete(log)
            }

            try context.save()
        } catch {
            print("Failed to prune persisted logs: \(error)")
        }
    }

    func loadPersistedLogs() async {
        guard let context = modelContext else { return }

        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
            let descriptor = FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.timestamp >= cutoffDate },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )

            let persistedLogs = try context.fetch(descriptor)

            let loadedEntries = persistedLogs.compactMap { entry -> LogEntryData? in
                guard let level = LogLevel(rawValue: entry.level) else { return nil }
                return LogEntryData(
                    level: level,
                    source: entry.source,
                    message: entry.message
                )
            }

            logs = loadedEntries.suffix(maxMemoryEntries).map { $0 }

        } catch {
            print("Failed to load persisted logs: \(error)")
        }
    }
}
