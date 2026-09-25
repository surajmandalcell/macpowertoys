import AppKit
import QuickLook
import SwiftUI

private enum DiskExplorerPage: Hashable {
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

enum DiskResultTab: String, CaseIterable, Identifiable {
    case visualization = "Visualization"
    case largestFiles = "Largest Files"
    var id: String { rawValue }
}

struct DiskExplorerWindowView: View {
    @State private var model: DiskExplorerModel
    private let scansOnAppear: Bool
    @State private var page = DiskExplorerPage.explore
    @State private var search = ""
    @State private var sort = DiskEntrySort.size
    @State private var visibleLimit = 250
    @State private var resultTab = DiskResultTab.visualization
    @State private var showsContents = false
    @State private var showsStatistics = false
    @State private var largestSearch = ""
    @State private var selectedFile: DiskEntry?
    @State private var previewURL: URL?
    @State private var showingReview = false
    @AppStorage("diskExplorer.chartStyle") private var chartStyle = DiskChartStyle.treemap.rawValue
    @AppStorage("diskExplorer.chartMeasure") private var chartMeasure = DiskChartMeasure.space.rawValue
    @AppStorage("diskExplorer.apparentSize") private var apparentSize = false
    @AppStorage("diskExplorer.includeHidden") private var includeHidden = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var chart: DiskChartStyle { DiskChartStyle(rawValue: chartStyle) ?? .treemap }
    private var measure: DiskChartMeasure { DiskChartMeasure(rawValue: chartMeasure) ?? .space }

    @MainActor init() {
        self.init(model: DiskExplorerModel())
    }

