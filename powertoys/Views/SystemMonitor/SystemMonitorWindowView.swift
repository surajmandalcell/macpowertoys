import AppKit
import OnePlusUI
import SwiftUI

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

struct SystemMonitorPlacementPicker: View {
    let metric: SystemMonitorMenuMetric
    @Binding var selection: SystemMonitorMenuPlacement

    var body: some View {
        TaskManagerSegments(
            choices: SystemMonitorMenuPlacement.allCases.map { ($0, $0.title) },
            selection: $selection
        )
        .frame(width: 204, height: UtilityLayout.workspaceActionHeight)
        .help("Show \(metric.title) in one Task Manager item, a separate item, or neither")
        .accessibilityIdentifier("system-monitor.\(metric.rawValue).menu-placement")
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
        case .remote: "Remote Stats"
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
    private let remoteProfilesOverride: [SystemMonitorRemoteProfile]?
    @State private var service = SystemMonitorService.shared
    @State private var overviewSampler = SystemMonitorProcessSampler()
    @State private var overviewProcesses: [SystemMonitorProcess] = []
    @AppStorage("systemMonitor.windowPage") private var pageID = SystemMonitorPage.overview.rawValue
    @AppStorage("systemMonitor.processHierarchy") private var processHierarchy = false
    @AppStorage("systemMonitor.historyMinutes") private var historyMinutes = 2
    @State private var processSearch = ""
    @State private var reportSearch = ""
    @State private var reportAction: TaskManagerSystemReportAction?
    @State private var processSearchFocusTrigger = 0
    @State private var remoteAddRequest = 0

    init(
        reportSnapshot: [TaskManagerReportCategory] = [],
        remoteProfiles: [SystemMonitorRemoteProfile]? = nil
    ) {
        self.reportSnapshot = reportSnapshot
        remoteProfilesOverride = remoteProfiles
    }

    private var page: SystemMonitorPage { SystemMonitorPage.resolve(pageID) ?? .overview }
    private var remoteProfiles: [SystemMonitorRemoteProfile] {
        remoteProfilesOverride ?? SystemMonitorRemoteProfiles.load()
    }
    private var recentHistory: [SystemMonitorSample] {
        Array(service.history.suffix(max(60, historyMinutes * 60)))
    }

    var body: some View {
        OnePlusWindowRoot(canvas: .systemMonitor) {
            sidebar
        } content: {
            VStack(spacing: 0) {
                header
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .utilityContentTransition(value: pageID)
            }
        }
        .onePlusDensity(.compact)
        .background(WindowAccessor(identifier: "system-monitor"))
        .onAppear {
            pageID = page.rawValue
            service.startDetailed(metrics: page.detailedMetrics)
        }
        .onChange(of: pageID) { _, _ in service.updateDetailed(metrics: page.detailedMetrics) }
        .onDisappear { service.stopDetailed() }
        .onOpenToolPage("system-monitor") { requestedPage in
            guard let destination = SystemMonitorPage.resolve(requestedPage) else { return }
            pageID = destination.rawValue
        }
        .task(id: pageID) {
            guard page == .overview else { return }
            await sampleOverviewProcesses()
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

    private var sidebar: some View {
        OnePlusSidebar(title: "Task Manager") {
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
                .accessibilityIdentifier("task-manager.sidebar.\(item.rawValue)")
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
                            .toggleStyle(.switch)
                            .controlSize(.mini)
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
                    reportButton("doc.on.doc", label: "Copy current report") { reportAction = .copy }
                    Menu {
                        Button("Save Text Report…") { reportAction = .exportText }
                        Button("Save JSON Report…") { reportAction = .exportJSON }
                    } label: {
                        OnePlusControlLabel(variant: .icon, size: .small) {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .focusEffectDisabled()
                    .help("Export system report")
                    .accessibilityLabel("Export system report")
                    TaskManagerSearchField(prompt: "Search all system information", text: $reportSearch, width: 320)
                }
            }
        case .cpu:
            metricHeader(.cpu)
        case .gpu:
            metricHeader(.gpu)
        case .memory:
            metricHeader(.memory)
        case .network:
            metricHeader(.network)
        case .disk:
            metricHeader(.disk)
        case .battery:
            metricHeader(.battery)
        case .sensors:
            metricHeader(.thermal)
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

    private func metricHeader(_ metric: SystemMonitorMenuMetric) -> some View {
        TaskManagerHeader(title: page.title, subtitle: page.subtitle) {
            menuPlacement(metric)
        }
    }

    private func menuPlacement(_ metric: SystemMonitorMenuMetric) -> some View {
        SystemMonitorPlacementPicker(metric: metric, selection: Binding(
            get: {
                guard let item = service.menuSettings.items.first(where: { $0.metric == metric }),
                      service.menuSettings.enabled, item.enabled else { return .off }
                return item.placement
            },
            set: { placement in service.updateMenuSettings { $0.setPlacement(placement, for: metric) } }
        ))
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .overview: scrollPage { overviewPage }
        case .processes:
            SystemMonitorProcessesView(
                search: $processSearch,
                hierarchy: $processHierarchy,
                showsToolbar: false
            )
            .padding(.horizontal, TaskManagerTheme.contentInset)
            .padding(.top, TaskManagerTheme.pageTopInset)
            .padding(.bottom, 18)
        case .cpu: scrollPage { cpuPage }
        case .gpu: scrollPage { gpuPage }
        case .memory: scrollPage { memoryPage }
        case .network: scrollPage { networkPage }
        case .disk: scrollPage { diskPage }
        case .battery: scrollPage { batteryPage }
        case .sensors: scrollPage { sensorsPage }
        case .remote:
            SystemMonitorRemoteView(addRequest: remoteAddRequest)
                .padding(.horizontal, TaskManagerTheme.contentInset)
                .padding(.top, TaskManagerTheme.pageTopInset)
                .padding(.bottom, 18)
        case .report:
            TaskManagerSystemReportView(
                search: $reportSearch,
                requestedAction: $reportAction,
                initialCategories: reportSnapshot
            )
                .padding(.horizontal, TaskManagerTheme.contentInset)
                .padding(.top, TaskManagerTheme.pageTopInset)
                .padding(.bottom, 18)
        case .about: scrollPage { aboutPage }
        case .settings: settingsPage
        }
    }

    private func scrollPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentMargins(.horizontal, TaskManagerTheme.contentInset, for: .scrollContent)
        .contentMargins(.top, TaskManagerTheme.pageTopInset, for: .scrollContent)
        .contentMargins(.bottom, 18, for: .scrollContent)
        .thinScrollIndicators()
    }

    private var overviewPage: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                metricCard(.cpu, value: percent(service.snapshot?.cpuUsage), detail: "Across \(ProcessInfo.processInfo.activeProcessorCount) cores",
                           values: recentHistory.compactMap(\.cpuUsage), range: 0...100)
                metricCard(.gpu, value: percent(service.snapshot?.gpuUsage), detail: "Graphics utilization",
                           values: recentHistory.compactMap(\.gpuUsage), range: 0...100)
                metricCard(.memory, value: service.snapshot?.memoryUsage.percent ?? "—", detail: memoryDetail,
                           values: recentHistory.compactMap(\.memoryUsage), range: 0...100, accent: true)
                metricCard(.network, value: service.snapshot?.networkDownload.map(Self.rate) ?? "—",
                           detail: "↓ Download · ↑ \(service.snapshot?.networkUpload.map(Self.rate) ?? "—")",
                           values: recentHistory.compactMap(\.networkDownload),
                           secondary: recentHistory.compactMap(\.networkUpload), range: networkRange)
                metricCard(.disk, value: service.snapshot?.diskUsage.percent ?? "—", detail: "\(diskAvailable) available")
                metricCard(.battery, value: service.snapshot?.batteryPercent.map { "\($0)%" } ?? "—", detail: batteryDetail)
                metricCard(.thermal, title: "Thermal", value: service.snapshot?.thermalState ?? "—", detail: "System thermal pressure")
                metricCard(.cpu, title: "Load average", value: loadValue, detail: "1 minute · \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs",
                           values: recentHistory.compactMap { $0.loadAverage?.0 }, range: loadRange)
                    .help(loadExplanation)
            }

            remoteOverview

            LazyVGrid(columns: [GridItem(.flexible(minimum: 0), spacing: 10), GridItem(.flexible(minimum: 0))], spacing: 10) {
                topProcesses
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
        accent: Bool = false
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
                            primaryColor: accent ? TaskManagerTheme.accent : TaskManagerTheme.ink.opacity(0.76)
                        )
                            .frame(height: 33)
                            .padding(.horizontal, 11)
                            .padding(.bottom, 8)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            monitorIcon(metric)
                                .foregroundStyle(accent ? TaskManagerTheme.accent : TaskManagerTheme.secondary)
                            Text(title ?? metric.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(TaskManagerTheme.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(TaskManagerTheme.muted)
                        }
                        metricValue(value, valueSize: 27, unitSize: 12)
                            .padding(.top, 7)
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(TaskManagerTheme.secondary)
                            .lineLimit(1)
                            .padding(.top, 4)
                        Spacer(minLength: 28)
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
        .focusEffectDisabled()
        .accessibilityLabel("Open \(title ?? metric.title), \(value)")
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
                                Text("Add a Linux, macOS, or Windows SSH host in Remote Stats.")
                                    .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                            }
                            Spacer()
                            Text("Add  →").font(.system(size: 9)).foregroundStyle(TaskManagerTheme.muted)
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(height: 58)
                }
                .buttonStyle(.plain).focusEffectDisabled()
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

    private var topProcesses: some View {
        let sorted = Array(SystemMonitorProcessSorting.sorted(overviewProcesses, by: .cpu, descending: true).prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Top processes", action: "View all") { pageID = SystemMonitorPage.processes.rawValue }
            TaskManagerPanel {
                VStack(spacing: 0) {
                    tableHeader([("Process", nil), ("CPU", 62), ("Memory", 82)])
                    ForEach(sorted) { process in
                        Button {
                            pageID = SystemMonitorPage.processes.rawValue
                            processSearch = String(process.pid)
                        } label: {
                            HStack(spacing: 8) {
                                processIdentity(process).frame(maxWidth: .infinity, alignment: .leading)
                                Text(process.cpuPercent.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—")
                                    .frame(width: 62, alignment: .trailing)
                                Text(process.residentBytes == 0 ? "—" : Self.bytes(process.residentBytes))
                                    .frame(width: 82, alignment: .trailing)
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(TaskManagerTheme.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 0))
                        .focusEffectDisabled()
                        .onePlusTableRow()
                        if process.id != sorted.last?.id {
                            Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                        }
                    }
                    if sorted.isEmpty {
                        Text("—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(TaskManagerTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 165)
                    }
                }
            }
            .frame(height: 203)
        }
    }

    private var memoryAllocation: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Memory allocation", action: "Details") { pageID = SystemMonitorPage.memory.rawValue }
            memoryAllocationPanel
                .frame(height: 203)
        }
    }

    private var memoryAllocationPanel: some View {
        let used = service.snapshot?.memoryUsed ?? 0
        let total = max(service.snapshot?.memoryTotal ?? 1, 1)
        let wired = service.snapshot?.memoryDetails?.wired ?? 0
        let compressed = service.snapshot?.memoryDetails?.compressed ?? 0
        let applications = max(used - wired - compressed, 0)
        let available = max(total - used, 0)
        return TaskManagerPanel {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Rectangle().fill(TaskManagerTheme.ink.opacity(0.82))
                            .frame(width: proxy.size.width * CGFloat(Double(applications) / Double(total)))
                        Rectangle().fill(TaskManagerTheme.ink.opacity(0.58))
                            .frame(width: proxy.size.width * CGFloat(Double(wired) / Double(total)))
                        Rectangle().fill(TaskManagerTheme.ink.opacity(0.35))
                            .frame(width: proxy.size.width * CGFloat(Double(compressed) / Double(total)))
                        Rectangle().fill(TaskManagerTheme.lineSoft)
                            .frame(width: proxy.size.width * CGFloat(Double(available) / Double(total)))
                    }
                }
                .frame(height: 10)
                allocationRow("Applications", value: Self.bytes(applications))
                allocationRow("Wired", value: Self.bytes(wired))
                allocationRow("Compressed", value: Self.bytes(compressed))
                Rectangle().fill(TaskManagerTheme.lineSoft).frame(height: 1)
                allocationRow("Available", value: Self.bytes(available))
            }
            .padding(12)
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
        lowerScaleLabel: String? = nil,
        seriesLabels: (String, String)? = nil,
        stats: [(String, String)]
    ) -> some View {
        let displayed = unit.isEmpty ? TaskManagerMetricText.parts(value) : (value, unit)
        return TaskManagerPanel(textured: true) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(TaskManagerTheme.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(displayed.0)
                                .font(.system(size: 27, weight: .medium))
                                .tracking(-1)
                                .monospacedDigit()
                            if !displayed.1.isEmpty {
                                Text(displayed.1).font(.system(size: 12)).foregroundStyle(TaskManagerTheme.secondary)
                            }
                        }
                        Text(detail).font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 20) {
                        ForEach(stats.indices, id: \.self) { index in
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(stats[index].0).font(.system(size: 8)).foregroundStyle(TaskManagerTheme.muted)
                                Text(stats[index].1)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(index == stats.count - 1 && stats[index].1 == "Elevated" ? TaskManagerTheme.accent : TaskManagerTheme.ink)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                if let seriesLabels {
                    HStack(spacing: 12) {
                        chartLegend(seriesLabels.0, color: TaskManagerTheme.ink.opacity(0.76))
                        chartLegend(seriesLabels.1, color: TaskManagerTheme.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                TaskManagerHistoryChart(
                    values: values,
                    secondary: secondary,
                    range: range,
                    unit: unit,
                    upperScaleLabel: upperScaleLabel,
                    lowerScaleLabel: lowerScaleLabel
                )
                    .frame(height: 138)
                    .padding(.horizontal, 12)
                HStack {
                    Text("−\(historyMinutes) min")
                    Spacer()
                    Text("Now")
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(TaskManagerTheme.muted)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    private var cpuPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "CPU usage", value: service.snapshot?.cpuUsage.map(Self.decimal) ?? "—", unit: "%",
                detail: "Across \(ProcessInfo.processInfo.activeProcessorCount) logical cores",
                values: recentHistory.compactMap(\.cpuUsage), range: 0...100,
                upperScaleLabel: "100%", lowerScaleLabel: "0%",
                stats: [
                    ("User", service.snapshot?.cpuDetails.map { "\(Int($0.user.rounded()))%" } ?? "—"),
                    ("System", service.snapshot?.cpuDetails.map { "\(Int($0.system.rounded()))%" } ?? "—"),
                    ("Idle", service.snapshot?.cpuDetails.map { "\(Int($0.idle.rounded()))%" } ?? "—"),
                ]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Core activity")
                            .font(.system(size: 11, weight: .semibold))
                        Text(coreLayoutDescription)
                            .font(.system(size: 8.5))
                            .foregroundStyle(TaskManagerTheme.secondary)
                    }
                    Spacer(minLength: 8)
                    if TaskManagerHardwareSummary.coreLayout != nil {
                        HStack(spacing: 10) {
                            coreLegend("Performance", color: TaskManagerTheme.accent)
                            coreLegend("Efficiency", color: TaskManagerTheme.secondary)
                        }
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(TaskManagerTheme.window.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(TaskManagerTheme.lineSoft)
                    }
                }
            }
            .padding(12)
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
              index >= layout.performance else { return TaskManagerTheme.accent }
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
                values: recentHistory.compactMap(\.gpuUsage), range: 0...100,
                upperScaleLabel: "100%", lowerScaleLabel: "0%",
                stats: [("Memory", "Unified"), ("Thermal pressure", service.snapshot?.thermalState ?? "—")]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                informationPanel("Graphics details", rows: [
                    ("Architecture", "Integrated"), ("Memory", "Unified"),
                    ("Utilization", percent(service.snapshot?.gpuUsage)),
                ])
                informationPanel("Engine activity", rows: [
                    ("Combined activity", percent(service.snapshot?.gpuUsage)),
                    ("Per-engine counters", "Not exposed by macOS"),
                ])
            }
        }
    }

    private var memoryPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "Memory in use", value: service.snapshot?.memoryUsed.map(Self.bytes) ?? "—",
                detail: "\(service.snapshot?.memoryTotal.map(Self.bytes) ?? "—") unified memory",
                values: recentHistory.compactMap { $0.memoryUsed.map(Double.init) },
                range: 0...Double(max(service.snapshot?.memoryTotal ?? 1, 1)),
                upperScaleLabel: service.snapshot?.memoryTotal.map(Self.bytes) ?? "—",
                lowerScaleLabel: "0 GB",
                stats: [("Used", service.snapshot?.memoryUsage.percent ?? "—"), ("Available", memoryAvailable)]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Allocation").font(.system(size: 11, weight: .medium))
                    memoryAllocationPanel.frame(height: 203)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("Virtual memory").font(.system(size: 11, weight: .medium))
                    informationPanel("Memory details", rows: [
                        ("Swap used", service.snapshot?.memoryDetails?.swapUsed.map(Self.bytes) ?? "Unavailable"),
                        ("Compressed", service.snapshot?.memoryDetails.map { Self.bytes($0.compressed) } ?? "—"),
                        ("Cached files", service.snapshot?.memoryDetails.map { Self.bytes($0.cached) } ?? "—"),
                        ("Page-ins", service.snapshot?.memoryDetails.map { "\($0.pageIns.formatted()) pages" } ?? "—"),
                        ("Page-outs", service.snapshot?.memoryDetails.map { "\($0.pageOuts.formatted()) pages" } ?? "—"),
                    ])
                }
            }
        }
    }

    private var networkPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "Download", value: service.snapshot?.networkDownload.map(Self.rate) ?? "—",
                detail: "All active non-loopback interfaces",
                values: recentHistory.compactMap(\.networkDownload),
                secondary: recentHistory.compactMap(\.networkUpload), range: networkRange,
                upperScaleLabel: Self.rate(networkRange.upperBound), lowerScaleLabel: "0 KB/s",
                seriesLabels: ("Download", "Upload"),
                stats: [
                    ("Upload", service.snapshot?.networkUpload.map(Self.rate) ?? "—"),
                    ("Interface", service.snapshot?.networkDetails?.interfaceName ?? "—"),
                ]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                informationPanel("Interface", rows: [
                    ("Name", service.snapshot?.networkDetails?.interfaceName ?? "—"),
                    ("Local address", service.snapshot?.networkDetails?.localAddress ?? "Unavailable"),
                    ("Transferred down", service.snapshot?.networkDetails.map { Self.bytes($0.receivedTotal) } ?? "—"),
                    ("Transferred up", service.snapshot?.networkDetails.map { Self.bytes($0.sentTotal) } ?? "—"),
                ])
                informationPanel("Activity", rows: [
                    ("Download", service.snapshot?.networkDownload.map(Self.rate) ?? "—"),
                    ("Upload", service.snapshot?.networkUpload.map(Self.rate) ?? "—"),
                    ("Process endpoints", "Available in Process Information"),
                ])
            }
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
                            metricValue(service.snapshot?.diskUsed.map(Self.bytes) ?? "—", valueSize: 27, unitSize: 12)
                            Text("used of \(service.snapshot?.diskTotal.map(Self.bytes) ?? "—")")
                                .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                        }
                        Spacer()
                        detailStat("Available", diskAvailable)
                        detailStat("Used", service.snapshot?.diskUsage.percent ?? "—")
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            Rectangle().fill(TaskManagerTheme.ink.opacity(0.76))
                                .frame(width: proxy.size.width * CGFloat((service.snapshot?.diskUsage ?? 0) / 100))
                            Rectangle().fill(TaskManagerTheme.lineSoft)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(12)
            }
            detailHero(
                label: "Disk activity",
                value: service.snapshot?.diskDetails?.readPerSecond.map(Self.rate) ?? "—",
                detail: "Read throughput across physical storage",
                values: recentHistory.compactMap { $0.diskDetails?.readPerSecond },
                secondary: recentHistory.compactMap { $0.diskDetails?.writePerSecond },
                range: diskRateRange,
                upperScaleLabel: Self.rate(diskRateRange.upperBound), lowerScaleLabel: "0 KB/s",
                seriesLabels: ("Read", "Write"),
                stats: [
                    ("Write", service.snapshot?.diskDetails?.writePerSecond.map(Self.rate) ?? "—"),
                    ("Read total", service.snapshot?.diskDetails.map { Self.bytes($0.readTotal) } ?? "—"),
                ]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                informationPanel("Volume", rows: [("Mount point", "/"), ("Used", service.snapshot?.diskUsed.map(Self.bytes) ?? "—"), ("Available", diskAvailable)])
                informationPanel("Storage", rows: [
                    ("Capacity", service.snapshot?.diskTotal.map(Self.bytes) ?? "—"),
                    ("Read", service.snapshot?.diskDetails?.readPerSecond.map(Self.rate) ?? "—"),
                    ("Write", service.snapshot?.diskDetails?.writePerSecond.map(Self.rate) ?? "—"),
                    ("Status", "Mounted"),
                ])
            }
        }
    }

    private var batteryPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "Battery charge", value: service.snapshot?.batteryPercent.map(String.init) ?? "—", unit: "%",
                detail: batteryDetail,
                values: recentHistory.compactMap { $0.batteryPercent.map(Double.init) }, range: 0...100,
                upperScaleLabel: "100%", lowerScaleLabel: "0%",
                stats: [("Power source", powerSourceDetail), ("Status", batteryDetail)]
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                informationPanel("Battery details", rows: [
                    ("Charge", service.snapshot?.batteryPercent.map { "\($0)%" } ?? "—"),
                    ("Power source", powerSourceDetail),
                    ("Health", service.snapshot?.batteryDetails?.health ?? "Unavailable"),
                    ("Cycle count", service.snapshot?.batteryDetails?.cycleCount.map(String.init) ?? "Unavailable"),
                    ("Voltage", service.snapshot?.batteryDetails?.voltageMillivolts.map { "\($0) mV" } ?? "Unavailable"),
                    ("Amperage", service.snapshot?.batteryDetails?.amperageMilliamps.map { "\($0) mA" } ?? "Unavailable"),
                ])
                powerDrawPanel
            }
        }
    }

    private var powerDrawPanel: some View {
        let values = recentHistory.compactMap(Self.powerDraw)
        return TaskManagerPanel(textured: true) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Power draw", systemImage: "bolt")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TaskManagerTheme.secondary)
                metricValue(
                    service.snapshot.flatMap(Self.powerDraw).map { "\(Self.decimal($0)) W" } ?? "Unavailable",
                    valueSize: 27,
                    unitSize: 12
                )
                TaskManagerHistoryChart(
                    values: values,
                    range: 0...max((values.max() ?? 1) * 1.15, 1),
                    unit: " W",
                    compact: true
                )
                .frame(height: 82)
                Spacer(minLength: 0)
                Text("Calculated from battery voltage and current when macOS reports both values.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(TaskManagerTheme.muted)
            }
            .padding(12)
        }
    }

    private var sensorsPage: some View {
        VStack(spacing: 10) {
            detailHero(
                label: "Thermal pressure", value: service.snapshot?.thermalState ?? "—",
                detail: "System-reported thermal state",
                values: recentHistory.compactMap { Self.thermalLevel($0.thermalState) }, range: 0...100,
                upperScaleLabel: "Critical", lowerScaleLabel: "Nominal",
                stats: [("State", service.snapshot?.thermalState ?? "—"), ("Temperature", "Hardware dependent")]
            )
            informationPanel("Temperature sensors", rows: [
                ("System pressure", service.snapshot?.thermalState ?? "—"),
                ("Per-sensor temperatures", "Unavailable through public macOS APIs"),
            ])
            FanControlView(owner: "system-monitor-window")
        }
    }

    private var settingsPage: some View {
        OnePlusPage(header: { EmptyView() }) {
            SystemMonitorSettingsContent()
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 16) {
            TaskManagerPanel(textured: true) {
                HStack(spacing: 20) {
                    Image("SystemMonitorLogo")
                        .resizable().scaledToFit().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        TaskManagerDotTitle(text: "Task Manager", height: 24)
                        Text("A focused view of your Mac's activity.")
                            .font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary)
                    }
                    Spacer()
                }
                .padding(22)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                aboutPanel("Main window", icon: "display", text: "Processes, compute, memory, storage, network, battery, and thermal activity in dedicated workspaces.")
                aboutPanel("Menu bar", icon: "chart.bar.xaxis", text: "A compact panel with icon tabs, live metrics, remote instances, processes, and fan controls.")
            }
            informationPanel("Keyboard shortcuts", rows: [("Find a process", "⌘ K"), ("Dismiss a sheet or menu", "Esc")])
        }
    }

    private func informationPanel(_ title: String, rows: [(String, String)]) -> some View {
        TaskManagerPanel {
            VStack(spacing: 0) {
                HStack { Text(title).font(.system(size: 10.5, weight: .medium)); Spacer() }
                    .padding(.horizontal, 14).frame(height: 42)
                rowDivider
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text(rows[index].0).foregroundStyle(TaskManagerTheme.secondary)
                        Spacer(minLength: 12)
                        Text(rows[index].1)
                            .foregroundStyle(TaskManagerTheme.ink)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    if index < rows.count - 1 { rowDivider }
                }
            }
        }
    }

    private func aboutPanel(_ title: String, icon: String, text: String) -> some View {
        TaskManagerPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.system(size: 21)).foregroundStyle(TaskManagerTheme.secondary)
                Text(title).font(.system(size: 11, weight: .medium))
                Text(text).font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary).lineSpacing(4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
        }
    }

    private func sectionHeader(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        return HStack {
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Button(action, action: perform)
                .font(.system(size: 9)).foregroundStyle(TaskManagerTheme.secondary)
                .buttonStyle(.plain).focusEffectDisabled()
        }
        .frame(minHeight: 17)
    }

    private func reportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
        }
        .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
        .help(label)
        .accessibilityLabel(label)
    }

    private func tableHeader(_ columns: [(String, CGFloat?)]) -> some View {
        HStack(spacing: 8) {
            ForEach(columns.indices, id: \.self) { index in
                Text(columns[index].0.uppercased())
                    .font(.system(size: 8))
                    .tracking(0.4)
                    .foregroundStyle(TaskManagerTheme.muted)
                    .frame(width: columns[index].1, alignment: columns[index].1 == nil ? .leading : .trailing)
                    .frame(maxWidth: columns[index].1 == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .onePlusTableHeader()
    }

    private func processIdentity(_ process: SystemMonitorProcess) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.055))
                .overlay { Image(systemName: "app").font(.system(size: 10)).foregroundStyle(TaskManagerTheme.secondary) }
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(TaskManagerTheme.line) }
                .frame(width: 18, height: 18)
            Text(process.name).font(.system(size: 10)).foregroundStyle(TaskManagerTheme.ink).lineLimit(1)
        }
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
            Text(value).font(.system(size: 12, design: .monospaced))
        }
        .padding(.leading, 24)
    }

    private func metricValue(_ text: String, valueSize: CGFloat, unitSize: CGFloat) -> some View {
        let parts = TaskManagerMetricText.parts(text)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(parts.value)
                .font(.system(size: valueSize, weight: .medium))
                .tracking(-0.7)
                .monospacedDigit()
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: unitSize))
                    .foregroundStyle(TaskManagerTheme.secondary)
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
        return "\(Self.bytes(used)) / \(Self.bytes(total))"
    }

    private var memoryAvailable: String {
        guard let used = service.snapshot?.memoryUsed, let total = service.snapshot?.memoryTotal else { return "—" }
        return Self.bytes(max(total - used, 0))
    }

    private var diskAvailable: String {
        guard let used = service.snapshot?.diskUsed, let total = service.snapshot?.diskTotal else { return "—" }
        return Self.bytes(max(total - used, 0))
    }

    private var batteryDetail: String {
        guard service.snapshot?.batteryPercent != nil else { return "No internal battery detected" }
        return service.snapshot?.batteryCharging == true ? "Connected to power" : "On battery"
    }

    private var loadValue: String { service.snapshot?.loadAverage.map { Self.decimal($0.0) } ?? "—" }
    private var loadExplanation: String {
        "Load is the average number of processes running or waiting for a CPU. Compare it with \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs. It is not a percentage."
    }
    private var loadRange: ClosedRange<Double> {
        0...Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    }
    private var networkRange: ClosedRange<Double> {
        let maximum = recentHistory.flatMap { [$0.networkDownload, $0.networkUpload] }.compactMap { $0 }.max() ?? 1
        return 0...max(maximum * 1.15, 1)
    }

    private var diskRateRange: ClosedRange<Double> {
        let maximum = recentHistory.flatMap {
            [$0.diskDetails?.readPerSecond, $0.diskDetails?.writePerSecond]
        }.compactMap { $0 }.max() ?? 1
        return 0...max(maximum * 1.15, 1)
    }

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
              let charging = service.snapshot?.batteryCharging else { return "Unavailable" }
        return charging ? "AC adapter" : "Battery"
    }

    private func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "—" }

    private func sampleOverviewProcesses() async {
        guard page == .overview else { return }
        while !Task.isCancelled {
            overviewProcesses = await overviewSampler.sample()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    nonisolated private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 2 : 1)))
    }
    nonisolated private static func rate(_ value: Double) -> String {
        SystemMonitorDisplayFormat.byteRate(value)
    }
    nonisolated private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(value, 0), countStyle: .memory)
    }
    nonisolated private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .memory)
    }
    nonisolated private static func thermalLevel(_ state: String?) -> Double? {
        switch state {
        case "Nominal": 20
        case "Fair": 50
        case "Serious": 75
        case "Critical": 100
        default: nil
        }
    }

    nonisolated private static func powerDraw(_ sample: SystemMonitorSample) -> Double? {
        guard let voltage = sample.batteryDetails?.voltageMillivolts,
              let amperage = sample.batteryDetails?.amperageMilliamps else { return nil }
        return Double(voltage) * Double(abs(amperage)) / 1_000_000
    }
}

