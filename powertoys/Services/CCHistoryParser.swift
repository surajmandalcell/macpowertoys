//
//  CCHistoryParser.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation

class CCHistoryParser {
    
    // MARK: - JSONL Parsing
    
    /// Parse a JSONL file and extract messages using memory-efficient chunked reading
    nonisolated static func parseJSONLFile(at url: URL) -> [CCMessage] {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return [] }
        defer { try? handle.close() }

        var messages: [CCMessage] = []
        var buffer = Data()
        let chunkSize = 65536

        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard !lineData.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = json["type"] as? String,
                      ["user", "assistant", "system"].contains(type),
                      let message = parseMessage(from: json) else {
                    continue
                }

                messages.append(message)
            }
        }

        if !buffer.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any],
           let type = json["type"] as? String,
           ["user", "assistant", "system"].contains(type),
           let message = parseMessage(from: json) {
            messages.append(message)
        }

        return messages
    }

    /// Stream-parse a JSONL file, yielding messages as they're parsed
    static func parseJSONLFileStreaming(at url: URL) -> AsyncStream<CCMessage> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                guard let handle = FileHandle(forReadingAtPath: url.path) else {
                    continuation.finish()
                    return
                }
                defer { try? handle.close() }

                var buffer = Data()
                let chunkSize = 8192

                while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
                    buffer.append(chunk)

                    while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                        guard !lineData.isEmpty,
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let type = json["type"] as? String,
                              ["user", "assistant", "system"].contains(type),
                              let message = parseMessage(from: json) else {
                            continue
                        }

                        continuation.yield(message)
                    }
                }

                if !buffer.isEmpty,
                   let json = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any],
                   let type = json["type"] as? String,
                   ["user", "assistant", "system"].contains(type),
                   let message = parseMessage(from: json) {
                    continuation.yield(message)
                }

                continuation.finish()
            }
        }
    }
    
    /// Parse session metadata (first user message, timestamp) quickly without loading all messages
    nonisolated static func parseSessionMetadata(at url: URL) -> (firstUserMessage: String?, timestamp: Date?, messageCount: Int) {
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

    /// Quick metadata parsing - only gets first user message and timestamp (no message count)
    nonisolated static func parseSessionMetadataQuick(at url: URL) -> (firstUserMessage: String?, timestamp: Date?) {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return (nil, nil) }
        defer { try? handle.close() }

        guard let chunk = try? handle.read(upToCount: 16384) else { return (nil, nil) }
        guard let content = String(data: chunk, encoding: .utf8) else { return (nil, nil) }

        var firstUserMessage: String?
        var latestTimestamp: Date?

        for line in content.components(separatedBy: "\n").prefix(50) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String,
                  ["user", "assistant", "system"].contains(type) else {
                continue
            }

            if let timestampStr = json["timestamp"] as? String,
               let date = parseTimestamp(timestampStr) {
                if latestTimestamp == nil || date > latestTimestamp! {
                    latestTimestamp = date
                }
            }

            if type == "user" && firstUserMessage == nil {
                firstUserMessage = extractContent(from: json)
                if latestTimestamp != nil {
                    break
                }
            }
        }

        return (firstUserMessage, latestTimestamp)
    }

    /// Efficiently count messages using chunked reading (for background queue)
    nonisolated static func countMessages(at url: URL) -> Int {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return 0 }
        defer { try? handle.close() }

        var count = 0
        var buffer = Data()
        let chunkSize = 65536

        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard !lineData.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = json["type"] as? String,
                      ["user", "assistant", "system"].contains(type) else {
                    continue
                }
                count += 1
            }
        }

        if !buffer.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any],
           let type = json["type"] as? String,
           ["user", "assistant", "system"].contains(type) {
            count += 1
        }

        return count
    }

    // MARK: - Content Search

    /// Efficiently search file content for a query without fully parsing messages.
    /// Returns true if any message content contains the query (case-insensitive).
    nonisolated static func containsContent(at url: URL, query: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? handle.close() }

        let lowercasedQuery = query.lowercased()
        var buffer = Data()
        let chunkSize = 65536

        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard !lineData.isEmpty,
                      let lineString = String(data: lineData, encoding: .utf8) else {
                    continue
                }

                if lineString.lowercased().contains(lowercasedQuery) {
                    return true
                }
            }
        }

        if !buffer.isEmpty,
           let lineString = String(data: buffer, encoding: .utf8),
           lineString.lowercased().contains(lowercasedQuery) {
            return true
        }

        return false
    }

    /// Search file content and return matching message previews.
    nonisolated static func searchContent(at url: URL, query: String, maxMatches: Int = 3) -> [String] {
        guard maxMatches > 0, let handle = FileHandle(forReadingAtPath: url.path) else { return [] }
        defer { try? handle.close() }

        let lowercasedQuery = query.lowercased()
        var matches: [String] = []
        var buffer = Data()
        let chunkSize = 65536

        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard !lineData.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = json["type"] as? String,
                      ["user", "assistant"].contains(type) else {
                    continue
                }

                let content = extractContent(from: json)
                if content.lowercased().contains(lowercasedQuery) {
                    let preview = extractMatchPreview(from: content, query: query)
                    matches.append(preview)
                    if matches.count >= maxMatches { return matches }
                }
            }
        }

        if !buffer.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any],
           let type = json["type"] as? String,
           ["user", "assistant"].contains(type) {
            let content = extractContent(from: json)
            if content.lowercased().contains(lowercasedQuery) {
                matches.append(extractMatchPreview(from: content, query: query))
            }
        }

        return matches
    }

    private nonisolated static func extractMatchPreview(from content: String, query: String) -> String {
        let lowercased = content.lowercased()
        guard let range = lowercased.range(of: query.lowercased()) else {
            return String(content.prefix(100))
        }

        let matchIndex = lowercased.distance(from: lowercased.startIndex, to: range.lowerBound)
        let startIndex = max(0, matchIndex - 30)
        let start = content.index(content.startIndex, offsetBy: startIndex)
        let endIndex = min(content.count, matchIndex + query.count + 50)
        let end = content.index(content.startIndex, offsetBy: endIndex)

        var preview = String(content[start..<end])
        if startIndex > 0 { preview = "..." + preview }
        if endIndex < content.count { preview = preview + "..." }

        return preview.replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Private Helpers

    private nonisolated static func parseMessage(from json: [String: Any]) -> CCMessage? {
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
    
    private nonisolated static func extractContent(from json: [String: Any]) -> String {
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
    
    private nonisolated static func extractToolUse(from json: [String: Any]) -> [ToolUseBlock] {
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
    
    private nonisolated static func extractThinking(from json: [String: Any]) -> String? {
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
    
    private enum Formatters {
        nonisolated(unsafe) static let timestamp: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        nonisolated(unsafe) static let timestampNoFractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
    }

    private nonisolated static func parseTimestamp(_ string: String) -> Date? {
        Formatters.timestamp.date(from: string) ?? Formatters.timestampNoFractional.date(from: string)
    }
    
    private nonisolated static func formatJSON(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}
