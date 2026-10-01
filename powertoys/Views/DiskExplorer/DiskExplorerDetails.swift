import AppKit
import OnePlusUI
import SwiftUI
import UniformTypeIdentifiers

enum DiskEntryPresentation {
    static let size: ByteCountFormatter = {
        let formatter = ByteCountFormatter(); formatter.countStyle = .file; return formatter
    }()
    static let date: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short; return formatter
    }()
    static let measures = ["Space used", "Apparent size", "File count", "Recent changes"].map { ($0, $0) }
    nonisolated static func name(_ entry: DiskEntry) -> String { entry.kind == .aggregate ? "\(entry.fileCount.formatted()) smaller files" : entry.name }
    nonisolated static func symbol(_ entry: DiskEntry) -> String {
        switch entry.kind { case .directory: "folder"; case .symbolicLink: "link"; case .aggregate: "square.stack.3d.up"; default: "doc" }
    }
    nonisolated static func kind(_ entry: DiskEntry) -> String {
        switch entry.kind {
        case .directory: "Folder"
        case .symbolicLink: "Symbolic link"
        case .aggregate: "Grouped files"
        default: UTType(filenameExtension: (entry.name as NSString).pathExtension)?.localizedDescription ?? "File"
        }
    }
    static func breadcrumbs(to entry: DiskEntry, root: DiskEntry) -> [DiskEntry] {
        guard let route = entry.identityRoute(from: root.id) else { return [root] }
        var result = [root]
        var node = root
        for id in route.dropFirst() {
            guard let child = node.children.first(where: { $0.id == id }) else { break }
            result.append(child)
            node = child
        }
        return result
    }
    static func find(_ id: String, in root: DiskEntry) -> DiskEntry? {
        if root.id == id { return root }
        if let direct = root.children.first(where: { $0.id == id }) { return direct }
        for child in root.children where child.kind == .directory {
            if let match = find(id, in: child) { return match }
        }
        return nil
    }
    static func copy(_ paths: [String]) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }
    nonisolated static func previewURLs(_ entries: [DiskEntry]) -> [URL] {
        entries.filter { $0.kind != .aggregate }.map(\.url)
    }
    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }
    static func openWith(_ urls: [URL]) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]; panel.prompt = "Open"
        panel.begin { response in
            guard response == .OK, let application = panel.url else { return }
            NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

extension Int64 {
    var diskSize: String { DiskEntryPresentation.size.string(fromByteCount: self) }
}

nonisolated struct DiskEntryTableRequest: Hashable, Sendable {
    let revision: Date
    let sourceID: String
    let search: String
    let column: Int
    let ascending: Bool
    let apparent: Bool
    let showsFileCount: Bool

    func hasSamePresentation(as other: Self) -> Bool {
        sourceID == other.sourceID && search == other.search && column == other.column &&
            ascending == other.ascending && apparent == other.apparent &&
            showsFileCount == other.showsFileCount
    }
}

nonisolated struct DiskEntryTableRow: Identifiable, Sendable {
    let entry: DiskEntry
    let cells: [String]
    let symbol: String
    let url: URL?
    let sizeShare: Double
    var id: String { entry.id }
    var tableItem: OnePlusTableItem { OnePlusTableItem(id: id, cells: cells, symbol: symbol, url: url, usage: [2: sizeShare]) }
}

nonisolated struct DiskEntryTableProjection: Sendable {
    let request: DiskEntryTableRequest?
    let rows: [DiskEntryTableRow]
    let entriesByID: [String: DiskEntry]
    static let empty = DiskEntryTableProjection(request: nil, rows: [], entriesByID: [:])
}

struct DiskEntryTable: View {
    let entries: [DiskEntry]
    let revision: Date
    let sourceID: String
    let search: String
    let apparent: Bool
    @Binding var selection: Set<String>
    let open: (DiskEntry) -> Void
    let preview: ([DiskEntry]) -> Void
    let actions: ([DiskEntry]) -> [OnePlusTableAction]
    let remove: ([DiskEntry]) -> Void
    var showsFileCount = false
    var isWaitingForScan = false
    @State private var column = 2
    @State private var ascending = false
    @State private var projections: [DiskEntryTableRequest: DiskEntryTableProjection] = [:]
    @State private var tableItems: [DiskEntryTableRequest: [OnePlusTableItem]] = [:]
    @State private var displayedProjection = DiskEntryTableProjection.empty
    @State private var displayedTableItems: [OnePlusTableItem] = []

    nonisolated static func sorted(_ entries: [DiskEntry], column: Int, ascending: Bool, apparent: Bool) -> [DiskEntry] {
        entries.sorted { left, right in
            let comparison: ComparisonResult
            switch column {
            case 1: comparison = DiskEntryPresentation.kind(left).localizedStandardCompare(DiskEntryPresentation.kind(right))
            case 2: comparison = left.bytes(apparent: apparent) == right.bytes(apparent: apparent) ? .orderedSame :
                left.bytes(apparent: apparent) < right.bytes(apparent: apparent) ? .orderedAscending : .orderedDescending
            case 3: comparison = left.modifiedAt.compare(right.modifiedAt)
            case 4: comparison = left.fileCount == right.fileCount ? .orderedSame : left.fileCount < right.fileCount ? .orderedAscending : .orderedDescending
            default: comparison = DiskEntryPresentation.name(left).localizedStandardCompare(DiskEntryPresentation.name(right))
            }
            if comparison == .orderedSame {
                let name = DiskEntryPresentation.name(left)
                    .localizedStandardCompare(DiskEntryPresentation.name(right))
                return name == .orderedSame ? left.id < right.id : name == .orderedAscending
            }
            return comparison == (ascending ? .orderedAscending : .orderedDescending)
        }
    }
    nonisolated static func project(_ entries: [DiskEntry], request: DiskEntryTableRequest) -> DiskEntryTableProjection {
        let matches = sorted(entries.filter {
            request.search.isEmpty || DiskEntryPresentation.name($0).localizedStandardContains(request.search) ||
                ($0.kind != .aggregate && $0.url.path.localizedStandardContains(request.search))
        }, column: request.column, ascending: request.ascending, apparent: request.apparent)
        let largest = matches.map { $0.bytes(apparent: request.apparent) }.max() ?? 0
        let rows = matches.map { entry in
            DiskEntryTableRow(
                entry: entry,
                cells: [DiskEntryPresentation.name(entry), DiskEntryPresentation.kind(entry),
                        entry.bytes(apparent: request.apparent).formatted(.byteCount(style: .file)),
                        entry.modifiedAt.formatted(date: .numeric, time: .shortened)] +
                    (request.showsFileCount ? [entry.fileCount.formatted()] : []),
                symbol: DiskEntryPresentation.symbol(entry),
                url: entry.kind == .aggregate ? nil : entry.url,
                sizeShare: DiskChartGeometry.fraction(Double(entry.bytes(apparent: request.apparent)), of: Double(largest))
            )
        }
        return DiskEntryTableProjection(request: request, rows: rows,
                                        entriesByID: Dictionary(uniqueKeysWithValues: matches.map { ($0.id, $0) }))
    }
    var body: some View {
        let request = DiskEntryTableRequest(revision: revision, sourceID: sourceID, search: search,
                                            column: column, ascending: ascending, apparent: apparent,
                                            showsFileCount: showsFileCount)
        let cached = projections[request]
        let keepsPreviousRows = displayedProjection.request?.hasSamePresentation(as: request) == true
        let current = cached ?? (keepsPreviousRows ? displayedProjection : .empty)
        let rows = tableItems[request] ?? (keepsPreviousRows ? displayedTableItems : [])
        let columns: [OnePlusGridColumn] = [.init("Name", width: 450), .init("Kind", width: 180),
            .init("Size", width: 180, trailing: true), .init("Modified", width: 180)] +
            (showsFileCount ? [.init("Files", width: 80, trailing: true)] : [])
        OnePlusNativeTable(columns: columns,
                           rows: rows, selection: $selection,
                           sortColumn: column, ascending: ascending,
                           sort: { column = $0; ascending = $1 },
                           open: { $0.compactMap { current.entriesByID[$0] }.filter { $0.kind != .aggregate }.forEach(open) },
                           preview: { ids in preview(current.rows.filter { ids.contains($0.id) }.map(\.entry)) },
                           remove: { remove($0.compactMap { current.entriesByID[$0] }) },
                           actions: { actions($0.sorted().compactMap { current.entriesByID[$0] }) })
            .thinScrollIndicators()
            .overlay {
                if isWaitingForScan || (cached == nil && !keepsPreviousRows) {
                    OnePlusEmptyState(sourceID == "largest-files" ? "Loading largest files" : "Loading results",
                                      systemImage: "arrow.triangle.2.circlepath") {
                        ProgressView().controlSize(.small)
                    }
                }
                else if current.rows.isEmpty { OnePlusEmptyState("No matching items", systemImage: "doc.text.magnifyingglass") }
            }
            .task(id: request) {
                guard projections[request] == nil else { return }
                let source = entries
                let next = await Task.detached(priority: .userInitiated) { Self.project(source, request: request) }.value
                guard !Task.isCancelled else { return }
                if projections.keys.contains(where: { $0.revision != request.revision }) || projections.count >= 12 {
                    projections.removeAll(keepingCapacity: true)
                    tableItems.removeAll(keepingCapacity: true)
                }
                let nextItems = next.rows.map(\.tableItem)
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    tableItems[request] = nextItems
                    projections[request] = next
                    displayedTableItems = nextItems
                    displayedProjection = next
                }
            }
    }
}

