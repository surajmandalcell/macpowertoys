//
//  CachedConversation.swift
//  powertoys
//

import Foundation
import SwiftData

@Model
final class CachedConversation {
    @Attribute(.unique) var sessionId: String
    var projectPath: String
    var fileModificationDate: Date
    var firstUserMessage: String?
    var messageCount: Int
    var lastAccessDate: Date

    @Relationship(deleteRule: .cascade, inverse: \CachedMessage.conversation)
    var messages: [CachedMessage] = []

    init(
        sessionId: String,
        projectPath: String,
        fileModificationDate: Date,
        firstUserMessage: String? = nil,
        messageCount: Int = 0,
        lastAccessDate: Date = Date()
    ) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.fileModificationDate = fileModificationDate
        self.firstUserMessage = firstUserMessage
        self.messageCount = messageCount
        self.lastAccessDate = lastAccessDate
    }
}
