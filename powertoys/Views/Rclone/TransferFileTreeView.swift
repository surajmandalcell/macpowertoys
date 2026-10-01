//
//  TransferFileTreeView.swift
//  powertoys
//

import SwiftUI
import OnePlusUI
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
    @State private var patterns: [String] = []
    @State private var projection = Projection.empty

    struct DisplayRow: Identifiable {
        let entry: RemoteEntry
        let depth: Int
        let isIgnored: Bool
        let size: String
        let modified: String?
        var id: String { entry.path }
    }

    struct Projection {
        let treeRows: [DisplayRow]
        let searchRows: [DisplayRow]
        let pendingRows: [DisplayRow]
        let uploadedRows: [DisplayRow]

        static let empty = Projection(treeRows: [], searchRows: [], pendingRows: [], uploadedRows: [])
    }

    private var expandedStorageKey: String {
        let digest = SHA256.hash(data: Data(sourceFs.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "cloudsync.files.expanded.\(digest)"
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            QuietDivider()
            content
        }
        .overlay(alignment: .bottom) { toastView }
        .task {
            patterns = RcloneDefaults.parsePatterns(patternsText)
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
                rebuildProjection(search: "")
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            debouncedSearch = searchText
            rebuildProjection(search: searchText)
            ensureIndex()
        }
        .onDisappear { indexTask?.cancel() }
        .onChange(of: expanded) {
            persistExpandedPaths()
            rebuildProjection()
        }
        .onChange(of: hideIgnored) { rebuildProjection() }
        .onChange(of: patternsText) {
            let parsed = RcloneDefaults.parsePatterns(patternsText)
            patterns = parsed
            rebuildProjection(patterns: parsed)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                NativeSearchField(text: $searchText, placeholder: "Filter files...")
                if isIndexing {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(height: UtilityLayout.workspaceActionHeight)

            HStack(spacing: 6) {
                Toggle("List uploaded", isOn: $splitByUploadStatus)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .onePlusText(.caption)

                Toggle("Hide ignored", isOn: $hideIgnored)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .onePlusText(.caption)

                Spacer()
                Text("\(patterns.count) patterns active")
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.secondary)
                Button {
                    showPatternEditor.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .onePlusText(.caption)
                        .foregroundStyle(OnePlusColor.secondary)
                        .rotationEffect(.degrees(showPatternEditor ? 90 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled(!OnePlusFocusPolicy.shared.showsFocus)
                .help("Edit ignore patterns")
            }

            if showPatternEditor {
                TextEditor(text: $patternsText)
                    .thinScrollIndicators()
                    .onePlusText(.mono)
                    .scrollContentBackground(.hidden)
                    .frame(height: 70)
                    .padding(6)
                    .background(OnePlusColor.track)
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
                        .onePlusText(.row)
                        .foregroundStyle(OnePlusColor.secondary)
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
                    .onePlusText(.row)
                    .foregroundStyle(OnePlusColor.muted)
            }
        } else {
            treeList
        }
    }

    private var treeList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(projection.treeRows) { row in
                    FileTreeRowView(
                        entry: row.entry,
                        label: row.entry.name,
                        depth: row.depth,
                        showsDisclosure: true,
                        isExpanded: expanded.contains(row.entry.path),
                        isLoading: loadingPaths.contains(row.entry.path),
                        isIgnored: row.isIgnored,
                        size: row.size,
                        modified: row.modified,
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
                        .onePlusText(.row)
                        .foregroundStyle(OnePlusColor.secondary)
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
                        .onePlusText(.row)
                        .foregroundStyle(OnePlusColor.secondary)
                }
            }
        } else {
            if projection.searchRows.isEmpty {
                centered {
                    Text("No matches")
                        .onePlusText(.row)
                        .foregroundStyle(OnePlusColor.muted)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if indexTruncated {
                            Text("showing first \(Self.indexLimit.formatted())")
                                .onePlusText(.caption)
                                .foregroundStyle(OnePlusColor.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                        }
                        ForEach(projection.searchRows) { row in
                            FileTreeRowView(
                                entry: row.entry,
                                label: row.entry.path,
                                depth: 0,
                                showsDisclosure: false,
                                isExpanded: false,
                                isLoading: false,
                                isIgnored: row.isIgnored,
                                size: row.size,
                                modified: row.modified,
                                onToggle: {},
                                onIgnore: { addIgnorePattern(for: row.entry) }
                            )
                        }
                    }
                    .padding(8)
                }
                .thinScrollIndicators()
        }
        }
    }

    @ViewBuilder
    private var splitStatusView: some View {
        if let rootError {
            centered { Text(rootError).onePlusText(.row).foregroundStyle(OnePlusColor.secondary) }
        } else if let indexError {
            centered { Text(indexError).onePlusText(.row).foregroundStyle(OnePlusColor.secondary) }
        } else if let destinationError {
            centered { Text(destinationError).onePlusText(.row).foregroundStyle(OnePlusColor.secondary) }
        } else if allEntries == nil || isIndexing || isLoadingRoot || isLoadingDestination {
            centered {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Comparing source and destination…")
                        .onePlusText(.row)
                        .foregroundStyle(OnePlusColor.secondary)
                }
            }
        } else {
            VStack(spacing: 0) {
                if indexTruncated {
                    Text("Comparison is limited to the first \(Self.indexLimit.formatted()) source entries.")
                        .onePlusText(.caption)
                        .foregroundStyle(OnePlusColor.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    QuietDivider()
                }
                HStack(spacing: 0) {
                    statusColumn(title: "NOT UPLOADED", status: .pending, rows: projection.pendingRows, tint: OnePlusColor.warn)
                    QuietDivider()
                    statusColumn(title: "UPLOADED", status: .uploaded, rows: projection.uploadedRows, tint: OnePlusColor.ok)
                }
            }
        }
    }

    private func statusColumn(
        title: String,
        status: TransferFileStatus,
        rows: [DisplayRow],
        tint: Color
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title).onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                Text("\(rows.count)").onePlusText(.caption).foregroundStyle(OnePlusColor.muted).monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            QuietDivider()

            if rows.isEmpty {
                Text(status == .uploaded ? "Nothing uploaded yet" : "Everything is uploaded")
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(rows) { row in
                            FileTreeRowView(
                                entry: row.entry,
                                label: status == .uploaded ? row.entry.name : row.entry.path,
                                depth: row.depth,
                                showsDisclosure: status == .uploaded,
                                isExpanded: status == .uploaded && expanded.contains(row.entry.path),
                                isLoading: status == .uploaded && loadingPaths.contains(row.entry.path),
                                isIgnored: row.isIgnored,
                                size: row.size,
                                modified: row.modified,
                                onToggle: { if status == .uploaded { toggleExpand(row.entry) } },
                                onIgnore: { addIgnorePattern(for: row.entry) }
                            )
                        }
                    }
                    .padding(8)
                }
                .thinScrollIndicators()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .onePlusText(.caption)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    // MARK: Tree state

    static func makeProjection(
        roots: [RemoteEntry],
        children: [String: [RemoteEntry]],
        expanded: Set<String>,
        allEntries: [RemoteEntry],
        destinationEntries: [String: RemoteEntry],
        patterns: [String],
        hideIgnored: Bool,
        search: String,
        now: Date = Date()
    ) -> Projection {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        func row(_ entry: RemoteEntry, depth: Int) -> DisplayRow {
            DisplayRow(
                entry: entry,
                depth: depth,
                isIgnored: IgnoreMatcher.matches(
                    path: entry.path,
                    name: entry.name,
                    isDir: entry.isDir,
                    patterns: patterns
                ),
                size: entry.isDir ? "" : RcloneProjectionFormat.bytes(entry.size),
                modified: entry.modTime.map { formatter.localizedString(for: $0, relativeTo: now) }
            )
        }

        var visibleRows: [DisplayRow] = []
        func walk(_ entries: [RemoteEntry], depth: Int) {
            for entry in entries {
                visibleRows.append(row(entry, depth: depth))
                if entry.isDir, expanded.contains(entry.path), let nested = children[entry.path] {
                    walk(nested, depth: depth + 1)
                }
            }
        }
        walk(roots, depth: 0)

        let searchRows = search.isEmpty ? [] : allEntries
            .filter {
                $0.path.localizedCaseInsensitiveContains(search)
                    && (!hideIgnored || !IgnoreMatcher.matches(
                        path: $0.path,
                        name: $0.name,
                        isDir: $0.isDir,
                        patterns: patterns
                    ))
            }
            .map { row($0, depth: 0) }

        let statusEntries = allEntries
            .filter { !$0.isDir }
            .filter {
                !hideIgnored || !IgnoreMatcher.matches(
                    path: $0.path,
                    name: $0.name,
                    isDir: false,
                    patterns: patterns
                )
            }
            .filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        var pendingRows: [DisplayRow] = []
        var uploadedFiles: [String] = []
        for entry in statusEntries {
            switch TransferFileStatus.resolve(source: entry, destination: destinationEntries[entry.path]) {
            case .pending: pendingRows.append(row(entry, depth: 0))
            case .uploaded: uploadedFiles.append(entry.path)
            }
        }
        let uploadedPaths = treePaths(for: uploadedFiles)

        return Projection(
            treeRows: visibleRows.filter { !hideIgnored || !$0.isIgnored },
            searchRows: searchRows,
            pendingRows: pendingRows,
            uploadedRows: visibleRows.filter { uploadedPaths.contains($0.entry.path) }
        )
    }

    private func rebuildProjection(patterns newPatterns: [String]? = nil, search newSearch: String? = nil) {
        projection = Self.makeProjection(
            roots: roots,
            children: childrenCache,
            expanded: expanded,
            allEntries: allEntries ?? [],
            destinationEntries: destinationEntries,
            patterns: newPatterns ?? patterns,
            hideIgnored: hideIgnored,
            search: newSearch ?? debouncedSearch
        )
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
                    rebuildProjection()
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
        rebuildProjection()
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
                rebuildProjection()
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
            rebuildProjection()
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

    private func addIgnorePattern(for entry: RemoteEntry) {
        let pattern = entry.isDir ? entry.path + "/**" : entry.path
        if !patterns.contains(pattern) {
            patternsText = patternsText + "\n" + pattern
        }
        showToast("Added '\(pattern)' to ignore patterns. It applies to new and retried transfers.")
    }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            toast = nil
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
    let size: String
    let modified: String?
    let onToggle: () -> Void
    let onIgnore: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            leading

            Spacer(minLength: 8)

            if isIgnored {
                Text("ignored")
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.muted)

            } else if isHovering {
                Button(action: onIgnore) {
                    Image(systemName: "eye.slash")
                        .onePlusText(.caption)
                        .foregroundStyle(OnePlusColor.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled(!OnePlusFocusPolicy.shared.showsFocus)
                .accessibilityLabel("Add to ignore patterns")
            }

            trailingMeta
        }
        .padding(.vertical, 4)
        .padding(.trailing, 8)
        .padding(.leading, 8 + CGFloat(depth) * 16)
        .onePlusRowHover()
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
            .focusEffectDisabled(!OnePlusFocusPolicy.shared.showsFocus)
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
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12, height: 12)
        }
    }

    private var entryIcon: some View {
        Image(systemName: entry.icon)
            .onePlusText(.caption)
            .foregroundStyle(entry.isDir ? AnyShapeStyle(OnePlusColor.accent) : AnyShapeStyle(OnePlusColor.secondary))
            .frame(width: 16)
    }

    private var nameText: some View {
        Text(label)
            .onePlusText(.row)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private var trailingMeta: some View {
        if !size.isEmpty {
            Text(size)
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.secondary)
                .monospacedDigit()
        }
        if let modified {
            Text(modified)
                .onePlusText(.caption)
                .foregroundStyle(OnePlusColor.muted)
        }
    }
}