nonisolated struct DiskInspectorRequest: Hashable, Sendable {
    let revision: Date
    let entryID: String
    let apparent: Bool
}

nonisolated struct DiskInspectorProjection: Sendable {
    let request: DiskInspectorRequest?
    let path: String
    let folderCount: Int?
    let children: [DiskEntry]
    static let empty = DiskInspectorProjection(request: nil, path: "", folderCount: nil, children: [])

    func presentation(for next: DiskInspectorRequest?) -> Self {
        guard let request, let next,
              request.entryID == next.entryID, request.apparent == next.apparent else { return .empty }
        return self
    }
}

struct DiskSelectionInspector: View {
    let entry: DiskEntry?
    let parent: DiskEntry?
    let apparent: Bool
    let revision: Date
    let select: (DiskEntry) -> Void
    let explore: (DiskEntry) -> Void
    let copy: (DiskEntry) -> Void
    let open: (DiskEntry) -> Void
    let preview: (DiskEntry) -> Void
    let actions: ([DiskEntry]) -> [OnePlusTableAction]
    var availableBytes: Int64?
    var pendingURL: URL?
    @State private var projection = DiskInspectorProjection.empty

    var body: some View {
        let request = entry.map { DiskInspectorRequest(revision: revision, entryID: $0.id, apparent: apparent) }
        let current = projection.presentation(for: request)
        OnePlusCard {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Text("Selection").onePlusText(.captionUpper)
                if let entry {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                        identity(entry, path: current.path).modifier(DiskChartFileActions(entry: entry, actions: actions))
                        facts(entry, folderCount: current.folderCount)
                        if entry.kind == .directory { children(current.request == nil ? nil : current.children) }
                    }
                } else if let pendingURL {
                    HStack {
                        Label(pendingURL.lastPathComponent, systemImage: "folder").onePlusText(.sectionTitle).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("-").onePlusText(.mono)
                    }
                    Text(pendingURL.path).onePlusText(.mono).lineLimit(2).truncationMode(.middle)
                    OnePlusUsageBar(value: 0)
                    VStack(spacing: 0) {
                        OnePlusKeyValueRow("Kind", value: "Folder")
                        OnePlusKeyValueRow("Files", value: "-")
                        OnePlusKeyValueRow("Contents", value: "-")
                    }
                } else {
                    OnePlusEmptyState("Select an item", systemImage: "cursorarrow")
                }
                Spacer(minLength: 0)
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Button("View contents") { if let entry { explore(entry) } }
                        .buttonStyle(OnePlusButtonStyle()).disabled(entry?.kind != .directory)
                    Spacer(minLength: 0)
                    Button { if let entry { copy(entry) } } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(OnePlusButtonStyle(.icon)).disabled(entry == nil)
                        .help("Copy Path").accessibilityLabel("Copy Path")
                }
            }.padding(OnePlusMetrics.cardPadding).frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: request) {
            guard let entry, let request else {
                projection = .empty
                return
            }
            let limit = OnePlusDiskmanMetrics.inspectorChildren
            let next = await Task.detached(priority: .userInitiated) {
                DiskInspectorProjection(
                    request: request,
                    path: entry.url.path,
                    folderCount: entry.children.reduce(0) { $0 + ($1.kind == .directory ? 1 : 0) },
                    children: Array(entry.children.sorted {
                        let left = $0.bytes(apparent: request.apparent)
                        let right = $1.bytes(apparent: request.apparent)
                        return left == right ? $0.id < $1.id : left > right
                    }.prefix(limit))
                )
            }.value
            guard !Task.isCancelled else { return }
            withTransaction(Transaction(animation: nil)) { projection = next }
        }
    }
    private func identity(_ entry: DiskEntry, path: String) -> some View {
        let share = DiskChartGeometry.fraction(Double(entry.bytes(apparent: apparent)), of: Double(parent?.bytes(apparent: apparent) ?? 0))
        return VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Label(entry.name, systemImage: DiskEntryPresentation.symbol(entry)).onePlusText(.sectionTitle).lineLimit(1).help(entry.name)
                Spacer(minLength: 0)
                Text(entry.bytes(apparent: apparent).diskSize).onePlusText(.mono).fixedSize()
            }
            Text(path.isEmpty ? "-" : path).onePlusText(.mono).lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(path)
            HStack {
                Text("Of parent folder")
                Spacer()
                Text(share.formatted(.percent.precision(.fractionLength(1))))
            }.onePlusText(.caption)
            OnePlusUsageBar(value: share)
        }
    }
    private func facts(_ entry: DiskEntry, folderCount: Int?) -> some View {
        VStack(spacing: 0) {
            OnePlusKeyValueRow("Kind", value: DiskEntryPresentation.kind(entry)).monospacedDigit()
            OnePlusKeyValueRow("Files", value: entry.fileCount.formatted()).monospacedDigit()
            OnePlusKeyValueRow("Contents", value: folderCount.map { "\($0) folders" } ?? "-").monospacedDigit()
            if let availableBytes { OnePlusKeyValueRow("Free on disk", value: availableBytes.diskSize).monospacedDigit() }
        }
    }
    private func children(_ children: [DiskEntry]?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OnePlusColor.lineSoft.frame(height: 1)
            Text("Inside this folder").onePlusText(.caption)
                .frame(height: OnePlusMetrics.controlHeight, alignment: .leading)
            if children == nil {
                Text("-").onePlusText(.caption).frame(height: OnePlusMetrics.controlHeight, alignment: .leading)
            }
            ForEach(children ?? []) { child in
                Button {
                    guard child.kind != .aggregate else { return }
                    select(child)
                    if NSApp.currentEvent?.clickCount == 2 { open(child) }
                } label: {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Image(systemName: DiskEntryPresentation.symbol(child))
                        Text(DiskEntryPresentation.name(child)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(child.bytes(apparent: apparent).diskSize).fixedSize()
                    }.onePlusText(.caption).frame(height: OnePlusMetrics.controlHeight).contentShape(Rectangle())
                }.buttonStyle(OnePlusInteractionStyle())
                    .modifier(DiskChartFileActions(entry: child, actions: actions))
                    .onKeyPress(.return) { if child.kind != .aggregate { open(child) }; return .handled }
                    .onKeyPress(.space) { if child.kind != .aggregate { preview(child) }; return .handled }
            }
        }
    }
}

