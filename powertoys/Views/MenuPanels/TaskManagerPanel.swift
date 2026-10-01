import Observation
import OnePlusUI
import SwiftUI

nonisolated enum SystemMonitorTrayPage: String, CaseIterable, Identifiable {
    case home, cpu, gpu, memory, network, disk, battery, sensors, processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .sensors: "Sensors"
        case .processes: "Processes"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .sensors: "thermometer.medium"
        case .processes: "list.bullet.rectangle"
        }
    }

    var metrics: Set<SystemMonitorMenuMetric> {
        switch self {
        case .home: Set(SystemMonitorMenuMetric.allCases)
        case .cpu: [.cpu, .thermal]
        case .gpu: [.gpu, .thermal]
        case .memory: [.memory]
        case .network: [.network]
        case .disk: [.disk]
        case .battery: [.battery]
        case .sensors: [.thermal]
        case .processes: []
        }
    }
}

struct SystemMonitorMenuPopoverView: View {
    var maximumHeight: CGFloat?
    private let diagnostic: Bool
    private let defaults: UserDefaults
    private let suppliedRemoteProfiles: [SystemMonitorRemoteProfile]?
    private let onPreferredHeight: (CGFloat) -> Void
    @State private var remoteProfiles: [SystemMonitorRemoteProfile]

    init(
        remoteProfiles: [SystemMonitorRemoteProfile]? = nil,
        diagnostic: Bool = false,
        defaults: UserDefaults = .standard,
        maximumHeight: CGFloat? = nil,
        onPreferredHeight: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.maximumHeight = maximumHeight
        self.defaults = defaults
        self.diagnostic = diagnostic
        let profiles = remoteProfiles ?? []
        suppliedRemoteProfiles = remoteProfiles
        self.onPreferredHeight = onPreferredHeight
        _remoteProfiles = State(initialValue: profiles)
    }

    var body: some View {
        SystemMonitorTrayView(remoteProfiles: suppliedRemoteProfiles ?? remoteProfiles, diagnostic: diagnostic, onPreferredHeight: onPreferredHeight)
        .environment(\.onePlusMenuMaximumHeight, maximumHeight)
        .frame(width: OnePlusMenuMetrics.width)
        .defaultAppStorage(defaults)
        .utilityMotionPolicy()
        .task {
            guard suppliedRemoteProfiles == nil else { return }
            let defaults = defaults
            let profiles = await Task.detached(priority: .userInitiated) {
                SystemMonitorRemoteProfiles.load(defaults: defaults)
            }.value
            guard !Task.isCancelled else { return }
            remoteProfiles = profiles
        }
    }
}

struct SystemMonitorTrayView: View {
    private let diagnostic: Bool
    @AppStorage("systemMonitor.trayPage") private var pageID = SystemMonitorTrayPage.home.rawValue
    private let remoteProfiles: [SystemMonitorRemoteProfile]
    private let onPreferredHeight: (CGFloat) -> Void
    @State private var processModel = TaskManagerMenuProcessModel.shared
    @State private var presentation = TaskManagerMenuPresentation()
    @State private var selectionTask: Task<Void, Never>?

    init(
        remoteProfiles: [SystemMonitorRemoteProfile] = [],
        diagnostic: Bool = false,
        onPreferredHeight: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.remoteProfiles = remoteProfiles
        self.diagnostic = diagnostic
        self.onPreferredHeight = onPreferredHeight
    }

    private var page: SystemMonitorTrayPage { SystemMonitorTrayPage(rawValue: pageID) ?? .home }
    private var selection: Binding<SystemMonitorTrayPage> {
        Binding(get: { page }, set: select)
    }

    private func select(_ destination: SystemMonitorTrayPage) {
        selectionTask?.cancel()
        selectionTask = nil
        guard destination != page else { return }
        if !OnePlusPanelTimings.shared.hasPending("system-monitor", tab: destination.rawValue) {
            OnePlusPanelTimings.shared.begin(panel: "system-monitor", operation: .tabSwitch, tab: destination.rawValue)
        }
        if destination == .processes {
            selectionTask = Task {
                await processModel.prepareForPresentation()
                guard !Task.isCancelled else { return }
                pageID = destination.rawValue
                selectionTask = nil
            }
        } else {
            pageID = destination.rawValue
        }
    }

