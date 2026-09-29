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
    static func name(_ entry: DiskEntry) -> String { entry.kind == .aggregate ? "\(entry.fileCount.formatted()) smaller files" : entry.name }
    static func symbol(_ entry: DiskEntry) -> String {
        switch entry.kind { case .directory: "folder"; case .symbolicLink: "link"; case .aggregate: "square.stack.3d.up"; default: "doc" }
    }
    static func kind(_ entry: DiskEntry) -> String {
        switch entry.kind {
        case .directory: "Folder"
        case .symbolicLink: "Symbolic link"
        case .aggregate: "Grouped files"
        default: UTType(filenameExtension: entry.url.pathExtension)?.localizedDescription ?? "File"
        }
    }
    static func breadcrumbs(to entry: DiskEntry, root: DiskEntry) -> [DiskEntry] {
        var result = [root]
        var node = root
        while node.id != entry.id, let child = node.children.first(where: {
            $0.kind == .directory && (entry.id == $0.id || entry.id.hasPrefix($0.id + "/"))
        }) { result.append(child); node = child }
        return result
    }
    static func find(_ id: String, in root: DiskEntry) -> DiskEntry? {
        if root.id == id { return root }
        if let direct = root.children.first(where: { $0.id == id }) { return direct }
        guard let child = root.children.first(where: { $0.kind == .directory && id.hasPrefix($0.id + "/") }) else { return nil }
        return find(id, in: child)
    }
    static func copy(_ paths: [String]) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
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

struct DiskSizeLabel: View {
    let bytes: Int64
    var accent = false
    var body: some View {
        let parts = bytes.diskSize.split(separator: " ")
        HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.spacing[1]) {
            Text(parts.count > 1 ? parts.dropLast().joined(separator: " ") : bytes.diskSize)
                .font(.system(size: OnePlusTextRole.metric.size(for: .regular), weight: .semibold))
            if parts.count > 1 {
                Text(String(parts.last!)).font(.system(size: OnePlusTextRole.unit.size(for: .regular)))
            }
        }.foregroundStyle(accent ? OnePlusColor.accent : OnePlusColor.ink).monospacedDigit().lineLimit(1)
    }
}

struct DiskEntryTable: View {
    let entries: [DiskEntry]
    let search: String
    let apparent: Bool
    @Binding var selection: Set<String>
    let open: (DiskEntry) -> Void
    let preview: (DiskEntry) -> Void
    let actions: ([DiskEntry]) -> [OnePlusTableAction]
    let remove: ([DiskEntry]) -> Void
    var showsFileCount = false
    @State private var column = 2
    @State private var ascending = false

    static func sorted(_ entries: [DiskEntry], column: Int, ascending: Bool, apparent: Bool) -> [DiskEntry] {
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
            if comparison == .orderedSame { return left.id < right.id }
            return comparison == (ascending ? .orderedAscending : .orderedDescending)
        }
    }
    var body: some View {
        let matches = Self.sorted(entries.filter {
            search.isEmpty || DiskEntryPresentation.name($0).localizedStandardContains(search) ||
                ($0.kind != .aggregate && $0.url.path.localizedStandardContains(search))
        }, column: column, ascending: ascending, apparent: apparent)
        let lookup = Dictionary(uniqueKeysWithValues: matches.map { ($0.id, $0) })
        let columns: [OnePlusGridColumn] = [.init("Name", width: 450), .init("Kind", width: 180),
            .init("Size", width: 120, trailing: true), .init("Modified", width: 180)] +
            (showsFileCount ? [.init("Files", width: 80, trailing: true)] : [])
        OnePlusNativeTable(columns: columns,
                           rows: matches.map { entry in
            OnePlusTableItem(id: entry.id, cells: [DiskEntryPresentation.name(entry), DiskEntryPresentation.kind(entry),
                                                  entry.bytes(apparent: apparent).diskSize,
                                                  DiskEntryPresentation.date.string(from: entry.modifiedAt)] + (showsFileCount ? [entry.fileCount.formatted()] : []),
                             symbol: DiskEntryPresentation.symbol(entry), url: entry.kind == .aggregate ? nil : entry.url)
        }, selection: $selection, sortColumn: column, ascending: ascending,
                           sort: { column = $0; ascending = $1 },
                           open: { $0.compactMap { lookup[$0] }.filter { $0.kind != .aggregate }.forEach(open) },
                           preview: { if let entry = $0.sorted().compactMap({ lookup[$0] }).first, entry.kind != .aggregate { preview(entry) } },
                           remove: { remove($0.compactMap { lookup[$0] }) },
                           actions: { actions($0.sorted().compactMap { lookup[$0] }) })
            .thinScrollIndicators()
            .overlay {
                if matches.isEmpty { OnePlusEmptyState("No matching items", systemImage: "doc.text.magnifyingglass", caption: "Try another search or location.") }
            }
    }
}

