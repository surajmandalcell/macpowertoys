//
//  ExportManager.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

class ExportManager {
    
    static func export(messages: [CCMessage], format: ExportFormat) {
        let content = formatMessages(messages, format: format)
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "conversation.\(format.fileExtension)"
        panel.message = "Export conversation as \(format.rawValue)"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Export error: \(error)")
            }
        }
    }
    
    static func exportToClipboard(messages: [CCMessage], format: ExportFormat) {
        let content = formatMessages(messages, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    private static func formatMessages(_ messages: [CCMessage], format: ExportFormat) -> String {
        switch format {
        case .markdown:
            return formatAsMarkdown(messages)
        case .json:
            return formatAsJSON(messages)
        case .plainText:
            return formatAsPlainText(messages)
        }
    }
    
    private static func formatAsMarkdown(_ messages: [CCMessage]) -> String {
        var output = "# Conversation Export\n\n"
        output += "Exported: \(Date().formatted())\n\n---\n\n"
        
        for message in messages {
            output += "## \(message.type.displayName)\n\n"
            output += message.content
            output += "\n\n"
            
            if !message.toolUse.isEmpty {
                output += "### Tool Calls\n\n"
                for tool in message.toolUse {
                    output += "**\(tool.name)**\n\n"
                    output += "```json\n\(tool.input)\n```\n\n"
                    if let toolOutput = tool.output {
                        output += "Output:\n```\n\(toolOutput)\n```\n\n"
                    }
                }
            }
            
            output += "---\n\n"
        }
        
        return output
    }
    
    private static func formatAsJSON(_ messages: [CCMessage]) -> String {
        let exportData = messages.map { message -> [String: Any] in
            var dict: [String: Any] = [
                "id": message.id,
                "type": message.type.rawValue,
                "content": message.content,
                "timestamp": ISO8601DateFormatter().string(from: message.timestamp)
            ]
            
            if !message.toolUse.isEmpty {
                dict["toolUse"] = message.toolUse.map { tool -> [String: Any] in
                    var toolDict: [String: Any] = [
                        "id": tool.id,
                        "name": tool.name,
                        "input": tool.input
                    ]
                    if let output = tool.output {
                        toolDict["output"] = output
                    }
                    return toolDict
                }
            }
            
            if let thinking = message.thinking {
                dict["thinking"] = thinking
            }
            
            return dict
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        
        return "[]"
    }
    
    private static func formatAsPlainText(_ messages: [CCMessage]) -> String {
        var output = "Conversation Export\n"
        output += "Exported: \(Date().formatted())\n"
        output += String(repeating: "=", count: 50) + "\n\n"
        
        for message in messages {
            output += "[\(message.type.displayName.uppercased())]\n"
            output += message.content
            output += "\n\n"
            
            if !message.toolUse.isEmpty {
                output += "Tool Calls:\n"
                for tool in message.toolUse {
                    output += "  - \(tool.name)\n"
                }
                output += "\n"
            }
            
            output += String(repeating: "-", count: 50) + "\n\n"
        }
        
        return output
    }
}