struct DiskChooseFolderSheet: View {
    let volumes: [DiskVolume]
    let result: DiskScanResult?
    let choose: (URL) -> Void
    let browse: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        OnePlusSheet(diskmanFolderTitle: "Choose a folder") {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                ScrollView {
                    OnePlusCard {
                        location("Home Folder", url: FileManager.default.homeDirectoryForCurrentUser, icon: "house")
                        ForEach(volumes) { volume in location(volume.name, url: volume.url, icon: "externaldrive") }
                    }
                }.thinScrollIndicators()
                    .frame(height: min(CGFloat(volumes.count + 1) * OnePlusMetrics.settingRow, OnePlusDiskmanMetrics.folderListHeight))
            }
        } footer: {
            Button("Cancel") { dismiss() }.buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
            Button("Browse for folder...", systemImage: "folder.badge.plus", action: browse).buttonStyle(OnePlusButtonStyle())
        }
    }
    private func location(_ title: String, url: URL, icon: String) -> some View {
        Button { choose(url) } label: {
            HStack(spacing: OnePlusMetrics.navIconGap) {
                Image(systemName: icon)
                Text(title).onePlusText(.row).lineLimit(1)
                Spacer()
                Text(result?.root.url == url ? "\(result!.root.allocatedBytes.diskSize) \(result!.isComplete ? "indexed" : "measured so far")" : "Not indexed")
                    .onePlusText(.caption).lineLimit(1)
                Image(systemName: "chevron.right").onePlusText(.caption)
            }.padding(.horizontal, OnePlusMetrics.cardPadding).frame(height: OnePlusMetrics.settingRow)
        }.buttonStyle(OnePlusInteractionStyle()).help(url.path)
    }
}

