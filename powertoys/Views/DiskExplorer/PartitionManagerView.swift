import AppKit
import OnePlusUI
import SwiftUI

/// Partition Manager is the one surface with purposeful motion. Reduce Motion makes every change instant.
enum PartitionMotion {
    static func spring(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.86)
    }
}

enum PartitionMapMetrics {
    static let minimumBlock = OnePlusMetrics.controlHeight * 2
    static let labelledBlock = OnePlusMetrics.controlHeight * 3
    static let blockGap = OnePlusMetrics.spacing[0]
    static let selectionLine = OnePlusMetrics.spacing[0]
    static let inspectorWidth = OnePlusDiskmanMetrics.inspectorWidth
    /// The unused part of a partition block darkens its storage color by this amount; used space keeps the full color.
    static let freeSpaceOpacity = 0.45
    static let progressScrimOpacity = 0.55
}

extension Int64 {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter(); formatter.countStyle = .file; return formatter
    }()
    var diskSize: String { Self.byteFormatter.string(fromByteCount: self) }
}

enum PartitionManagerPage: Hashable { case disks, about }

struct DiskExplorerWindowView: View {
    @MainActor private static var retainedDisks: [ManagedDisk] = []
    @State private var model: DiskManagementModel
    @State private var page = PartitionManagerPage.disks
    @State private var sheet: PartitionSheetRequest?
    @State private var editor: PartitionEditor?
    @State private var refreshTask: Task<Void, Never>?
    @Namespace private var selectionSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let refreshesOnAppear: Bool

    @MainActor init() {
        _model = State(initialValue: DiskManagementModel(disks: Self.retainedDisks))
        refreshesOnAppear = true
    }
    @MainActor init(model: DiskManagementModel, refreshesOnAppear: Bool = false) {
        _model = State(initialValue: model)
        self.refreshesOnAppear = refreshesOnAppear
    }

    var body: some View {
        OnePlusWindowRoot(canvas: .diskExplorer) { sidebar } content: { content }
            .background(WindowAccessor(identifier: "disk-explorer"))
            .background { shortcuts }
            .onAppear { if refreshesOnAppear { refresh() } }
            .onDisappear { refreshTask?.cancel(); refreshTask = nil }
            .onChange(of: model.selection) { _, _ in
                if editor != nil { editor = nil; model.preview = nil }
            }
            .sheet(item: $sheet) { request in
                PartitionOperationSheet(model: model, request: request) { sheet = nil; editor = nil }
            }
            .sheet(item: $model.blockedEject) { DiskBlockedEjectSheet(model: model, blocked: $0) }
            .onOpenToolPage("disk-explorer", perform: openPage)
    }

    private var groupedDisks: [(DiskKind, [ManagedDisk])] {
        [DiskKind.internal, .external, .removable, .image].compactMap { kind in
            let disks = model.disks.filter { $0.kind == kind }
            return disks.isEmpty ? nil : (kind, disks)
        }
    }

    private var sidebar: some View {
        OnePlusSidebar(title: "Partition Manager") {
            ForEach(groupedDisks, id: \.0) { kind, disks in
                OnePlusNavCaption(kind.title)
                ForEach(disks) { disk in diskRow(disk) }
            }
            if model.disks.isEmpty {
                Text(model.isRefreshing ? "Reading disks..." : "No disks found")
                    .onePlusText(.caption).padding(OnePlusMetrics.navPadding)
            }
        } bottom: {
            OnePlusNavRow("About", systemImage: "info.circle", selected: page == .about) { page = .about }
        }
    }

