import AppKit
import Darwin
import OnePlusUI
import QuickLook
import SwiftUI

enum DiskExplorerPage: String, Hashable {
    case explore, modify, settings, about
    static func restored(_ id: String?, hasDevices: Bool) -> Self {
        let page = id.flatMap(Self.init(rawValue:)) ?? .explore
        return page == .modify && !hasDevices ? .explore : page
    }
}

private struct DiskExplorerLiveUpdateObserver: View {
    @Environment(\.onePlusIsVisible) private var isVisible
    @Binding var isActive: Bool

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: isVisible, initial: true) { _, next in isActive = next }
    }
}

enum DiskResultTab: String, CaseIterable, Identifiable {
    case visualization
    case largestFiles = "largest-files"
    case results
    var id: String { rawValue }
}

struct DiskExplorerWindowView: View {
    @MainActor private static var retainedDisks: [ManagedDisk] = []
    @State private var model: DiskExplorerModel
    @State private var diskManagement: DiskManagementModel
    private let scansOnAppear: Bool
    @State private var page = DiskExplorerPage.explore
    @State private var resultTab = DiskResultTab.visualization
    @State private var search = ""
    @State private var searchFocus = 0
    @State private var chartLayouts = DiskChartLayoutCache()
    @State private var selection: Set<String> = []
    @State private var selectedID: String?
    @State private var history: [String] = []
    @State private var historyIndex = -1
    @State private var hoveredDetail: String?
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    @State private var showingReview = false
    @State private var showingFolder = false
    @State private var pendingDevice: String?
    @State private var inventoryTask: Task<Void, Never>?
    @State private var presentsLiveUpdates = false
    @AppStorage("diskExplorer.chartStyle") private var chartStyle = DiskChartStyle.treemap.rawValue
    @AppStorage("diskExplorer.chartMeasure") private var chartMeasure = DiskChartMeasure.space.rawValue
    @AppStorage("diskExplorer.apparentSize") private var apparentSize = false
    @AppStorage("diskExplorer.includeHidden") private var includeHidden = true
    @AppStorage("diskExplorer.page") private var savedPage = DiskExplorerPage.explore.rawValue
    @AppStorage("diskExplorer.resultTab") private var savedResultTab = DiskResultTab.visualization.rawValue

    private var chart: DiskChartStyle { DiskChartStyle(rawValue: chartStyle) ?? .treemap }
    private var measure: DiskChartMeasure { DiskChartMeasure(rawValue: chartMeasure) ?? .space }
    private var sourceName: String {
        guard let url = model.sourceURL else { return "Partition Manager" }
        if url == FileManager.default.homeDirectoryForCurrentUser { return "Home Folder" }
        return model.volumes.first { $0.url == url }?.name ?? url.lastPathComponent
    }
    private var inspected: DiskEntry? {
        guard let current = model.current else { return nil }
        if let selectedID, let entry = DiskEntryPresentation.find(selectedID, in: current), entry.kind != .aggregate { return entry }
        return current
    }
    private var inspectedParent: DiskEntry? {
        guard let entry = inspected, let root = model.result?.root else { return model.current }
        guard let parentID = entry.parentEntry?.id else { return root }
        return DiskEntryPresentation.find(parentID, in: root) ?? root
    }

    @MainActor init() { self.init(model: DiskExplorerModel()) }
    @MainActor init(model: DiskExplorerModel, scansOnAppear: Bool = true, initialTab: DiskResultTab? = nil) {
        _model = State(initialValue: model)
        #if DEBUG
        _diskManagement = State(initialValue: ProcessInfo.processInfo.environment["MACPOWERTOYS_UI_TEST"] == "1"
            ? DiskManagementModel(disks: [Self.modifyPreviewDisk], selectedPartitionID: "disk91s2", isPreview: true)
            : DiskManagementModel(disks: Self.retainedDisks))
        #else
        _diskManagement = State(initialValue: DiskManagementModel(disks: Self.retainedDisks))
        #endif
        self.scansOnAppear = scansOnAppear
        _page = State(initialValue: scansOnAppear ? DiskExplorerPage.restored(
            UserDefaults.standard.string(forKey: "diskExplorer.page"), hasDevices: !_diskManagement.wrappedValue.disks.isEmpty) : .explore)
        _resultTab = State(initialValue: initialTab ?? (scansOnAppear ? DiskResultTab(
            rawValue: UserDefaults.standard.string(forKey: "diskExplorer.resultTab") ?? "") : nil) ?? .visualization)
    }

