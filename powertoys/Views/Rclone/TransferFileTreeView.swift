//
//  TransferFileTreeView.swift
//  powertoys
//

import SwiftUI
import CryptoKit

struct TransferFileTreeView: View {
    let sourceFs: String
    let destinationFs: String

    private static let indexLimit = 5_000

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

    @AppStorage("cloudsync.files.showPatternEditor") private var showPatternEditor = false
    @AppStorage("cloudsync.files.splitByUploadStatus") private var splitByUploadStatus = false
    @AppStorage("cloudsync.files.hideIgnored") private var hideIgnored = false
    @State private var destinationEntries: [String: RemoteEntry] = [:]
    @State private var isLoadingDestination = false
    @State private var destinationError: String?
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

    private var expandedStorageKey: String {
        let digest = SHA256.hash(data: Data(sourceFs.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "cloudsync.files.expanded.\(digest)"
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .overlay(alignment: .bottom) { toastView }
        .task {
            restoreExpandedPaths()
            await loadRoots()
        }
        .task(id: splitByUploadStatus) {
            guard splitByUploadStatus else { return }
            ensureIndex()
            await loadDestinationIndex()
        }
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
        .onChange(of: expanded) { persistExpandedPaths() }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            SearchField(text: $searchText, placeholder: "Filter files...", isLoading: isIndexing)

            HStack(spacing: 6) {
                Toggle("List uploaded", isOn: $splitByUploadStatus)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.system(size: 11))

                Toggle("Hide ignored", isOn: $hideIgnored)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.system(size: 11))

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
                    .thinScrollIndicators()
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
        if splitByUploadStatus {
            splitStatusView
        } else if !debouncedSearch.isEmpty {
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
                ForEach(visibleRows.filter { !hideIgnored || !isIgnored($0.entry, patterns: patterns) }) { row in
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
        .thinScrollIndicators()
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
                            Text("showing first \(Self.indexLimit.formatted())")
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
                .thinScrollIndicators()
            }
        }
    }

    private var filteredEntries: [RemoteEntry] {
        let patterns = currentPatterns
        return (allEntries ?? []).filter {
            $0.path.localizedCaseInsensitiveContains(debouncedSearch)
                && (!hideIgnored || !isIgnored($0, patterns: patterns))
        }
    }

    @ViewBuilder
    private var splitStatusView: some View {
        if let rootError {
            centered { Text(rootError).font(.system(size: 12)).foregroundStyle(.secondary) }
        } else if let indexError {
            centered { Text(indexError).font(.system(size: 12)).foregroundStyle(.secondary) }
        } else if let destinationError {
            centered { Text(destinationError).font(.system(size: 12)).foregroundStyle(.secondary) }
        } else if allEntries == nil || isIndexing || isLoadingRoot || isLoadingDestination {
            centered {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Comparing source and destination…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(spacing: 0) {
                if indexTruncated {
                    Text("Comparison is limited to the first \(Self.indexLimit.formatted()) source entries.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    Divider()
                }
                HStack(spacing: 0) {
                    statusColumn(title: "NOT UPLOADED", status: .pending, tint: .orange)
                    Divider()
                    statusColumn(title: "UPLOADED", status: .uploaded, tint: .green)
                }
            }
        }
    }

    private func statusColumn(title: String, status: TransferFileStatus, tint: Color) -> some View {
        let entries = statusEntries(status)
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text("\(entries.count)").font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if entries.isEmpty {
                Text(status == .uploaded ? "Nothing uploaded yet" : "Everything is uploaded")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if status == .uploaded {
                            ForEach(uploadedTreeRows) { row in
                                FileTreeRowView(
                                    entry: row.entry,
                                    label: row.entry.name,
                                    depth: row.depth,
                                    showsDisclosure: true,
                                    isExpanded: expanded.contains(row.entry.path),
                                    isLoading: loadingPaths.contains(row.entry.path),
                                    isIgnored: isIgnored(row.entry, patterns: currentPatterns),
                                    onToggle: { toggleExpand(row.entry) },
                                    onIgnore: { addIgnorePattern(for: row.entry) }
                                )
                            }
                        } else {
                            ForEach(entries) { entry in
                                FileTreeRowView(
                                    entry: entry,
                                    label: entry.path,
                                    depth: 0,
                                    showsDisclosure: false,
                                    isExpanded: false,
                                    isLoading: false,
                                    isIgnored: isIgnored(entry, patterns: currentPatterns),
                                    onToggle: {},
                                    onIgnore: { addIgnorePattern(for: entry) }
                                )
                            }
                        }
                    }
                    .padding(8)
                }
                .thinScrollIndicators()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusEntries(_ status: TransferFileStatus) -> [RemoteEntry] {
        let patterns = currentPatterns
        return (allEntries ?? [])
            .filter { !$0.isDir }
            .filter { !hideIgnored || !isIgnored($0, patterns: patterns) }
            .filter { debouncedSearch.isEmpty || $0.path.localizedCaseInsensitiveContains(debouncedSearch) }
            .filter { TransferFileStatus.resolve(source: $0, destination: destinationEntries[$0.path]) == status }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private var uploadedTreeRows: [VisibleRow] {
        let paths = Self.treePaths(for: statusEntries(.uploaded).map(\.path))
        return visibleRows.filter { paths.contains($0.entry.path) }
    }

    static func treePaths(for filePaths: [String]) -> Set<String> {
        var paths = Set(filePaths)
        for filePath in filePaths {
            var parent = (filePath as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                paths.insert(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return paths
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
                        childrenCache[entry.path] = Self.sorted(try await manager.listDirectory(fs: sourceFs, path: entry.path))
                    } catch {
                        expanded.remove(entry.path)
                        showToast("Could not open '\(entry.name)': \(error.localizedDescription)")
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
            roots = Self.sorted(try await manager.listDirectory(fs: sourceFs, path: ""))
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
                var entries = try await manager.listDirectory(fs: sourceFs, path: "", recurse: true)
                if entries.count > Self.indexLimit {
                    indexTruncated = true
                    entries = Array(entries.prefix(Self.indexLimit))
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

    private func loadDestinationIndex() async {
        guard destinationEntries.isEmpty, !isLoadingDestination else { return }
        isLoadingDestination = true
        destinationError = nil
        defer { isLoadingDestination = false }
        do {
            let entries = try await manager.listDirectory(fs: destinationFs, path: "", recurse: true)
            destinationEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        } catch {
            destinationError = "Could not compare the destination: \(error.localizedDescription)"
        }
    }

    private func restoreExpandedPaths() {
        guard let data = UserDefaults.standard.data(forKey: expandedStorageKey),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        expanded = Set(paths)
    }

    private func persistExpandedPaths() {
        guard let data = try? JSONEncoder().encode(expanded.sorted()) else { return }
        UserDefaults.standard.set(data, forKey: expandedStorageKey)
    }

    private static func sorted(_ entries: [RemoteEntry]) -> [RemoteEntry] {
        entries.sorted {
            if $0.isDir != $1.isDir { return $0.isDir }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: Ignore patterns

    private func isIgnored(_ entry: RemoteEntry, patterns: [String]) -> Bool {
        IgnoreMatcher.matches(path: entry.path, name: entry.name, isDir: entry.isDir, patterns: patterns)
    }

    private func addIgnorePattern(for entry: RemoteEntry) {
        let pattern = entry.isDir ? entry.path + "/**" : entry.path
        if !currentPatterns.contains(pattern) {
            patternsText = patternsText + "\n" + pattern
        }
        showToast("Added '\(pattern)' to ignore patterns. It applies to new and retried transfers.")
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