    var body: some View {
        OnePlusMenuPanel(contentID: pageID) {
            OnePlusMenuTabStrip(
                tabs: SystemMonitorTrayPage.allCases.map {
                    OnePlusMenuTab($0, $0.title, systemImage: $0.symbol,
                                   accessibilityIdentifier: "system-monitor.tray.\($0.rawValue)")
                },
                selection: selection
            )
        } actions: {
            OnePlusMenuOpenApp {
                ToolActionRouter.shared.open(toolID: "system-monitor")
            }
            .accessibilityIdentifier("system-monitor.menu.open-app")
        } content: {
            Group {
                switch page {
                case .home: homePage
                case .processes: TaskManagerMenuProcessesView(model: processModel)
                default:
                    if let state = presentation.pages[page] {
                        TaskManagerMenuDetailPage(page: page, state: state)
                    }
                }
            }
            .modifier(TaskManagerMenuSampling(page: page, presentation: presentation))
        }
        .onOnePlusMenuHeightChange(onPreferredHeight)
        .onePlusPanelTimings(panel: "system-monitor", tab: pageID)
        .focusedValue(\.appOpenSettings) {
            ToolActionRouter.shared.open(toolID: "system-monitor", page: "settings")
        }
        .onOpenToolPage(diagnostic ? "menu.system-monitor" : nil) { id in
            if let destination = SystemMonitorTrayPage(rawValue: id) { select(destination) }
        }
        .onDisappear { selectionTask?.cancel() }
    }

    private var homePage: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            Grid(horizontalSpacing: OnePlusMenuMetrics.tileGap, verticalSpacing: OnePlusMenuMetrics.tileGap) {
                GridRow { tile(.cpu); tile(.gpu); tile(.memory) }
                GridRow { tile(.network).gridCellColumns(2); tile(.disk) }
                GridRow { tile(.sensors).gridCellColumns(2); tile(.battery) }
            }
            FanControlView(owner: "system-monitor-tray-home", compact: true)
            remoteSummary
        }
    }

    @ViewBuilder private func tile(_ page: SystemMonitorTrayPage) -> some View {
        if let state = presentation.pages[page] {
            TaskManagerMenuHomeTile(page: page, state: state, selection: selection)
        }
    }

    private var remoteSummary: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            OnePlusMenuSectionHeader("Remote instances", actionTitle: "Manage", compactAction: true) {
                UserDefaults.standard.set("remote", forKey: "systemMonitor.windowPage")
                ToolActionRouter.shared.open(toolID: "system-monitor")
            }
            TaskManagerRemoteMenuCard(profiles: remoteProfiles)
        }
    }
}

private struct TaskManagerMenuHomeTile: View {
    let page: SystemMonitorTrayPage
    @Bindable var state: TaskManagerMenuPageState
    @Binding var selection: SystemMonitorTrayPage

