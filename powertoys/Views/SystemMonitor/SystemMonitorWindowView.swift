import SwiftUI

enum SystemMonitorPalette {
    // Coolors: 264653-2a9d8f-e9c46a-f4a261-e76f51 and
    // 004e64-00a5cf-9fffcb-25a18e-7ae582 and 457b9d-a8dadc-f1faee-e63946.
    static let teal = Color(red: 42.0 / 255, green: 157.0 / 255, blue: 143.0 / 255)
    static let coral = Color(red: 231.0 / 255, green: 111.0 / 255, blue: 81.0 / 255)
    static let gold = Color(red: 233.0 / 255, green: 196.0 / 255, blue: 106.0 / 255)
    static let orange = Color(red: 244.0 / 255, green: 162.0 / 255, blue: 97.0 / 255)
    static let cyan = Color(red: 0, green: 165.0 / 255, blue: 207.0 / 255)
    static let green = Color(red: 122.0 / 255, green: 229.0 / 255, blue: 130.0 / 255)
    static let blue = Color(red: 69.0 / 255, green: 123.0 / 255, blue: 157.0 / 255)

    static func gradient(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint.opacity(0.29), tint.opacity(0.12), tint.opacity(0.17)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct SystemMonitorPlacementPicker: View {
    let metric: SystemMonitorMenuMetric
    @Binding var selection: SystemMonitorMenuPlacement

    var body: some View {
        Picker("\(metric.title) menu bar", selection: $selection) {
            ForEach(SystemMonitorMenuPlacement.allCases) { placement in
                Text(placement.title).tag(placement)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 204, height: UtilityLayout.workspaceActionHeight)
        .help("Show \(metric.title) in the combined menu bar item, a separate item, or neither")
        .accessibilityIdentifier("system-monitor.\(metric.rawValue).menu-placement")
    }
}

private enum SystemMonitorPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Processes"
    case processor = "CPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"
    case remote = "Remote Stats"
    case about = "About"

    var id: String { rawValue }
    var detailedMetrics: Set<SystemMonitorMenuMetric> {
        switch self {
        case .overview: Set(SystemMonitorMenuMetric.allCases)
        case .processor: [.cpu, .thermal]
        case .memory: [.memory]
        case .network: [.network]
        case .disk: [.disk]
        case .processes, .remote, .about: []
        }
    }
    var icon: String {
        switch self {
        case .overview: "chart.xyaxis.line"
        case .processor: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .processes: "list.bullet.rectangle"
        case .remote: "server.rack"
        case .about: "info.circle"
        }
    }
}

struct SystemMonitorWindowView: View {
    @State private var service = SystemMonitorService.shared
    @State private var page = SystemMonitorPage.overview
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: UtilityLayout.compactSidebarWidth)
            content
                .utilityContentTransition(value: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colorScheme == .dark
                    ? Color(red: 0.115, green: 0.108, blue: 0.102)
                    : Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "system-monitor"))
        .onAppear { service.startDetailed(metrics: page.detailedMetrics) }
        .onChange(of: page) { _, newPage in
            service.updateDetailed(metrics: newPage.detailedMetrics)
        }
        .onDisappear { service.stopDetailed() }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            (colorScheme == .dark
                ? Color(red: 0.13, green: 0.122, blue: 0.116)
                : Color(nsColor: .controlBackgroundColor))
            SidebarTitle(text: "System Monitor")
            VStack(spacing: 4) {
                ForEach(SystemMonitorPage.allCases) { item in
                    SidebarRow(icon: item.icon, title: item.rawValue, isSelected: page == item,
                               customSelectionColor: Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12)) {
                        page = item
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, UtilityLayout.workspaceContentTopInset)
            .padding(.bottom, 12)
            .tint(.gray)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .overview: overviewPage
        case .processor: processorPage
        case .memory: memoryPage
        case .network: networkPage
        case .disk: diskPage
        case .processes: SystemMonitorProcessesView()
        case .remote: SystemMonitorRemoteView()
        case .about: ToolAboutView(toolId: "system-monitor", showsSettings: false)
        }
    }

    private var overviewPage: some View {
        WorkspacePage("Overview") {
            metricGrid
            FanControlView(owner: "system-monitor-window")
        }
    }

    private func menuPlacement(_ metric: SystemMonitorMenuMetric) -> some View {
        let selection = Binding<SystemMonitorMenuPlacement>(
            get: {
                guard let item = service.menuSettings.items.first(where: { $0.metric == metric }),
                      service.menuSettings.enabled, item.enabled else { return .off }
                return item.placement
            },
            set: { placement in
                service.updateMenuSettings { $0.setPlacement(placement, for: metric) }
            }
        )
        return SystemMonitorPlacementPicker(metric: metric, selection: selection)
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200), spacing: 12)]
    }

    private var chartColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320), spacing: 12)]
    }

    private var metricGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(
                    icon: "cpu",
                    title: "CPU",
                    value: service.snapshot?.cpuUsage.map { "\(Int($0.rounded()))%" } ?? "...",
                    detail: "All cores",
                    values: service.history.compactMap(\.cpuUsage),
                    tint: usageTint(service.snapshot?.cpuUsage),
                    surfaceTint: SystemMonitorPalette.teal,
                    featured: true
                )
                metricCard(
                    icon: "memorychip",
                    title: "Memory",
                    value: service.snapshot?.memoryUsage.percent ?? "Not available",
                    detail: memoryDetail,
                    values: service.history.compactMap(\.memoryUsage),
                    tint: usageTint(service.snapshot?.memoryUsage),
                    surfaceTint: SystemMonitorPalette.coral,
                    featured: true
                )
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                metricCard(
                    icon: "rectangle.3.group",
                    title: "GPU",
                    value: service.snapshot?.gpuUsage.percent ?? "Not available",
                    detail: "Graphics utilization",
                    values: service.history.compactMap(\.gpuUsage),
                    tint: usageTint(service.snapshot?.gpuUsage),
                    surfaceTint: SystemMonitorPalette.blue
                )
                metricCard(
                    icon: "internaldrive",
                    title: "Disk",
                    value: service.snapshot?.diskUsage.percent ?? "Not available",
                    detail: diskDetail,
                    values: service.history.compactMap(\.diskUsage),
                    tint: usageTint(service.snapshot?.diskUsage),
                    surfaceTint: SystemMonitorPalette.orange
                )
                metricCard(
                    icon: "arrow.down.circle",
                    title: "Network",
                    value: service.snapshot?.networkDownload.map(Self.rate) ?? "...",
                    detail: "Upload \(service.snapshot?.networkUpload.map(Self.rate) ?? "...")",
                    values: service.history.compactMap { sample in
                        guard let down = sample.networkDownload, let up = sample.networkUpload else { return nil }
                        return max(down, up)
                    },
                    tint: SystemMonitorPalette.cyan
                )
                metricCard(
                    icon: "thermometer.medium",
                    title: "Thermal",
                    value: service.snapshot?.thermalState ?? "Not available",
                    detail: "System pressure",
                    values: service.history.compactMap { Self.thermalLevel($0.thermalState) },
                    tint: thermalTint,
                    surfaceTint: SystemMonitorPalette.green
                )
                metricCard(
                    icon: "battery.75percent",
                    title: "Battery",
                    value: service.snapshot?.batteryPercent.map { "\($0)%" } ?? "Not available",
                    detail: batteryDetail,
                    values: service.history.compactMap { $0.batteryPercent.map(Double.init) },
                    tint: batteryTint,
                    surfaceTint: SystemMonitorPalette.gold
                )
                metricCard(
                    icon: "chart.bar",
                    title: "Load · 1 min",
                    value: loadAverage,
                    detail: "Average CPU demand · \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs",
                    values: service.history.compactMap { $0.loadAverage.map { $0.0 } },
                    tint: usageTint(loadLevel),
                    surfaceTint: SystemMonitorPalette.blue
                )
                .help(loadExplanation)
            }
        }
    }

    private func metricCard(
        icon: String,
        title: String,
        value: String,
        detail: String,
        values: [Double] = [],
        tint: Color = .gray,
        surfaceTint: Color? = nil,
        featured: Bool = false
    ) -> some View {
        let surface = surfaceTint ?? tint
        return ZStack(alignment: .bottom) {
            StatsSparkline(values: values, color: tint)
                .frame(height: featured ? 78 : 44)
                .opacity(0.58)
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? tint : .primary)
                Text(value)
                    .font(.system(size: featured ? 30 : 22, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .utilityAnimation(value: value)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(featured ? 18 : 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: featured ? 158 : 112)
        .background(SystemMonitorPalette.gradient(surface))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(surface.opacity(0.25)) }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chartCard(
        title: String,
        suffix: String,
        values: [Double],
        formatter: (Double) -> String = { "\(Int($0.rounded()))" }
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(values.last.map { formatter($0) + suffix } ?? "Not available")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            StatsSparkline(values: values)
                .frame(height: 80)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var processorPage: some View {
        WorkspacePage("CPU") {
            menuPlacement(.cpu)
        } content: {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                metricCard(icon: "cpu", title: "Usage", value: service.snapshot?.cpuUsage.map { "\(Int($0.rounded()))%" } ?? "...", detail: "User + system + nice")
                metricCard(icon: "chart.bar", title: "Load · 1 min", value: loadAverage, detail: loadAverageDetail)
                    .help(loadExplanation)
                metricCard(icon: "thermometer.medium", title: "Thermal", value: service.snapshot?.thermalState ?? "Not available", detail: "System thermal pressure")
            }
            chartCard(title: "CPU Usage", suffix: "%", values: service.history.compactMap(\.cpuUsage))
        }
    }

    private var memoryPage: some View {
        WorkspacePage("Memory") {
            menuPlacement(.memory)
        } content: {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                metricCard(icon: "memorychip", title: "Used", value: service.snapshot?.memoryUsed.map(\.bytes) ?? "Not available", detail: memoryDetail)
                metricCard(icon: "square.stack.3d.up", title: "Physical", value: service.snapshot?.memoryTotal.map(\.bytes) ?? "Not available", detail: "Installed unified memory")
                metricCard(icon: "gauge.with.dots.needle.50percent", title: "Utilization", value: service.snapshot?.memoryUsage.percent ?? "Not available", detail: "Used physical memory")
            }
            chartCard(title: "Memory Utilization", suffix: "%", values: service.history.compactMap(\.memoryUsage))
        }
    }

    private var networkPage: some View {
        WorkspacePage("Network") {
            menuPlacement(.network)
        } content: {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                metricCard(icon: "arrow.down", title: "Download", value: service.snapshot?.networkDownload.map(Self.rate) ?? "...", detail: "All active non-loopback interfaces")
                metricCard(icon: "arrow.up", title: "Upload", value: service.snapshot?.networkUpload.map(Self.rate) ?? "...", detail: "All active non-loopback interfaces")
            }
            LazyVGrid(columns: chartColumns, spacing: 12) {
                chartCard(title: "Download", suffix: "/s", values: service.history.compactMap(\.networkDownload), formatter: Self.rate)
                chartCard(title: "Upload", suffix: "/s", values: service.history.compactMap(\.networkUpload), formatter: Self.rate)
            }
        }
    }

    private var diskPage: some View {
        WorkspacePage("Disk") {
            menuPlacement(.disk)
        } content: {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                metricCard(icon: "internaldrive", title: "Used", value: service.snapshot?.diskUsed.map(\.bytes) ?? "Not available", detail: diskDetail)
                metricCard(icon: "internaldrive.fill", title: "Available", value: diskAvailable, detail: "Startup volume")
                metricCard(icon: "chart.pie", title: "Utilization", value: service.snapshot?.diskUsage.percent ?? "Not available", detail: "Startup volume")
            }
            chartCard(title: "Disk Utilization", suffix: "%", values: service.history.compactMap(\.diskUsage))
        }
    }

    private var loadAverage: String {
        service.snapshot?.loadAverage.map { $0.0.formatted(.number.precision(.fractionLength(2))) } ?? "..."
    }

    private var loadAverageDetail: String {
        guard let load = service.snapshot?.loadAverage else { return "..." }
        return "5m \(load.1.formatted(.number.precision(.fractionLength(2)))) · 15m \(load.2.formatted(.number.precision(.fractionLength(2))))"
    }

    private var loadExplanation: String {
        "Load is the average number of processes running or ready for a CPU. Compare it with \(ProcessInfo.processInfo.activeProcessorCount) logical CPUs. The 1-, 5-, and 15-minute averages show short and longer demand; they are not percentages."
    }

    private var loadLevel: Double? {
        service.snapshot?.loadAverage.map {
            min($0.0 / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1)) * 100, 100)
        }
    }

    private var memoryDetail: String {
        guard let used = service.snapshot?.memoryUsed, let total = service.snapshot?.memoryTotal else { return "Host memory counters" }
        return "\(used.bytes) of \(total.bytes)"
    }

    private var diskDetail: String {
        guard let used = service.snapshot?.diskUsed, let total = service.snapshot?.diskTotal else { return "Startup volume" }
        return "\(used.bytes) of \(total.bytes)"
    }

    private var diskAvailable: String {
        guard let used = service.snapshot?.diskUsed, let total = service.snapshot?.diskTotal else { return "Not available" }
        return max(total - used, 0).bytes
    }

    private var batteryDetail: String {
        guard service.snapshot?.batteryPercent != nil else { return "No internal battery detected" }
        return service.snapshot?.batteryCharging == true ? "Connected to power" : "On battery"
    }

    private var batteryTint: Color {
        guard let percent = service.snapshot?.batteryPercent else { return .gray }
        if service.snapshot?.batteryCharging == true { return .green }
        if percent < 20 { return .red }
        if percent < 50 { return .orange }
        return .blue
    }

    private var thermalTint: Color {
        switch service.snapshot?.thermalState {
        case "Critical": .red
        case "Serious": .orange
        case "Fair": .blue
        case "Nominal": .green
        default: .gray
        }
    }

    private func usageTint(_ value: Double?) -> Color {
        guard let value else { return .gray }
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        if value >= 35 { return .blue }
        return .green
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

    nonisolated private static func rate(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 0)), countStyle: .file)
    }
}

