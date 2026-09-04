//
//  DevSyncConflictCard.swift
//  powertoys
//

import SwiftUI

nonisolated struct DevConflictDiffLine: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case context
        case added
        case removed
    }

    let id: Int
    let kind: Kind
    let text: String

    var prefix: String {
        switch kind {
        case .context: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    var tint: Color {
        switch kind {
        case .context: return .secondary
        case .added: return .green
        case .removed: return .red
        }
    }
}

nonisolated enum DevConflictDiff {
    static let maximumFileBytes = 64 * 1_024
    static let maximumLines = 200

    static func load(internalPath: String?, externalPath: String?) async -> [DevConflictDiffLine] {
        guard let internalPath, let externalPath,
              let newText = readText(at: internalPath),
              let oldText = readText(at: externalPath)
        else { return [] }
        return lines(newText: newText, oldText: oldText)
    }

    static func readText(at path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey]),
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size <= maximumFileBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func lines(newText: String, oldText: String) -> [DevConflictDiffLine] {
        let new = newText.components(separatedBy: "\n")
        let old = oldText.components(separatedBy: "\n")
        let difference = new.difference(from: old)

        var removedOffsets: Set<Int> = []
        var insertions: [Int: String] = [:]
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, let element, _): insertions[offset] = element
            }
        }

        var result: [DevConflictDiffLine] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if result.count >= maximumLines { break }
            if newIndex < new.count, let inserted = insertions[newIndex] {
                result.append(DevConflictDiffLine(id: result.count, kind: .added, text: inserted))
                newIndex += 1
            } else if oldIndex < old.count, removedOffsets.contains(oldIndex) {
                result.append(DevConflictDiffLine(id: result.count, kind: .removed, text: old[oldIndex]))
                oldIndex += 1
            } else if oldIndex < old.count, newIndex < new.count {
                result.append(DevConflictDiffLine(id: result.count, kind: .context, text: old[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else {
                break
            }
        }
        return result
    }
}

struct DevSyncConflictCard: View {
    let pair: DevSyncPair
    let conflict: DevConflict
    let manager: DevSyncManager

    @State private var diff: [DevConflictDiffLine] = []

    private var isFocused: Bool {
        manager.focusedConflictProjectID == conflict.projectID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerLine
            metadataGrid
            safetyCopies

            if !diff.isEmpty {
                diffView
            }

            actionRow
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(isFocused ? 0.6 : 0), lineWidth: 1)
        )
        .utilityAnimation(value: isFocused)
        .task(id: conflict.id) {
            diff = await DevConflictDiff.load(
                internalPath: conflict.internalSafetyPath,
                externalPath: conflict.externalSafetyPath
            )
        }
    }

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(conflict.relativePath)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            DevSyncStateBadge(
                icon: "exclamationmark.triangle.fill",
                title: conflict.type.displayName,
                tint: .red
            )
        }
    }

    private var metadataGrid: some View {
        HStack(alignment: .top, spacing: 20) {
            sideColumn(title: "Internal", signature: conflict.internalSignature)
            sideColumn(title: "External", signature: conflict.externalSignature)
            sideColumn(title: "Baseline", signature: conflict.baselineSignature)
        }
    }

    private func sideColumn(title: String, signature: DevFileSignature?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .utilitySectionHeader()
            Text(sizeText(signature))
                .font(.system(size: 11))
                .monospacedDigit()
            Text(timeText(signature))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func sizeText(_ signature: DevFileSignature?) -> String {
        guard let size = signature?.size else { return "Not present" }
        return RcloneFormat.bytes(Int64(size))
    }

    private func timeText(_ signature: DevFileSignature?) -> String {
        guard let nanoseconds = signature?.modificationTimeNanoseconds else { return "No time" }
        return DevSyncFormat.relative(Date(timeIntervalSince1970: Double(nanoseconds) / 1_000_000_000))
    }

    @ViewBuilder
    private var safetyCopies: some View {
        if conflict.internalSafetyPath != nil || conflict.externalSafetyPath != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let path = conflict.internalSafetyPath {
                    safetyRow(title: "Internal copy", path: path)
                }
                if let path = conflict.externalSafetyPath {
                    safetyRow(title: "External copy", path: path)
                }
            }
        }
    }

    private func safetyRow(title: String, path: String) -> some View {
        HStack(spacing: 8) {
            Text("\(title): \(path)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Reveal in Finder") { manager.reveal(URL(fileURLWithPath: path)) }
                .controlSize(.small)
                .accessibilityLabel("Reveal \(title) in Finder")
        }
    }

    private var diffView: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(diff) { line in
                Text("\(line.prefix) \(line.text)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.tint)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ForEach(DevSyncConflictCard.resolutions, id: \.self) { resolution in
                Button(resolution.displayName) { resolve(resolution) }
                    .controlSize(.small)
            }
            Button("Open Both") { openBoth() }
                .controlSize(.small)
            Spacer(minLength: 8)
        }
    }

    private static let resolutions: [DevConflictResolution] = [
        .keepInternal, .keepExternal, .keepBoth, .markSame, .excludePath
    ]

    private func resolve(_ resolution: DevConflictResolution) {
        Task { await manager.resolveConflict(pairID: pair.id, conflictID: conflict.id, resolution: resolution) }
    }

    private func openBoth() {
        if let path = conflict.internalSafetyPath { manager.open(URL(fileURLWithPath: path)) }
        if let path = conflict.externalSafetyPath { manager.open(URL(fileURLWithPath: path)) }
    }
}

#Preview {
    let manager = DevSyncPreviewFixture.manager()
    let pair = manager.pairs[0]
    return VStack(spacing: 10) {
        ForEach(manager.unresolvedConflicts(for: pair.id)) { conflict in
            DevSyncConflictCard(pair: pair, conflict: conflict, manager: manager)
        }
    }
    .padding(20)
    .frame(width: 760)
}
