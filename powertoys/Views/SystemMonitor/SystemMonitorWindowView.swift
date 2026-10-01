import OnePlusUI
import SwiftUI

private struct TaskManagerVisibilityBinding: View {
    @Environment(\.onePlusIsVisible) private var sharedVisibility
    @Binding var isVisible: Bool

    var body: some View {
        Color.clear
            .onAppear { isVisible = sharedVisibility }
            .onChange(of: sharedVisibility) { _, visible in isVisible = visible }
    }
}

enum SystemMonitorPalette {
    static let accent = TaskManagerTheme.accent
    static let teal = TaskManagerTheme.ink
    static let coral = TaskManagerTheme.accent
    static let gold = TaskManagerTheme.ink
    static let orange = TaskManagerTheme.ink
    static let cyan = TaskManagerTheme.ink
    static let green = TaskManagerTheme.ink
    static let blue = TaskManagerTheme.ink

    static func surface(_ tint: Color = TaskManagerTheme.ink, radius: CGFloat = 9) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(TaskManagerTheme.card)
            TaskManagerDitherTexture()
                .clipShape(RoundedRectangle(cornerRadius: radius))
        }
    }
}

struct GPUCardIcon: View {
    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(lineWidth: 1.2)
                .overlay {
                    HStack(spacing: 1.5) {
                        Circle().strokeBorder(lineWidth: 0.9)
                        Circle().strokeBorder(lineWidth: 0.9)
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2.5)
                }
                .frame(width: 12, height: 9)
            RoundedRectangle(cornerRadius: 0.5).frame(width: 1.5, height: 4)
        }
        .frame(width: 15, height: 13)
        .accessibilityHidden(true)
    }
}

enum SystemMonitorPage: String, CaseIterable, Identifiable {
    case overview, processes, cpu, gpu, memory, network, disk, battery, sensors
    case remote, report, about, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .processes: "Processes"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .sensors: "Sensors"
        case .remote: "Remote stats"
        case .report: "System Report"
        case .about: "About"
        case .settings: "Settings"
        }
    }

    static func resolve(_ value: String) -> Self? {
        Self(rawValue: value) ?? allCases.first { $0.title == value }
    }

    var detailedMetrics: Set<SystemMonitorMenuMetric> {
        switch self {
        case .overview: Set(SystemMonitorMenuMetric.allCases)
        case .cpu: [.cpu, .thermal]
        case .gpu: [.gpu, .thermal]
        case .memory: [.memory]
        case .network: [.network]
        case .disk: [.disk]
        case .battery: [.battery]
        case .sensors: [.thermal]
        case .processes, .remote, .report, .about, .settings: []
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .processes: "list.bullet.rectangle"
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .sensors: "thermometer.medium"
        case .remote: "server.rack"
        case .report: "doc.text.magnifyingglass"
        case .about: "info.circle"
        case .settings: "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .report: "Hardware, network, and software information"
        case .settings: "Menu bar and monitoring preferences"
        case .about: "Task Manager"
        default: TaskManagerHardwareSummary.current
        }
    }

    static let primary: [Self] = [.overview, .processes]
    static let metrics: [Self] = [.cpu, .gpu, .memory, .network, .disk, .battery, .sensors]
    static let secondary: [Self] = [.remote, .report]
    static let bottom: [Self] = [.about, .settings]
}

struct SystemMonitorWindowView: View {
    private let reportSnapshot: [TaskManagerReportCategory]
    private let loadsRemoteProfiles: Bool
    @State private var remoteProfiles: [SystemMonitorRemoteProfile]
    @AppStorage("systemMonitor.windowPage") private var pageID = SystemMonitorPage.overview.rawValue
    @AppStorage("systemMonitor.processHierarchy") private var processHierarchy = false
    @AppStorage("systemMonitor.historyMinutes") private var historyMinutes = 2
    @State private var processSearch = ""
    @State private var reportSearch = ""
    @State private var reportAction: TaskManagerSystemReportAction?
    @State private var processSearchFocusTrigger = 0
    @State private var remoteAddRequest = 0
    @State private var isWindowActive = false

    init(
        reportSnapshot: [TaskManagerReportCategory] = [],
        remoteProfiles: [SystemMonitorRemoteProfile]? = nil
    ) {
        self.reportSnapshot = reportSnapshot
        loadsRemoteProfiles = remoteProfiles == nil
        _remoteProfiles = State(initialValue: remoteProfiles ?? [])
    }

    private var page: SystemMonitorPage { SystemMonitorPage.resolve(pageID) ?? .overview }
    private var service: SystemMonitorService { .shared }
    private func chartHistory(_ metric: SystemMonitorMenuMetric) -> SystemMonitorWindowHistory {
        service.history.windowValues(for: metric, minutes: historyMinutes)
    }
    private var historySampleCapacity: Int { historyMinutes == 1 ? 60 : SystemMonitorHistory.capacity }