    var body: some View {
        let data = state.home
        Group {
            switch page {
            case .cpu, .gpu, .memory:
                OnePlusMenuTile(action: { selection = page }) {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                        metricLabel
                        HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.navRowGap) {
                            TaskManagerMenuValueView(parts: data.value)
                            Spacer(minLength: 0)
                            if page != .gpu {
                                Text(data.caption).onePlusText(.caption).lineLimit(1).minimumScaleFactor(page == .memory ? 1 : 0.7)
                                    .fixedSize(horizontal: page == .memory, vertical: false)
                                    .layoutPriority(page == .memory ? 1 : 0)
                                    .accessibilityLabel(data.captionHelp)
                            }
                        }
                    }
                }
                .historyBackground(values: data.history, color: page == .memory ? OnePlusColor.accent : OnePlusColor.chartLine)
                .help(data.captionHelp)
            case .network:
                OnePlusMenuTile(span: 2, height: 34, textured: false, action: { selection = page }) {
                    HStack(spacing: OnePlusMetrics.navRowGap) {
                        metricLabel
                        Spacer(minLength: 0)
                        rate("↓", data.value)
                        rate("↑", data.upload, accent: true)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            case .disk:
                OnePlusMenuTile(height: 34, textured: false, action: { selection = page }) {
                    HStack(spacing: OnePlusMenuMetrics.tileGap) {
                        metricLabel
                        Spacer(minLength: OnePlusMetrics.navRowGap)
                        Text(data.value.value + data.value.unit).onePlusText(.nav, color: OnePlusColor.ink).monospacedDigit()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .help(data.caption)
                .accessibilityValue(data.caption)
            case .sensors:
                OnePlusMenuTile(span: 2, height: 34, textured: false, action: { selection = page }) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        metricLabel
                        Spacer(minLength: OnePlusMetrics.navRowGap)
                        Text(data.value.value).onePlusText(.row).monospacedDigit()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            case .battery:
                OnePlusMenuTile(height: 34, textured: false, action: { selection = page }) {
                    HStack(spacing: OnePlusMenuMetrics.tileGap) {
                        Image(systemName: page.symbol).font(.system(size: OnePlusMenuMetrics.glyphSize)).foregroundStyle(OnePlusColor.secondary)
                        Spacer(minLength: OnePlusMetrics.navRowGap)
                        Text(data.value.value + data.value.unit).onePlusText(.nav, color: OnePlusColor.ink).monospacedDigit()
                        if data.charging { Image(systemName: "bolt.fill").font(.system(size: OnePlusMenuMetrics.glyphSize)).foregroundStyle(OnePlusColor.muted) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            default: EmptyView()
            }
        }
        .accessibilityHint("Show " + page.title + " details")
        .accessibilityIdentifier("system-monitor.tray.summary." + page.rawValue)
    }

    private var metricLabel: some View {
        HStack(spacing: OnePlusMetrics.navRowGap) {
            Image(systemName: page.symbol).font(.system(size: OnePlusMenuMetrics.glyphSize)).accessibilityHidden(true)
            Text(page == .sensors ? "Thermal" : page.title)
                .lineLimit(1).truncationMode(.tail).help(page == .sensors ? "Thermal" : page.title)
        }.onePlusText(page == .cpu || page == .gpu || page == .memory ? .cardTitle : .row,
                      color: OnePlusColor.secondary).layoutPriority(1)
    }

    private func rate(_ arrow: String, _ parts: TaskManagerMenuValue, accent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.navRowGap) {
            Text(arrow).foregroundStyle(accent ? OnePlusColor.accent : OnePlusColor.secondary)
            Text(parts.value).onePlusText(.nav, color: OnePlusColor.ink).monospacedDigit().lineLimit(1)
            if !parts.unit.isEmpty { Text(parts.unit).onePlusText(.caption, color: OnePlusColor.secondary).lineLimit(1) }
        }.fixedSize(horizontal: true, vertical: false).layoutPriority(2)
    }
}

private struct TaskManagerMenuValueView: View, Equatable {
    let parts: TaskManagerMenuValue
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.navRowGap) {
            Text(parts.value).onePlusText(.metric).monospacedDigit()
            if !parts.unit.isEmpty { Text(parts.unit).onePlusText(.unit) }
        }.lineLimit(1).minimumScaleFactor(0.7)
    }
}

private struct TaskManagerMenuDetailPage: View {
    let page: SystemMonitorTrayPage
    let state: TaskManagerMenuPageState
    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            TaskManagerMenuHero(page: page, state: state)
            if page == .disk {
                OnePlusMenuCard {
                    VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                        HStack { Text("Disk activity").onePlusText(.cardTitle); Spacer(); Text("MB/s").onePlusText(.caption, color: OnePlusColor.secondary) }
                        TaskManagerMenuChart(page: page, state: state)
                    }
                }
            }
            if page == .sensors {
                FanControlView(owner: "system-monitor-tray-sensors", compact: true)
            } else {
                TaskManagerMenuDetailRows(page: page, state: state)
            }
        }
    }
}

