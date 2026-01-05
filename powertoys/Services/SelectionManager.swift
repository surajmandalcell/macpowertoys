//
//  SelectionManager.swift
//  powertoys
//

import Foundation
import AppKit

@Observable
@MainActor
final class SelectionManager {
    var selectedMessageIds: Set<String> = []
    var copyFormat: CopyFormat = .plainText
    
    // MARK: - Selection
    
    func selectMessage(_ id: String) {
        selectedMessageIds = [id]
    }
    
    func toggleMessage(_ id: String) {
        if selectedMessageIds.contains(id) {
            selectedMessageIds.remove(id)
        } else {
            selectedMessageIds.insert(id)
        }
    }
    
    func selectRange(from startId: String, to endId: String, in messages: [CCMessage]) {
        guard let startIndex = messages.firstIndex(where: { $0.id == startId }),
              let endIndex = messages.firstIndex(where: { $0.id == endId }) else {
            return
        }
        
        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        selectedMessageIds = Set(messages[range].map(\.id))
    }
    
    func selectAll(messages: [CCMessage]) {
        selectedMessageIds = Set(messages.map(\.id))
    }
    
    func clearSelection() {
        selectedMessageIds.removeAll()
    }
    
    func isSelected(_ id: String) -> Bool {
        selectedMessageIds.contains(id)
    }
    
    // MARK: - Copy
    
    func copySelected(messages: [CCMessage]) {
        let selectedMessages = messages.filter { selectedMessageIds.contains($0.id) }
        copyMessages(selectedMessages)
    }
    
    func copyMessage(_ message: CCMessage) {
        copyMessages([message])
    }
    
    private func copyMessages(_ messages: [CCMessage]) {
        let content: String
        
        switch copyFormat {
        case .plainText:
            content = messages.map { formatMessagePlainText($0) }.joined(separator: "\n\n---\n\n")
        case .markdown:
            content = messages.map { formatMessageMarkdown($0) }.joined(separator: "\n\n---\n\n")
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    private func formatMessagePlainText(_ message: CCMessage) -> String {
        """
        [\(message.type.displayName)]
        \(message.content)
        """
    }
    
    private func formatMessageMarkdown(_ message: CCMessage) -> String {
        """
        ## \(message.type.displayName)
        
        \(message.content)
        """
    }
}