/// Settings content only. The host supplies page chrome, scrolling and density.
struct DiskExplorerSettingsView: View {
    let unreadableCount: Int?
    @AppStorage("diskExplorer.chartStyle") private var chartStyle = DiskChartStyle.treemap.rawValue
    @AppStorage("diskExplorer.chartMeasure") private var chartMeasure = DiskChartMeasure.space.rawValue
    @AppStorage("diskExplorer.apparentSize") private var apparentSize = false
    @AppStorage("diskExplorer.includeHidden") private var includeHidden = true
    @State private var settings = SettingsManager.shared

    init(unreadableCount: Int? = nil) {
        self.unreadableCount = unreadableCount
    }

    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            OnePlusSettingRow("Enable Diskman", separator: false) {
                Toggle("Enable Diskman", isOn: Binding(get: { settings.isToolEnabled("disk-explorer") },
                    set: { settings.setToolEnabled($0, for: "disk-explorer") }))
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    .disabled(settings.isToolTransitioning("disk-explorer"))
            }.environment(\.onePlusCardPadding, 0).help("Show Diskman in the launcher")
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                OnePlusCard {
                    OnePlusCardHeader("Display", systemImage: "square.grid.2x2")
                    OnePlusSettingRow("Visualization") {
                        OnePlusSelect(choices: DiskChartStyle.allCases.map { ($0.rawValue, $0.rawValue) }, selection: $chartStyle, accessibilityLabel: "Visualization")
                    }
                    OnePlusSettingRow("Measure") {
                        OnePlusSelect(choices: DiskChartMeasure.allCases.map { ($0.rawValue, $0.title) }, selection: $chartMeasure, accessibilityLabel: "Measure")
                    }
                    OnePlusSettingRow("Show apparent file size", separator: false) {
                        Toggle("Show apparent file size", isOn: $apparentSize).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    }.help("File length before storage allocation")
                }
                OnePlusCard {
                    OnePlusCardHeader("Scanning", systemImage: "folder")
                    OnePlusSettingRow("Include hidden files") {
                        Toggle("Include hidden files", isOn: $includeHidden).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    }.help("Include files and folders with hidden names.")
                    OnePlusSettingRow("Disk access", controlWidth: OnePlusMetrics.controlColumn * 2, separator: false) {
                        HStack(spacing: OnePlusMetrics.actionSpacing) {
                            Text(unreadableCount.map { $0 > 0 ? "Needs attention" : "No blocked folders found" } ?? "Not checked")
                                .onePlusText(.mono)
                            Button("Open Settings") { DiskEntryPresentation.openFullDiskAccess() }
                                .buttonStyle(OnePlusButtonStyle(.link, horizontalPadding: 0))
                        }
                    }.help("A scan reports folders that macOS did not let Diskman read.")
                }
            }
        }
    }
}

