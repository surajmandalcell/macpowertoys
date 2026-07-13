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

    nonisolated init(level: LogLevel, source: String, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.source = source
        self.message = message
    }

    nonisolated init(id: UUID, timestamp: Date, level: LogLevel, source: String, message: String) {
        self.id = id
        self.timestamp = timestamp
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
    private static let iso8601Formatter = ISO8601DateFormatter()

    private(set) var logs: [LogEntryData] = []
    private let maxMemoryEntries = 1000
    private let retentionDays = 2

    private var persistence: LogPersistence?
    private var pendingPersist: [LogEntryData] = []
    private var flushTask: Task<Void, Never>?

    private init() {}

    func configurePersistence(container: ModelContainer) {
        persistence = LogPersistence(modelContainer: container)
    }

    func log(_ message: String, level: LogLevel, source: String) {
        let entry = LogEntryData(level: level, source: source, message: message)

        logs.append(entry)

        if logs.count > maxMemoryEntries {
            logs.removeFirst(logs.count - maxMemoryEntries)
        }

        pendingPersist.append(entry)
        scheduleFlush()

        #if DEBUG
        let timestamp = Self.iso8601Formatter.string(from: entry.timestamp)
        print("[\(level.name.uppercased())] [\(source)] \(timestamp): \(message)")
        #endif
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.flushPending()
        }
    }

    func flushPending() async {
        flushTask?.cancel()
        flushTask = nil
        guard let persistence, !pendingPersist.isEmpty else { return }
        let batch = pendingPersist
        pendingPersist.removeAll()
        await persistence.persist(batch)
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

        await persistence?.prune(before: cutoffDate)

        info("Pruned logs older than \(retentionDays) days", source: "LogManager")
    }

    func loadPersistedLogs() async {
        guard let persistence else { return }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        logs = await persistence.load(since: cutoffDate, limit: maxMemoryEntries)
    }
}
