//
//  CCHistoryParser.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation

class CCHistoryParser {
    
    // MARK: - JSONL Parsing
    
    /// Parse a JSONL file and extract messages
    static func parseJSONLFile(at url: URL) -> [CCMessage] {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        
        let lines = data.components(separatedBy: .newlines)
        var messages: [CCMessage] = []
        
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            
            // Skip file-history-snapshot and other non-message types
            guard let type = json["type"] as? String,
                  ["user", "assistant", "system"].contains(type) else {
                continue
            }
            
            if let message = parseMessage(from: json) {
                messages.append(message)
            }
        }
        
        return messages
    }
    
    /// Parse session metadata (first user message, timestamp) quickly without loading all messages
    static func parseSessionMetadata(at url: URL) -> (firstUserMessage: String?, timestamp: Date?, messageCount: Int) {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, nil, 0)
        }
        
        let lines = data.components(separatedBy: .newlines)
        var firstUserMessage: String?
        var latestTimestamp: Date?
        var messageCount = 0
        
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            
            guard let type = json["type"] as? String,
                  ["user", "assistant", "system"].contains(type) else {
                continue
            }
            
            messageCount += 1
            
            // Extract timestamp
            if let timestampStr = json["timestamp"] as? String {
                if let date = parseTimestamp(timestampStr) {
                    if latestTimestamp == nil || date > latestTimestamp! {
                        latestTimestamp = date
                    }
                }
            }
            
            // Get first user message
            if type == "user" && firstUserMessage == nil {
                firstUserMessage = extractContent(from: json)
            }
        }
        
        return (firstUserMessage, latestTimestamp, messageCount)
    }
    
    // MARK: - Private Helpers
    
    private static func parseMessage(from json: [String: Any]) -> CCMessage? {
        guard let uuid = json["uuid"] as? String,
              let typeStr = json["type"] as? String,
              let type = MessageType(rawValue: typeStr),
              let timestampStr = json["timestamp"] as? String,
              let timestamp = parseTimestamp(timestampStr) else {
            return nil
        }
        
        let content = extractContent(from: json)
        let parentUuid = json["parentUuid"] as? String
        let sessionId = json["sessionId"] as? String ?? ""
        let toolUse = extractToolUse(from: json)
        let thinking = extractThinking(from: json)
        
        return CCMessage(
            id: uuid,
            type: type,
            content: content,
            timestamp: timestamp,
            parentUuid: parentUuid,
            toolUse: toolUse,
            thinking: thinking,
            sessionId: sessionId
        )
    }
    
    private static func extractContent(from json: [String: Any]) -> String {
        // Check for message.content (user/assistant messages)
        if let message = json["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                return content
            }
            // Handle content array (assistant messages with tool_use, text, etc.)
            if let contentArray = message["content"] as? [[String: Any]] {
                var textParts: [String] = []
                for item in contentArray {
                    if let type = item["type"] as? String, type == "text",
                       let text = item["text"] as? String {
                        textParts.append(text)
                    }
                }
                return textParts.joined(separator: "\n")
            }
        }
        
        // Fallback: direct content field (system messages)
        if let content = json["content"] as? String {
            return content
        }
        
        return ""
    }
    
    private static func extractToolUse(from json: [String: Any]) -> [ToolUseBlock] {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else {
            return []
        }
        
        var toolBlocks: [ToolUseBlock] = []
        
        for item in contentArray {
            if let type = item["type"] as? String, type == "tool_use",
               let id = item["id"] as? String,
               let name = item["name"] as? String {
                let input = formatJSON(item["input"])
                toolBlocks.append(ToolUseBlock(id: id, name: name, input: input, output: nil))
            }
        }
        
        return toolBlocks
    }
    
    private static func extractThinking(from json: [String: Any]) -> String? {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else {
            return nil
        }
        
        for item in contentArray {
            if let type = item["type"] as? String, type == "thinking",
               let thinking = item["thinking"] as? String {
                return thinking
            }
        }
        
        return nil
    }
    
    private static func parseTimestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    private static func formatJSON(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}
