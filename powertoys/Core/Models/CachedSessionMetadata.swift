//
//  CachedSessionMetadata.swift
//  powertoys
//

import Foundation
import SwiftData

@Model
final class CachedSessionMetadata {
    @Attribute(.unique) var sessionId: String
    var projectPath: String
    var filePath: String
    var fileModificationDate: Date
    var firstUserMessage: String?
    var messageCount: Int
    var timestamp: Date?

    init(
        sessionId: String,
        projectPath: String,
        filePath: String,
        fileModificationDate: Date,
        firstUserMessage: String? = nil,
        messageCount: Int = 0,
        timestamp: Date? = nil
    ) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.filePath = filePath
        self.fileModificationDate = fileModificationDate
        self.firstUserMessage = firstUserMessage
        self.messageCount = messageCount
        self.timestamp = timestamp
    }
}
