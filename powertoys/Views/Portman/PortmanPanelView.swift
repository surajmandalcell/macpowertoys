import AppKit
import Charts
import SwiftUI
import UserNotifications

struct PortmanPanelView: View {
    private enum Page: String, CaseIterable {
        case local = "Servers", forward = "Forward", alerts = "Alerts", settings = "Settings"
    }

    @State private var service = PortmanService.shared
    @State private var page = Page.local
    @State private var selectedPortID: String?
    @State private var host = ""
    @State private var aliases: [String] = []
    @State private var discoveredHost = ""
    @State private var selectedRemotePorts = Set<UInt16>()
    @State private var localPortInputs: [UInt16: String] = [:]
    @State private var manualPort = ""
    @State private var cleanupMode = false
    @State private var selectedCleanupProcesses = Set<String>()
    @State private var pendingCleanupPorts: [PortmanLocalPort] = []
    @State private var pendingStop: PortmanLocalPort?
    @State private var hoveredTime: Date?
    @State private var highlightedProcessID: String?
    @State private var hoveredRowID: String?
    @State private var showingMacMemory = false
    @State private var showingMore = false
    @State private var showingProcesses = false

    private let portColors: [Color] = [
        Color(red: 0.43, green: 0.78, blue: 0.93),
        Color(red: 0.71, green: 0.60, blue: 0.94),
        Color(red: 0.92, green: 0.61, blue: 0.83),
        Color(red: 0.49, green: 0.61, blue: 0.95),
        Color(red: 0.49, green: 0.86, blue: 0.88)
    ]

    private var selectedPort: PortmanLocalPort? {
        service.localPorts.first { $0.id == selectedPortID }
    }

    private var activeTunnelCount: Int {
        service.tunnels.reduce(0) { count, tunnel in
            if case .running = tunnel.state { return count + 1 }
            return count
        }
    }

