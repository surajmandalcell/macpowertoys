//
//  SessionMetadataCache.swift
//  powertoys
//
//  Lightweight JSON-based cache for session metadata.
//  NO SwiftData - just simple JSON file for fast reads.
//

import Foundation

struct SessionMetadata: Codable, Sendable {
    let sessionId: String
    let projectPath: String
    let firstUserMessage: String?
    let fileModificationDate: Date
    var messageCount: Int?
}

actor SessionMetadataCache {
    static let shared = SessionMetadataCache()

    private var cache: [String: SessionMetadata] = [:]
    private var isDirty = false
    private let cacheURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("powertoys", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        cacheURL = appDir.appendingPathComponent("session-metadata-cache.json")
    }

    func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoded = try JSONDecoder().decode([String: SessionMetadata].self, from: data)
            cache = decoded
        } catch {
            cache = [:]
        }
    }

    func saveCache() {
        guard isDirty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            isDirty = false
        } catch {}
    }

    func get(_ sessionId: String) -> SessionMetadata? {
        cache[sessionId]
    }

    func set(_ metadata: SessionMetadata) {
        cache[metadata.sessionId] = metadata
        isDirty = true
    }

    func isValid(_ sessionId: String, fileModDate: Date) -> Bool {
        guard let cached = cache[sessionId] else { return false }
        return abs(cached.fileModificationDate.timeIntervalSince(fileModDate)) < 1.0
    }

    func clear() {
        cache.removeAll()
        isDirty = true
    }

    func clearAndDeleteFile() {
        cache.removeAll()
        isDirty = false
        try? FileManager.default.removeItem(at: cacheURL)
    }

    func cacheSize() -> Int {
        cache.count
    }

    func cacheFileSize() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }
}
