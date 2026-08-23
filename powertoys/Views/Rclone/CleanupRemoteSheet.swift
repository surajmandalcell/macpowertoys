//
//  CleanupRemoteSheet.swift
//  powertoys
//

import SwiftUI

extension Notification.Name {
    static let remoteCleanupCompleted = Notification.Name("remoteCleanupCompleted")
}

struct CleanupRemoteSheet: View {
    let remote: RcloneRemote
    let startPath: String

    @Environment(RcloneJobManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .scanning
    @State private var groups: [CleanupGroup] = []
    @State private var checked: Set<String> = []
    @State private var truncatedFrom: Int?
    @State private var scanTask: Task<Void, Never>?

    private static let displayCap = 5000

    private enum Phase: Hashable {
        case scanning
        case empty
        case review
        case deleting(Int)
        case done(deleted: Int, failed: Int)
        case failure(String)
    }

    private struct CleanupGroup: Identifiable {
        let id: String
        let title: String
        let items: [RemoteEntry]
    }

    private var scope: String {
        startPath.isEmpty ? remote.pathPrefix : "\(remote.pathPrefix)\(startPath)"
    }

    private var allMatches: [RemoteEntry] { groups.flatMap(\.items) }

    private var checkedBytes: Int64 {
        allMatches.reduce(0) { $0 + (!$1.isDir && checked.contains($1.path) ? $1.size : 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            QuietDivider()
            content
                .utilityContentTransition(value: phase)
            if phase == .review {
                QuietDivider()
                footer
            }
        }
        .frame(width: 560, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .utilityAnimation(value: phase == .review)
        .onAppear(perform: startScan)
        .onDisappear { scanTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                )

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Clean Up by Ignore Rules")
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize()
                Text(scope)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            headerButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var headerButton: some View {
        switch phase {
        case .scanning:
            Button("Cancel") {
                scanTask?.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        case .review, .deleting:
            EmptyView()
        case .empty, .done, .failure:
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            stateContainer {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning \(scope) for matches…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .empty:
            stateContainer {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("Nothing matches your ignore rules.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .review:
            reviewList
        case .deleting(let count):
            stateContainer {
                ProgressView()
                    .controlSize(.small)
                Text("Deleting \(count) items…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .done(let deleted, let failed):
            doneSummary(deleted: deleted, failed: failed)
        case .failure(let message):
            stateContainer {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Retry", action: startScan)
            }
        }
    }

    private func stateContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneSummary(deleted: Int, failed: Int) -> some View {
        stateContainer {
            Image(systemName: failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(failed > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.green))
            HStack(spacing: 4) {
                Text(deleted == 1 ? "Deleted 1 item" : "Deleted \(deleted) items")
                    .font(.system(size: 13))
                    .monospacedDigit()
                if failed > 0 {
                    Text("· \(failed) failed")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: Review List

    private var reviewList: some View {
        VStack(spacing: 0) {
            selectionHeader
            QuietDivider()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if let truncatedFrom {
                        truncationNote(total: truncatedFrom)
                    }
                    ForEach(groups) { group in
                        groupRow(group)
                        ForEach(group.items) { entry in
                            entryRow(entry)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var selectionHeader: some View {
        HStack(spacing: 8) {
            CheckboxButton(state: selectAllState, action: toggleAll)
            Text("Select all")
                .font(.system(size: 12))
            Spacer()
            Text("\(checked.count) selected · \(RcloneFormat.bytes(checkedBytes))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func truncationNote(total: Int) -> some View {
        Text("Showing the first \(Self.displayCap) of \(total) matches. Run the cleanup again to catch the rest.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
    }

    private func groupRow(_ group: CleanupGroup) -> some View {
        HStack(spacing: 8) {
            CheckboxButton(state: groupState(group)) { toggleGroup(group) }
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(group.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(group.items.count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func entryRow(_ entry: RemoteEntry) -> some View {
        HStack(spacing: 8) {
            CheckboxButton(state: checked.contains(entry.path) ? .on : .off) { toggle(entry) }
            Image(systemName: entry.icon)
                .font(.system(size: 12))
                .foregroundStyle(entry.isDir ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 16)
            Text(entry.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(entry.isDir ? "folder + contents" : RcloneFormat.bytes(entry.size))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.leading, 24)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(checked.count == 1 ? "Delete 1 Item" : "Delete \(checked.count) Items") {
                deleteSelected()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(checked.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Selection

    private var selectAllState: CleanupCheckState {
        if checked.isEmpty { return .off }
        return checked.count == allMatches.count ? .on : .mixed
    }

    private func groupState(_ group: CleanupGroup) -> CleanupCheckState {
        let count = group.items.count { checked.contains($0.path) }
        if count == 0 { return .off }
        return count == group.items.count ? .on : .mixed
    }

    private func toggleAll() {
        if selectAllState == .on {
            checked.removeAll()
        } else {
            checked = Set(allMatches.map(\.path))
        }
    }

    private func toggleGroup(_ group: CleanupGroup) {
        let paths = group.items.map(\.path)
        if groupState(group) == .on {
            checked.subtract(paths)
        } else {
            checked.formUnion(paths)
        }
    }

    private func toggle(_ entry: RemoteEntry) {
        if checked.contains(entry.path) {
            checked.remove(entry.path)
        } else {
            checked.insert(entry.path)
        }
    }

    // MARK: Actions

    private func startScan() {
        scanTask?.cancel()
        phase = .scanning
        truncatedFrom = nil
        groups = []
        checked = []
        scanTask = Task {
            do {
                let entries = try await manager.listDirectory(fs: remote.pathPrefix, path: startPath, recurse: true)
                guard !Task.isCancelled else { return }
                let patterns = manager.settings.ignorePatterns
                var matches = Self.topMostMatches(entries.filter {
                    IgnoreMatcher.matches(path: $0.path, name: $0.name, isDir: $0.isDir, patterns: patterns)
                })
                if matches.count > Self.displayCap {
                    truncatedFrom = matches.count
                    matches = Array(matches.prefix(Self.displayCap))
                }
                if matches.isEmpty {
                    phase = .empty
                } else {
                    groups = Self.groupByParent(matches)
                    checked = Set(matches.map(\.path))
                    phase = .review
                }
            } catch is CancellationError {
            } catch {
                phase = .failure((error as? LocalizedError)?.errorDescription ?? "Could not scan \(scope).")
            }
        }
    }

    private func deleteSelected() {
        let selection = allMatches.filter { checked.contains($0.path) }
        guard !selection.isEmpty else { return }
        phase = .deleting(selection.count)
        Task {
            let result = await manager.deleteRemoteEntries(remote: remote, entries: selection)
            phase = .done(deleted: result.deleted, failed: result.failed)
            NotificationCenter.default.post(name: .remoteCleanupCompleted, object: remote.name)
        }
    }

    // MARK: Match Processing

    private static func topMostMatches(_ matches: [RemoteEntry]) -> [RemoteEntry] {
        var kept: [RemoteEntry] = []
        var coveringDirs: [String] = []
        for entry in matches.sorted(by: { $0.path < $1.path }) {
            if coveringDirs.contains(where: { entry.path.hasPrefix($0 + "/") }) { continue }
            if entry.isDir { coveringDirs.append(entry.path) }
            kept.append(entry)
        }
        return kept
    }

    private static func groupByParent(_ matches: [RemoteEntry]) -> [CleanupGroup] {
        var buckets: [String: [RemoteEntry]] = [:]
        for entry in matches {
            let parent = entry.path.contains("/")
                ? entry.path.split(separator: "/").dropLast().joined(separator: "/")
                : ""
            buckets[parent, default: []].append(entry)
        }
        return buckets
            .sorted { $0.key < $1.key }
            .map { key, items in
                CleanupGroup(
                    id: key,
                    title: key.isEmpty ? "Top level" : key,
                    items: items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
    }
}

// MARK: - Checkbox

private enum CleanupCheckState {
    case on, off, mixed

    var icon: String {
        switch self {
        case .on: return "checkmark.square.fill"
        case .off: return "square"
        case .mixed: return "minus.square.fill"
        }
    }
}

private struct CheckboxButton: View {
    let state: CleanupCheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.icon)
                .font(.system(size: 13))
                .foregroundStyle(state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}