struct SystemMonitorMenuSettingsView: View {
    @State private var service = SystemMonitorService.shared
    let showsContainerScroll: Bool

    init(showsContainerScroll: Bool = true) {
        self.showsContainerScroll = showsContainerScroll
    }

    @ViewBuilder
    var body: some View {
        if showsContainerScroll {
            ScrollView {
                settingsContent
                    .padding(.horizontal, UtilityLayout.horizontalInset)
                    .padding(.vertical, 12)
            }
            .thinScrollIndicators()
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
            displaySection
            itemsSection
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISPLAY").utilitySectionHeader()
            globalIntervalControl
        }
        .utilitySectionCard()
    }

    private var globalIntervalControl: some View {
        settingControl("GLOBAL INTERVAL", width: 112) {
            Picker("Global interval", selection: menuSetting(
                get: { $0.interval },
                set: { $0.interval = $1 }
            )) {
                ForEach(SystemMonitorMenuInterval.allowedSeconds, id: \.self) { seconds in
                    Text(Self.intervalTitle(seconds)).tag(seconds)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityIdentifier("system-monitor.menu.global-interval")
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("MENU BAR ITEMS").utilitySectionHeader()
                Text("Drag to reorder")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            LazyVStack(spacing: 0) {
                ForEach(service.menuSettings.items) { item in
                    itemRow(item)
                    if item.metric != service.menuSettings.items.last?.metric {
                        QuietDivider()
                    }
                }
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func itemRow(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                itemIdentity(item)
                Spacer(minLength: 12)
                itemControls(item)
            }

            VStack(alignment: .leading, spacing: 8) {
                itemIdentity(item)
                itemControls(item)
                    .padding(.leading, 50)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .draggable(item.metric.rawValue)
        .dropDestination(for: String.self) { values, _ in
            guard let rawValue = values.first,
                  let source = SystemMonitorMenuMetric(rawValue: rawValue) else { return false }
            move(source, to: item.metric)
            return true
        }
        .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue)")
    }

    private func itemIdentity(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        HStack(spacing: 8) {
            reorderMenu(item.metric)

            Picker(item.metric.title, selection: Binding<SystemMonitorMenuPlacement>(
                get: {
                    guard let current = service.menuSettings.items.first(where: { $0.metric == item.metric }),
                          current.enabled else { return .off }
                    return current.placement
                },
                set: { placement in
                    service.updateMenuSettings { $0.setPlacement(placement, for: item.metric) }
                }
            )) {
                ForEach(SystemMonitorMenuPlacement.allCases) { placement in
                    Text(placement.title).tag(placement)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 120, height: UtilityLayout.workspaceActionHeight)
            .accessibilityLabel("\(item.metric.title) menu bar placement")
            .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).placement")

            Label(item.metric.title, systemImage: item.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 104, alignment: .leading)
                .lineLimit(1)
        }
    }

    private func itemControls(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                primaryItemControls(item)
                itemSpecificControl(item)
            }

            VStack(alignment: .leading, spacing: 6) {
                primaryItemControls(item)
                itemSpecificControl(item)
            }
        }
    }

    private func primaryItemControls(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            settingControl("STYLE", width: 92) {
                Picker("Style", selection: itemSetting(
                    item,
                    get: { $0.style },
                    set: { $0.style = $1 }
                )) {
                    ForEach(SystemMonitorMenuItemStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("\(item.metric.title) style")
                .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).style")
            }

            settingControl("ICON", width: 82) {
                Picker("Icon", selection: itemSetting(
                    item,
                    get: { $0.symbol },
                    set: { $0.symbol = $1 }
                )) {
                    ForEach(item.metric.symbols, id: \.self) { symbol in
                        Label(Self.iconTitle(symbol, for: item.metric), systemImage: symbol).tag(symbol)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("\(item.metric.title) icon")
                .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).icon")
            }

            settingControl("INTERVAL", width: 94) {
                Picker("Interval", selection: itemSetting(
                    item,
                    get: { $0.interval },
                    set: { $0.interval = $1 }
                )) {
                    ForEach(
                        item.metric.supportedIntervals(global: service.menuSettings.interval)
                    ) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("\(item.metric.title) interval")
                .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).interval")
            }
        }
    }

    @ViewBuilder
    private func itemSpecificControl(_ item: SystemMonitorMenuItemConfiguration) -> some View {
        switch item.metric {
        case .memory:
            settingControl("UNIT", width: 88) {
                Picker("Unit", selection: itemSetting(
                    item,
                    get: { $0.memoryUnit },
                    set: { $0.memoryUnit = $1 }
                )) {
                    ForEach(SystemMonitorMemoryUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Memory unit")
                .accessibilityIdentifier("system-monitor.menu.item.memory.unit")
            }
        case .disk:
            settingControl("UNIT", width: 88) {
                Picker("Unit", selection: itemSetting(
                    item,
                    get: { $0.diskUnit },
                    set: { $0.diskUnit = $1 }
                )) {
                    ForEach(SystemMonitorDiskUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Disk unit")
                .accessibilityIdentifier("system-monitor.menu.item.disk.unit")
            }
        case .network:
            HStack(alignment: .bottom, spacing: 10) {
                settingControl("DIRECTION", width: 100) {
                    Picker("Direction", selection: itemSetting(
                        item,
                        get: { $0.networkDirection },
                        set: { $0.networkDirection = $1 }
                    )) {
                        ForEach(SystemMonitorNetworkDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Network direction")
                    .accessibilityIdentifier("system-monitor.menu.item.network.direction")
                }

                settingControl("UNIT", width: 130) {
                    Picker("Unit", selection: itemSetting(
                        item,
                        get: { $0.networkUnit },
                        set: { $0.networkUnit = $1 }
                    )) {
                        ForEach(SystemMonitorNetworkUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Network unit")
                    .accessibilityIdentifier("system-monitor.menu.item.network.unit")
                }
            }
        case .battery:
            settingControl("DISPLAY", width: 150) {
                Picker("Display", selection: itemSetting(
                    item,
                    get: { $0.batteryDisplay },
                    set: { $0.batteryDisplay = $1 }
                )) {
                    ForEach(SystemMonitorBatteryDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Battery display")
                .accessibilityIdentifier("system-monitor.menu.item.battery.display")
            }
        case .thermal:
            settingControl("DISPLAY", width: 100) {
                Picker("Display", selection: itemSetting(
                    item,
                    get: { $0.thermalDisplay },
                    set: { $0.thermalDisplay = $1 }
                )) {
                    ForEach(SystemMonitorThermalDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Thermal display")
                .accessibilityIdentifier("system-monitor.menu.item.thermal.display")
            }
        default:
            EmptyView()
        }
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
                .foregroundStyle(.secondary)
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

    private func settingControl<Content: View>(
        _ label: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
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

private struct StatsSparkline: View {
    let values: [Double]
    var color: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maximum = values.max(), let minimum = values.min() else { return }
            let range = max(maximum - minimum, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
                    y: size.height - CGFloat((value - minimum) / range) * size.height
                )
            }
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: size.height))
            points.forEach { fill.addLine(to: $0) }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.14), color.opacity(0.01)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            var path = Path()
            for (index, point) in points.enumerated() {
                if index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color.opacity(0.72)), lineWidth: 1.5)
        }
        .accessibilityLabel("Recent \(values.last?.formatted() ?? "unavailable")")
    }
}

private extension Optional where Wrapped == Double {
    var percent: String { map { "\(Int($0.rounded()))%" } ?? "Not available" }
}

private extension Int64 {
    var bytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .memory) }
}

#Preview {
    SystemMonitorWindowView().frame(width: 1080, height: 720)
}