private struct TaskManagerMenuHero: View {
    let page: SystemMonitorTrayPage
    @Bindable var state: TaskManagerMenuPageState
    private var title: String {
        switch page {
        case .cpu: "CPU usage"; case .gpu: "GPU usage"; case .memory: "Memory used"
        case .network: "Download"; case .disk: "System disk"; case .battery: "Battery"
        case .sensors: "Thermal pressure"; default: page.title
        }
    }
    var body: some View {
        let data = state.hero
        OnePlusMenuCard(textured: true) {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack {
                    Label(title, systemImage: page.symbol).onePlusText(.caption)
                    Spacer(minLength: OnePlusMetrics.navRowGap)
                    if page != .gpu && page != .sensors {
                        Text(data.caption).onePlusText(.caption).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }.help(data.caption)
                HStack(alignment: .firstTextBaseline) {
                    TaskManagerMenuValueView(parts: data.value).equatable()
                    Spacer(minLength: OnePlusMetrics.actionSpacing)
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        ForEach(data.accessories, id: \.title) { reading in
                            HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.navRowGap) {
                                Text(reading.title).onePlusText(.caption)
                                Text(reading.value).onePlusText(.mono).lineLimit(1)
                            }
                        }
                    }
                }
                if page == .disk {
                    OnePlusUsageBar(value: data.usage).accessibilityLabel("Disk usage")
                } else {
                    TaskManagerMenuChart(page: page, state: state)
                }
            }
        }
    }
}

private struct TaskManagerMenuChart: View {
    let page: SystemMonitorTrayPage
    @Bindable var state: TaskManagerMenuPageState
    var body: some View {
        let data = state.chart
        VStack(spacing: OnePlusMetrics.navRowGap) {
            if page == .network {
                HStack { Spacer(); Text("MB/s").onePlusText(.caption, color: OnePlusColor.secondary) }
            }
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                GeometryReader { proxy in
                    ForEach(data.labels.indices, id: \.self) { index in
                        let fraction = CGFloat(index) / CGFloat(data.labels.count - 1)
                        let y = min((fraction * proxy.size.height).rounded(.down), (proxy.size.height - 1).rounded(.down)) + 0.5
                        Text(data.labels[index]).frame(width: proxy.size.width, alignment: .trailing)
                            .position(x: proxy.size.width / 2, y: y)
                    }
                }.onePlusText(.caption).lineLimit(1)
                    .frame(width: [.sensors, .network, .disk].contains(page) ? OnePlusMetrics.titleRow : OnePlusMetrics.compactControlHeight)
                    .allowsHitTesting(false)
                TaskManagerHistoryChart(values: data.primary, secondary: data.secondary, range: 0...data.ceiling,
                                        unit: page == .memory ? "GB" : page == .network || page == .disk ? "B/s" : page == .sensors ? "" : "%",
                                        compact: true, stepped: page == .sensors,
                                        primaryColor: page == .network || page == .disk ? OnePlusColor.chartLine : OnePlusColor.accent)
            }.frame(height: OnePlusMetrics.searchHeight * 2).padding(.vertical, OnePlusMetrics.menuTileRadius)
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Text("−2 min")
                Spacer(minLength: OnePlusMetrics.navRowGap)
                if page == .network || page == .disk {
                    Label(page == .network ? "Download" : "Read", systemImage: "minus").foregroundStyle(OnePlusColor.chartLine)
                    Label(page == .network ? "Upload" : "Write", systemImage: "minus").foregroundStyle(OnePlusColor.accent)
                    Spacer(minLength: OnePlusMetrics.navRowGap)
                }
                Text("Now")
            }.onePlusText(.caption)
        }
    }
}