    var body: some View {
        OnePlusWindowRoot(canvas: .diskExplorer) { sidebar } content: {
            content.background(DiskExplorerLiveUpdateObserver(isActive: $presentsLiveUpdates))
        }
            .background(WindowAccessor(identifier: "disk-explorer"))
            .background { shortcuts }
            .onAppear {
                if scansOnAppear { savedPage = page.rawValue; savedResultTab = resultTab.rawValue }
                if scansOnAppear && !diskManagement.isPreview { refreshInventory() }
                if scansOnAppear, page == .explore, let source = model.sourceURL, model.result == nil, !model.isScanning {
                    model.start(source, includeHidden: includeHidden)
                }
            }
            .task { if scansOnAppear { await model.refreshVolumes() } }
            .onDisappear {
                model.leave(); inventoryTask?.cancel(); inventoryTask = nil
                chartLayouts.clear()
                selectedID = nil; selection = []; history = []; previewURL = nil; previewURLs = []
            }
            .onChange(of: page) { _, next in
                if scansOnAppear { savedPage = next.rawValue }
                if next != .explore { model.cancel() }
                else if scansOnAppear, model.result == nil, !model.isScanning, let source = model.sourceURL {
                    model.start(source, includeHidden: includeHidden)
                }
                model.setPresentationActive(presentsLiveUpdates && next == .explore)
            }
            .onChange(of: presentsLiveUpdates, initial: true) { _, active in
                model.setPresentationActive(active && page == .explore)
            }
            .onChange(of: includeHidden) { _, _ in
                if page == .explore, let source = model.sourceURL { startScan(source) }
            }
            .onChange(of: model.current?.id) { _, _ in selectedID = nil; selection = []; hoveredDetail = nil }
            .onChange(of: resultTab) { _, next in
                if scansOnAppear { savedResultTab = next.rawValue }
                selection = []; search = ""; hoveredDetail = nil
            }
            .onChange(of: chartStyle) { _, _ in hoveredDetail = nil }
            .onChange(of: diskManagement.disks.map(\.id)) { _, _ in selectPendingDevice() }
            .quickLookPreview($previewURL, in: previewURLs)
            .sheet(isPresented: $showingFolder) { folderSheet }
            .sheet(isPresented: $showingReview) { DiskExplorerReviewSheet(model: model, includeHidden: includeHidden) }
            .sheet(item: $diskManagement.blockedEject) { DiskBlockedEjectSheet(model: diskManagement, blocked: $0) }
            .onOpenToolPage("disk-explorer", perform: openPage)
    }