struct DiskSelectionInspector: View {
    let entry: DiskEntry?
    let parent: DiskEntry
    let apparent: Bool
    let select: (DiskEntry) -> Void
    let explore: (DiskEntry) -> Void
    let copy: (DiskEntry) -> Void
    let open: (DiskEntry) -> Void
    let preview: (DiskEntry) -> Void
    let actions: ([DiskEntry]) -> [OnePlusTableAction]
    var availableBytes: Int64?

    var body: some View {
        OnePlusCard {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Text("Selection").onePlusText(.captionUpper)
                if let entry {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                            identity(entry).modifier(DiskChartFileActions(entry: entry, actions: actions))
                            facts(entry)
                            if entry.kind == .directory { children(entry) }
                        }
                    }.thinScrollIndicators()
                    Spacer(minLength: 0)
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Button("View contents") { explore(entry) }.buttonStyle(OnePlusButtonStyle(.neutral))
                            .disabled(entry.kind != .directory)
                        Spacer(minLength: 0)
                        Button { copy(entry) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(OnePlusButtonStyle(.icon)).help("Copy Path").accessibilityLabel("Copy Path")
                    }
                } else {
                    OnePlusEmptyState("Select an item", systemImage: "cursorarrow", caption: "Click a tile to see its details.")
                }
            }.padding(OnePlusMetrics.cardPadding).frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
    private func identity(_ entry: DiskEntry) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            Label(entry.name, systemImage: DiskEntryPresentation.symbol(entry)).onePlusText(.sectionTitle).lineLimit(2).help(entry.name)
            Text(entry.url.path).onePlusText(.mono).lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(entry.url.path)
            DiskSizeLabel(bytes: entry.bytes(apparent: apparent)).padding(.top, OnePlusMetrics.actionSpacing)
            HStack {
                Text("Of parent folder")
                Spacer()
                Text((Double(entry.bytes(apparent: apparent)) / Double(max(1, parent.bytes(apparent: apparent)))).formatted(.percent.precision(.fractionLength(1))))
            }.onePlusText(.caption)
            OnePlusUsageBar(value: Double(entry.bytes(apparent: apparent)) / Double(max(1, parent.bytes(apparent: apparent))), color: OnePlusColor.accent)
        }
    }
    private func facts(_ entry: DiskEntry) -> some View {
        VStack(spacing: 0) {
            OnePlusKeyValueRow("Kind", value: DiskEntryPresentation.kind(entry))
            OnePlusKeyValueRow("Files", value: entry.fileCount.formatted(), monospaced: true)
            OnePlusKeyValueRow("Contents", value: "\(entry.children.filter { $0.kind == .directory }.count) folders")
            if let availableBytes { OnePlusKeyValueRow("Free on disk", value: availableBytes.diskSize, monospaced: true) }
        }
    }
    private func children(_ entry: DiskEntry) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            OnePlusColor.lineSoft.frame(height: 1)
            Text("Inside this folder").onePlusText(.caption)
            ForEach(entry.children.sorted { $0.bytes(apparent: apparent) > $1.bytes(apparent: apparent) }.prefix(OnePlusDiskmanMetrics.inspectorChildren)) { child in
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
                }.buttonStyle(OnePlusInteractionStyle()).help(DiskEntryPresentation.name(child))
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
                Text("Select a common location or browse for another folder.").onePlusText(.caption)
                ScrollView {
                    OnePlusCard {
                        location("Home Folder", url: FileManager.default.homeDirectoryForCurrentUser, icon: "house")
                        ForEach(volumes) { volume in location(volume.name, url: volume.url, icon: "externaldrive") }
                    }
                }.thinScrollIndicators()
                    .frame(height: min(CGFloat(volumes.count + 1) * OnePlusMetrics.captionedSettingRow, OnePlusDiskmanMetrics.folderListHeight))
                Button("Browse for folder...", systemImage: "folder.badge.plus", action: browse).buttonStyle(OnePlusButtonStyle())
            }
        } footer: { Button("Cancel") { dismiss() }.buttonStyle(OnePlusButtonStyle(.ghost)).keyboardShortcut(.cancelAction) }
    }
    private func location(_ title: String, url: URL, icon: String) -> some View {
        Button { choose(url) } label: {
            HStack(spacing: OnePlusMetrics.navIconGap) {
                Image(systemName: icon)
                VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                    Text(title).onePlusText(.row)
                    Text(result?.root.url == url ? "\(result!.root.allocatedBytes.diskSize) \(result!.isComplete ? "indexed" : "measured so far")" : "Not indexed")
                        .onePlusText(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right").onePlusText(.caption)
            }.padding(.horizontal, OnePlusMetrics.cardPadding).frame(height: OnePlusMetrics.captionedSettingRow)
        }.buttonStyle(OnePlusInteractionStyle()).help(url.path)
    }
}

