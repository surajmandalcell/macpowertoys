import SwiftUI

private enum SystemMonitorPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processor = "Processor"
    case memory = "Memory"
    case network = "Network & Disk"
    case menuBar = "Menu Bar"
    case about = "About"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "chart.xyaxis.line"
        case .processor: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .menuBar: "menubar.rectangle"
        case .about: "info.circle"
        }
    }
}

struct SystemMonitorWindowView: View {
    @State private var service = SystemMonitorService.shared
    @State private var page = SystemMonitorPage.overview

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: UtilityLayout.dataSidebarWidth)
            content
                .utilityContentTransition(value: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "system-monitor"))
        .onAppear { service.startDetailed() }
        .onDisappear { service.stopDetailed() }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar)
            SidebarTitle(text: "System Monitor")
            VStack(spacing: 4) {
                ForEach(SystemMonitorPage.allCases) { item in
                    SidebarRow(icon: item.icon, title: item.rawValue, isSelected: page == item) {
                        page = item
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, UtilityLayout.workspaceContentTopInset)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .overview: overviewPage
        case .processor: processorPage
        case .memory: memoryPage
        case .network: networkPage
        case .menuBar: menuBarPage
        case .about: ToolAboutView(toolId: "system-monitor")
        }
    }

    private var overviewPage: some View {
        WorkspacePage("Overview", subtitle: "Live while this window is open") {
            metricGrid
            VStack(alignment: .leading, spacing: 10) {
                Text("LAST TWO MINUTES").utilitySectionHeader()
                LazyVGrid(columns: chartColumns, spacing: 12) {
                    chartCard(title: "CPU", suffix: "%", values: service.history.compactMap(\.cpuUsage))
                    chartCard(title: "Memory", suffix: "%", values: service.history.compactMap(\.memoryUsage))
                    chartCard(
                        title: "Download",
                        suffix: "/s",
                        values: service.history.compactMap(\.networkDownload),
                        formatter: Self.rate
                    )
                }
            }
        }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200), spacing: 12)]
    }

    private var chartColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320), spacing: 12)]
    }

    private var metricGrid: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            metricCard(
                icon: "cpu",
                title: "CPU",
                value: service.snapshot?.cpuUsage.percent ?? "Priming…",
                detail: loadDetail
            )
            metricCard(
                icon: "memorychip",
                title: "Memory",
                value: service.snapshot?.memoryUsage.percent ?? "Not available",
                detail: memoryDetail
            )
            metricCard(
                icon: "internaldrive",
                title: "Disk",
                value: service.snapshot?.diskUsage.percent ?? "Not available",
                detail: diskDetail
            )
            metricCard(
                icon: "arrow.down.circle",
                title: "Network",
                value: service.snapshot?.networkDownload.map(Self.rate) ?? "Priming…",
                detail: "Upload \(service.snapshot?.networkUpload.map(Self.rate) ?? "not available")"
            )
            metricCard(
                icon: "thermometer.medium",
                title: "Thermal",
                value: service.snapshot?.thermalState ?? "Not available",
                detail: "System pressure"
            )
            metricCard(
                icon: "battery.75percent",
                title: "Battery",
                value: service.snapshot?.batteryPercent.map { "\($0)%" } ?? "Not available",
                detail: batteryDetail
            )
        }
    }

    private func metricCard(icon: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .utilityAnimation(value: value)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(Color.primary.opacity(0.03))
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
            StatsSparkline(values: values)
                .frame(height: 80)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var processorPage: some View {
        WorkspacePage("Processor", subtitle: "System load and pressure") {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                metricCard(icon: "cpu", title: "Usage", value: service.snapshot?.cpuUsage.percent ?? "Priming…", detail: "User + system + nice")
                metricCard(icon: "chart.bar", title: "Load Average", value: loadAverage, detail: "1, 5, and 15 minute run queue")
                metricCard(icon: "thermometer.medium", title: "Thermal", value: service.snapshot?.thermalState ?? "Not available", detail: "System thermal pressure")
            }
            chartCard(title: "CPU Usage", suffix: "%", values: service.history.compactMap(\.cpuUsage))
        }
    }

    private var memoryPage: some View {
        WorkspacePage("Memory", subtitle: "Physical and compressed memory") {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                metricCard(icon: "memorychip", title: "Used", value: service.snapshot?.memoryUsed.map(\.bytes) ?? "Not available", detail: memoryDetail)
                metricCard(icon: "square.stack.3d.up", title: "Physical", value: service.snapshot?.memoryTotal.map(\.bytes) ?? "Not available", detail: "Installed unified memory")
                metricCard(icon: "gauge.with.dots.needle.50percent", title: "Utilization", value: service.snapshot?.memoryUsage.percent ?? "Not available", detail: "Used physical memory")
            }
            chartCard(title: "Memory Utilization", suffix: "%", values: service.history.compactMap(\.memoryUsage))
        }
    }

    private var networkPage: some View {
        WorkspacePage("Network & Disk", subtitle: "Current rates and startup disk use") {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                metricCard(icon: "arrow.down", title: "Download", value: service.snapshot?.networkDownload.map(Self.rate) ?? "Priming…", detail: "All active non-loopback interfaces")
                metricCard(icon: "arrow.up", title: "Upload", value: service.snapshot?.networkUpload.map(Self.rate) ?? "Priming…", detail: "All active non-loopback interfaces")
                metricCard(icon: "internaldrive", title: "Disk Used", value: service.snapshot?.diskUsed.map(\.bytes) ?? "Not available", detail: diskDetail)
            }
            LazyVGrid(columns: chartColumns, spacing: 12) {
                chartCard(title: "Download", suffix: "/s", values: service.history.compactMap(\.networkDownload), formatter: Self.rate)
                chartCard(title: "Upload", suffix: "/s", values: service.history.compactMap(\.networkUpload), formatter: Self.rate)
            }
        }
    }

    private var menuBarPage: some View {
        WorkspacePage("Menu Bar", subtitle: "Optional lightweight status") {
            SystemMonitorMenuSettingsView(showsContainerScroll: false)
        }
    }

    private var loadDetail: String {
        service.snapshot?.loadAverage.map { "Load \($0.0.formatted(.number.precision(.fractionLength(2))))" } ?? "Waiting for first delta"
    }

    private var loadAverage: String {
        service.snapshot?.loadAverage.map {
            [$0.0, $0.1, $0.2].map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: " · ")
        } ?? "Not available"
    }

    private var memoryDetail: String {
        guard let used = service.snapshot?.memoryUsed, let total = service.snapshot?.memoryTotal else { return "Host memory counters" }
        return "\(used.bytes) of \(total.bytes)"
    }

    private var diskDetail: String {
        guard let used = service.snapshot?.diskUsed, let total = service.snapshot?.diskTotal else { return "Startup volume" }
        return "\(used.bytes) of \(total.bytes)"
    }

    private var batteryDetail: String {
        guard service.snapshot?.batteryPercent != nil else { return "No internal battery detected" }
        return service.snapshot?.batteryCharging == true ? "Connected to power" : "On battery"
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    menuToggle
                    Spacer(minLength: 12)
                    layoutControl
                    globalIntervalControl
                }

                VStack(alignment: .leading, spacing: 10) {
                    menuToggle
                    HStack(spacing: 16) {
                        layoutControl
                        globalIntervalControl
                    }
                }
            }
        }
        .utilitySectionCard()
    }

    private var menuToggle: some View {
        Toggle("Show in menu bar", isOn: menuSetting(
            get: { $0.enabled },
            set: { $0.enabled = $1 }
        ))
        .toggleStyle(.switch)
        .accessibilityIdentifier("system-monitor.menu.enabled")
    }

    private var layoutControl: some View {
        settingControl("LAYOUT", width: 112) {
            Picker("Layout", selection: menuSetting(
                get: { $0.mode },
                set: { $0.mode = $1 }
            )) {
                ForEach(SystemMonitorMenuMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("Menu bar layout")
            .accessibilityIdentifier("system-monitor.menu.layout")
        }
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

            VStack(spacing: 0) {
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

            Toggle(item.metric.title, isOn: itemSetting(
                item,
                get: { $0.enabled },
                set: { $0.enabled = $1 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel("Show \(item.metric.title) in the menu bar")
            .accessibilityIdentifier("system-monitor.menu.item.\(item.metric.rawValue).enabled")

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

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maximum = values.max(), let minimum = values.min() else { return }
            let range = max(maximum - minimum, 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
                    y: size.height - CGFloat((value - minimum) / range) * size.height
                )
                if index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
