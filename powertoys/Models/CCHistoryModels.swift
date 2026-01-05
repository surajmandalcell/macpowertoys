//
//  CCHistoryModels.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation

// MARK: - Project

struct CCProject: Identifiable, Hashable {
    let id: String           // Folder name (encoded path)
    let path: String         // Decoded path (e.g., /Users/surajmandal/dev/...)
    let displayName: String  // Last path component
    var sessions: [CCSession]
    
    init(folderName: String, sessions: [CCSession] = []) {
        self.id = folderName
        self.path = folderName.replacingOccurrences(of: "-", with: "/")
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        self.displayName = components.suffix(2).joined(separator: "/")
        self.sessions = sessions
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CCProject, rhs: CCProject) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session

struct CCSession: Identifiable, Hashable, Codable {
    let id: String           // Session UUID (filename without extension)
    let filePath: URL
    var firstUserMessage: String?
    var timestamp: Date?
    var messageCount: Int
    
    init(id: String, filePath: URL, firstUserMessage: String? = nil, timestamp: Date? = nil, messageCount: Int = 0) {
        self.id = id
        self.filePath = filePath
        self.firstUserMessage = firstUserMessage
        self.timestamp = timestamp
        self.messageCount = messageCount
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CCSession, rhs: CCSession) -> Bool {
        lhs.id == rhs.id
    }
    
    var displayTitle: String {
        if let firstMessage = firstUserMessage {
            let truncated = firstMessage.prefix(50)
            return truncated.count < firstMessage.count ? "\(truncated)..." : String(truncated)
        }
        return id
    }
    
    var displayDate: String {
        guard let timestamp = timestamp else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Message

struct CCMessage: Identifiable, Hashable {
    let id: String           // uuid from JSONL
    let type: MessageType
    let content: String
    let timestamp: Date
    let parentUuid: String?
    let toolUse: [ToolUseBlock]
    let thinking: String?
    let sessionId: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CCMessage, rhs: CCMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum MessageType: String, Codable, CaseIterable {
    case user
    case assistant
    case system
    
    var displayName: String {
        switch self {
        case .user: return "User"
        case .assistant: return "Claude"
        case .system: return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .user: return "person.fill"
        case .assistant: return "brain"
        case .system: return "gearshape.fill"
        }
    }
}

// MARK: - Tool Use

struct ToolUseBlock: Identifiable, Hashable {
    let id: String
    let name: String
    let input: String
    let output: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ToolUseBlock, rhs: ToolUseBlock) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Filter Options

struct FilterOptions {
    var showUser: Bool = true
    var showAssistant: Bool = true
    var showSystem: Bool = false
    var showToolCalls: Bool = false
    var showToolOutputs: Bool = false
    var showThinking: Bool = false
    
    func shouldShow(message: CCMessage) -> Bool {
        switch message.type {
        case .user:
            return showUser
        case .assistant:
            return showAssistant
        case .system:
            return showSystem
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case json = "JSON"
    case plainText = "Plain Text"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .plainText: return "txt"
        }
    }
}

// MARK: - Copy Format

enum CopyFormat: String, CaseIterable, Identifiable {
    case plainText = "Plain Text"
    case markdown = "Markdown"
    
    var id: String { rawValue }
}
