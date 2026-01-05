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

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func getCachedMessages(sessionId: String, filePath: URL) -> [CCMessage]? {
        guard let context = modelContext else { return nil }

        let descriptor = FetchDescriptor<CachedConversation>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )

        guard let cached = try? context.fetch(descriptor).first else {
            return nil
        }

        guard isValidCache(cached, filePath: filePath) else {
            invalidate(sessionId)
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

        invalidate(sessionId)

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
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedConversation>(
            sortBy: [SortDescriptor(\.lastAccessDate, order: .reverse)]
        )

        guard let conversations = try? context.fetch(descriptor) else { return [] }

        return conversations.map { conv in
            (
                sessionId: conv.sessionId,
                projectPath: conv.projectPath,
                firstUserMessage: conv.firstUserMessage,
                messageCount: conv.messageCount,
                timestamp: conv.fileModificationDate
            )
        }
    }

    func pruneStaleCache(olderThan days: Int = 30) {
        guard let context = modelContext else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<CachedConversation>(
            predicate: #Predicate { $0.lastAccessDate < cutoff }
        )

        if let stale = try? context.fetch(descriptor) {
            for conversation in stale {
                context.delete(conversation)
            }
            try? context.save()

            if !stale.isEmpty {
                LogManager.shared.info("Pruned \(stale.count) stale cached conversations", source: "Cache")
            }
        }
    }

    private func isValidCache(_ cached: CachedConversation, filePath: URL) -> Bool {
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
