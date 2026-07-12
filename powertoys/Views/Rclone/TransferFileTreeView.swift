//
//  TransferFileTreeView.swift
//  powertoys
//

import SwiftUI

struct TransferFileTreeView: View {
    let rootFs: String

    @Environment(RcloneJobManager.self) private var manager
    @AppStorage(RcloneDefaults.ignorePatternsKey) private var patternsText = RcloneDefaults.ignorePatterns

    @State private var roots: [RemoteEntry] = []
    @State private var isLoadingRoot = true
    @State private var rootError: String?
    @State private var expanded: Set<String> = []
    @State private var childrenCache: [String: [RemoteEntry]] = [:]
    @State private var loadingPaths: Set<String> = []

    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var allEntries: [RemoteEntry]?
    @State private var isIndexing = false
    @State private var indexTruncated = false
    @State private var indexError: String?
    @State private var indexTask: Task<Void, Never>?

    @State private var showPatternEditor = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    private struct VisibleRow: Identifiable {
        let entry: RemoteEntry
        let depth: Int
        var id: String { entry.path }
    }

    private var currentPatterns: [String] {
        RcloneDefaults.parsePatterns(patternsText)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .overlay(alignment: .bottom) { toastView }
        .task { await loadRoots() }
        .task(id: searchText) {
            guard !searchText.isEmpty else {
                debouncedSearch = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            debouncedSearch = searchText
            ensureIndex()
        }
        .onDisappear { indexTask?.cancel() }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            SearchField(text: $searchText, placeholder: "Filter files...", isLoading: isIndexing)

            HStack(spacing: 6) {
                Spacer()
                Text("\(currentPatterns.count) patterns active")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showPatternEditor.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showPatternEditor ? 90 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Edit ignore patterns")
            }

            if showPatternEditor {
                TextEditor(text: $patternsText)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 70)
                    .padding(6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !debouncedSearch.isEmpty {
            searchResults
        } else if isLoadingRoot {
            centered { ProgressView() }
        } else if let rootError {
            centered {
                VStack(spacing: 10) {
                    Text(rootError)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadRoots() }
                    }
                }
                .padding(.horizontal, 24)
            }
        } else if roots.isEmpty {
            centered {
                Text("No files found")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        } else {
            treeList
        }
    }

    private var treeList: some View {
        let patterns = currentPatterns
        return ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(visibleRows) { row in
                    FileTreeRowView(
                        entry: row.entry,
                        label: row.entry.name,
                        depth: row.depth,
                        showsDisclosure: true,
                        isExpanded: expanded.contains(row.entry.path),
                        isLoading: loadingPaths.contains(row.entry.path),
                        isIgnored: isIgnored(row.entry, patterns: patterns),
                        onToggle: { toggleExpand(row.entry) },
                        onIgnore: { addIgnorePattern(for: row.entry) }
                    )
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let indexError {
            centered {
                VStack(spacing: 10) {
                    Text(indexError)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { ensureIndex() }
                }
                .padding(.horizontal, 24)
            }
        } else if allEntries == nil {
            centered {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("indexing…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            let matches = filteredEntries
            if matches.isEmpty {
                centered {
                    Text("No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            } else {
                let patterns = currentPatterns
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if indexTruncated {
                            Text("showing first 5,000")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                        }
                        ForEach(matches) { entry in
                            FileTreeRowView(
                                entry: entry,
                                label: entry.path,
                                depth: 0,
                                showsDisclosure: false,
                                isExpanded: false,
                                isLoading: false,
                                isIgnored: isIgnored(entry, patterns: patterns),
                                onToggle: {},
                                onIgnore: { addIgnorePattern(for: entry) }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var filteredEntries: [RemoteEntry] {
        (allEntries ?? []).filter { $0.path.localizedCaseInsensitiveContains(debouncedSearch) }
    }

    private func centered(@ViewBuilder _ inner: () -> some View) -> some View {
        VStack { inner() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 11))
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Tree state

    private var visibleRows: [VisibleRow] {
        var rows: [VisibleRow] = []
        func walk(_ entries: [RemoteEntry], depth: Int) {
            for entry in entries {
                rows.append(VisibleRow(entry: entry, depth: depth))
                if entry.isDir, expanded.contains(entry.path), let children = childrenCache[entry.path] {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(roots, depth: 0)
        return rows
    }

    private func toggleExpand(_ entry: RemoteEntry) {
        guard entry.isDir else { return }
        if expanded.contains(entry.path) {
            expanded.remove(entry.path)
        } else {
            expanded.insert(entry.path)
            if childrenCache[entry.path] == nil, !loadingPaths.contains(entry.path) {
                loadingPaths.insert(entry.path)
                Task {
                    do {
                        childrenCache[entry.path] = Self.sorted(try await manager.listDirectory(fs: rootFs, path: entry.path))
                    } catch {
                        expanded.remove(entry.path)
                        showToast("Couldn't open '\(entry.name)': \(error.localizedDescription)")
                    }
                    loadingPaths.remove(entry.path)
                }
            }
        }
    }

    private func loadRoots() async {
        isLoadingRoot = true
        rootError = nil
        do {
            roots = Self.sorted(try await manager.listDirectory(fs: rootFs, path: ""))
        } catch {
            rootError = error.localizedDescription
        }
        isLoadingRoot = false
    }

    private func ensureIndex() {
        guard allEntries == nil, indexTask == nil else { return }
        isIndexing = true
        indexError = nil
        indexTask = Task {
            do {
                var entries = try await manager.listDirectory(fs: rootFs, path: "", recurse: true)
                if entries.count > 5000 {
                    indexTruncated = true
                    entries = Array(entries.prefix(5000))
                }
                allEntries = entries
            } catch is CancellationError {
            } catch {
                indexError = error.localizedDescription
            }
            isIndexing = false
            indexTask = nil
        }
    }

    private static func sorted(_ entries: [RemoteEntry]) -> [RemoteEntry] {
        entries.sorted {
            if $0.isDir != $1.isDir { return $0.isDir }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: Ignore patterns

    private func isIgnored(_ entry: RemoteEntry, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern == entry.name || pattern == entry.path { return true }
            if pattern.hasPrefix("*."), entry.name.hasSuffix(String(pattern.dropFirst())) { return true }
            if pattern.hasSuffix("/**") {
                let dir = String(pattern.dropLast(3))
                if entry.path == dir || entry.path.hasPrefix(dir + "/") { return true }
                if !dir.contains("/"), entry.path.split(separator: "/").contains(Substring(dir)) { return true }
            }
            if pattern.hasSuffix("*"), !pattern.hasPrefix("*"), !pattern.hasSuffix("/**"),
               entry.name.hasPrefix(String(pattern.dropLast())) { return true }
        }
        return false
    }

    private func addIgnorePattern(for entry: RemoteEntry) {
        let pattern = entry.isDir ? entry.path + "/**" : entry.path
        if !currentPatterns.contains(pattern) {
            patternsText = patternsText + "\n" + pattern
        }
        showToast("Added '\(pattern)' to ignore patterns — applies to new and retried transfers")
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.15)) { toast = message }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.15)) { toast = nil }
        }
    }
}

// MARK: - Row

private struct FileTreeRowView: View {
    let entry: RemoteEntry
    let label: String
    let depth: Int
    let showsDisclosure: Bool
    let isExpanded: Bool
    let isLoading: Bool
    let isIgnored: Bool
    let onToggle: () -> Void
    let onIgnore: () -> Void

    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            leading
                .opacity(isIgnored ? 0.45 : 1)

            Spacer(minLength: 8)

            if isIgnored {
                Text("ignored")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            } else if isHovering {
                Button(action: onIgnore) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Add to ignore patterns")
            }

            trailingMeta
                .opacity(isIgnored ? 0.45 : 1)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 8)
        .padding(.leading, 8 + CGFloat(depth) * 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var leading: some View {
        if entry.isDir, showsDisclosure {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    disclosureIndicator
                    entryIcon
                    nameText
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        } else {
            HStack(spacing: 6) {
                if showsDisclosure {
                    Color.clear.frame(width: 12, height: 12)
                }
                entryIcon
                nameText
            }
        }
    }

    @ViewBuilder
    private var disclosureIndicator: some View {
        if isLoading {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.15), value: isExpanded)
                .frame(width: 12, height: 12)
        }
    }

    private var entryIcon: some View {
        Image(systemName: entry.icon)
            .font(.system(size: 11))
            .foregroundStyle(entry.isDir ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .frame(width: 16)
    }

    private var nameText: some View {
        Text(label)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private var trailingMeta: some View {
        if !entry.isDir {
            Text(RcloneFormat.bytes(entry.size))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        if let modTime = entry.modTime {
            Text(Self.relativeFormatter.localizedString(for: modTime, relativeTo: Date()))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
