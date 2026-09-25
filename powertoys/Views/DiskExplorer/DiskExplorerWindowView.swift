import AppKit
import QuickLook
import SwiftUI

private enum DiskExplorerPage {
    case explore
    case settings
    case about
}

private enum DiskEntrySort: String, CaseIterable, Identifiable {
    case size = "Size"
    case files = "Files"
    case name = "Name"
    case modified = "Modified"
    var id: String { rawValue }
}

struct DiskExplorerWindowView: View {
    @State private var model = DiskExplorerModel()
    @State private var page = DiskExplorerPage.explore
    @State private var search = ""
    @State private var sort = DiskEntrySort.size
    @State private var visibleLimit = 250
    @State private var selectedFile: DiskEntry?
    @State private var previewURL: URL?
    @State private var showingReview = false
    @AppStorage("diskExplorer.chartStyle") private var chartStyle = DiskChartStyle.treemap.rawValue
    @AppStorage("diskExplorer.apparentSize") private var apparentSize = false
    @AppStorage("diskExplorer.includeHidden") private var includeHidden = true

    private var chart: DiskChartStyle { DiskChartStyle(rawValue: chartStyle) ?? .treemap }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: UtilityLayout.dataSidebarWidth)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) { statusInset }
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "disk-explorer"))
        .onAppear { model.refreshVolumes() }
        .onDisappear { model.leave() }
        .onChange(of: includeHidden) { _, newValue in
            if let source = model.sourceURL { model.start(source, includeHidden: newValue) }
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showingReview) {
            DiskExplorerReviewSheet(model: model, includeHidden: includeHidden)
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar)
            SidebarTitle(text: "Disk Explorer")
            VStack(alignment: .leading, spacing: 5) {
                Text("VOLUMES").utilitySectionHeader().padding(.leading, 8)
                ForEach(model.volumes) { volume in
                    SidebarRow(
                        icon: volume.url.path == "/" ? "internaldrive" : "externaldrive",
                        title: volume.name,
                        isSelected: page == .explore && model.sourceURL == volume.url
                    ) {
                        page = .explore
                        model.start(volume.url, includeHidden: includeHidden)
                    }
                    .help(volume.url.path)
                }
                Text("FOLDERS").utilitySectionHeader().padding(.leading, 8).padding(.top, 15)
                SidebarRow(icon: "house", title: "Home Folder",
                           isSelected: page == .explore && model.sourceURL == FileManager.default.homeDirectoryForCurrentUser) {
                    page = .explore
                    model.start(FileManager.default.homeDirectoryForCurrentUser, includeHidden: includeHidden)
                }
                SidebarRow(icon: "folder.badge.plus", title: "Choose Folder…", isSelected: false) {
                    chooseFolder()
                }
                Spacer()
                QuietDivider().padding(.vertical, 5)
                SidebarRow(icon: "gearshape", title: "Settings", isSelected: page == .settings) {
                    page = .settings
                }
                SidebarRow(icon: "info.circle", title: "About", isSelected: page == .about) {
                    page = .about
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, UtilityLayout.workspaceContentTopInset)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .explore: explorerPage
        case .settings:
            WorkspacePage("Settings") {
                DiskExplorerSettingsView(unreadableCount: model.result?.unreadableCount)
            }
        case .about:
            ToolAboutView(toolId: "disk-explorer", showsSettings: false)
        }
    }

    private var explorerPage: some View {
        WorkspacePage(
            "Disk Explorer",
            subtitle: model.sourceURL?.path ?? "Choose a volume or folder",
            actions: {
                if model.isScanning {
                    Button("Stop", systemImage: "stop.fill") { model.cancel() }
                } else if let source = model.sourceURL {
                    Button("Rescan", systemImage: "arrow.clockwise") {
                        model.start(source, includeHidden: includeHidden)
                    }
                }
                Button("Review \(model.markedEntries.count)", systemImage: "tray.full") {
                    showingReview = true
                }
                .disabled(model.markedEntries.isEmpty || model.isRemoving)
            }
        ) {
            if let current = model.current, let snapshot = model.result {
                exploredContent(current, snapshot: snapshot)
            } else if model.isScanning {
                ContentUnavailableView("Scanning", systemImage: "internaldrive",
                                       description: Text("\(model.scannedEntries.formatted()) items checked"))
                    .frame(maxWidth: .infinity, minHeight: 480)
            } else {
                ContentUnavailableView("Choose a Disk", systemImage: "internaldrive",
                                       description: Text("Select a volume or folder to see where its space goes."))
                    .frame(maxWidth: .infinity, minHeight: 480)
            }
        }
    }

    private func exploredContent(_ current: DiskEntry, snapshot: DiskScanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning · \(model.scannedEntries.formatted()) items checked")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            breadcrumbs(for: current, root: snapshot.root)
            HStack(spacing: 18) {
                metric("Used here", current.bytes(apparent: apparentSize).diskSize)
                metric("Files", current.fileCount.formatted())
                metric("Folders", max(current.directoryCount - 1, 0).formatted())
                if let volume = model.volumes.first(where: { $0.url == model.sourceURL }),
                   let available = volume.available {
                    metric("Free on disk", available.diskSize)
                }
                Spacer()
            }
            QuietDivider()
            HStack(spacing: 10) {
                Picker("View", selection: $chartStyle) {
                    ForEach(DiskChartStyle.allCases) { style in
                        Label(style.rawValue, systemImage: style.symbol).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                TextField("Search this folder", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                    .accessibilityLabel("Search files in current folder")
                Picker("Sort", selection: $sort) {
                    ForEach(DiskEntrySort.allCases) { value in Text(value.rawValue).tag(value) }
                }
                .fixedSize()
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    chartView(current).frame(minWidth: 400, maxWidth: .infinity).frame(height: 480)
                    entriesView(current).frame(width: 340, height: 480)
                }
                VStack(spacing: 16) {
                    chartView(current).frame(height: 420)
                    entriesView(current).frame(height: 420)
                }
            }
            if current.id == snapshot.root.id && !snapshot.largestFiles.isEmpty {
                largestFiles(snapshot.largestFiles)
            }
            if let file = selectedFile {
                fileInspector(file)
            }
            if snapshot.unreadableCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                    Text("\(snapshot.unreadableCount.formatted()) items could not be read. This scan is incomplete.")
                    Spacer()
                    Button("Full Disk Access Settings") { openFullDiskAccessSettings() }
                        .controlSize(.small)
                }
                .font(.system(size: 11))
                .padding(10)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onChange(of: current.id) { _, _ in search = ""; visibleLimit = 250; selectedFile = nil }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .medium)).monospacedDigit()
        }
    }

    private func breadcrumbs(for current: DiskEntry, root: DiskEntry) -> some View {
        var nodes = [root]
        var node = root
        let path = current.id
        while node.id != path,
              let next = node.children.first(where: {
                  $0.kind == .directory && path.hasPrefix($0.id + "/") || $0.id == path
              }) {
            nodes.append(next)
            node = next
        }
        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(nodes) { entry in
                    Button(entry.name) { model.navigate(to: entry) }
                        .buttonStyle(.borderless)
                        .focusEffectDisabled()
                    if entry.id != nodes.last?.id {
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .thinScrollIndicators()
    }

    @ViewBuilder private func chartView(_ directory: DiskEntry) -> some View {
        Group {
            if chart == .treemap {
                DiskTreemapView(directory: directory, apparent: apparentSize, select: inspect)
            } else {
                DiskSunburstView(directory: directory, apparent: apparentSize, select: inspect)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func entriesView(_ directory: DiskEntry) -> some View {
        let matches = orderedEntries(in: directory)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Contents").font(.system(size: 12, weight: .medium))
                Spacer()
                Text(matches.count.formatted()).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            QuietDivider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    // ponytail: render 250 rows at a time; add virtualized table paging if folders with over 10,000 direct children feel slow.
                    ForEach(matches.prefix(visibleLimit)) { entry in entryRow(entry) }
                    if matches.count > visibleLimit {
                        Button("Show more (\(matches.count - visibleLimit) remaining)") {
                            visibleLimit += 250
                        }
                        .buttonStyle(.borderless)
                        .focusEffectDisabled()
                        .padding(10)
                    }
                }
                .padding(5)
            }
            .thinScrollIndicators()
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func orderedEntries(in directory: DiskEntry) -> [DiskEntry] {
        let entries = search.isEmpty ? directory.children : directory.children.filter {
            $0.name.localizedStandardContains(search)
        }
        switch sort {
        case .size: return entries.sorted { $0.bytes(apparent: apparentSize) > $1.bytes(apparent: apparentSize) }
        case .files: return entries.sorted { $0.fileCount > $1.fileCount }
        case .name: return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .modified: return entries.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    private func entryRow(_ entry: DiskEntry) -> some View {
        HStack(spacing: 3) {
            Button { inspect(entry) } label: {
                HStack(spacing: 7) {
                    Image(systemName: entry.kind == .directory ? "folder.fill" :
                          entry.kind == .symbolicLink ? "link" : "doc")
                        .frame(width: 17).foregroundStyle(.secondary)
                    Text(entry.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(entry.bytes(apparent: apparentSize).diskSize)
                        .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                }
                .font(.system(size: 11))
                .padding(.horizontal, 5).frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
            .focusEffectDisabled()
            .contextMenu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                if entry.kind == .file { Button("Quick Look") { previewURL = entry.url } }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url.path, forType: .string)
                }
                if let root = model.result?.root.url, DiskRemoval.isAllowed(entry, under: root) {
                    Button(model.marks[entry.id] == nil ? "Mark for Removal" : "Unmark") {
                        model.toggleMark(entry)
                    }
                }
            }
            if let root = model.result?.root.url, DiskRemoval.isAllowed(entry, under: root) {
                Button { model.toggleMark(entry) } label: {
                    Image(systemName: model.marks[entry.id] == nil ? "plus.circle" : "checkmark.circle.fill")
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .contentShape(Rectangle())
                .accessibilityLabel(model.marks[entry.id] == nil ? "Mark \(entry.name) for removal" : "Unmark \(entry.name)")
                .help("Review before removing")
            }
        }
    }

    private func inspect(_ entry: DiskEntry) {
        if entry.kind == .directory {
            model.navigate(to: entry)
        } else {
            selectedFile = entry
        }
    }

    private func fileInspector(_ file: DiskEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(file.url.path).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer()
            Button("Quick Look") { previewURL = file.url }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        }
        .controlSize(.small)
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func largestFiles(_ files: [DiskEntry]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("LARGEST FILES").utilitySectionHeader()
            ForEach(files.prefix(12)) { entry in
                HStack(spacing: 8) {
                    Image(systemName: "doc").foregroundStyle(.secondary)
                    Button(entry.url.path) { selectedFile = entry }
                        .buttonStyle(.borderless)
                        .focusEffectDisabled()
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(entry.allocatedBytes.diskSize).monospacedDigit().foregroundStyle(.secondary)
                    Button("Show in Finder", systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                    }
                    .labelStyle(.iconOnly)
                    .help("Show in Finder")
                }
                .font(.system(size: 11))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var statusInset: some View {
        if model.isScanning || model.isRemoving || model.errorMessage != nil || model.operationMessage != nil {
            VStack(spacing: 0) {
                QuietDivider()
                HStack(spacing: 8) {
                    if model.isScanning || model.isRemoving { ProgressView().controlSize(.small) }
                    Text(model.errorMessage ?? model.operationMessage ??
                         (model.isRemoving ? "Removing selected items…" : "Scanning…"))
                        .font(.system(size: 11)).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            page = .explore
            model.start(url, includeHidden: includeHidden)
        }
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct DiskExplorerSettingsView: View {
    var unreadableCount: Int? = nil
    @AppStorage("diskExplorer.chartStyle") private var chartStyle = DiskChartStyle.treemap.rawValue
    @AppStorage("diskExplorer.apparentSize") private var apparentSize = false
    @AppStorage("diskExplorer.includeHidden") private var includeHidden = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DISPLAY").utilitySectionHeader()
            VStack(alignment: .leading, spacing: 12) {
                Picker("Visualization", selection: $chartStyle) {
                    ForEach(DiskChartStyle.allCases) { style in Text(style.rawValue).tag(style.rawValue) }
                }
                Toggle("Show apparent file size", isOn: $apparentSize)
                Toggle("Include hidden files in scans", isOn: $includeHidden)
            }
            .utilitySectionCard()
            Text("DISK ACCESS").utilitySectionHeader()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(unreadableCount.map { $0 > 0 ? "Needs Attention" : "No blocked folders found" } ?? "Not checked")
                        .font(.system(size: 12, weight: .medium))
                    Text("A scan reports folders that macOS did not let this app read.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Full Disk Access Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            .utilitySectionCard()
            Spacer()
        }
        .settingsPageInsets(horizontal: 24, top: 12, bottom: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DiskExplorerReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: DiskExplorerModel
    let includeHidden: Bool
    @State private var confirmPermanent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Items").font(.system(size: 17, weight: .medium))
            Text("\(model.markedEntries.count) items · \(model.markedBytes.diskSize)")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            QuietDivider()
            List {
                ForEach(model.markedEntries) { entry in
                    HStack {
                        Image(systemName: entry.kind == .directory ? "folder" : "doc")
                        VStack(alignment: .leading) {
                            Text(entry.name).lineLimit(1)
                            Text(entry.url.path).font(.system(size: 10)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(entry.allocatedBytes.diskSize).monospacedDigit()
                        Button("Remove from Review", systemImage: "minus.circle") {
                            model.toggleMark(entry)
                        }
                        .labelStyle(.iconOnly)
                        .help("Remove from review")
                    }
                }
            }
            .listStyle(.plain)
            .thinScrollIndicators()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Delete Permanently…", role: .destructive) { confirmPermanent = true }
                    .disabled(model.markedEntries.isEmpty)
                Button("Move to Trash") {
                    model.removeMarked(permanently: false, includeHidden: includeHidden)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.markedEntries.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 480)
        .confirmationDialog(
            "Permanently delete \(model.markedEntries.count) items?",
            isPresented: $confirmPermanent
        ) {
            Button("Delete Permanently", role: .destructive) {
                model.removeMarked(permanently: true, includeHidden: includeHidden)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. \(model.markedBytes.diskSize) is selected.")
        }
    }
}

private extension Int64 {
    var diskSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