    var body: some View {
        OnePlusWindowRoot(canvas: .systemMonitor) {
            sidebar
        } content: {
            OnePlusPage(scrolls: false) {
                header
            } content: {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(TaskManagerVisibilityBinding(isVisible: $isWindowActive))
            .onePlusLiveUpdates(includeOccluded: true)
        }
        .onePlusDensity(.compact)
        .background(WindowAccessor(identifier: "system-monitor"))
        .onAppear {
            pageID = page.rawValue
            updateSamplingForWindowVisibility()
        }
        .onChange(of: isWindowActive) { _, _ in
            updateSamplingForWindowVisibility()
        }
        .onDisappear { service.stopDetailed() }
        .onOpenToolPage("system-monitor") { requestedPage in
            guard let destination = SystemMonitorPage.resolve(requestedPage) else { return }
            pageID = destination.rawValue
        }
        .task {
            guard loadsRemoteProfiles else { return }
            let profiles = await Task.detached(priority: .userInitiated) {
                SystemMonitorRemoteProfiles.load()
            }.value
            guard !Task.isCancelled else { return }
            remoteProfiles = profiles
        }
        .overlay(alignment: .topLeading) {
            Button("") {
                pageID = SystemMonitorPage.processes.rawValue
                processSearchFocusTrigger &+= 1
            }
            .keyboardShortcut("k", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func updateSamplingForWindowVisibility() {
        if isWindowActive {
            // Keep all charts warm while the window is visible; only the active page observes.
            service.startDetailed()
        } else {
            service.stopDetailed()
        }
    }

    private var sidebar: some View {
        OnePlusSidebar(title: "Task Manager", titleAccessibilityIdentifier: "task-manager.sidebar.title") {
            sidebarGroup(SystemMonitorPage.primary)
            sidebarBreak
            sidebarGroup(SystemMonitorPage.metrics)
            sidebarBreak
            sidebarGroup(SystemMonitorPage.secondary)
        } bottom: {
            sidebarGroup(SystemMonitorPage.bottom)
        }
        .accessibilityIdentifier("task-manager.sidebar")
    }

    private func sidebarGroup(_ pages: [SystemMonitorPage]) -> some View {
        VStack(spacing: OnePlusMetrics.navRowGap) {
            ForEach(pages) { item in
                OnePlusNavRow(
                    item.title,
                    systemImage: item.icon,
                    selected: page == item,
                    count: item == .remote && !remoteProfiles.isEmpty ? remoteProfiles.count : nil
                ) {
                    pageID = item.rawValue
                }
                .accessibilityIdentifier(item == .remote ? "task-manager.sidebar.remote-stats" : "task-manager.sidebar.\(item.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sidebarBreak: some View {
        OnePlusColor.lineSoft
            .frame(height: 1)
            .padding(.vertical, 9)
    }

    @ViewBuilder
    private var header: some View {
        switch page {
        case .processes:
            TaskManagerHeader(title: page.title, subtitle: page.subtitle) {
                HStack(spacing: 14) {
                    HStack(spacing: 7) {
                        Text("Hierarchy")
                            .font(.system(size: 9))
                            .foregroundStyle(TaskManagerTheme.secondary)
                        Toggle("Hierarchy", isOn: $processHierarchy)
                            .labelsHidden()
                            .toggleStyle(OnePlusSwitchStyle())
                    }
                    TaskManagerSearchField(
                        prompt: "Search name, path, or PID",
                        text: $processSearch,
                        focusTrigger: processSearchFocusTrigger,
                        accessibilityIdentifier: "task-manager.process.search"
                    )
                }
            }
        case .report:
            TaskManagerHeader(title: page.title, subtitle: page.subtitle) {
                HStack(spacing: 8) {
                    TaskManagerSearchField(prompt: "Search all system information", text: $reportSearch, width: 320)
                    reportButton("doc.on.doc", label: "Copy current report") { reportAction = .copy }
                    OnePlusMenuButton(
                        "Export system report", systemImage: "square.and.arrow.down", variant: .borderedIcon,
                        items: [
                            .item(OnePlusPopupMenuItem("Save Text Report…") { reportAction = .exportText }),
                            .item(OnePlusPopupMenuItem("Save JSON Report…") { reportAction = .exportJSON }),
                        ]
                    )
                }
            }
        case .cpu, .gpu, .memory, .network, .disk, .battery, .sensors:
            TaskManagerHeader(page.title, subtitle: page.subtitle)
        case .remote:
            TaskManagerHeader(title: page.title, subtitle: page.subtitle) {
                Button {
                    remoteAddRequest &+= 1
                } label: {
                    Label("Add host", systemImage: "plus")
                }
                .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
                .accessibilityIdentifier("system-monitor.remote.add-host")
            }
        default:
            TaskManagerHeader(page.title, subtitle: page.subtitle)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .overview:
            SystemMonitorObservationScope { scrollPage { overviewPage } }
        case .processes:
            SystemMonitorProcessesView(
                search: $processSearch,
                hierarchy: $processHierarchy,
                showsToolbar: false
            )
        case .cpu:
            SystemMonitorObservationScope { scrollPage { cpuPage } }
        case .gpu:
            SystemMonitorObservationScope { scrollPage { gpuPage } }
        case .memory:
            SystemMonitorObservationScope { scrollPage { memoryPage } }
        case .network:
            SystemMonitorObservationScope { scrollPage { networkPage } }
        case .disk:
            SystemMonitorObservationScope { scrollPage { diskPage } }
        case .battery:
            SystemMonitorObservationScope { scrollPage { batteryPage } }
        case .sensors:
            SystemMonitorObservationScope { scrollPage { sensorsPage } }
        case .remote:
            SystemMonitorRemoteView(
                addRequest: remoteAddRequest,
                initialProfiles: remoteProfiles
            ) { remoteProfiles = $0 }
        case .report:
            TaskManagerSystemReportView(
                search: $reportSearch,
                requestedAction: $reportAction,
                initialCategories: reportSnapshot
            )
        case .about:
            scrollPage { aboutPage }
        case .settings:
            scrollPage { SystemMonitorSettingsContent() }
        }
    }

    private func scrollPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .thinScrollIndicators()
    }

    private enum MetricFooter {
        case none
        case disk(Double?)
        case battery(Int?)
        case thermal(String?)
    }

    private var overviewPage: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 4), spacing: 10) {
                metricCard(.cpu, value: percent(service.snapshot?.cpuUsage), detail: "Across \(ProcessInfo.processInfo.activeProcessorCount) cores",
                           values: chartHistory(.cpu).values, range: 0...100)
                metricCard(.gpu, value: percent(service.snapshot?.gpuUsage), detail: "Graphics utilization",
                           values: chartHistory(.gpu).values, range: 0...100)
                metricCard(.memory, value: service.snapshot?.memoryUsage.percent ?? "—", detail: memoryDetail,
                           values: chartHistory(.memory).memoryPercent, range: 0...100, accent: memoryIsHigh)
                metricCard(.network, value: service.snapshot?.networkDownload.map(Self.rate) ?? "—",
                           detail: "↓ Download · ↑ \(service.snapshot?.networkUpload.map(Self.rate) ?? "—")",
                           values: chartHistory(.network).values,
                           secondary: chartHistory(.network).secondary, range: networkRange)
                metricCard(.disk, value: service.snapshot?.diskUsage.percent ?? "—", detail: "\(diskAvailable) available",
                           footer: .disk(service.snapshot?.diskUsage))
                metricCard(.battery, value: service.snapshot?.batteryPercent.map { "\($0)%" } ?? "—", detail: batteryDetail,
                           footer: .battery(service.snapshot?.batteryPercent))
                metricCard(.thermal, title: "Thermal", value: service.snapshot?.thermalState ?? "—",
                           detail: "System thermal pressure", footer: .thermal(service.snapshot?.thermalState))
                metricCard(.cpu, title: "Load average", value: loadValue, detail: "1 minute · \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs",
                           values: chartHistory(.cpu).load, range: loadRange)
                    .help(loadExplanation)
            }

            remoteOverview

            LazyVGrid(columns: detailColumns, spacing: 10) {
                SystemMonitorOverviewProcessesView {
                    pageID = SystemMonitorPage.processes.rawValue
                } onSelect: { process in
                    pageID = SystemMonitorPage.processes.rawValue
                    processSearch = String(process.pid)
                }
                memoryAllocation
            }
        }
    }

    private func metricCard(
        _ metric: SystemMonitorMenuMetric,
        title: String? = nil,
        value: String,
        detail: String,
        values: [Double] = [],
        secondary: [Double] = [],
        range: ClosedRange<Double> = 0...100,
        accent: Bool = false,
        footer: MetricFooter = .none
    ) -> some View {
        Button {
            pageID = switch metric {
            case .cpu: SystemMonitorPage.cpu.rawValue
            case .gpu: SystemMonitorPage.gpu.rawValue
            case .memory: SystemMonitorPage.memory.rawValue
            case .network: SystemMonitorPage.network.rawValue
            case .disk: SystemMonitorPage.disk.rawValue
            case .battery: SystemMonitorPage.battery.rawValue
            case .thermal: SystemMonitorPage.sensors.rawValue
            }
        } label: {
            TaskManagerPanel(textured: true) {
                ZStack(alignment: .bottom) {
                    if !values.isEmpty {
                        TaskManagerHistoryChart(
                            values: values,
                            secondary: secondary,
                            range: range,
                            unit: metric == .network ? "/s" : "%",
                            compact: true,
                            sampleCapacity: historySampleCapacity,
                            primaryColor: accent ? TaskManagerTheme.accent : TaskManagerTheme.ink.opacity(0.76)
                        )
                            .frame(height: 33)
                            .padding(.horizontal, 11)
                            .padding(.bottom, 8)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            monitorIcon(metric)
                                .foregroundStyle(TaskManagerTheme.secondary)
                            Text(title ?? metric.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(TaskManagerTheme.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(TaskManagerTheme.muted)
                        }
                        metricValue(value)
                            .padding(.top, 7)
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(TaskManagerTheme.secondary)
                            .lineLimit(1)
                            .padding(.top, 4)
                        Spacer(minLength: 8)
                        metricFooter(footer)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 11)
                    .padding(.bottom, 9)
                }
            }
            .frame(height: 124)
            .contentShape(Rectangle())
        }
        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: TaskManagerTheme.panelRadius))
        .accessibilityLabel("Open \(title ?? metric.title), \(value)")
    }

    @ViewBuilder
    private func metricFooter(_ footer: MetricFooter) -> some View {
        switch footer {
        case .none:
            Spacer(minLength: 20)
        case .disk(let usage):
            Text("\(service.snapshot?.diskUsed.map(Self.diskBytes) ?? "—") / \(service.snapshot?.diskTotal.map(Self.diskBytes) ?? "—") used")
                .onePlusText(.caption)
                .padding(.bottom, 6)
            OnePlusUsageBar(value: (usage ?? 0) / 100)
                .accessibilityLabel(usage.map { "Disk, \(Int($0.rounded())) percent used" } ?? "Disk usage unavailable")
        case .battery(let percent):
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < (percent ?? 0) / 10 ? TaskManagerTheme.ink.opacity(0.76) : TaskManagerTheme.lineSoft)
                }
            }
            .frame(height: 8)
            .accessibilityLabel(percent.map { "Battery, \($0) percent" } ?? "Battery charge unavailable")
        case .thermal(let state):
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Self.thermalBand(state).map { index <= $0 } == true
                            ? TaskManagerTheme.ink.opacity(0.76) : TaskManagerTheme.lineSoft)
                }
            }
            .frame(height: 8)
            .accessibilityLabel(state.map { "Thermal pressure, \($0)" } ?? "Thermal pressure unavailable")
        }
    }

    private var remoteOverview: some View {
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Remote instances", action: "Manage") { pageID = SystemMonitorPage.remote.rawValue }
            if remoteProfiles.isEmpty {
                Button { pageID = SystemMonitorPage.remote.rawValue } label: {
                    TaskManagerPanel {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 13))
                                .foregroundStyle(TaskManagerTheme.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("No remote hosts").font(.system(size: 11, weight: .medium))
                                Text("Add a Linux, macOS, or Windows SSH host in Remote stats.")
                                    .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                            }
                            Spacer()
                            Text("Add  →").font(.system(size: 9)).foregroundStyle(TaskManagerTheme.muted)
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(height: 58)
                }
                .buttonStyle(.plain)
            } else if remoteProfiles.count == 1, let profile = remoteProfiles.first {
                TaskManagerRemoteCard(
                    profile: profile,
                    reading: nil,
                    state: "Offline",
                    onTerminal: { SystemMonitorRemoteTerminal.open(profile) },
                    primaryTitle: "Open App",
                    primarySymbol: "arrow.right",
                    onPrimary: { pageID = SystemMonitorPage.remote.rawValue }
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(remoteProfiles) { profile in
                            TaskManagerRemoteCard(
                                profile: profile,
                                reading: nil,
                                state: "Offline",
                                onTerminal: { SystemMonitorRemoteTerminal.open(profile) },
                                primaryTitle: "Open App",
                                primarySymbol: "arrow.right",
                                onPrimary: { pageID = SystemMonitorPage.remote.rawValue }
                            )
                            .frame(width: 402)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.visible)
                .thinScrollIndicators()
            }
        }
    }

    private var memoryAllocation: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Memory allocation", action: "Details") { pageID = SystemMonitorPage.memory.rawValue }
            memoryAllocationPanel()
                .frame(height: 203)
        }
    }

    private func memoryAllocationPanel(header: String? = nil) -> some View {
        return TaskManagerPanel {
            VStack(alignment: .leading, spacing: 0) {
                if let header { OnePlusCardHeader(header) }
                if let allocation = service.memoryAllocation {
                    VStack(alignment: .leading, spacing: 10) {
                        OnePlusSegmentBar(values: [Double(allocation.applications), Double(allocation.wired),
                                                   Double(allocation.compressed), Double(allocation.available)])
                        allocationRow("Applications", value: Self.bytes(allocation.applications))
                        allocationRow("Wired", value: Self.bytes(allocation.wired))
                        allocationRow("Compressed", value: Self.bytes(allocation.compressed))
                        Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                        allocationRow("Available", value: Self.bytes(allocation.available))
                    }
                    .padding(12)
                } else {
                    OnePlusEmptyState("Memory data unavailable", systemImage: "memorychip")
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func detailHero(
        label: String,
        value: String,
        unit: String = "",
        detail: String,
        values: [Double],
        secondary: [Double] = [],
        range: ClosedRange<Double>,
        upperScaleLabel: String? = nil,
        middleScaleLabel: String? = nil,
        lowerScaleLabel: String? = nil,
        scaleLabels: [String] = [],
        seriesLabels: [String] = [],
        stepped: Bool = false,
        chartHeight: CGFloat = 138,
        stats: [(String, String)]
    ) -> some View {
        let displayed = unit.isEmpty ? TaskManagerMetricText.parts(value) : (value, unit)
        return TaskManagerPanel(textured: true) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                        HStack(spacing: OnePlusMetrics.spacing[2]) {
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(TaskManagerTheme.secondary)
                            if !detail.isEmpty {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(TaskManagerTheme.muted)
                                    .help(detail)
                                    .accessibilityLabel(detail)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(displayed.0)
                                .onePlusText(.metric)
                            if !displayed.1.isEmpty {
                                Text(displayed.1).onePlusText(.unit)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 20) {
                        ForEach(stats.indices, id: \.self) { index in
                            HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.spacing[2]) {
                                Text(stats[index].0).font(.system(size: 8)).foregroundStyle(TaskManagerTheme.muted)
                                Text(stats[index].1)
                                    .font(.system(size: 12))
                                    .monospacedDigit()
                                    .foregroundStyle(index == stats.count - 1 && stats[index].1 == "Elevated" ? TaskManagerTheme.accent : TaskManagerTheme.ink)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                TaskManagerHistoryChart(
                    values: values,
                    secondary: secondary,
                    range: range,
                    unit: unit,
                    sampleCapacity: historySampleCapacity,
                    stepped: stepped,
                    upperScaleLabel: upperScaleLabel,
                    middleScaleLabel: middleScaleLabel,
                    lowerScaleLabel: lowerScaleLabel,
                    scaleLabels: scaleLabels
                )
                    .frame(height: chartHeight)
                    .padding(.vertical, OnePlusMetrics.spacing[2])
                    .padding(.horizontal, 12)
                HStack {
                    Text("−\(historyMinutes == 1 ? 1 : 2) min")
                    Spacer()
                    Text("Now")
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(TaskManagerTheme.muted)
                .padding(.leading, 74)
                .padding(.trailing, 12)
                if !seriesLabels.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(seriesLabels.indices, id: \.self) { index in
                            chartLegend(
                                seriesLabels[index],
                                color: index == 0 ? TaskManagerTheme.ink.opacity(0.76) : TaskManagerTheme.accent
                            )
                        }
                        Spacer()
                    }
                    .padding(.leading, 74)
                    .padding(.trailing, 12)
                }
            }
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var cpuPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "CPU usage", value: service.snapshot?.cpuUsage.map(Self.decimal) ?? "—", unit: "%",
                detail: "Across \(ProcessInfo.processInfo.activeProcessorCount) logical cores",
                values: chartHistory(.cpu).values,
                secondary: chartHistory(.cpu).secondary, range: 0...100,
                upperScaleLabel: "100%", middleScaleLabel: "50%", lowerScaleLabel: "0%",
                seriesLabels: ["Total usage", "System"],
                stats: [
                    ("User", service.snapshot?.cpuDetails.map { "\(Int($0.user.rounded()))%" } ?? "—"),
                    ("System", service.snapshot?.cpuDetails.map { "\(Int($0.system.rounded()))%" } ?? "—"),
                    ("Idle", service.snapshot?.cpuDetails.map { "\(Int($0.idle.rounded()))%" } ?? "—"),
                ]
            )
            LazyVGrid(columns: detailColumns, spacing: 10) {
                coreActivity
                informationPanel("Load average", rows: [
                    ("1 minute", service.snapshot?.loadAverage.map { Self.decimal($0.0) } ?? "—"),
                    ("5 minutes", service.snapshot?.loadAverage.map { Self.decimal($0.1) } ?? "—"),
                    ("15 minutes", service.snapshot?.loadAverage.map { Self.decimal($0.2) } ?? "—"),
                    ("Thermal pressure", service.snapshot?.thermalState ?? "—"),
                ])
                .help(loadExplanation)
            }
        }
    }

    private var coreActivity: some View {
        let cores = service.snapshot?.cpuDetails?.cores ?? []
        return TaskManagerPanel(textured: true) {
            VStack(alignment: .leading, spacing: 0) {
                OnePlusCardHeader("Core activity") {
                    Text(coreLayoutDescription)
                        .font(.system(size: 8.5))
                        .foregroundStyle(TaskManagerTheme.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if TaskManagerHardwareSummary.coreLayout != nil {
                        HStack(spacing: 10) {
                            coreLegend("Performance", color: TaskManagerTheme.ink.opacity(0.76))
                            coreLegend("Efficiency", color: TaskManagerTheme.secondary)
                        }
                    }
                    if cores.isEmpty {
                        Text("—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(TaskManagerTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 92)
                    } else {
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(cores.indices, id: \.self) { index in
                                if isFirstEfficiencyCore(index) {
                                    Rectangle()
                                        .fill(TaskManagerTheme.line)
                                        .frame(width: 1, height: 76)
                                        .padding(.horizontal, 2)
                                }
                                VStack(spacing: 6) {
                                    Text("\(Int(cores[index].rounded()))%")
                                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(TaskManagerTheme.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    GeometryReader { proxy in
                                        let fraction = CGFloat(min(max(cores[index] / 100, 0), 1))
                                        ZStack(alignment: .bottom) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(TaskManagerTheme.lineSoft.opacity(0.7))
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(coreColor(index))
                                                .frame(height: max(2, proxy.size.height * fraction))
                                        }
                                    }
                                    .frame(height: 54)
                                    Text(coreLabel(index))
                                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(TaskManagerTheme.muted)
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(coreLabel(index)), \(Int(cores[index].rounded())) percent")
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func coreLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(TaskManagerTheme.secondary)
        }
    }

    private func coreColor(_ index: Int) -> Color {
        guard let layout = TaskManagerHardwareSummary.coreLayout,
              index >= layout.performance else { return TaskManagerTheme.ink.opacity(0.76) }
        return TaskManagerTheme.secondary
    }

    private func isFirstEfficiencyCore(_ index: Int) -> Bool {
        TaskManagerHardwareSummary.coreLayout?.performance == index
    }

    private var gpuPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "GPU usage", value: service.snapshot?.gpuUsage.map(Self.decimal) ?? "—", unit: "%",
                detail: "Integrated graphics",
                values: chartHistory(.gpu).values, range: 0...100,
                upperScaleLabel: "100%", middleScaleLabel: "50%", lowerScaleLabel: "0%",
                seriesLabels: ["Graphics utilization"],
                stats: [("Thermal pressure", service.snapshot?.thermalState ?? "—")]
            )
            informationPanel("Graphics details", rows: [("Architecture", "Integrated"), ("Memory", "Unified")])
        }
    }

    private var memoryPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "Memory in use", value: service.snapshot?.memoryUsed.map(Self.bytes) ?? "—",
                detail: "\(service.snapshot?.memoryTotal.map(Self.bytes) ?? "—") unified memory",
                values: chartHistory(.memory).values,
                range: 0...Double(max(service.snapshot?.memoryTotal ?? 1, 1)),
                upperScaleLabel: service.snapshot?.memoryTotal.map(Self.bytes) ?? "—",
                middleScaleLabel: service.snapshot?.memoryTotal.map { Self.bytes($0 / 2) } ?? "—",
                lowerScaleLabel: "0 GB",
                seriesLabels: ["Used memory"],
                stats: [("Used", service.snapshot?.memoryUsage.percent ?? "—"), ("Available", memoryAvailable)]
            )
            LazyVGrid(columns: detailColumns, spacing: 10) {
                memoryAllocationPanel(header: "Allocation")
                informationPanel("Virtual memory", rows: [
                        ("Swap used", service.snapshot?.memoryDetails?.swapUsed.map(Self.bytes) ?? "—"),
                        ("Compressed", service.snapshot?.memoryDetails.map { Self.bytes($0.compressed) } ?? "—"),
                        ("Cached files", service.snapshot?.memoryDetails.map { Self.bytes($0.cached) } ?? "—"),
                        ("Page-ins", service.snapshot?.memoryDetails.map { "\($0.pageIns.formatted()) pages" } ?? "—"),
                        ("Page-outs", service.snapshot?.memoryDetails.map { "\($0.pageOuts.formatted()) pages" } ?? "—"),
                ])
            }
        }
    }

    private var networkPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "Download", value: service.snapshot?.networkDownload.map(Self.rate) ?? "—",
                detail: "All active non-loopback interfaces",
                values: chartHistory(.network).values,
                secondary: chartHistory(.network).secondary, range: networkRange,
                upperScaleLabel: Self.rate(networkRange.upperBound),
                middleScaleLabel: Self.rate(networkRange.upperBound / 2), lowerScaleLabel: "0 KB/s",
                seriesLabels: ["Download", "Upload"],
                stats: [
                    ("Upload", service.snapshot?.networkUpload.map(Self.rate) ?? "—"),
                    ("Interface", service.snapshot?.networkDetails?.interfaceName ?? "—"),
                ]
            )
            informationPanel("Interface", rows: [
                    ("Name", service.snapshot?.networkDetails?.interfaceName ?? "—"),
                    ("Local address", service.snapshot?.networkDetails?.localAddress ?? "—"),
                    ("Transferred down", service.snapshot?.networkDetails.map { Self.bytes($0.receivedTotal) } ?? "—"),
                    ("Transferred up", service.snapshot?.networkDetails.map { Self.bytes($0.sentTotal) } ?? "—"),
            ])
        }
    }

    private var diskPage: some View {
        VStack(spacing: 10) {
            TaskManagerPanel(textured: true) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("Startup volume", systemImage: "internaldrive")
                                .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
                            metricValue(service.snapshot?.diskUsed.map(Self.diskBytes) ?? "—")
                            Text("used of \(service.snapshot?.diskTotal.map(Self.diskBytes) ?? "—")")
                                .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                        }
                        Spacer()
                        detailStat("Available", diskAvailable)
                        detailStat("Used", service.snapshot?.diskUsage.percent ?? "—")
                    }
                    OnePlusUsageBar(value: (service.snapshot?.diskUsage ?? 0) / 100)
                }
                .padding(12)
            }
            detailHero(
                label: "Disk activity",
                value: service.snapshot?.diskDetails?.readPerSecond.map(Self.rate) ?? "—",
                detail: "Read throughput across physical storage",
                values: chartHistory(.disk).values,
                secondary: chartHistory(.disk).secondary,
                range: diskRateRange,
                upperScaleLabel: Self.rate(diskRateRange.upperBound),
                middleScaleLabel: Self.rate(diskRateRange.upperBound / 2), lowerScaleLabel: "0 KB/s",
                seriesLabels: ["Read", "Write"],
                stats: [
                    ("Write", service.snapshot?.diskDetails?.writePerSecond.map(Self.rate) ?? "—"),
                    ("Read total", service.snapshot?.diskDetails.map { Self.diskBytes(Int64(clamping: $0.readTotal)) } ?? "—"),
                ]
            )
            LazyVGrid(columns: detailColumns, spacing: 10) {
                informationPanel("Volume", rows: [("Mount point", "/"), ("Used", service.snapshot?.diskUsed.map(Self.diskBytes) ?? "—"), ("Available", diskAvailable)])
                informationPanel("Storage", rows: [
                    ("Capacity", service.snapshot?.diskTotal.map(Self.diskBytes) ?? "—"),
                    ("Read", service.snapshot?.diskDetails?.readPerSecond.map(Self.rate) ?? "—"),
                    ("Write", service.snapshot?.diskDetails?.writePerSecond.map(Self.rate) ?? "—"),
                    ("Status", "Mounted"),
                ])
            }
        }
    }

    @ViewBuilder
    private var batteryPage: some View {
        if service.snapshot?.unavailableMetrics.contains(.battery) == true {
            TaskManagerPanel {
                OnePlusEmptyState(
                    "No internal battery",
                    systemImage: "battery.slash",
                    caption: "This Mac does not report an internal battery."
                )
            }
        } else {
            VStack(spacing: 10) {
            detailHero(
                label: "Battery charge", value: service.snapshot?.batteryPercent.map(String.init) ?? "—", unit: "%",
                detail: batteryDetail,
                values: chartHistory(.battery).values, range: 0...100,
                upperScaleLabel: "100%", middleScaleLabel: "50%", lowerScaleLabel: "0%",
                seriesLabels: ["Battery charge"],
                stats: [("Power source", powerSourceDetail)]
            )
            LazyVGrid(columns: detailColumns, spacing: 10) {
                informationPanel("Battery details", rows: batteryDetailRows)
                powerDrawPanel
            }
        }
        }
    }

    private var powerDrawPanel: some View {
        let values = chartHistory(.battery).power
        let upper = chartHistory(.battery).powerRange.upperBound
        return detailHero(
            label: "Power draw", value: service.snapshot.flatMap(SystemMonitorWindowHistory.powerDraw).map(Self.decimal) ?? "—", unit: "W",
            detail: values.isEmpty ? "Power use is not reported for this battery." : "",
            values: values, range: 0...upper,
            upperScaleLabel: "\(Self.decimal(upper)) W",
            middleScaleLabel: "\(Self.decimal(upper / 2)) W", lowerScaleLabel: "0 W",
            seriesLabels: ["Power draw"], chartHeight: 72, stats: []
        )
    }

    private var sensorsPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "Thermal pressure", value: service.snapshot?.thermalState ?? "—",
                detail: "System-reported thermal state",
                values: chartHistory(.thermal).values, range: 0...100,
                upperScaleLabel: "Critical", middleScaleLabel: "Fair", lowerScaleLabel: "Nominal",
                scaleLabels: ["Critical", "Serious", "Fair", "Nominal"],
                seriesLabels: ["Thermal state"], stepped: true,
                stats: []
            )
            FanControlView(owner: "system-monitor-window")
        }
    }

    private var detailColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10, alignment: .top),
            GridItem(.flexible(), alignment: .top),
        ]
    }

    private var aboutPage: some View {
        VStack(spacing: 10) {
            OnePlusCard(textured: true) {
                HStack(spacing: 12) {
                    Image("SystemMonitorLogo")
                        .resizable().scaledToFit().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                        Text("Task Manager").onePlusText(.cardTitle).onePlusDensity(.regular)
                        Text("A focused view of your Mac's activity.")
                            .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 10) {
                aboutPanel("Main window", icon: "display", text: "Processes, compute, memory, storage, network, battery, and thermal activity in dedicated workspaces.")
                aboutPanel("Menu bar", icon: "chart.bar.xaxis", text: "A compact panel with icon tabs, live metrics, remote instances, processes, and fan controls.")
            }
            informationPanel("Keyboard shortcuts", rows: [("Find a process", "⌘ K"), ("Dismiss a sheet or menu", "Esc")])
        }
    }

    private func informationPanel(_ title: String, rows: [(String, String)]) -> some View {
        let hasMissingValue = rows.contains { $0.1 == "—" }
        return TaskManagerPanel {
            VStack(spacing: 0) {
                OnePlusCardHeader(title) {
                    if hasMissingValue {
                        Image(systemName: "info.circle")
                            .help("Some details are not reported for this Mac.")
                            .accessibilityLabel("Some details are not reported for this Mac.")
                    }
                }
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text(rows[index].0).foregroundStyle(TaskManagerTheme.secondary)
                        Spacer(minLength: 12)
                        Text(rows[index].1)
                            .foregroundStyle(TaskManagerTheme.ink)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .onePlusRowHover()
                    .overlay(alignment: .bottom) {
                        if index < rows.count - 1 { rowDivider }
                    }
                }
            }
        }
    }

    private func aboutPanel(_ title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[2]) {
            Label(title, systemImage: icon).onePlusText(.sectionTitle)
            Text(text).onePlusText(.row).foregroundStyle(TaskManagerTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        return HStack {
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Button(action, action: perform)
                .buttonStyle(OnePlusButtonStyle(.link, size: .small))
        }
        .frame(minHeight: 17)
    }

    private func reportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
        }
        .buttonStyle(OnePlusButtonStyle(.borderedIcon, size: .small))
        .help(label)
        .accessibilityLabel(label)
    }

    private func allocationRow(_ title: String, value: String) -> some View {
        let color: Color = switch title {
        case "Applications": TaskManagerTheme.ink.opacity(0.82)
        case "Wired": TaskManagerTheme.ink.opacity(0.58)
        case "Compressed": TaskManagerTheme.ink.opacity(0.35)
        default: TaskManagerTheme.line
        }
        return HStack {
            Rectangle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
            Spacer()
            Text(value).font(.system(size: 9, design: .monospaced))
        }
    }

    private func detailStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(title).font(.system(size: 8)).foregroundStyle(TaskManagerTheme.muted)
            Text(value).font(.system(size: 12)).monospacedDigit()
        }
        .padding(.leading, 24)
    }

    private func metricValue(_ text: String) -> some View {
        let parts = TaskManagerMetricText.parts(text)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(parts.value)
                .onePlusText(.metric)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .onePlusText(.unit)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private func chartLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 9, height: 2)
            Text(title).font(.system(size: 8)).foregroundStyle(TaskManagerTheme.secondary)
        }
    }

    private var rowDivider: some View { Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1) }

    @ViewBuilder
    private func monitorIcon(_ metric: SystemMonitorMenuMetric) -> some View {
        if metric == .gpu { GPUCardIcon() } else { Image(systemName: metric.symbol).font(.system(size: 11)) }
    }

    private var memoryDetail: String {
        guard let used = service.snapshot?.memoryUsed, let total = service.snapshot?.memoryTotal else { return "Physical memory" }
        return "\(Self.bytes(used)) / \(Self.bytes(total))\(memoryIsHigh ? " · High" : "")"
    }

    private var memoryIsHigh: Bool { (service.snapshot?.memoryUsage ?? 0) >= 90 }

    private var memoryAvailable: String {
        guard let used = service.snapshot?.memoryUsed, let total = service.snapshot?.memoryTotal else { return "—" }
        return Self.bytes(max(total - used, 0))
    }

    private var diskAvailable: String {
        guard let used = service.snapshot?.diskUsed, let total = service.snapshot?.diskTotal else { return "—" }
        return Self.diskBytes(max(total - used, 0))
    }

    private var batteryDetail: String {
        Self.batteryDetail(for: service.snapshot)
    }

    nonisolated static func batteryDetail(for sample: SystemMonitorSample?) -> String {
        guard let sample else { return "—" }
        guard sample.batteryPercent != nil else {
            return sample.unavailableMetrics.contains(.battery) ? "No internal battery detected" : "—"
        }
        guard let charging = sample.batteryCharging else { return "—" }
        return charging ? "Connected to power" : "On battery"
    }

    private var loadValue: String { service.snapshot?.loadAverage.map { Self.decimal($0.0) } ?? "—" }
    private var loadExplanation: String {
        "Load is the average number of processes running or waiting for a CPU. Compare it with \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs. It is not a percentage."
    }
    private var loadRange: ClosedRange<Double> {
        0...Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    }
    private var networkRange: ClosedRange<Double> { chartHistory(.network).range }
    private var diskRateRange: ClosedRange<Double> { chartHistory(.disk).range }

    private var coreLayoutDescription: String {
        guard let layout = TaskManagerHardwareSummary.coreLayout else {
            return "\(ProcessInfo.processInfo.activeProcessorCount) logical cores"
        }
        return "\(layout.performance) performance · \(layout.efficiency) efficiency"
    }

    private func coreLabel(_ index: Int) -> String {
        guard let layout = TaskManagerHardwareSummary.coreLayout else { return "C\(index + 1)" }
        return index < layout.performance ? "P\(index + 1)" : "E\(index - layout.performance + 1)"
    }

    private var powerSourceDetail: String {
        guard service.snapshot?.batteryPercent != nil,
              let charging = service.snapshot?.batteryCharging else { return "—" }
        return charging ? "AC adapter" : "Battery"
    }

    private var batteryDetailRows: [(String, String)] {
        guard let details = service.snapshot?.batteryDetails else { return [] }
        var rows: [(String, String)] = []
        if let health = details.health { rows.append(("Health", health)) }
        if let cycleCount = details.cycleCount { rows.append(("Cycle count", String(cycleCount))) }
        if let voltage = details.voltageMillivolts {
            rows.append(("Voltage", "\((Double(voltage) / 1_000).formatted(.number.precision(.fractionLength(2)))) V"))
        }
        if let amperage = details.amperageMilliamps { rows.append(("Amperage", "\(amperage) mA")) }
        return rows
    }

    private func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "—" }

    nonisolated private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 2 : 1)))
    }
    nonisolated private static func rate(_ value: Double) -> String {
        SystemMonitorDisplayFormat.byteRate(value)
    }
    nonisolated private static func diskBytes(_ value: Int64) -> String {
        TrayPopoverLayout.diskBytes(max(value, 0))
    }
    nonisolated private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(value, 0), countStyle: .memory)
    }
    nonisolated private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .memory)
    }
    nonisolated private static func thermalBand(_ state: String?) -> Int? {
        switch state {
        case "Nominal": 0
        case "Fair": 1
        case "Serious": 2
        case "Critical": 3
        default: nil
        }
    }


}