    private var panelHeight: CGFloat {
        let target: CGFloat = switch page {
        case .local:
            selectedPort == nil ? 240 + CGFloat(service.localPorts.count) * 56 : 620
        case .forward:
            400 + CGFloat(service.tunnels.count) * 48 + CGFloat(service.remotePorts.count) * 28
        case .alerts:
            280 + CGFloat(service.activeAlerts.count) * 92
        case .settings:
            620
        }
        let available = (NSScreen.main?.visibleFrame.height ?? 900) * 0.72
        return min(available, min(650, max(320, target)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "circle.grid.2x2.fill")
                    .foregroundStyle(.secondary)
                Text("Portman").font(.system(size: 12, weight: .semibold))
                Spacer()
                if page == .local {
                    Button { Task { await service.refreshLocal() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh servers")
                }
                Button { page = page == .settings ? .local : .settings } label: {
                    Image(systemName: page == .settings ? "xmark" : "gearshape")
                }
                .help(page == .settings ? "Close settings" : "Portman settings")
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            HStack(spacing: 18) {
                ForEach([Page.local, .forward, .alerts], id: \.self) { destination in
                    Button { page = destination; selectedPortID = nil } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(destination.rawValue)
                                if destination == .alerts && !service.activeAlerts.isEmpty {
                                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                                }
                            }
                                .font(.system(size: 12, weight: page == destination ? .semibold : .regular))
                                .foregroundStyle(page == destination ? Color.primary : Color.secondary)
                            Capsule().fill(page == destination ? Color.accentColor : .clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == destination ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)

            QuietDivider()

            ScrollView {
                Group {
                    switch page {
                    case .local:
                        if let selectedPort { localDetail(selectedPort) }
                        else { localOverview }
                    case .forward: forwardingPage
                    case .alerts: alertsPage
                    case .settings: PortmanSettingsView(compact: true)
                    }
                }
                .utilityContentTransition(value: page)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .thinScrollIndicators()
        }
        .frame(width: 400, height: panelHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            PortmanMenuController.shared.setHeight(panelHeight)
            service.beginMonitoring()
            Task.detached(priority: .utility) {
                let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
                let data = (try? Data(contentsOf: url)) ?? Data()
                let names = SSHConfigEditor.entries(in: data).flatMap(\.aliases)
                    .filter(SystemMonitorRemoteProtocol.validHost)
                await MainActor.run { aliases = Array(Set(names)).sorted() }
            }
        }
        .onDisappear { service.endMonitoring() }
        .onChange(of: panelHeight) { PortmanMenuController.shared.setHeight(panelHeight) }
        .onChange(of: selectedPortID) { showingMore = false; showingProcesses = false }
        .onChange(of: host) {
            selectedRemotePorts = []
            localPortInputs = [:]
            service.forwardingError = nil
        }
        .onChange(of: service.localPorts.map(\.processID)) {
            selectedCleanupProcesses.formIntersection(Set(service.localPorts.map(\.processID)))
        }
        .task(id: selectedPortID) {
            hoveredTime = nil
            if let selectedPort { await service.loadMetadata(for: selectedPort) }
        }
        .confirmationDialog("Stop this server process?", isPresented: Binding(
            get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }
        ), presenting: pendingStop) { port in
            Button("Stop PID \(port.pid)", role: .destructive) { service.stopLocal(port) }
        } message: { port in
            Text("Port \(port.port) will stop. Eligible child processes may also stop.")
        }
        .confirmationDialog("Stop selected server processes?", isPresented: Binding(
            get: { !pendingCleanupPorts.isEmpty },
            set: { if !$0 { pendingCleanupPorts = [] } }
        ), titleVisibility: .visible) {
            Button("Stop \(Set(pendingCleanupPorts.map(\.processID)).count) Processes", role: .destructive) {
                service.stopLocalProcesses(pendingCleanupPorts)
                pendingCleanupPorts = []
                cleanupMode = false
                selectedCleanupProcesses = []
            }
        } message: {
            Text("Stopping these processes may interrupt open work. Save it before continuing.")
        }
    }

    private var localOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Text(cleanupMode ? "Clean up" : "Servers")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            VStack(spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: showingMacMemory && !cleanupMode
                    ? service.systemMemoryUsedBytes : overviewMemory, countStyle: .memory))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Text(cleanupMode
                     ? "freed by stopping \(selectedCleanupProcesses.count) server\(selectedCleanupProcesses.count == 1 ? "" : "s")"
                     : showingMacMemory ? "used by this Mac" : "used by \(uniquePorts.count) servers")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !cleanupMode {
                    Picker("Memory scope", selection: $showingMacMemory) {
                        Text("Servers").tag(false)
                        Text("Mac").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 130)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)

            memoryBreakdown

            if service.localPorts.isEmpty {
                ContentUnavailableView("No servers listening", systemImage: "network",
                                       description: Text("Local development ports \(PortmanPreferences.scanRange.lowerBound)–\(PortmanPreferences.scanRange.upperBound) will appear here."))
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(service.localPorts) { port in localRow(port) }
                }
                QuietDivider()
                HStack {
                    if cleanupMode {
                        Button("Cancel") { cleanupMode = false; selectedCleanupProcesses = [] }
                        Spacer()
                        Button("Stop \(selectedCleanupProcesses.count) · free \(memoryString(overviewMemory))", role: .destructive) {
                            pendingCleanupPorts = service.localPorts.filter {
                                selectedCleanupProcesses.contains($0.processID)
                            }
                        }
                        .disabled(selectedCleanupProcesses.isEmpty)
                    } else {
                        Text("\(uniquePorts.count) servers · \(String(format: "%.1f", overviewCPU))% CPU")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(suggestedCleanupIDs.isEmpty ? "Clean up" : "Clean up \(suggestedCleanupIDs.count)") {
                            selectedCleanupProcesses = suggestedCleanupIDs
                            cleanupMode = true
                        }
                            .disabled(!service.localPorts.contains(where: \.canStop))
                    }
                }
                .controlSize(.small)
            }
            if let error = service.localError { errorText(error) }
            if let error = service.controlError { errorText(error) }
        }
    }

    private func localRow(_ port: PortmanLocalPort) -> some View {
        let attention = service.warning(for: port)
        return HStack(spacing: 8) {
            if cleanupMode {
                Toggle(isOn: Binding(
                    get: { selectedCleanupProcesses.contains(port.processID) },
                    set: { if $0 { selectedCleanupProcesses.insert(port.processID) } else { selectedCleanupProcesses.remove(port.processID) } }
                )) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!port.canStop)
                .accessibilityLabel("Select process \(port.pid) for cleanup")
            }
            Button {
                if cleanupMode {
                    guard port.canStop else { return }
                    if selectedCleanupProcesses.contains(port.processID) {
                        selectedCleanupProcesses.remove(port.processID)
                    } else {
                        selectedCleanupProcesses.insert(port.processID)
                    }
                } else { selectedPortID = port.id }
            } label: {
                HStack(spacing: 9) {
                    HStack(spacing: 4) {
                        VStack(spacing: 3) {
                            Circle().fill(portColor(port)).frame(width: 3, height: 3)
                            Circle().fill(portColor(port)).frame(width: 3, height: 3)
                        }
                        Text("\(port.port)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(portColor(port))
                    .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.metadata[port.id]?.branch ?? service.metadata[port.id]?.project ?? port.command)
                            .font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(attention ?? "\(service.metadata[port.id]?.project ?? port.command) · up \(port.uptime)")
                            .font(.system(size: 11))
                            .foregroundStyle(attention == nil ? Color.secondary : Color.orange)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .frame(minHeight: 52)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(UtilityInteractionButtonStyle())
            .help(cleanupMode ? "Select port \(port.port) for cleanup" : "Show port \(port.port) details")
            if hoveredRowID == port.id && !cleanupMode {
                Button { openLocal(port.port) } label: {
                    Image(systemName: "arrow.up.right.square").frame(width: 20, height: 24)
                }
                .help("Open localhost:\(port.port)")
                .accessibilityLabel("Open localhost port \(port.port)")
                if port.canStop {
                    Button { pendingStop = port } label: {
                        Image(systemName: "stop.fill").frame(width: 20, height: 24)
                    }
                    .help("Stop port \(port.port) process tree")
                    .accessibilityLabel("Stop process tree for port \(port.port)")
                }
            } else {
                sparkline(for: port, attention: attention != nil)
                    .frame(width: 42, height: 24)
            }
            Text(memoryString(port.memoryBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(attention == nil ? Color.primary : Color.orange)
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)
        }
        .opacity(highlightedProcessID == nil || highlightedProcessID == port.processID ? 1 : 0.45)
        .onHover { inside in
            hoveredRowID = inside ? port.id : nil
            highlightedProcessID = inside ? port.processID : nil
        }
        .task(id: port.id) { await service.loadMetadata(for: port) }
        .contextMenu {
            Button("Open localhost:\(port.port)") { openLocal(port.port) }
            if port.canStop {
                Button("Stop process tree…", role: .destructive) { pendingStop = port }
            }
        }
    }

    private var uniquePorts: [PortmanLocalPort] {
        var seen = Set<String>()
        return service.localPorts.filter { seen.insert($0.processID).inserted }
    }

    private struct UsageSegment: Identifiable {
        let port: PortmanLocalPort
        let memoryBytes: Int64
        let cpuPercent: Double
        var id: String { port.id }
    }

    private func usageSegments(for ports: [PortmanLocalPort]) -> [UsageSegment] {
        var seen = Set<Int32>()
        return ports.map { port in
            let childMemory = port.processes.reduce(Int64(0)) { $0 + $1.memoryBytes }
            let childCPU = port.processes.reduce(0.0) { $0 + $1.cpuPercent }
            var memory: Int64 = 0
            var cpu = 0.0
            if seen.insert(port.pid).inserted {
                memory += max(0, port.memoryBytes - childMemory)
                cpu += max(0, port.cpuPercent - childCPU)
            }
            for child in port.processes where seen.insert(child.pid).inserted {
                memory += child.memoryBytes
                cpu += child.cpuPercent
            }
            return UsageSegment(port: port, memoryBytes: memory, cpuPercent: cpu)
        }
    }

    private var usageSegments: [UsageSegment] { usageSegments(for: uniquePorts) }

    private var displayedUsageSegments: [UsageSegment] {
        cleanupMode ? usageSegments(for: uniquePorts.filter {
            selectedCleanupProcesses.contains($0.processID)
        }) : usageSegments
    }

    private var suggestedCleanupIDs: Set<String> {
        Set(uniquePorts.filter { port in
            guard port.canStop, service.warning(for: port) == nil else { return false }
            if let folder = service.metadata[port.id]?.folder,
               folder.hasSuffix(" (deleted)") { return true }
            guard !port.hasConnections,
                  let lastConnection = service.lastConnectionAt[port.processID] else { return false }
            return Date().timeIntervalSince(lastConnection) >= PortmanPreferences.idleSuggestionHours * 3_600
        }.map(\.processID))
    }

    private func memoryString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private func portColor(_ port: PortmanLocalPort) -> Color {
        portColors[(Int(port.port) * 7 / 11) % portColors.count]
    }

    private var memoryBreakdown: some View {
        let physical = max(1, Int64(ProcessInfo.processInfo.physicalMemory))
        let allServers = usageSegments.reduce(Int64(0)) { $0 + $1.memoryBytes }
        let used = min(physical, max(allServers, service.systemMemoryUsedBytes))
        let other = max(0, used - allServers)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(usageSegments) { segment in
                        Rectangle().fill(portColor(segment.port))
                            .frame(width: max(1, geometry.size.width * Double(segment.memoryBytes) / Double(physical)))
                            .opacity(highlightedProcessID == nil || highlightedProcessID == segment.port.processID ? 1 : 0.45)
                            .onHover { highlightedProcessID = $0 ? segment.port.processID : nil }
                            .help("Port \(segment.port.port): \(memoryString(segment.memoryBytes))")
                    }
                    Rectangle().fill(Color.primary.opacity(0.25))
                        .frame(width: max(0, geometry.size.width * Double(other) / Double(physical)))
                        .help("Other use: \(memoryString(other))")
                    Rectangle().fill(Color.primary.opacity(0.08))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 12)
            HStack {
                if let segment = usageSegments.first(where: { $0.port.processID == highlightedProcessID }) {
                    Circle().fill(portColor(segment.port)).frame(width: 6, height: 6)
                    Text(":\(segment.port.port) · \(memoryString(segment.memoryBytes))")
                } else {
                    Text("Servers \(memoryString(allServers))")
                }
                Spacer()
                Text("Other use \(memoryString(other))")
                Text("Free \(memoryString(physical - used))")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private func sparkline(for port: PortmanLocalPort, attention: Bool) -> some View {
        let samples = service.history[port.id] ?? []
        return Chart(samples) { sample in
            LineMark(x: .value("Time", sample.date), y: .value("Memory", sample.memoryBytes))
                .foregroundStyle(attention ? Color.orange : portColor(port))
                .lineStyle(StrokeStyle(lineWidth: 1.3))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Recent memory use for port \(port.port)")
    }

    private var overviewMemory: Int64 {
        displayedUsageSegments.reduce(0) { $0 + $1.memoryBytes }
    }

    private var overviewCPU: Double {
        displayedUsageSegments.reduce(0) { $0 + $1.cpuPercent }
    }

    private func localDetail(_ port: PortmanLocalPort) -> some View {
        let samples = service.history[port.id] ?? []
        let hovered = hoveredTime.flatMap { time in
            samples.min { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { selectedPortID = nil } label: { Label("Servers", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                Spacer()
                Text(service.metadata[port.id]?.project ?? port.command)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text(":\(port.port)")
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(portColor(port))
                Spacer()
                Text("up \(port.uptime)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                if port.canStop {
                    Button { pendingStop = port } label: {
                        Image(systemName: "stop.circle").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Stop port \(port.port) process tree")
                    .accessibilityLabel("Stop process tree for port \(port.port)")
                }
            }
            if let attention = service.warning(for: port) {
                Label(attention, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            if let metadata = service.metadata[port.id], let branch = metadata.branch {
                detailRow("Branch", branch)
            }
            Button(showingMore ? "Less" : "More details") { showingMore.toggle() }
                .font(.system(size: 11)).buttonStyle(.plain)
                .foregroundStyle(.secondary)
            if showingMore {
                detailRow("Process", "\(port.pid)")
                detailRow("Address", port.address)
                if let metadata = service.metadata[port.id] {
                    detailRow("Project", metadata.project)
                    detailRow("Folder", metadata.folder)
                }
                detailRow("Command", port.launchCommand)
                detailRow("Running", port.uptime)
            }
            QuietDivider()
            HStack(alignment: .firstTextBaseline) {
                Text("Memory").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(memoryString(hovered?.memoryBytes ?? port.memoryBytes))
                    .font(.system(size: 13, design: .monospaced))
                    .monospacedDigit()
            }
            if samples.count > 1 {
                Chart {
                    ForEach(samples) { sample in
                        LineMark(x: .value("Time", sample.date),
                                 y: .value("Memory", sample.memoryBytes))
                            .foregroundStyle(portColor(port))
                    }
                    RuleMark(y: .value("Alert", PortmanPreferences.memoryAlertBytes))
                        .foregroundStyle(Color.orange.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if let hovered {
                        RuleMark(x: .value("Time", hovered.date))
                            .foregroundStyle(.secondary)
                        PointMark(x: .value("Time", hovered.date),
                                  y: .value("Memory", hovered.memoryBytes))
                            .foregroundStyle(portColor(port))
                    }
                }
                .chartYScale(domain: 0...max(PortmanPreferences.memoryAlertBytes * 11 / 10,
                                             (samples.map(\.memoryBytes).max() ?? 1) * 12 / 10))
                .chartOverlay { proxy in chartHover(proxy) }
                .frame(height: 115)
                .accessibilityLabel("Memory history for port \(port.port)")

                HStack {
                    Text("CPU").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(String(format: "%.1f%%", hovered?.cpuPercent ?? port.cpuPercent))
                        .font(.system(size: 13, design: .monospaced))
                }
                Chart {
                    ForEach(samples) { sample in
                        BarMark(x: .value("Time", sample.date),
                                y: .value("CPU", sample.cpuPercent))
                            .foregroundStyle(hovered?.date == sample.date ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    if let hovered {
                        RuleMark(x: .value("Time", hovered.date))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartOverlay { proxy in chartHover(proxy) }
                .frame(height: 55)
                .accessibilityLabel("CPU history for port \(port.port)")
            }
            if let hovered {
                Text(hovered.date.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            QuietDivider()
            DisclosureGroup(isExpanded: $showingProcesses) {
                processRow(pid: port.pid, command: port.command,
                           memoryBytes: max(0, port.memoryBytes - port.processes.reduce(0) { $0 + $1.memoryBytes }),
                           totalBytes: port.memoryBytes)
                ForEach(port.processes) { process in
                    processRow(pid: process.pid, command: process.command,
                               memoryBytes: process.memoryBytes, totalBytes: port.memoryBytes)
                }
            } label: {
                HStack {
                    Text("Processes").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(port.processes.count + 1) · \(memoryString(port.memoryBytes))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Open localhost:\(port.port)") { openLocal(port.port) }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Menu {
                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("http://127.0.0.1:\(port.port)/", forType: .string)
                    }
                    Button("Copy command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(port.launchCommand, forType: .string)
                    }
                    if let folder = service.metadata[port.id]?.folder {
                        Button("Show folder in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                        }
                    }
                    if port.canStop {
                        Button("Stop process tree…", role: .destructive) { pendingStop = port }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More actions for port \(port.port)")
            }
            .controlSize(.small)
            if let error = service.controlError { errorText(error) }
        }
    }

    private func processRow(pid: Int32, command: String, memoryBytes: Int64, totalBytes: Int64) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(command).lineLimit(1)
                Spacer()
                Text("\(pid)").foregroundStyle(.secondary)
                Text(memoryString(memoryBytes)).frame(width: 68, alignment: .trailing)
            }
            .font(.system(size: 10, design: .monospaced))
            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor.opacity(0.7))
                            .frame(width: geometry.size.width * min(1, Double(memoryBytes) / Double(max(1, totalBytes))))
                    }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 3)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }

    private func chartHover(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plotFrame = proxy.plotFrame else { return }
                        let x = location.x - geometry[plotFrame].origin.x
                        hoveredTime = (0...proxy.plotSize.width).contains(x) ? proxy.value(atX: x) : nil
                    case .ended:
                        hoveredTime = nil
                    }
                }
        }
    }

    private var alertsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Alerts").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(service.activeAlerts.count) active")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if service.activeAlerts.isEmpty {
                ContentUnavailableView("No active alerts", systemImage: "checkmark.circle",
                                       description: Text("Servers above your memory or growth limits appear here."))
                    .frame(maxWidth: .infinity, minHeight: 170)
            }
            ForEach(service.activeAlerts) { port in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(":\(port.port) · \(service.metadata[port.id]?.project ?? port.command)")
                            .font(.system(size: 12, weight: .medium))
                        Text(service.warning(for: port) ?? "")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                        HStack {
                            Button("Inspect") { page = .local; selectedPortID = port.id }
                            Button("Snooze 1h") { service.snooze(port) }
                        }
                        .controlSize(.mini)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                QuietDivider()
            }
            let snoozed = service.localPorts.filter {
                service.warning(for: $0) != nil
                    && (service.snoozedUntil[$0.processID] ?? .distantPast) > Date()
            }
            if !snoozed.isEmpty {
                Text("Snoozed").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                ForEach(snoozed) { port in
                    HStack {
                        Text(":\(port.port) · \(service.warning(for: port) ?? "")")
                            .font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        Button("Rearm") { service.rearm(port) }.controlSize(.mini)
                    }
                }
            }
        }
    }

    private var forwardingPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SSH port forwarding").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(activeTunnelCount) active")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if !service.tunnels.isEmpty {
                ForEach(service.tunnels) { tunnel in tunnelRow(tunnel) }
                QuietDivider()
            }
            HStack(spacing: 8) {
                TextField("SSH host or alias", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .accessibilityLabel("SSH host or alias")
                Menu {
                    if aliases.isEmpty { Text("No hosts in ~/.ssh/config") }
                    ForEach(aliases, id: \.self) { alias in
                        Button(alias) { host = alias }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .help("Choose an SSH host")
                Button("Scan") {
                    selectedRemotePorts = []
                    discoveredHost = host
                    Task { await service.refreshRemote(host: host) }
                }
                .disabled(host.isEmpty || service.isLoadingRemote)
                .controlSize(.small)
            }
            if service.isLoadingRemote { ProgressView("Checking remote ports…").controlSize(.small) }
            Text("Ports stay on the server. Portman binds each tunnel to 127.0.0.1 on this Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            if discoveredHost == host && !service.remotePorts.isEmpty {
                QuietDivider()
                HStack {
                    Text("Listening on \(host)").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Local port").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(service.remotePorts, id: \.self) { port in remoteRow(port) }
            }
            if discoveredHost == host && service.remotePorts.isEmpty
                && !service.isLoadingRemote && service.forwardingError == nil && !host.isEmpty {
                Text("No listening ports found. You can add a remote port manually.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Remote port", text: $manualPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .accessibilityLabel("Remote port to add")
                Button("Add port") {
                    if let port = UInt16(manualPort), port > 0 {
                        selectedRemotePorts.insert(port)
                        localPortInputs[port] = String(port)
                        manualPort = ""
                    } else { service.forwardingError = "Enter a port from 1 to 65535." }
                }
                .disabled(host.isEmpty)
                .controlSize(.small)
                Spacer()
            }
            ForEach(selectedRemotePorts.sorted().filter { !service.remotePorts.contains($0) || discoveredHost != host }, id: \.self) {
                remoteRow($0)
            }

            Button("Forward \(selectedRemotePorts.count) selected") { forwardSelected() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedRemotePorts.isEmpty || host.isEmpty)

            if let error = service.forwardingError { errorText(error) }
        }
    }

    private func remoteRow(_ port: UInt16) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { selectedRemotePorts.contains(port) },
                set: { if $0 { selectedRemotePorts.insert(port) } else { selectedRemotePorts.remove(port) } }
            )) {
                Text(":\(port)").font(.system(size: 12, design: .monospaced))
            }
            .toggleStyle(.checkbox)
            Spacer()
            TextField(String(port), text: Binding(
                get: { localPortInputs[port] ?? String(port) },
                set: { localPortInputs[port] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)
            .accessibilityLabel("Local port for remote port \(port)")
        }
        .frame(minHeight: 28)
    }

    private func tunnelRow(_ tunnel: PortmanTunnel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tunnelSymbol(tunnel.state))
                .foregroundStyle(tunnelColor(tunnel.state))
            VStack(alignment: .leading, spacing: 2) {
                Text("localhost:\(tunnel.localPort) → \(tunnel.host):\(tunnel.remotePort)")
                    .font(.system(size: 12, design: .monospaced)).lineLimit(1)
                Text(tunnelStatus(tunnel.state))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if case .running = tunnel.state {
                Button { openLocal(tunnel.localPort) } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open localhost:\(tunnel.localPort)")
                .accessibilityLabel("Open tunnel on port \(tunnel.localPort)")
            }
            if case .failed = tunnel.state {
                Button("Retry") {
                    service.stopTunnel(tunnel.id)
                    _ = service.forward(host: tunnel.host, remotePort: tunnel.remotePort,
                                        localPort: tunnel.localPort)
                }
                .controlSize(.small)
            }
            Button("Stop") { service.stopTunnel(tunnel.id) }
                .controlSize(.small)
        }
        .frame(minHeight: 36)
    }

    private func forwardSelected() {
        var requests: [(UInt16, UInt16)] = []
        for remotePort in selectedRemotePorts.sorted() {
            guard let localPort = UInt16(localPortInputs[remotePort] ?? String(remotePort)), localPort > 0 else {
                service.forwardingError = "Check the local port for remote port \(remotePort)."
                return
            }
            requests.append((remotePort, localPort))
        }
        guard Set(requests.map(\.1)).count == requests.count else {
            service.forwardingError = "Each selected port needs a different local port."
            return
        }
        for (remotePort, localPort) in requests {
            guard service.forward(host: host, remotePort: remotePort, localPort: localPort) else { return }
            selectedRemotePorts.remove(remotePort)
        }
    }

    private func openLocal(_ port: UInt16) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return }
        NSWorkspace.shared.open(url)
    }

    private func errorText(_ message: String) -> some View {
        Text(message).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled)
    }

    private func tunnelSymbol(_ state: PortmanTunnel.State) -> String {
        switch state { case .connecting: "hourglass"; case .running: "circle.fill"; case .failed: "exclamationmark.triangle" }
    }

    private func tunnelColor(_ state: PortmanTunnel.State) -> Color {
        switch state { case .connecting: .secondary; case .running: .green; case .failed: .red }
    }

    private func tunnelStatus(_ state: PortmanTunnel.State) -> String {
        switch state { case .connecting: "Connecting"; case .running: "Forwarding"; case .failed(let message): message }
    }
}

struct PortmanSettingsView: View {
    var compact = false
    @State private var service = PortmanService.shared
    @AppStorage("portman.scanLowerPort") private var lowerPort = 3000
    @AppStorage("portman.scanUpperPort") private var upperPort = 9999
    @AppStorage("portman.scanInterval") private var scanInterval = 5.0
    @AppStorage("portman.memoryAlertMB") private var memoryAlertMB = 2_048
    @AppStorage("portman.growthAlertMB") private var growthAlertMB = 500
    @AppStorage("portman.idleHours") private var idleHours = 8.0
    @AppStorage("portman.protectedCommands") private var protectedCommands = ""
    @AppStorage("portman.showAllListeners") private var showAllListeners = false
    @AppStorage("portman.notificationsEnabled") private var notificationsEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.system(size: 13, weight: .semibold))
            HStack {
                Text("Keyboard shortcut")
                Spacer()
                ShortcutRecorderField(action: .portman)
            }
            QuietDivider()
            Text("Ports & processes").font(.system(size: 12, weight: .medium))
            Toggle("Include other listening processes", isOn: $showAllListeners)
            HStack {
                Text("Scan ports")
                Spacer()
                TextField("From", value: $lowerPort, format: .number)
                    .frame(width: 60)
                Text("–")
                TextField("To", value: $upperPort, format: .number)
                    .frame(width: 60)
            }
            if lowerPort < 1 || upperPort < lowerPort || upperPort > 65_535 {
                Text("Choose ports between 1 and 65535, with the first no higher than the last.")
                    .foregroundStyle(.red)
            }
            HStack {
                Text("Scan every")
                Spacer()
                Picker("Scan every", selection: $scanInterval) {
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
                .labelsHidden().frame(width: 130)
            }
            TextField("Extra protected process names, comma-separated", text: $protectedCommands)
                .accessibilityLabel("Extra protected process names")
            Text("Databases, Docker, and SSH are always protected.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            QuietDivider()
            Text("Alerts").font(.system(size: 12, weight: .medium))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac notifications")
                    Text(service.notificationStatus)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if service.notificationStatus == "Not requested" {
                    Button("Enable") { Task { await service.enableNotifications() } }
                } else if service.notificationStatus == "Allowed" {
                    Toggle("Mac notifications", isOn: $notificationsEnabled).labelsHidden()
                } else {
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            if let error = service.notificationError {
                Text(error).foregroundStyle(.red)
            }
            HStack {
                Text("Memory above")
                Spacer()
                TextField("MB", value: $memoryAlertMB, format: .number)
                    .frame(width: 74)
                Text("MB").foregroundStyle(.secondary)
            }
            HStack {
                Text("Growth in 10 minutes")
                Spacer()
                TextField("MB", value: $growthAlertMB, format: .number)
                    .frame(width: 74)
                Text("MB").foregroundStyle(.secondary)
            }
            if memoryAlertMB < 1 || growthAlertMB < 1 {
                Text("Alert limits must be greater than zero.").foregroundStyle(.red)
            }
            QuietDivider()
            Text("Clean up").font(.system(size: 12, weight: .medium))
            Stepper("Suggest after \(Int(idleHours)) idle hours", value: $idleHours, in: 1...72, step: 1)
            Text("Only servers observed without connections for this long are suggested. Warnings are not selected automatically.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if !compact {
                Button("Open Portman in menu bar") { ToolActionRouter.shared.open(toolID: "portman") }
                    .controlSize(.small)
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .padding(compact ? 0 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await service.refreshNotificationStatus() }
        .onChange(of: notificationsEnabled) { service.resetNotificationDelivery() }
    }
}

@MainActor
final class PortmanMenuController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PortmanMenuController()

    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
    }

    func start() {
        guard observers.isEmpty else { refresh() ; return }
        let notifications = UNUserNotificationCenter.current()
        notifications.setNotificationCategories([UNNotificationCategory(
            identifier: "PORTMAN_ALERT",
            actions: [UNNotificationAction(identifier: "PORTMAN_SNOOZE", title: "Snooze 1h")],
            intentIdentifiers: []
        )])
        notifications.delegate = self
        Task { await PortmanService.shared.refreshNotificationStatus() }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .toolEnablementChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center.addObserver(forName: .portmanSnapshotChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateButton() }
            }
        ]
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        popover.close()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        PortmanService.shared.endMonitoring()
    }

    func show() {
        start()
        guard let button = item?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard !popover.isShown else { return }
        popover.contentViewController = NSHostingController(rootView: PortmanPanelView().utilityMotionPolicy())
        popover.contentSize = NSSize(width: 400, height: 400)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func setHeight(_ height: CGFloat) {
        popover.contentSize = NSSize(width: 400, height: height)
    }

    func owns(button: NSStatusBarButton) -> Bool { item?.button === button }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Portman", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let refresh = NSMenuItem(title: "Refresh servers", action: #selector(refreshFromMenu), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        let ports = PortmanService.shared.localPorts
        if !ports.isEmpty {
            menu.addItem(.separator())
            for port in ports {
                let entry = NSMenuItem(title: "Open localhost:\(port.port)",
                                       action: #selector(openLocalFromMenu(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = NSNumber(value: port.port)
                menu.addItem(entry)
            }
        }
        return menu
    }

    @objc private func openFromMenu() { show() }

    @objc private func refreshFromMenu() {
        Task { await PortmanService.shared.refreshLocal() }
    }

    @objc private func openLocalFromMenu(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? NSNumber,
              let url = URL(string: "http://127.0.0.1:\(port.intValue)/") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refresh() {
        if SettingsManager.shared.isToolEnabled("portman") {
            guard item == nil else { return }
            let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            newItem.autosaveName = "MacPowerToys.portman"
            item = newItem
            newItem.button?.target = self
            newItem.button?.action = #selector(toggle)
            newItem.button?.sendAction(on: [.leftMouseUp])
            PortmanService.shared.beginMonitoring()
            updateButton()
        } else if let item {
            popover.close()
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            PortmanService.shared.endMonitoring()
        }
    }

    private func updateButton() {
        guard let button = item?.button else { return }
        let ports = PortmanService.shared.localPorts
        let image = NSImage(systemSymbolName: "circle.grid.2x2.fill",
                            accessibilityDescription: "Portman")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = " \(ports.count)"
        let forwarded = PortmanService.shared.tunnels.reduce(0) { count, tunnel in
            if case .running = tunnel.state { return count + 1 }
            return count
        }
        button.toolTip = "Portman · \(ports.count) listening · \(forwarded) forwarded"
        button.contentTintColor = !PortmanService.shared.activeAlerts.isEmpty
            ? .systemOrange : nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let processID = response.notification.request.content.userInfo["processID"] as? String
        let snooze = response.actionIdentifier == "PORTMAN_SNOOZE"
        Task { @MainActor [weak self] in
            if snooze, let processID { PortmanService.shared.snooze(processID: processID) }
            else { self?.show() }
            completionHandler()
        }
    }

    @objc private func toggle() {
        if popover.isShown { popover.close() } else { show() }
    }
}
