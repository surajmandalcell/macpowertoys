//
//  CachedMessage.swift
//  powertoys
//

import Foundation
import SwiftData

@Model
final class CachedMessage {
    var messageId: String
    var type: String
    var content: String
    var timestamp: Date
    var parentUuid: String?
    var toolUseJSON: String?
    var thinking: String?
    var sortOrder: Int

    var conversation: CachedConversation?

    init(
        messageId: String,
        type: String,
        content: String,
        timestamp: Date,
        parentUuid: String? = nil,
        toolUseJSON: String? = nil,
        thinking: String? = nil,
        sortOrder: Int = 0
    ) {
        self.messageId = messageId
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.parentUuid = parentUuid
        self.toolUseJSON = toolUseJSON
        self.thinking = thinking
        self.sortOrder = sortOrder
    }

    func toCCMessage(sessionId: String) -> CCMessage {
        let messageType: MessageType
        switch type {
        case "user": messageType = .user
        case "assistant": messageType = .assistant
        default: messageType = .system
        }

        var toolUse: [ToolUseBlock] = []
        if let json = toolUseJSON, let data = json.data(using: .utf8) {
            if let decoded = try? JSONDecoder().decode([ToolUseBlock].self, from: data) {
                toolUse = decoded
            }
        }

        return CCMessage(
            id: messageId,
            type: messageType,
            content: content,
            timestamp: timestamp,
            parentUuid: parentUuid,
            toolUse: toolUse,
            thinking: thinking,
            sessionId: sessionId
        )
    }
}
