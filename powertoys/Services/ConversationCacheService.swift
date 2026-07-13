//
//  ConversationCacheService.swift
//  powertoys
//

import Foundation
import SwiftData

@MainActor
final class ConversationCacheService {
    static let shared = ConversationCacheService()

    private var modelContext: ModelContext?

    init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Session Metadata Cache

    func getAllCachedMetadata() -> [CachedSessionMetadata] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedSessionMetadata>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    func getCachedMetadata(sessionId: String) -> CachedSessionMetadata? {
        guard let context = modelContext else { return nil }

        let descriptor = FetchDescriptor<CachedSessionMetadata>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )

        return try? context.fetch(descriptor).first
    }

    func cacheMetadata(
        sessionId: String,
        projectPath: String,
        filePath: URL,
        fileModDate: Date,
        firstUserMessage: String?,
        messageCount: Int,
        timestamp: Date?
    ) {
        guard let context = modelContext else { return }

        if let existing = getCachedMetadata(sessionId: sessionId) {
            existing.projectPath = projectPath
            existing.filePath = filePath.path
            existing.fileModificationDate = fileModDate
            existing.firstUserMessage = firstUserMessage
            existing.messageCount = messageCount
            existing.timestamp = timestamp
        } else {
            let metadata = CachedSessionMetadata(
                sessionId: sessionId,
                projectPath: projectPath,
                filePath: filePath.path,
                fileModificationDate: fileModDate,
                firstUserMessage: firstUserMessage,
                messageCount: messageCount,
                timestamp: timestamp
            )
            context.insert(metadata)
        }

        try? context.save()
    }

    func isMetadataValid(sessionId: String, currentModDate: Date) -> Bool {
        guard let cached = getCachedMetadata(sessionId: sessionId) else {
            return false
        }
        return abs(cached.fileModificationDate.timeIntervalSince(currentModDate)) < 1.0
    }

    // MARK: - Message Cache

    func getCachedMessages(sessionId: String, filePath: URL) -> [CCMessage]? {
        guard let context = modelContext else { return nil }

        let descriptor = FetchDescriptor<CachedConversation>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )

        guard let cached = try? context.fetch(descriptor).first else {
            return nil
        }

        guard isValidMessageCache(cached, filePath: filePath) else {
            invalidateMessages(sessionId)
            return nil
        }

        cached.lastAccessDate = Date()
        try? context.save()

        let sortedMessages = cached.messages.sorted { $0.sortOrder < $1.sortOrder }
        return sortedMessages.map { $0.toCCMessage(sessionId: sessionId) }
    }

    func cacheConversation(
        sessionId: String,
        projectPath: String,
        filePath: URL,
        messages: [CCMessage]
    ) {
        guard let context = modelContext else { return }

        invalidateMessages(sessionId)

        let modDate = getFileModificationDate(filePath) ?? Date()
        let firstUserMessage = messages.first { $0.type == .user }?.content
        let conversation = CachedConversation(
            sessionId: sessionId,
            projectPath: projectPath,
            fileModificationDate: modDate,
            firstUserMessage: firstUserMessage,
            messageCount: messages.count
        )

        context.insert(conversation)

        for (index, msg) in messages.enumerated() {
            let toolJSON: String?
            if !msg.toolUse.isEmpty {
                toolJSON = try? String(data: JSONEncoder().encode(msg.toolUse), encoding: .utf8)
            } else {
                toolJSON = nil
            }

            let cached = CachedMessage(
                messageId: msg.id,
                type: msg.type.rawValue,
                content: msg.content,
                timestamp: msg.timestamp,
                parentUuid: msg.parentUuid,
                toolUseJSON: toolJSON,
                thinking: msg.thinking,
                sortOrder: index
            )
            cached.conversation = conversation
            context.insert(cached)
        }

        try? context.save()
        LogManager.shared.debug("Cached \(messages.count) messages for session \(sessionId)", source: "Cache")
    }

    func invalidate(_ sessionId: String) {
        invalidateMetadata(sessionId)
        invalidateMessages(sessionId)
    }

    func invalidateMetadata(_ sessionId: String) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<CachedSessionMetadata>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )

        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
            try? context.save()
        }
    }

    func invalidateMessages(_ sessionId: String) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<CachedConversation>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )

        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
            try? context.save()
        }
    }

    func getCachedSessionMetadata() -> [(sessionId: String, projectPath: String, firstUserMessage: String?, messageCount: Int, timestamp: Date)] {
        let allMetadata = getAllCachedMetadata()
        return allMetadata.map { meta in
            (
                sessionId: meta.sessionId,
                projectPath: meta.projectPath,
                firstUserMessage: meta.firstUserMessage,
                messageCount: meta.messageCount,
                timestamp: meta.timestamp ?? meta.fileModificationDate
            )
        }
    }

    func pruneStaleCache(olderThan days: Int = 30) {
        guard let context = modelContext else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let convDescriptor = FetchDescriptor<CachedConversation>(
            predicate: #Predicate { $0.lastAccessDate < cutoff }
        )

        if let stale = try? context.fetch(convDescriptor) {
            for conversation in stale {
                context.delete(conversation)
            }

            if !stale.isEmpty {
                LogManager.shared.info("Pruned \(stale.count) stale message caches", source: "Cache")
            }
        }

        try? context.save()
    }

    private func isValidMessageCache(_ cached: CachedConversation, filePath: URL) -> Bool {
        guard let fileModDate = getFileModificationDate(filePath) else {
            return false
        }
        return abs(cached.fileModificationDate.timeIntervalSince(fileModDate)) < 1.0
    }

    private func getFileModificationDate(_ url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}