    @MainActor init(model: DiskExplorerModel, scansOnAppear: Bool = true,
                    initialTab: DiskResultTab = .visualization) {
        _model = State(initialValue: model)
        _resultTab = State(initialValue: initialTab)
        self.scansOnAppear = scansOnAppear
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: UtilityLayout.dataSidebarWidth)
            content
                .utilityContentTransition(value: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) { statusInset }
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "disk-explorer"))
        .onAppear {
            model.refreshVolumes()
            if scansOnAppear {
                model.start(model.sourceURL ?? FileManager.default.homeDirectoryForCurrentUser,
                            includeHidden: includeHidden)
            }
        }
        .onDisappear { model.leave() }
        .onChange(of: includeHidden) { _, newValue in
            if let source = model.sourceURL { model.start(source, includeHidden: newValue) }
        }
        .quickLookPreview($previewURL)
        .popover(item: $selectedFile) { file in
            fileInspector(file).frame(width: 440)
        }
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
                        startScan(volume.url)
                    }
                    .help(volume.url.path)
                }
                Text("FOLDERS").utilitySectionHeader().padding(.leading, 8).padding(.top, 15)
                SidebarRow(icon: "house", title: "Home Folder",
                           isSelected: page == .explore && model.sourceURL == FileManager.default.homeDirectoryForCurrentUser) {
                    startScan(FileManager.default.homeDirectoryForCurrentUser)
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
                Menu("Scan", systemImage: "internaldrive") {
                    Button("Home Folder") {
                        startScan(FileManager.default.homeDirectoryForCurrentUser)
                    }
                    ForEach(model.volumes) { volume in
                        Button(volume.name) { startScan(volume.url) }
                    }
                    Divider()
                    Button("Choose Folder…") { chooseFolder() }
                }
                .accessibilityIdentifier("diskExplorer.scan")
                if model.isScanning {
                    Button("Stop", systemImage: "stop.fill") { model.cancel() }
                } else if let source = model.sourceURL {
                    Button("Rescan", systemImage: "arrow.clockwise") {
                        model.start(source, includeHidden: includeHidden)
                    }
                }
                if model.result != nil {
                    Button("Scan Statistics", systemImage: "info.circle") {
                        showsStatistics.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("diskExplorer.statistics")
                    .help("Scan statistics")
                    .popover(isPresented: $showsStatistics) {
                        scanStatistics.frame(width: 260).padding(16)
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
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Reading the first folders…")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                    .frame(maxWidth: .infinity, minHeight: 480)
            } else {
                ContentUnavailableView("Choose a Disk", systemImage: "internaldrive",
                                       description: Text("Select a volume or folder to see where its space goes."))
                    .frame(maxWidth: .infinity, minHeight: 480)
            }
        }
    }

    private func exploredContent(_ current: DiskEntry, snapshot: DiskScanResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Results", selection: $resultTab) {
                    ForEach(DiskResultTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("diskExplorer.resultTabs")
                Spacer()
                if resultTab == .visualization {
                    Picker("View", selection: $chartStyle) {
                        ForEach(DiskChartStyle.allCases) { style in
                            Label(style.rawValue, systemImage: style.symbol).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Picker("Measure", selection: $chartMeasure) {
                        ForEach(DiskChartMeasure.allCases) { value in Text(value.rawValue).tag(value.rawValue) }
                    }
                    .fixedSize()
                    Button {
                        withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion)) {
                            showsContents.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.bordered)
                    .tint(showsContents ? .accentColor : nil)
                    .accessibilityLabel(showsContents ? "Hide Contents" : "Show Contents")
                    .accessibilityIdentifier("diskExplorer.contents")
                    .help(showsContents ? "Hide Contents" : "Show Contents")
                } else {
                    TextField("Filter largest files", text: $largestSearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                }
            }
            HStack(spacing: 8) {
                breadcrumbs(for: current, root: snapshot.root)
                if !snapshot.isComplete {
                    Text(model.isScanning ? "LIVE · MEASURED SO FAR" : "PARTIAL SCAN")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .fixedSize()
                }
            }
            if resultTab == .visualization {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        chartView(current)
                            .id(current.id)
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 520)
                    if showsContents {
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                TextField("Search Contents", text: $search)
                                    .textFieldStyle(.roundedBorder)
                                Picker("Sort", selection: $sort) {
                                    ForEach(DiskEntrySort.allCases) { value in
                                        Text(value.rawValue).tag(value)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 90)
                            }
                            .padding(8)
                            entriesView(current)
                        }
                        .frame(width: 290, height: 520)
                        .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
                    }
                }
            } else {
                largestFiles(snapshot.largestFiles)
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

    private var scanStatistics: some View {
        let current = model.current
        let snapshot = model.result
        return VStack(alignment: .leading, spacing: 12) {
            Text(snapshot?.isComplete == true ? "Scan Statistics" : "Measured So Far")
                .font(.system(size: 13, weight: .semibold))
            metric("Used here", current?.bytes(apparent: apparentSize).diskSize ?? "—")
            HStack(spacing: 18) {
                metric("Files", current?.fileCount.formatted() ?? "—")
                metric("Folders", max((current?.directoryCount ?? 1) - 1, 0).formatted())
            }
            if let volume = model.volumes.first(where: { $0.url == model.sourceURL }),
               let available = volume.available {
                metric("Free on disk", available.diskSize)
            }
            if let snapshot, snapshot.unreadableCount > 0 {
                Text("\(snapshot.unreadableCount.formatted()) unreadable items")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
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
                    Button(entry.name) {
                        withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion)) {
                            model.navigate(to: entry)
                        }
                    }
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
        VStack(spacing: 0) {
            Group {
                if directory.children.isEmpty && model.isScanning {
                    VStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text("Scanning this folder…")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if directory.children.isEmpty {
                    ContentUnavailableView("No Measured Items", systemImage: "square.dashed")
                } else if chart == .treemap {
                    DiskTreemapView(directory: directory, apparent: apparentSize, measure: measure, select: inspect)
                } else {
                    DiskSunburstView(directory: directory, apparent: apparentSize, measure: measure, select: inspect)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if measure == .age {
                HStack(spacing: 14) {
                    ageKey("7 days", color: DiskChartPalette.color(1))
                    ageKey("30 days", color: DiskChartPalette.color(6))
                    ageKey("1 year", color: DiskChartPalette.color(0))
                    ageKey("Older", color: DiskChartPalette.color(3))
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
        .background(LinearGradient(colors: [Color.accentColor.opacity(0.07), Color.primary.opacity(0.025)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func ageKey(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
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
                if model.result?.isComplete == true,
                   let root = model.result?.root.url, DiskRemoval.isAllowed(entry, under: root) {
                    Button(model.marks[entry.id] == nil ? "Mark for Removal" : "Unmark") {
                        model.toggleMark(entry)
                    }
                }
            }
            if model.result?.isComplete == true,
               let root = model.result?.root.url, DiskRemoval.isAllowed(entry, under: root) {
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
            withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion)) {
                model.navigate(to: entry)
            }
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
        let matches = largestSearch.isEmpty ? files : files.filter {
            $0.url.path.localizedStandardContains(largestSearch)
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.isScanning ? "Largest files measured so far" : "Largest files")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(matches.count) of \(files.count)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            QuietDivider()
            if matches.isEmpty {
                ContentUnavailableView(model.isScanning ? "Finding Large Files" : "No Matching Files",
                                       systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(matches.indices, id: \.self) { index in
                        let entry = matches[index]
                        HStack(spacing: 10) {
                            Text("\(index + 1)").monospacedDigit()
                                .foregroundStyle(.tertiary).frame(width: 28, alignment: .trailing)
                            Button { selectedFile = entry } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "doc.fill").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name).lineLimit(1).truncationMode(.middle)
                                            .foregroundStyle(.primary)
                                        Text(entry.url.deletingLastPathComponent().path)
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer(minLength: 8)
                                    Text(entry.allocatedBytes.diskSize)
                                        .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                                }
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
                            .accessibilityLabel("Inspect \(entry.name)")
                            Button("Show in Finder", systemImage: "arrow.up.right.square") {
                                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                            }
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                            .focusEffectDisabled()
                            .help("Show in Finder")
                            if model.result?.isComplete == true,
                               let root = model.result?.root.url,
                               DiskRemoval.isAllowed(entry, under: root) {
                                Button(model.marks[entry.id] == nil ? "Mark for Removal" : "Unmark", systemImage: model.marks[entry.id] == nil ?
                                       "plus.circle" : "checkmark.circle.fill") {
                                    model.toggleMark(entry)
                                }
                                .labelStyle(.iconOnly).buttonStyle(.plain)
                                .focusEffectDisabled()
                                .help(model.marks[entry.id] == nil ? "Mark for Removal" : "Unmark")
                            }
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        QuietDivider()
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var statusInset: some View {
        if model.isScanning || model.isRemoving || model.errorMessage != nil ||
           model.operationMessage != nil || model.result?.isComplete == false {
            VStack(spacing: 0) {
                QuietDivider()
                HStack(spacing: 8) {
                    if model.isScanning || model.isRemoving { ProgressView().controlSize(.small) }
                    Text(model.errorMessage ?? model.operationMessage ??
                         (model.isRemoving ? "Removing selected items…" :
                          model.isScanning ? "Scanning · \(model.scannedEntries.formatted()) items checked; chart updates live" :
                          "Scan stopped. Results are partial; scan again before removal."))
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
            startScan(url)
        }
    }

    private func startScan(_ url: URL) {
        page = .explore
        resultTab = .visualization
        selectedFile = nil
        showsStatistics = false
        model.start(url, includeHidden: includeHidden)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct DiskExplorerSettingsView: View {
    var unreadableCount: Int? = nil
    @AppStorage("diskExplorer.chartStyle") private var chartStyle = DiskChartStyle.treemap.rawValue
    @AppStorage("diskExplorer.chartMeasure") private var chartMeasure = DiskChartMeasure.space.rawValue
    @AppStorage("diskExplorer.apparentSize") private var apparentSize = false
    @AppStorage("diskExplorer.includeHidden") private var includeHidden = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DISPLAY").utilitySectionHeader()
            VStack(alignment: .leading, spacing: 12) {
                Picker("Visualization", selection: $chartStyle) {
                    ForEach(DiskChartStyle.allCases) { style in Text(style.rawValue).tag(style.rawValue) }
                }
                Picker("Measure", selection: $chartMeasure) {
                    ForEach(DiskChartMeasure.allCases) { value in Text(value.rawValue).tag(value.rawValue) }
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