    private func diskRow(_ disk: ManagedDisk) -> some View {
        OnePlusDeviceNavRow(disk.name, subtitle: "\(disk.id) · \(disk.size.diskSize)", systemImage: disk.symbol,
                            selected: page == .disks && model.selection?.diskID == disk.id,
                            locked: disk.protectionReason != nil, accessibilityIdentifier: "partitions.disk.\(disk.id)",
                            action: { page = .disks; select(.disk(disk.id)) }) { EmptyView() }
            .help(disk.protectionReason.map { "\(disk.name), \(disk.id). \($0)" } ?? "\(disk.name), \(disk.id), \(disk.size.diskSize)")
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .disks: disksPage
        case .about: PartitionManagerAboutPage()
        }
    }

    private var disksPage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Partition Manager",
                              subtitle: "\(model.disks.count) disks · \(model.disks.filter { $0.protectionReason == nil }.count) can be changed") {
                OnePlusHeaderActions {
                    Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(OnePlusButtonStyle(.icon)).disabled(model.isBusy || model.isRefreshing || model.isPreview)
                        .help("Refresh disks").accessibilityLabel("Refresh disks")
                }
            }
        } footer: {
            notices
        } content: {
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                diskList
                PartitionInspector(model: model, editor: $editor, sheet: $sheet)
                    .frame(width: PartitionMapMetrics.inspectorWidth).padding(.bottom, OnePlusMetrics.gutter)
            }.frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var diskList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: OnePlusMetrics.cardGap) {
                    ForEach(model.disks) { disk in
                        PartitionDiskCard(disk: disk, model: model, namespace: selectionSpace, select: select).id(disk.id)
                    }
                    if model.disks.isEmpty {
                        OnePlusCard {
                            OnePlusEmptyState(model.isRefreshing ? "Reading disks..." : "No disks found", systemImage: "externaldrive",
                                              caption: "Connect a disk or attach a disk image, then refresh.") {
                                Button("Refresh", action: refresh).buttonStyle(OnePlusButtonStyle()).disabled(model.isRefreshing)
                            }
                        }
                    }
                }.padding(.bottom, OnePlusMetrics.gutter)
            }
            .onePlusScrollIndicators()
            .onAppear { if let id = model.selection?.diskID { proxy.scrollTo(id, anchor: .top) } }
            .onChange(of: model.selection?.diskID) { _, id in
                guard let id else { return }
                withAnimation(PartitionMotion.spring(reduceMotion)) { proxy.scrollTo(id, anchor: .top) }
            }
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private var notices: some View {
        if let error = model.error {
            OnePlusBanner(error, tone: .error) {
                Button("Dismiss") { model.clearMessages() }.buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
            }.accessibilityIdentifier("partitions.error")
        } else if let message = model.message {
            OnePlusBanner(message) {
                Button("Dismiss") { model.clearMessages() }.buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
            }
        }
    }

    private func select(_ selection: PartitionSelection) {
        withAnimation(PartitionMotion.spring(reduceMotion)) { model.selection = selection }
    }
    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await model.refresh()
            if !model.disks.isEmpty { Self.retainedDisks = model.disks }
        }
    }
    private func openPage(_ id: String) {
        switch id {
        case "about": page = .about
        default:
            page = .disks
            if id.hasPrefix("device/") {
                let target = String(id.dropFirst("device/".count))
                if let disk = model.disks.first(where: { $0.id == DiskSafety.wholeDiskID(target) }) {
                    select(disk.partitions.contains { $0.id == target } ? .partition(disk: disk.id, id: target) : .disk(disk.id))
                }
            }
        }
    }
    private var shortcuts: some View {
        Group {
            Button("Refresh") { refresh() }.keyboardShortcut("r")
            ForEach(0..<9, id: \.self) { index in
                Button("Disk \(index + 1)") {
                    if model.disks.indices.contains(index) { page = .disks; select(.disk(model.disks[index].id)) }
                }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
        }.hidden()
    }
}

extension ManagedDisk {
    var symbol: String {
        switch kind {
        case .internal: "internaldrive"
        case .external: "externaldrive"
        case .removable: bus == "Secure Digital" ? "sdcard" : "externaldrive"
        case .image: "opticaldiscdrive"
        }
    }
    var summary: String {
        [id, schemeTitle, size.diskSize, kind == .image ? "Disk image" : bus].joined(separator: " · ")
    }
}

/// Settings content only. The host supplies page chrome, scrolling and density.
struct DiskExplorerSettingsView: View {
    let showsEnableControl: Bool
    @State private var settings = SettingsManager.shared

    init(showsEnableControl: Bool = true) { self.showsEnableControl = showsEnableControl }

    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            if showsEnableControl {
                OnePlusSettingRow("Enable Partition Manager", separator: false) {
                    Toggle("Enable Partition Manager", isOn: Binding(get: { settings.isToolEnabled("disk-explorer") },
                        set: { settings.setToolEnabled($0, for: "disk-explorer") }))
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .disabled(settings.isToolTransitioning("disk-explorer"))
                }.environment(\.onePlusCardPadding, 0)
            }
            OnePlusCard {
                OnePlusCardHeader("Protected disks", systemImage: "lock")
                OnePlusSettingRow("Startup disk and the disk with this app") { Text("Never changed").onePlusText(.mono) }
                OnePlusSettingRow("Internal disks") { Text("Never changed").onePlusText(.mono) }
                OnePlusSettingRow("External1TB, disk6, and disk7", separator: false) { Text("Never changed").onePlusText(.mono) }
            }
        }
    }
}

struct PartitionManagerAboutPage: View {
    var body: some View {
        OnePlusPage { OnePlusPageHeader(title: "About Partition Manager", subtitle: "Native disk and partition tools") } content: {
            OnePlusCard {
                OnePlusCardHeader("Partition Manager")
                VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                    Text("Mount, format, resize, create, and delete partitions with the macOS disk tools.").onePlusText(.row)
                    OnePlusKeyValueRow("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                }.padding(OnePlusMetrics.cardPadding)
            }
            OnePlusCard {
                OnePlusCardHeader("Keyboard shortcuts")
                VStack(spacing: 0) {
                    OnePlusKeyValueRow("Refresh disks", value: "⌘R")
                    OnePlusKeyValueRow("Select disk 1 to 9", value: "⌘1 to ⌘9")
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