struct SystemMonitorSettingsContent: View {
    @State private var service = SystemMonitorService.shared
    @State private var expandedMetric: SystemMonitorMenuMetric?
    @AppStorage("systemMonitor.rememberTrayPage") private var rememberPanel = true
    @AppStorage("systemMonitor.historyMinutes") private var historyMinutes = 2

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            displaySection
            itemsSection
        }
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
                    choices: [(1, "1 minute"), (2, "2 minutes"), (5, "5 minutes")],
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
            Text("").frame(width: 28)
            Text("Metric").frame(width: 110, alignment: .leading)
            Text("Placement").frame(width: 106, alignment: .leading)
            Text("Style").frame(width: 104, alignment: .leading)
            Text("Update").frame(width: 100, alignment: .leading)
            Text("Format").frame(width: 162, alignment: .leading)
            Text("").frame(width: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onePlusTableHeader()
    }

    private func itemRow(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                reorderMenu(item.metric).frame(width: 28)
                Label(item.metric.title, systemImage: item.symbol)
                    .onePlusText(.row)
                    .frame(width: 110, alignment: .leading)
                    .lineLimit(1)
                placementControl(item).frame(width: 106)
                styleControl(item).frame(width: 104)
                intervalControl(item).frame(width: 100)
                formatControl(item).frame(width: 162)
                Button {
                    expandedMetric = expandedMetric == item.metric ? nil : item.metric
                } label: {
                    Image(systemName: expandedMetric == item.metric ? "chevron.up" : "ellipsis")
                }
                .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                .frame(width: 28)
                .accessibilityLabel("\(item.metric.title) details")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 34)
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
            width: 106,
            accessibilityLabel: "\(item.metric.title) menu bar placement"
        )
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).placement")
    }

    private func styleControl(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        TaskManagerSelect(
            choices: SystemMonitorMenuItemStyle.allCases.map { ($0, $0.title) },
            selection: itemSetting(item, get: { $0.style }, set: { $0.style = $1 }),
            width: 104,
            accessibilityLabel: "\(item.metric.title) style"
        )
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).style")
    }

    private func intervalControl(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        TaskManagerSelect(
            choices: item.metric.supportedIntervals(global: service.menuSettings.interval)
                .map { ($0, $0.title) },
            selection: itemSetting(item, get: { $0.interval }, set: { $0.interval = $1 }),
            width: 100,
            accessibilityLabel: "\(item.metric.title) update interval"
        )
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).interval")
    }

    @ViewBuilder
    private func formatControl(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        switch item.metric {
        case .memory:
            TaskManagerSelect(
                choices: SystemMonitorMemoryUnit.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.memoryUnit }, set: { $0.memoryUnit = $1 }),
                width: 162,
                accessibilityLabel: "Memory format"
            )
        case .disk:
            TaskManagerSelect(
                choices: SystemMonitorDiskUnit.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.diskUnit }, set: { $0.diskUnit = $1 }),
                width: 162,
                accessibilityLabel: "Disk format"
            )
        case .network:
            TaskManagerSelect(
                choices: SystemMonitorNetworkUnit.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.networkUnit }, set: { $0.networkUnit = $1 }),
                width: 162,
                accessibilityLabel: "Network format"
            )
        case .battery:
            TaskManagerSelect(
                choices: SystemMonitorBatteryDisplay.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.batteryDisplay }, set: { $0.batteryDisplay = $1 }),
                width: 162,
                accessibilityLabel: "Battery format"
            )
        case .thermal:
            TaskManagerSelect(
                choices: SystemMonitorThermalDisplay.allCases.map { ($0, $0.title) },
                selection: itemSetting(item, get: { $0.thermalDisplay }, set: { $0.thermalDisplay = $1 }),
                width: 162,
                accessibilityLabel: "Thermal format"
            )
        case .cpu, .gpu:
            Text("Default")
                .onePlusText(.control)
                .frame(width: 162, alignment: .leading)
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
        .focusEffectDisabled()
        .fixedSize()
        .help("Reorder \(metric.title)")
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