private struct TaskManagerMenuDetailRows: View {
    let page: SystemMonitorTrayPage
    @Bindable var state: TaskManagerMenuPageState
    private var title: String {
        switch page {
        case .cpu: "Load average"; case .gpu: "Graphics"; case .memory: "Allocation"
        case .network: "Interface"; case .disk: "Disk details"; case .battery: "Battery details"
        default: page.title
        }
    }
    var body: some View {
        let rows = state.rows
        OnePlusMenuCard {
            VStack(spacing: 0) {
                HStack { Text(title).onePlusText(.cardTitle); Spacer() }.padding(.bottom, OnePlusMenuMetrics.tileGap)
                OnePlusRule()
                ForEach(rows, id: \.title) { row in
                    TaskManagerMenuDetailRow(reading: row, separator: row.title != rows.last?.title).equatable()
                }
            }
        }
    }
}

private struct TaskManagerMenuDetailRow: View, Equatable {
    let reading: TaskManagerMenuReading
    let separator: Bool
    var body: some View {
        OnePlusKeyValueRow(reading.title, value: reading.value, monospaced: true)
            .onePlusRowHover()
            .overlay(alignment: .bottom) { if separator { OnePlusRule() } }
    }
}

private struct TaskManagerMenuProcessRequest: Hashable {
    let generation: Int
    let search: String
    let visible: Bool
}

private struct TaskManagerMenuSampling: ViewModifier {
    let page: SystemMonitorTrayPage
    let presentation: TaskManagerMenuPresentation
    @Environment(\.onePlusIsVisible) private var isVisible

    func body(content: Content) -> some View {
        content
            .onChange(of: isVisible, initial: true) {
                if isVisible {
                    presentation.start()
                    SystemMonitorService.shared.startDetailed(owner: "tray", metrics: page.metrics)
                } else {
                    presentation.stop()
                    SystemMonitorService.shared.stopDetailed(owner: "tray")
                }
            }
            .onChange(of: page) {
                if isVisible { SystemMonitorService.shared.updateDetailed(owner: "tray", metrics: page.metrics) }
            }
            .onDisappear {
                presentation.stop()
                SystemMonitorService.shared.stopDetailed(owner: "tray")
            }
    }
}

@Observable
final class TaskManagerMenuProcessModel {
    static let shared = TaskManagerMenuProcessModel()
    @ObservationIgnored let sampler = SystemMonitorProcessSampler()
    @ObservationIgnored private var initialPreparation: Task<Void, Never>?
    private(set) var hasPreparedSnapshot = false
    var processes: [SystemMonitorProcess] = []
    var rows: [SystemMonitorProcessHierarchy.Row] = []
    var footerTitle = "All processes →"
    @ObservationIgnored var lastPublication: ContinuousClock.Instant?
    var generation = 0
    var search = ""

    func prepareForPresentation() async {
        guard !hasPreparedSnapshot else { return }
        if let initialPreparation { await initialPreparation.value; return }
        let task = Task {
            let processes = await sampler.sample()
            let result = await SystemMonitorProcessRows.prepareOffMain(
                processes, search: search, hierarchy: false, column: .cpu, descending: true
            )
            self.processes = processes
            rows = result.rows
            footerTitle = "All " + String(processes.count) + " processes →"
            lastPublication = .now
            hasPreparedSnapshot = true
            generation &+= 1
        }
        initialPreparation = task
        await task.value
        initialPreparation = nil
    }
}

private struct TaskManagerMenuProcessesView: View {
    @Bindable var model: TaskManagerMenuProcessModel
    @Environment(\.onePlusIsVisible) private var isVisible

    private var request: TaskManagerMenuProcessRequest {
        TaskManagerMenuProcessRequest(generation: model.generation, search: model.search, visible: isVisible)
    }

