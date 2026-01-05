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
    var onToolSelect: ((ToolUseBlock) -> Void)?

    @Environment(SelectionManager.self) private var selectionManager
    @State private var isHovering: Bool = false

    private var rolePrefix: String {
        switch message.type {
        case .user: return "[user]"
        case .assistant: return "[claude]"
        case .system: return "[system]"
        }
    }

    private var roleColor: Color {
        switch message.type {
        case .user: return .blue
        case .assistant: return .secondary
        case .system: return .orange
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Thinking (inline, subtle)
            if showThinking, let thinking = message.thinking, !thinking.isEmpty {
                Text(thinking)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.purple.opacity(0.7))
                    .textSelection(.enabled)
                    .padding(.leading, 16)
            }

            // Main content line
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(rolePrefix)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(roleColor)

                Text(" ")

                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text(" ")
            }

            // Content
            MessageContentView(content: message.content, searchText: searchText)
                .padding(.leading, 16)

            // Tool calls (compact)
            if showToolCalls && !message.toolUse.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(message.toolUse) { tool in
                        ToolUseView(tool: tool, showOutput: showToolOutputs, onSelect: onToolSelect)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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
            attributedString[attrRange].backgroundColor = Color.accentColor.opacity(0.2)
            searchStart = range.upperBound
        }
        
        return attributedString
    }
    
    private static let codeBlockRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "```(\\w*)\\n([\\s\\S]*?)```", options: [])
    }()

    private func parseContent() -> [ContentBlock] {
        var blocks: [ContentBlock] = []

        guard let regex = Self.codeBlockRegex else {
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
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
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
    var onSelect: ((ToolUseBlock) -> Void)?

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("[tool]")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)

                Text(tool.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                if onSelect != nil {
                    Button {
                        onSelect?(tool)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded {
                Text(tool.input)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .padding(.leading, 16)

                if showOutput, let output = tool.output {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(10)
                        .padding(.leading, 16)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
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
