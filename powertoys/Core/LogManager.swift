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
    nonisolated static let maxMemoryEntries = 1000
    nonisolated static let retentionDays = 2
    private(set) var persistenceError: String?

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

        if logs.count > Self.maxMemoryEntries {
            logs.removeFirst(logs.count - Self.maxMemoryEntries)
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
            guard !Task.isCancelled else { return }
            await self?.flushPending()
        }
    }

    func flushPending() async {
        flushTask?.cancel()
        flushTask = nil
        guard let persistence, !pendingPersist.isEmpty else { return }
        let batch = pendingPersist
        pendingPersist.removeAll()
        do {
            try await persistence.persist(batch)
            persistenceError = nil
            await pruneOldLogs()
        } catch {
            pendingPersist.insert(contentsOf: batch, at: 0)
            persistenceError = error.localizedDescription
        }
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

    func clearMemoryLogs() {
        logs.removeAll()
    }

    func pruneOldLogs() async {
        let cutoffDate = Self.retentionCutoff()

        logs.removeAll { $0.timestamp < cutoffDate }

        do {
            try await persistence?.prune(before: cutoffDate)
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func loadPersistedLogs() async {
        guard let persistence else { return }
        do {
            let loaded = try await persistence.load(since: Self.retentionCutoff(), limit: Self.maxMemoryEntries)
            logs = Self.merging(loaded, with: logs)
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    nonisolated static func retentionCutoff(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
    }

    nonisolated static func merging(_ loaded: [LogEntryData], with current: [LogEntryData]) -> [LogEntryData] {
        let currentIDs = Set(current.map(\.id))
        return Array((loaded.filter { !currentIDs.contains($0.id) } + current)
            .sorted { $0.timestamp < $1.timestamp }.suffix(maxMemoryEntries))
    }
}