struct DiskExplorerSettingsView: View {
    var unreadableCount: Int? = nil
    @AppStorage("diskExplorer.chartStyle") private var chartStyle = DiskChartStyle.treemap.rawValue
    @AppStorage("diskExplorer.chartMeasure") private var chartMeasure = DiskChartMeasure.space.rawValue
    @AppStorage("diskExplorer.apparentSize") private var apparentSize = false
    @AppStorage("diskExplorer.includeHidden") private var includeHidden = true
    @State private var settings = SettingsManager.shared
    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusSettingRow("Enable Diskman", caption: "Show Diskman in the launcher", separator: false) {
                    Toggle("Enable Diskman", isOn: Binding(get: { settings.isToolEnabled("disk-explorer") },
                        set: { settings.setToolEnabled($0, for: "disk-explorer") }))
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .disabled(settings.isToolTransitioning("disk-explorer"))
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Display", systemImage: "square.grid.2x2")
                OnePlusSettingRow("Visualization") {
                    OnePlusSelect(choices: DiskChartStyle.allCases.map { ($0.rawValue, $0.rawValue) }, selection: $chartStyle, accessibilityLabel: "Visualization")
                }
                OnePlusSettingRow("Measure") {
                    OnePlusSelect(choices: DiskChartMeasure.allCases.map { ($0.rawValue, $0.title) }, selection: $chartMeasure, accessibilityLabel: "Measure")
                }
                OnePlusSettingRow("Show apparent file size", caption: "File length before storage allocation", separator: false) {
                    Toggle("Show apparent file size", isOn: $apparentSize).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Scanning", systemImage: "folder")
                OnePlusSettingRow("Include hidden files", separator: false) {
                    Toggle("Include hidden files", isOn: $includeHidden).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Disk access", systemImage: "lock.shield")
                OnePlusSettingRow(unreadableCount.map { $0 > 0 ? "Needs attention" : "No blocked folders found" } ?? "Not checked",
                                  caption: "A scan reports folders that macOS did not let Diskman read.", separator: false) {
                    Button("Open Settings") { DiskEntryPresentation.openFullDiskAccess() }.buttonStyle(OnePlusButtonStyle(.link))
                }
            }
        }
    }
}

struct DiskmanAboutPage: View {
    var body: some View {
        OnePlusPage { OnePlusPageHeader(title: "About Diskman", subtitle: "Storage analysis and native disk tools") } content: {
            OnePlusCard {
                OnePlusCardHeader("Diskman", systemImage: "internaldrive")
                VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                    Text("Find large folders and files, review removals, and manage physical disks with macOS tools.").onePlusText(.row)
                    Text("Space used counts allocated blocks once per hard-linked file. APFS clones can share blocks, so removed size may differ from recovered space.")
                        .onePlusText(.caption)
                    OnePlusKeyValueRow("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                }.padding(OnePlusMetrics.cardPadding)
            }
            OnePlusCard {
                OnePlusCardHeader("Keyboard shortcuts", systemImage: "keyboard")
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
                            Text(guideText(point)).onePlusText(.row).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(OnePlusMetrics.cardPadding)
                }
            }
        }
    }
    private func guideText(_ point: String) -> String {
        if point.hasPrefix("Your Home Folder scans") { return "Choose Home Folder, a mounted volume, or another folder to start a scan." }
        if point.hasPrefix("Click a folder in the chart") { return "Click an item to select it. Double-click a folder to explore it. Use the breadcrumb to go back." }
        return point
    }
}