struct DiskmanAboutPage: View {
    var body: some View {
        OnePlusPage { OnePlusPageHeader(title: "About Diskman", subtitle: "Storage analysis and native disk tools") } content: {
            OnePlusCard {
                OnePlusCardHeader("Diskman")
                VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                    Text("Find large folders and files, review removals, and manage physical disks with macOS tools.").onePlusText(.row)
                        .help("Space used counts allocated blocks once per hard-linked file. APFS clones can share blocks, so removed size may differ from recovered space.")
                    OnePlusKeyValueRow("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                }.padding(OnePlusMetrics.cardPadding)
            }
            OnePlusCard {
                OnePlusCardHeader("Keyboard shortcuts")
                VStack(spacing: 0) {
                    OnePlusKeyValueRow("Rescan", value: "⌘R")
                    OnePlusKeyValueRow("Search Results", value: "⌘F")
                    OnePlusKeyValueRow("Back / Forward", value: "⌘[ / ⌘]")
                    OnePlusKeyValueRow("Open / Quick Look", value: "Return / Space")
                    OnePlusKeyValueRow("Settings", value: "⌘,")
                }.padding(OnePlusMetrics.cardPadding)
            }
            ForEach(DiskExplorerTool.shared.manual, id: \.title) { section in
                OnePlusCard {
                    OnePlusCardHeader(section.title)
                    VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                        ForEach(section.points, id: \.self) { point in
                            Text(point).onePlusText(.row).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(OnePlusMetrics.cardPadding)
                }
            }
        }
    }
}