    var body: some View {
        VStack(spacing: OnePlusMetrics.actionSpacing) {
            TaskManagerSearchField(prompt: "Find a process…", text: $model.search, width: OnePlusMenuMetrics.bodyWidth)

            OnePlusMenuCard(padded: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Process").padding(.leading, OnePlusMetrics.compactControlHeight)
                        Spacer()
                        Text("CPU").frame(width: 52, alignment: .trailing)
                        Text("Memory").frame(width: 72, alignment: .trailing)
                    }
                    .onePlusText(.tableHeader)
                    .padding(.horizontal, OnePlusMenuMetrics.bodyInset)
                    .frame(height: OnePlusTable.rowHeight(.compact))
                    .background(OnePlusColor.sidebar)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if model.rows.isEmpty {
                                Text(model.hasPreparedSnapshot ? "No matching processes" : "Reading processes…")
                                    .onePlusText(.caption)
                                    .frame(maxWidth: .infinity, minHeight: OnePlusTable.rowHeight(.compact))
                            }
                            ForEach(model.rows) { row in
                                TaskManagerMenuProcessRow(row: row).equatable()
                            }
                        }
                    }
                    .frame(height: OnePlusTable.rowHeight(.compact) * CGFloat(min(max(model.rows.count, 1), 8)))
                    .thinScrollIndicators()

                    Button { TaskManagerMenuProcessRow.openProcesses() } label: {
                        Text(model.footerTitle).onePlusText(.caption)
                            .frame(maxWidth: .infinity, minHeight: OnePlusTable.rowHeight(.compact), alignment: .trailing)
                            .padding(.horizontal, OnePlusMenuMetrics.bodyInset)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.menuTileRadius))
                }
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            await model.prepareForPresentation()
            guard !Task.isCancelled else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                let processes = await model.sampler.sample()
                guard !Task.isCancelled else { return }
                model.processes = processes
                model.generation &+= 1
            }
        }
        .task(id: request) { await prepareRows(request) }
    }

    private func prepareRows(_ request: TaskManagerMenuProcessRequest) async {
        guard isVisible else { return }
        if let lastPublication = model.lastPublication {
            try? await Task.sleep(until: lastPublication.advanced(by: TaskManagerMenuPresentation.minimumUpdateInterval), clock: .continuous)
        }
        guard !Task.isCancelled else { return }
        let processes = model.processes
        let result = await SystemMonitorProcessRows.prepareOffMain(
            processes,
            search: request.search,
            hierarchy: false,
            column: .cpu,
            descending: true
        )
        guard !Task.isCancelled, self.request == request else { return }
        if model.rows != result.rows { model.rows = result.rows }
        let footer = "All " + String(processes.count) + " processes →"
        if model.footerTitle != footer { model.footerTitle = footer }
        model.lastPublication = .now
    }
}

private struct TaskManagerMenuProcessRow: View, Equatable {
    let row: SystemMonitorProcessHierarchy.Row

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row.id == rhs.row.id && lhs.row.displayName == rhs.row.displayName
            && lhs.row.symbol == rhs.row.symbol && lhs.row.cpuText == rhs.row.cpuText
            && lhs.row.memoryText == rhs.row.memoryText
    }

    var body: some View {
        Button { Self.openProcesses() } label: {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Image(systemName: row.symbol).onePlusText(.caption)
                    .frame(width: OnePlusMetrics.navIcon, height: OnePlusMetrics.navIcon)
                Text(row.displayName).onePlusText(.caption, color: OnePlusColor.ink).lineLimit(1)
                Spacer(minLength: OnePlusMetrics.navRowGap)
                Text(row.cpuText).frame(width: 52, alignment: .trailing)
                Text(row.memoryText).frame(width: 72, alignment: .trailing)
            }
            .onePlusText(.mono)
            .padding(.horizontal, OnePlusMenuMetrics.bodyInset)
            .frame(maxWidth: .infinity, minHeight: OnePlusTable.rowHeight(.compact))
            .contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.menuTileRadius))
        .overlay(alignment: .bottom) { OnePlusRule() }
    }

    static func openProcesses() {
        UserDefaults.standard.set("processes", forKey: "systemMonitor.windowPage")
        ToolActionRouter.shared.open(toolID: "system-monitor")
    }
}