    private var sidebar: some View {
        OnePlusSidebar(title: "Partition Manager") {
            OnePlusNavCaption("Analyze")
            OnePlusNavRow("Home Folder", systemImage: "house", selected: page == .explore && model.sourceURL == FileManager.default.homeDirectoryForCurrentUser) {
                startScan(FileManager.default.homeDirectoryForCurrentUser)
            }
            .contextMenu {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.homeDirectoryForCurrentUser]) }
                Button("Copy Path") { DiskEntryPresentation.copy([FileManager.default.homeDirectoryForCurrentUser.path]) }
            }
            ForEach(model.volumes) { volume in
                OnePlusNavRow(volume.name, systemImage: volume.url.path == "/" ? "internaldrive" : "externaldrive",
                              selected: page == .explore && model.sourceURL == volume.url) { startScan(volume.url) }
                    .contextMenu {
                        Button("Analyze") { startScan(volume.url) }
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([volume.url]) }
                        Button("Copy Path") { DiskEntryPresentation.copy([volume.url.path]) }
                    }
            }
            OnePlusNavRow("Choose Folder", systemImage: "folder.badge.plus") { showingFolder = true }
            OnePlusNavCaption("Devices").padding(.top, OnePlusMetrics.cardGap)
            ForEach(diskManagement.disks) { disk in deviceRow(disk) }
            if diskManagement.disks.isEmpty {
                Text(diskManagement.isBusy ? "Reading devices..." : "No physical devices")
                    .onePlusText(.caption).padding(OnePlusMetrics.navPadding)
            }
        } bottom: {
            OnePlusNavRow("Settings", systemImage: "gearshape", selected: page == .settings) { page = .settings }
            OnePlusNavRow("About", systemImage: "info.circle", selected: page == .about) { page = .about }
        }
    }

    private func deviceRow(_ disk: ManagedDisk) -> some View {
        let locked = diskManagement.isLocked(disk)
        return OnePlusDeviceNavRow(disk.name, subtitle: "\(disk.id) · \(TrayPopoverLayout.compactDiskBytes(disk.size, fractionLength: 0))",
                                  systemImage: disk.bus == "Secure Digital" ? "sdcard" : "externaldrive",
                                  selected: page == .modify && diskManagement.selectedDiskID == disk.id,
                                  locked: locked, accessibilityIdentifier: "diskman.disk.\(disk.id)",
                                  action: { diskManagement.select(disk); page = .modify }) {
            Button { eject(disk) } label: { Image(systemName: "eject") }
                .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                .disabled(locked || !disk.manageable || diskManagement.isBusy)
                .help(disk.protectionReason ?? (locked ? "Unlock this disk before ejecting" : "Eject \(disk.name)"))
                .accessibilityLabel("Eject \(disk.name)").accessibilityIdentifier("diskman.eject.\(disk.id)")
        }
        .help("\(disk.name), \(disk.id), \(disk.size.diskSize), \(disk.size.formatted()) bytes")
        .accessibilityHint("\(disk.id), \(disk.size.diskSize), \(disk.size.formatted()) bytes")
        .contextMenu {
            Button(locked ? "Unlock Disk" : "Lock Disk", systemImage: locked ? "lock.open" : "lock.fill") {
                diskManagement.setLocked(!locked, for: disk)
            }.disabled(diskManagement.isBusy || diskManagement.isPreview || !disk.manageable)
            Button("Eject", systemImage: "eject") { eject(disk) }
                .disabled(locked || !disk.manageable || diskManagement.isBusy)
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .explore: explorerPage
        case .modify: DiskModifyView(model: diskManagement)
        case .settings:
            OnePlusPage { OnePlusPageHeader(title: "Settings", subtitle: "Partition Manager display and scan preferences") }
                content: { DiskExplorerSettingsView(unreadableCount: model.result?.unreadableCount) }
        case .about: DiskmanAboutPage()
        }
    }

    private var explorerPage: some View {
        OnePlusPage(scrolls: false) {
            VStack(spacing: 0) {
                OnePlusPageHeader(title: sourceName,
                                  subtitle: model.sourceURL?.path ?? "Choose a volume or folder to analyze",
                                  subtitleRole: .mono) { headerActions }
                stats.padding(.horizontal, OnePlusMetrics.gutter).padding(.top, OnePlusMetrics.contentGap)
                    .padding(.bottom, OnePlusMetrics.cardGap)
            }
        } tabs: {
            OnePlusTabStrip(tabs: [.init(.visualization, "Visualization"),
                                  .init(.largestFiles, "Largest files", count: model.result?.largestFiles.count ?? 0),
                                  .init(.results, "Results")], selection: $resultTab) { tabTools }
                .accessibilityIdentifier("diskExplorer.resultTabs")
        } footer: {
            scanNotices
        } content: {
            if model.current != nil || model.isScanning {
                if resultTab == .visualization { visualization(model.current) }
                else { results(model.current) }
            } else { emptyState.frame(maxHeight: .infinity) }
        }
    }

    private var scanNotices: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            if let error = model.errorMessage {
                OnePlusBanner(error, tone: .error) { Button("Try again") { rescan() } }
            } else if model.isRemoving {
                OnePlusBanner("Removing selected items...") { ProgressView().controlSize(.small) }
            } else if model.result?.isComplete == false && !model.isScanning {
                OnePlusBanner("Scan stopped. These results are partial. Rescan before removing files.", tone: .warning)
            } else if let message = model.operationMessage {
                OnePlusBanner(message)
            }
            if let count = model.result?.unreadableCount, count > 0 { unreadableNotice(count) }
        }
    }

    private var headerActions: some View {
        OnePlusHeaderActions {
            if model.isScanning {
                Button("Stop", systemImage: "stop.fill") { model.cancel() }.buttonStyle(OnePlusButtonStyle())
            } else {
                Button("Rescan", systemImage: "arrow.clockwise", action: rescan)
                    .buttonStyle(OnePlusButtonStyle(.primary)).keyboardShortcut("r")
                    .disabled(model.sourceURL == nil || model.isRemoving)
            }
            OnePlusMenuButton("More actions", variant: .borderedIcon, items: [
                .item(OnePlusPopupMenuItem("Reveal in Finder", isEnabled: model.sourceURL != nil) {
                    if let url = model.sourceURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }),
                .item(OnePlusPopupMenuItem("Copy Path", isEnabled: model.sourceURL != nil) {
                    if let url = model.sourceURL { DiskEntryPresentation.copy([url.path]) }
                }),
                .item(OnePlusPopupMenuItem("Choose Folder...") { showingFolder = true }),
                .separator(),
                .item(OnePlusPopupMenuItem("Review \(model.markedEntries.count) items", isEnabled: !model.marks.isEmpty) {
                    showingReview = true
                })
            ])
                .accessibilityIdentifier("diskExplorer.scan")
        }
    }

    private var stats: some View {
        let root = model.result?.root
        return HStack(spacing: OnePlusMetrics.cardGap) {
            stat("Space used", value: root?.allocatedBytes.diskSize ?? "-", accent: true)
            stat("Files scanned", value: root?.fileCount.formatted() ?? "-")
            stat("Folders", value: root.map { max(0, $0.directoryCount - 1).formatted() } ?? "-")
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                if model.isScanning { ProgressView().controlSize(.small) }
                stat(model.isScanning ? "Scanning" : "Last scan",
                     value: model.isScanning ? "\(model.scannedEntries.formatted()) checked" :
                        model.result?.isComplete == false ? "Stopped" :
                        model.result.map { DiskEntryPresentation.date.string(from: $0.scannedAt) } ?? "Not scanned")
            }
        }.frame(height: OnePlusMetrics.controlHeight)
    }
    private func stat(_ title: String, value: String, accent: Bool = false) -> some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Text(title).onePlusText(.caption)
            Spacer(minLength: 0)
            Text(value).onePlusText(.mono, color: accent ? OnePlusColor.accent : OnePlusColor.ink)
                .monospacedDigit().lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private var tabTools: some View {
        if resultTab == .visualization {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusSegmented(choices: DiskChartStyle.allCases.map { ($0.rawValue, $0.rawValue) }, selection: $chartStyle,
                                 accessibilityLabel: "Visualization").fixedSize()
                OnePlusSelect(choices: DiskEntryPresentation.measures, selection: measureBinding, accessibilityLabel: "Measure")
            }
        }
    }
    private var measureBinding: Binding<String> {
        Binding(get: { measure == .space && apparentSize ? "Apparent size" : measure.title }, set: { value in
            apparentSize = value == "Apparent size"
            chartMeasure = value == "File count" ? DiskChartMeasure.files.rawValue : value == "Recent changes" ? DiskChartMeasure.age.rawValue : DiskChartMeasure.space.rawValue
        })
    }

    private func visualization(_ current: DiskEntry?) -> some View {
        HStack(spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    breadcrumbs(current)
                    Spacer(minLength: OnePlusMetrics.actionSpacing)
                    Text(current.map { "\($0.children.filter { $0.kind == .directory }.count) folders" } ?? "- folders")
                        .onePlusText(.caption)
                }.padding(.horizontal, OnePlusMetrics.cardPadding).frame(height: OnePlusMetrics.cardHeader)
                OnePlusColor.lineSoft.frame(height: 1)
                chartView(current).padding(OnePlusMetrics.actionSpacing).frame(maxWidth: .infinity, maxHeight: .infinity)
                if measure == .age { ageLegend }
                HStack {
                    Text(hoveredDetail ?? "")
                        .lineLimit(1).help(hoveredDetail ?? "")
                        .accessibilityIdentifier("diskExplorer.hoverDetail").accessibilityValue(hoveredDetail ?? "")
                    Spacer(minLength: OnePlusMetrics.actionSpacing)
                    Image(systemName: "info.circle").help("\(chartCaption). Click to select. Double-click a folder to explore.")
                        .accessibilityLabel("Chart guidance")
                }.onePlusText(.caption).padding(.horizontal, OnePlusMetrics.cardPadding).frame(height: OnePlusMetrics.controlHeight)
            }
            DiskSelectionInspector(entry: inspected, parent: inspectedParent ?? current, apparent: apparentSize,
                                   revision: model.result?.scannedAt ?? .distantPast,
                                   select: select, explore: navigate, copy: { DiskEntryPresentation.copy([$0.url.path]) },
                                   open: open, preview: preview, actions: fileActions,
                                   availableBytes: model.volumes.first { $0.url == inspected?.url }?.available,
                                   pendingURL: model.isScanning ? model.sourceURL : nil)
                .frame(width: OnePlusDiskmanMetrics.inspectorWidth)
        }.frame(maxHeight: .infinity)
    }
    private var chartCaption: String {
        let unit = chart == .sunburst ? "Arc length" : "Area"
        if measure == .files { return "\(unit) represents file count" }
        if apparentSize { return "\(unit) represents apparent size" }
        return "\(unit) represents space used"
    }
    private var ageLegend: some View {
        HStack(spacing: OnePlusMetrics.cardGap) {
            ForEach([1, 6, 0, 3], id: \.self) { index in
                Label { Text(index == 1 ? "7 days" : index == 6 ? "30 days" : index == 0 ? "1 year" : "Older") } icon: {
                    Circle().fill(DiskChartPalette.color(index)).frame(width: OnePlusMetrics.actionSpacing, height: OnePlusMetrics.actionSpacing)
                }.onePlusText(.caption)
            }
        }.padding(.horizontal, OnePlusMetrics.cardPadding).frame(height: OnePlusMetrics.controlHeight)
    }
    @ViewBuilder private func chartView(_ current: DiskEntry?) -> some View {
        if let current, !current.children.isEmpty {
            populatedChart(current)
        } else {
            OnePlusEmptyState(model.isScanning ? "Reading this folder..." : "No measured items", systemImage: "folder") {
                if model.isScanning { ProgressView().controlSize(.small) }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    @ViewBuilder private func populatedChart(_ current: DiskEntry) -> some View {
        if chart == .treemap {
            DiskTreemapView(directory: current, apparent: apparentSize, measure: measure,
                            scanComplete: model.result?.isComplete == true,
                            revision: model.result?.scannedAt ?? .distantPast,
                            cache: chartLayouts, select: select,
                            onHoverDetail: { hoveredDetail = $0 }, selectedEntryID: selectedID,
                            open: open, preview: preview, actions: fileActions)
        } else {
            DiskSunburstView(directory: current, apparent: apparentSize, measure: measure,
                             scanComplete: model.result?.isComplete == true,
                             revision: model.result?.scannedAt ?? .distantPast,
                             cache: chartLayouts, select: select,
                             onHoverDetail: { hoveredDetail = $0 }, selectedEntryID: selectedID,
                             open: open, preview: preview, actions: fileActions)
        }
    }
    private func results(_ current: DiskEntry?) -> some View {
        VStack(spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusSearchField(prompt: resultTab == .largestFiles ? "Search largest files" : "Search Results", text: $search,
                                   focusTrigger: searchFocus, shortcutHint: "⌘F")
                Spacer()
                Text(model.result == nil ? "Reading folders..." : model.result?.isComplete == true ? "Completed scan" : "Measured so far")
                    .onePlusText(.caption)
                Button("Review \(model.markedEntries.count)") { showingReview = true }
                    .buttonStyle(OnePlusButtonStyle()).disabled(model.marks.isEmpty || model.isRemoving)
            }
            if resultTab == .results {
                breadcrumbs(current).frame(height: OnePlusMetrics.controlHeight)
            }
            OnePlusCard {
                DiskEntryTable(entries: resultTab == .largestFiles ? model.result?.largestFiles ?? [] : current?.children ?? [],
                               revision: model.result?.scannedAt ?? .distantPast,
                               sourceID: resultTab == .largestFiles ? "largest-files" : current?.id ?? "pending-results",
                               search: search, apparent: apparentSize, selection: $selection, open: open,
                               preview: preview, actions: fileActions, remove: stageRemoval, showsFileCount: resultTab == .results,
                               isWaitingForScan: model.result == nil && model.isScanning)
                    .frame(maxHeight: .infinity)
            }
        }.frame(maxHeight: .infinity)
    }
    private func breadcrumbs(_ current: DiskEntry?) -> some View {
        let nodes = current.flatMap { current in model.result.map { DiskEntryPresentation.breadcrumbs(to: current, root: $0.root) } } ?? []
        return ScrollView(.horizontal) {
            HStack(spacing: OnePlusMetrics.spacing[1]) {
                ForEach(nodes) { entry in
                    Button { navigate(entry) } label: { Label(entry.name, systemImage: "folder") }
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small, horizontalPadding: 0)).help(entry.url.path)
                        .modifier(DiskChartFileActions(entry: entry, actions: fileActions))
                    if entry.id != nodes.last?.id { Image(systemName: "chevron.right").onePlusText(.caption) }
                }
                if nodes.isEmpty, let source = model.sourceURL {
                    Label(source.lastPathComponent, systemImage: "folder").onePlusText(.caption)
                }
            }.frame(height: OnePlusMetrics.compactControlHeight)
        }.thinScrollIndicators().frame(height: OnePlusMetrics.compactControlHeight)
    }
    private var emptyState: some View {
        OnePlusEmptyState("Choose a location", systemImage: "internaldrive") {
            Button("Choose Folder") { showingFolder = true }
        }.frame(maxHeight: .infinity)
    }
    private func unreadableNotice(_ count: Int) -> some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Image(systemName: "lock").foregroundStyle(OnePlusColor.warn)
            Text("Items could not be read").onePlusText(.row)
            Spacer()
            Text(count.formatted()).onePlusText(.mono)
            Button("Open Settings") { DiskEntryPresentation.openFullDiskAccess() }
                .buttonStyle(OnePlusButtonStyle(.link, horizontalPadding: 0))
        }.frame(height: OnePlusMetrics.controlHeight)
            .help("Grant Full Disk Access to complete the scan.")
            .accessibilityIdentifier("diskExplorer.unreadableInfo")
    }
    private var folderSheet: some View {
        DiskChooseFolderSheet(volumes: model.volumes, result: model.result, choose: { url in
            showingFolder = false; startScan(url)
        }, browse: {
            showingFolder = false
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.allowsMultipleSelection = false; panel.prompt = "Scan"
            panel.begin { response in if response == .OK, let url = panel.url { startScan(url) } }
        })
    }

    private func select(_ entry: DiskEntry) { selectedID = entry.id }
    private func open(_ entry: DiskEntry) {
        guard entry.kind != .aggregate else { return }
        if entry.kind == .directory { navigate(entry) } else { NSWorkspace.shared.open(entry.url) }
    }
    private func preview(_ entry: DiskEntry) { preview([entry]) }
    private func preview(_ entries: [DiskEntry]) {
        let urls = DiskEntryPresentation.previewURLs(entries)
        guard let first = urls.first else { return }
        previewURLs = urls; previewURL = first
    }
    private func navigate(_ entry: DiskEntry) {
        guard entry.kind == .directory, entry.id != model.current?.id else { return }
        if history.isEmpty, let current = model.current { history = [current.id]; historyIndex = 0 }
        history = Array(history.prefix(historyIndex + 1)); history.append(entry.id); historyIndex = history.count - 1
        model.navigate(to: entry)
    }
    private func traverse(_ delta: Int) {
        let next = historyIndex + delta
        guard history.indices.contains(next), let root = model.result?.root,
              let entry = DiskEntryPresentation.find(history[next], in: root) else { return }
        historyIndex = next; model.navigate(to: entry)
    }
    private func fileActions(_ entries: [DiskEntry]) -> [OnePlusTableAction] {
        let files = entries.filter { $0.kind != .aggregate }
        guard !files.isEmpty, files.count == entries.count else { return [] }
        let allMarked = files.allSatisfy { model.marks[$0.id] != nil }
        return [
            .init("Open") { files.forEach(open) },
            .init("Open With...") { DiskEntryPresentation.openWith(files.map(\.url)) },
            .init("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url)) },
            .init("Quick Look") { preview(files) },
            .init("Copy Path") { DiskEntryPresentation.copy(files.map { $0.url.path }) },
            .init(allMarked ? "Unmark" : "Mark for removal", enabled: canRemove(files)) {
                files.forEach { if allMarked || model.marks[$0.id] == nil { model.toggleMark($0) } }
            },
            .init("Move to Trash...", enabled: canRemove(files)) { stageRemoval(files) }
        ]
    }
    private func canRemove(_ entries: [DiskEntry]) -> Bool {
        guard let result = model.result, result.isComplete, !model.isRemoving else { return false }
        return !entries.isEmpty && entries.allSatisfy { DiskRemoval.isAllowed($0, under: result.root.url) }
    }
    private func stageRemoval(_ entries: [DiskEntry]) {
        guard canRemove(entries) else { return }
        entries.forEach { if model.marks[$0.id] == nil { model.toggleMark($0) } }; showingReview = true
    }
    private func startScan(_ url: URL) {
        chartLayouts.clear()
        page = .explore; resultTab = .visualization; selection = []; selectedID = nil
        history = []; historyIndex = -1; search = ""; model.start(url, includeHidden: includeHidden)
    }
    private func rescan() { if let source = model.sourceURL { startScan(source) } }
    private func refreshInventory() {
        inventoryTask?.cancel(); inventoryTask = Task {
            await diskManagement.refresh()
            if !diskManagement.disks.isEmpty { Self.retainedDisks = diskManagement.disks }
            selectPendingDevice()
        }
    }
    private func eject(_ disk: ManagedDisk) {
        diskManagement.select(disk); page = .modify
        #if DEBUG
        if diskManagement.isPreview {
            diskManagement.blockedEject = BlockedDiskEject(disk: disk, blockers: [
                DiskEjectBlocker(pid: 12345, name: "Example Editor", started: 1, userID: geteuid())
            ], reason: "The disk is in use."); return
        }
        #endif
        Task { await diskManagement.eject(disk) }
    }
    private func openPage(_ id: String) {
        switch id {
        case "home": startScan(FileManager.default.homeDirectoryForCurrentUser)
        case "largest-files": page = .explore; resultTab = .largestFiles
        case "results": page = .explore; resultTab = .results
        case "rings": page = .explore; resultTab = .visualization; chartStyle = DiskChartStyle.sunburst.rawValue
        case "choose-folder": showingFolder = true
        case "settings": page = .settings
        case "about": page = .about
        default:
            if id.hasPrefix("device/") { pendingDevice = String(id.dropFirst("device/".count)); page = .modify; selectPendingDevice() }
        }
    }
    private func selectPendingDevice() {
        guard let pendingDevice, let disk = diskManagement.disks.first(where: { $0.id == pendingDevice }) else { return }
        diskManagement.select(disk); self.pendingDevice = nil
    }
    private var shortcuts: some View {
        Group {
            Button("Back") { traverse(-1) }.keyboardShortcut("[").disabled(page != .explore || historyIndex <= 0)
            Button("Forward") { traverse(1) }.keyboardShortcut("]").disabled(page != .explore || historyIndex + 1 >= history.count)
            Button("Search Results") { page = .explore; resultTab = .results; searchFocus += 1 }.keyboardShortcut("f")
            Button("Partition Manager Settings") { page = .settings }.keyboardShortcut(",")
            ForEach(0..<9, id: \.self) { index in
                Button("Navigate \(index + 1)") { sidebarShortcut(index) }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
        }.hidden()
    }
    private func sidebarShortcut(_ index: Int) {
        if index == 0 { startScan(FileManager.default.homeDirectoryForCurrentUser); return }
        if model.volumes.indices.contains(index - 1) { startScan(model.volumes[index - 1].url); return }
        let deviceIndex = index - model.volumes.count - 2
        if deviceIndex == -1 { showingFolder = true }
        else if diskManagement.disks.indices.contains(deviceIndex) { diskManagement.select(diskManagement.disks[deviceIndex]); page = .modify }
        else if deviceIndex == diskManagement.disks.count { page = .settings }
        else if deviceIndex == diskManagement.disks.count + 1 { page = .about }
    }

    #if DEBUG
    private static let modifyPreviewDisk = ManagedDisk(
        id: "disk91", name: "Preview SD card", size: 15_634_268_160, bus: "Secure Digital",
        scheme: "GUID_partition_scheme", devicePath: "hosted-preview", writable: true, manageable: true, mediaRegistryID: 1,
        partitions: [ManagedPartition(id: "disk91s1", name: "EFI", content: "EFI", size: 209_715_200, mountPoint: nil, uuid: nil),
            ManagedPartition(id: "disk91s2", name: "FIRST", content: "Microsoft Basic Data", size: 4_000_000_000,
                             mountPoint: nil, uuid: "first", fileSystem: "ExFAT"),
            ManagedPartition(id: "disk91s3", name: "SECOND", content: "Microsoft Basic Data", size: 11_422_455_808,
                             mountPoint: nil, uuid: "second", fileSystem: "ExFAT")])
    #endif
}