struct SystemMonitorSettingsContent: View {
    private enum Column {
        static let drag: CGFloat = 28
        static let metric: CGFloat = 112
        static let placement: CGFloat = 112
        static let style: CGFloat = 160
        static let update: CGFloat = 110
        static let details: CGFloat = 28
    }

    @State private var service = SystemMonitorService.shared
    @State private var expandedMetric: SystemMonitorMenuMetric?
    @AppStorage("systemMonitor.rememberTrayPage") private var rememberPanel = true
    @AppStorage("systemMonitor.historyMinutes") private var historyMinutes = 2
    @Environment(\.onePlusDensity) private var density

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 16) {
            displaySection
            itemsSection
        }
        .onAppear { if ![1, 2].contains(historyMinutes) { historyMinutes = 2 } }
    }

    private var displaySection: some View {
        OnePlusCard {
            OnePlusCardHeader("Display")
            OnePlusSettingRow("Show in menu bar", controlWidth: 180) {
                Toggle("Show in menu bar", isOn: menuSetting(
                    get: { $0.enabled },
                    set: { $0.enabled = $1 }
                ))
                .labelsHidden()
                .toggleStyle(OnePlusSwitchStyle())
                .accessibilityIdentifier("system-monitor.menu.enabled")
            }
            OnePlusSettingRow("Remember last panel", controlWidth: 180) {
                Toggle("Remember last panel", isOn: $rememberPanel)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("Global interval", controlWidth: 180) {
                globalIntervalControl
                    .disabled(!service.menuSettings.enabled)
            }
            OnePlusSettingRow("History window", controlWidth: 180, separator: false) {
                TaskManagerSelect(
                    choices: [(1, "1 minute"), (2, "2 minutes")],
                    selection: $historyMinutes,
                    width: 180,
                    accessibilityLabel: "History window"
                )
            }
        }
    }

    private var globalIntervalControl: some View {
        TaskManagerSelect(
            choices: SystemMonitorMenuInterval.allowedSeconds.map { ($0, Self.intervalTitle($0)) },
            selection: menuSetting(
                get: { $0.interval },
                set: { $0.interval = $1 }
            ),
            width: 180,
            accessibilityLabel: "Global interval"
        )
        .accessibilityIdentifier("system-monitor.menu.global-interval")
    }

    private var itemsSection: some View {
        OnePlusCard {
            OnePlusCardHeader("Menu bar items") {
                Text("Drag to reorder")
                    .onePlusText(.caption)
            }
            LazyVStack(spacing: 0) {
                itemsHeader
                ForEach(service.menuSettings.items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private var itemsHeader: some View {
        HStack(spacing: 8) {
            Text("").frame(width: Column.drag)
            Text("Metric").frame(width: Column.metric, alignment: .leading)
            Text("Placement").frame(width: Column.placement, alignment: .leading)
            Text("Style").frame(width: Column.style, alignment: .leading)
            Text("Update").frame(width: Column.update, alignment: .leading)
            Text("Format").frame(maxWidth: .infinity, alignment: .leading)
            Text("").frame(width: Column.details)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OnePlusMetrics.cardPadding - OnePlusTable.cellInset)
        .onePlusTableHeader()
    }

    private func itemRow(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                reorderMenu(item.metric).frame(width: Column.drag)
                Label(item.metric.title, systemImage: item.symbol)
                    .onePlusText(.row)
                    .frame(width: Column.metric, alignment: .leading)
                    .lineLimit(1)
                placementControl(item).frame(width: Column.placement)
                styleControl(item).frame(width: Column.style)
                intervalControl(item).frame(width: Column.update)
                GeometryReader { proxy in
                    formatControl(item, width: proxy.size.width)
                }
                .frame(height: density.controlHeight)
                .frame(maxWidth: .infinity)
                Button {
                    expandedMetric = expandedMetric == item.metric ? nil : item.metric
                } label: {
                    Image(systemName: expandedMetric == item.metric ? "chevron.up" : "ellipsis")
                }
                .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                .frame(width: Column.details)
                .accessibilityLabel("\(item.metric.title) details")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OnePlusMetrics.cardPadding)
            .frame(height: 34)
            .onePlusRowHover()
            .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
            if expandedMetric == item.metric { detailsRow(item) }
        }
        .contentShape(Rectangle())
        .draggable(item.metric.rawValue)
        .dropDestination(for: String.self) { values, _ in
            guard let rawValue = values.first,
                  let source = SystemMonitorMenuMetric(rawValue: rawValue) else { return false }
            move(source, to: item.metric)
            return true
        }
        .focusable()
        .onMoveCommand { direction in
            if direction == .up { move(item.metric, by: -1) }
            if direction == .down { move(item.metric, by: 1) }
        }
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue)")
        .accessibilityHint("Drag, or use Up Arrow and Down Arrow, to reorder")
    }

    private func placementControl(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        TaskManagerSelect(
            choices: SystemMonitorMenuPlacement.allCases.map { ($0, $0.title) },
            selection: Binding(
                get: {
                    guard let current = service.menuSettings.items.first(where: { $0.metric == item.metric }),
                          current.enabled else { return .off }
                    return current.placement
                },
                set: { placement in
                    service.updateMenuSettings { $0.setPlacement(placement, for: item.metric) }
                }
            ),
            width: Column.placement,
            accessibilityLabel: "\(item.metric.title) menu bar placement"
        )
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).placement")
    }

    private func styleControl(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        TaskManagerSelect(
            choices: SystemMonitorMenuItemStyle.allCases.map { ($0, $0.title) },
            selection: itemSetting(item, get: { $0.style }, set: { $0.style = $1 }),
            width: Column.style,
            accessibilityLabel: "\(item.metric.title) style"
        )
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).style")
    }

    private func intervalControl(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        TaskManagerSelect(
            choices: item.metric.supportedIntervals(global: service.menuSettings.interval)
                .map { ($0, $0.title) },
            selection: itemSetting(item, get: { $0.interval }, set: { $0.interval = $1 }),
            width: Column.update,
            accessibilityLabel: "\(item.metric.title) update interval"
        )
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).interval")
    }

    @ViewBuilder
    private func formatControl(_ item: SystemMonitorMenuItemConfiguration, width: CGFloat) -> some View {
        switch item.metric {
        case .memory:
            TaskManagerSelect(
                choices: SystemMonitorMemoryUnit.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.memoryUnit }, set: { $0.memoryUnit = $1 }),
                width: width,
                accessibilityLabel: "Memory format"
            )
        case .disk:
            TaskManagerSelect(
                choices: SystemMonitorDiskUnit.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.diskUnit }, set: { $0.diskUnit = $1 }),
                width: width,
                accessibilityLabel: "Disk format"
            )
        case .network:
            TaskManagerSelect(
                choices: SystemMonitorNetworkUnit.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.networkUnit }, set: { $0.networkUnit = $1 }),
                width: width,
                accessibilityLabel: "Network format"
            )
        case .battery:
            TaskManagerSelect(
                choices: SystemMonitorBatteryDisplay.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.batteryDisplay }, set: { $0.batteryDisplay = $1 }),
                width: width,
                accessibilityLabel: "Battery format"
            )
        case .thermal:
            TaskManagerSelect(
                choices: SystemMonitorThermalDisplay.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.thermalDisplay }, set: { $0.thermalDisplay = $1 }),
                width: width,
                accessibilityLabel: "Thermal format"
            )
        case .cpu, .gpu:
            TaskManagerSelect(
                choices: [("default", "Default")],
                selection: .constant("default"),
                width: width,
                accessibilityLabel: "\(item.metric.title) format"
            )
            .disabled(true)
        }
    }

    private func detailsRow(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        HStack(spacing: 12) {
            Text("Details")
                .onePlusText(.caption)
            TaskManagerSelect(
                choices: item.metric.symbols.map { ($0, Self.iconTitle($0, for: item.metric)) },
                selection: itemSetting(item, get: { $0.symbol }, set: { $0.symbol = $1 }),
                width: 126,
                accessibilityLabel: "\(item.metric.title) icon"
            )
            if item.metric == .network {
                TaskManagerSelect(
                    choices: SystemMonitorNetworkDirection.allCases.map { ($0, $0.title) },
                    selection: itemSetting(item, get: { $0.networkDirection }, set: { $0.networkDirection = $1 }),
                    width: 126,
                    accessibilityLabel: "Network direction"
                )
            } else {
                Text("Uses the global interval unless Update overrides it.")
                    .onePlusText(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 48)
        .frame(height: 44)
        .background(OnePlusColor.panelHover)
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
    }

    private func reorderMenu(_ metric: SystemMonitorMenuMetric) -> some View {
        let index = service.menuSettings.items.firstIndex { $0.metric == metric }
        return Menu {
            Button("Move Up") { move(metric, by: -1) }
                .disabled(index == service.menuSettings.items.startIndex)
            Button("Move Down") { move(metric, by: 1) }
                .disabled(index == service.menuSettings.items.indices.last)
        } label: {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(OnePlusColor.secondary)
                .frame(width: 16, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Reorder \(metric.title)")
        .accessibilityIdentifier("system-monitor.menu.item.\(metric.rawValue).reorder")
    }

    private func menuSetting<Value>(
        get: @escaping (SystemMonitorMenuSettings) -> Value,
        set: @escaping (inout SystemMonitorMenuSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(service.menuSettings) },
            set: { value in service.updateMenuSettings { set(&$0, value) } }
        )
    }

    private func itemSetting<Value>(
        _ item: SystemMonitorMenuItemConfiguration,
        get: @escaping (SystemMonitorMenuItemConfiguration) -> Value,
        set: @escaping (inout SystemMonitorMenuItemConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: {
                service.menuSettings.items.first { $0.metric == item.metric }.map(get) ?? get(item)
            },
            set: { value in
                service.updateMenuSettings { settings in
                    guard let index = settings.items.firstIndex(where: { $0.metric == item.metric }) else { return }
                    set(&settings.items[index], value)
                }
            }
        )
    }

    private func move(_ metric: SystemMonitorMenuMetric, by offset: Int) {
        service.updateMenuSettings { settings in
            guard let source = settings.items.firstIndex(where: { $0.metric == metric }) else { return }
            let destination = source + offset
            guard settings.items.indices.contains(destination) else { return }
            settings.items.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: offset > 0 ? destination + 1 : destination
            )
        }
    }

    private func move(_ sourceMetric: SystemMonitorMenuMetric, to destinationMetric: SystemMonitorMenuMetric) {
        guard sourceMetric != destinationMetric else { return }
        service.updateMenuSettings { settings in
            guard let source = settings.items.firstIndex(where: { $0.metric == sourceMetric }),
                  let destination = settings.items.firstIndex(where: { $0.metric == destinationMetric }) else { return }
            settings.items.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: destination > source ? destination + 1 : destination
            )
        }
    }

    private static func intervalTitle(_ seconds: TimeInterval) -> String {
        "\(Int(seconds)) \(seconds == 1 ? "second" : "seconds")"
    }

    private static func iconTitle(_ symbol: String, for metric: SystemMonitorMenuMetric) -> String {
        guard let index = metric.symbols.firstIndex(of: symbol), index > 0 else { return metric.title }
        return "Alternate \(index)"
    }
}

struct SystemMonitorDitherSparkline: View {
    let values: [Double]
    var color: Color = TaskManagerTheme.ink
    var showsGuide = false

    var body: some View {
        let maximum = max(values.filter(\.isFinite).max() ?? 1, 1)
        TaskManagerHistoryChart(values: values, range: 0...maximum, unit: "", compact: true)
    }
}

private extension Optional where Wrapped == Double {
    var percent: String { map { "\(Int($0.rounded()))%" } ?? "—" }
}

private extension Text {
    func taskManagerSectionTitle() -> some View {
        font(.system(size: 8, design: .monospaced))
            .tracking(1)
            .foregroundStyle(TaskManagerTheme.secondary)
    }
}

#Preview {
    SystemMonitorWindowView().frame(
        width: TaskManagerTheme.windowContentSize.width,
        height: TaskManagerTheme.windowContentSize.height
    )
}
