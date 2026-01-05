//
//  MessageRowView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct MessageRowView: View {
    let message: CCMessage
    let isSelected: Bool
    let searchText: String
    let showToolCalls: Bool
    let showToolOutputs: Bool
    let showThinking: Bool

    @Environment(SelectionManager.self) private var selectionManager
    @State private var isHovering: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Role badge
                HStack(spacing: 4) {
                    Image(systemName: message.type.icon)
                        .font(.caption)
                    Text(message.type.displayName)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(roleColor.opacity(0.15))
                .foregroundStyle(roleColor)
                .clipShape(Capsule())
                
                Text(message.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Copy button (shown on hover)
                if isHovering {
                    Button {
                        selectionManager.copyMessage(message)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            
            // Thinking (collapsible)
            if showThinking, let thinking = message.thinking, !thinking.isEmpty {
                DisclosureGroup {
                    Text(thinking)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } label: {
                    Label("Thinking", systemImage: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
            
            // Content
            MessageContentView(content: message.content, searchText: searchText)
            
            // Tool calls
            if showToolCalls && !message.toolUse.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(message.toolUse) { tool in
                        ToolUseView(tool: tool, showOutput: showToolOutputs)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var roleColor: Color {
        switch message.type {
        case .user: return .blue
        case .assistant: return .green
        case .system: return .orange
        }
    }
}

// MARK: - Message Content

struct MessageContentView: View {
    let content: String
    let searchText: String
    
    var body: some View {
        if content.contains("```") {
            // Has code blocks
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parseContent().enumerated()), id: \.offset) { _, block in
                    if block.isCode {
                        CodeBlockView(code: block.content, language: block.language)
                    } else {
                        Text(highlightSearch(block.content))
                            .textSelection(.enabled)
                    }
                }
            }
        } else {
            Text(highlightSearch(content))
                .textSelection(.enabled)
        }
    }
    
    private func highlightSearch(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        guard !searchText.isEmpty else { return attributedString }
        
        let lowercasedText = text.lowercased()
        let lowercasedSearch = searchText.lowercased()
        
        var searchStart = lowercasedText.startIndex
        while let range = lowercasedText.range(of: lowercasedSearch, range: searchStart..<lowercasedText.endIndex) {
            let attrRange = Range<AttributedString.Index>(
                uncheckedBounds: (
                    lower: AttributedString.Index(range.lowerBound, within: attributedString)!,
                    upper: AttributedString.Index(range.upperBound, within: attributedString)!
                )
            )
            attributedString[attrRange].backgroundColor = .yellow.opacity(0.3)
            searchStart = range.upperBound
        }
        
        return attributedString
    }
    
    private func parseContent() -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [ContentBlock(content: content, isCode: false, language: nil)]
        }
        
        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        
        var lastEnd = 0
        
        for match in matches {
            // Text before code block
            if match.range.location > lastEnd {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let text = nsContent.substring(with: textRange)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(ContentBlock(content: text, isCode: false, language: nil))
                }
            }
            
            // Code block
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            
            let language = languageRange.location != NSNotFound ? nsContent.substring(with: languageRange) : nil
            let code = codeRange.location != NSNotFound ? nsContent.substring(with: codeRange) : ""
            
            blocks.append(ContentBlock(content: code, isCode: true, language: language))
            
            lastEnd = match.range.location + match.range.length
        }
        
        // Text after last code block
        if lastEnd < nsContent.length {
            let text = nsContent.substring(from: lastEnd)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(ContentBlock(content: text, isCode: false, language: nil))
            }
        }
        
        return blocks.isEmpty ? [ContentBlock(content: content, isCode: false, language: nil)] : blocks
    }
}

struct ContentBlock {
    let content: String
    let isCode: Bool
    let language: String?
}

// MARK: - Code Block

struct CodeBlockView: View {
    let code: String
    let language: String?
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let language = language, !language.isEmpty {
                    Text(language)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isHovering {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Tool Use

struct ToolUseView: View {
    let tool: ToolUseBlock
    let showOutput: Bool
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                // Input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(tool.input)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                // Output (if available and enabled)
                if showOutput, let output = tool.output {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        ScrollView {
                            Text(output)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                
                Text(tool.name)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    VStack {
        MessageRowView(
            message: CCMessage(
                id: "1",
                type: .user,
                content: "How do I implement authentication?",
                timestamp: Date(),
                parentUuid: nil,
                toolUse: [],
                thinking: nil,
                sessionId: "session1"
            ),
            isSelected: false,
            searchText: "",
            showToolCalls: true,
            showToolOutputs: true,
            showThinking: true
        )
        
        MessageRowView(
            message: CCMessage(
                id: "2",
                type: .assistant,
                content: "Here's how you can implement authentication:\n\n```swift\nfunc authenticate() {\n    // Implementation\n}\n```\n\nThis should work!",
                timestamp: Date(),
                parentUuid: "1",
                toolUse: [
                    ToolUseBlock(
                        id: "tool1",
                        name: "write_file",
                        input: "{\"path\": \"auth.swift\"}",
                        output: "File written successfully"
                    )
                ],
                thinking: "I need to explain authentication...",
                sessionId: "session1"
            ),
            isSelected: true,
            searchText: "authentication",
            showToolCalls: true,
            showToolOutputs: true,
            showThinking: true
        )
    }
    .padding()
    .environment(SelectionManager())
}
