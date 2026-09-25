import AppKit
import Charts
import SwiftUI
import UserNotifications

struct PortmanPanelView: View {
    enum Page: String, CaseIterable {
        case local = "Servers", forward = "Forward", alerts = "Alerts", settings = "Settings"
    }

    init(initialPage: Page = .local, initialPortID: String? = nil,
         initialCleanupProcessID: String? = nil) {
        _page = State(initialValue: initialPage)
        _selectedPortID = State(initialValue: initialPortID)
        _cleanupMode = State(initialValue: initialCleanupProcessID != nil)
        _selectedCleanupProcesses = State(initialValue: Set(initialCleanupProcessID.map { [$0] } ?? []))
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
    @State private var pendingRestart: PortmanLocalPort?
    @State private var hoveredTime: Date?
    @State private var highlightedProcessID: String?
    @State private var hoveredSegmentID: String?
    @State private var hoveredRowID: String?
    @State private var hoveredStopPortID: String?
    @State private var showingMacMemory = false
    @State private var showingMore = false
    @State private var showingProcesses = false
    @AppStorage("portman.sessionLinksEnabled") private var sessionLinksEnabled = false
    @AppStorage("portman.publicGitHubLinksEnabled") private var publicGitHubLinksEnabled = false
    @AppStorage("portman.editor") private var editor = "auto"

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
            selectedPort == nil ? 300 + CGFloat(service.localPorts.count) * 64
                : 455 + (showingMore ? 110 : 0)
                    + (showingProcesses ? CGFloat((selectedPort?.processes.count ?? 0) + 1) * 28 : 0)
        case .forward:
            350 + CGFloat(max(0, service.tunnels.count - 1)) * 48
                + CGFloat(!host.isEmpty && discoveredHost == host ? service.remotePorts.count : 0) * 28
        case .alerts:
            260 + CGFloat(service.activeAlerts.count) * 92
        case .settings:
            620
        }
        let available = (NSScreen.main?.visibleFrame.height ?? 900) * 0.72
        return min(available, min(650, max(300, target)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image("PortmanStatusGlyph").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
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
                .accessibilityLabel(page == .settings ? "Close Portman settings" : "Portman settings")
                .accessibilityIdentifier("portman.settings")
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            HStack(spacing: 0) {
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
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == destination ? .isSelected : [])
                    .accessibilityIdentifier("portman.page.\(destination.rawValue)")
                }
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
                    case .settings: PortmanSettingsView()
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
        .onChange(of: selectedPortID) {
            showingMore = false
            showingProcesses = false
            hoveredStopPortID = nil
        }
        .onChange(of: host) {
            selectedRemotePorts = []
            localPortInputs = [:]
            service.forwardingError = nil
        }
        .onChange(of: service.localPorts.map(\.processID)) {
            selectedCleanupProcesses.formIntersection(Set(service.localPorts.map(\.processID)))
        }
        .task(id: "\(selectedPortID ?? "")|\(sessionLinksEnabled)|\(publicGitHubLinksEnabled)") {
            hoveredTime = nil
            if let selectedPort {
                await service.loadMetadata(for: selectedPort)
                await service.loadRestartAvailability(for: selectedPort)
                await service.loadSession(for: selectedPort)
                await service.loadGitHubLinks(for: selectedPort)
            }
        }
        .confirmationDialog("Stop this server process?", isPresented: Binding(
            get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }
        ), presenting: pendingStop) { port in
            Button("Stop PID \(String(port.pid))", role: .destructive) { service.stopLocal(port) }
        } message: { port in
            Text("Port \(String(port.port)) and eligible children will stop. Any still running after the grace period will be force quit.")
        }
        .confirmationDialog("Restart this server?", isPresented: Binding(
            get: { pendingRestart != nil }, set: { if !$0 { pendingRestart = nil } }
        ), presenting: pendingRestart) { port in
            Button("Restart PID \(String(port.pid))") { service.restartLocal(port) }
        } message: { port in
            Text("Port \(String(port.port)) will stop, then Portman will run its saved command in the same folder. Output goes to Library/Logs/MacPowerToys/Portman.")
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
            Text("Stopping these processes may interrupt open work. Any still running after the grace period will be force quit.")
        }
    }

    private var localOverview: some View {
        let focusedSegment = cleanupMode ? nil : usageSegments.first { $0.port.processID == hoveredSegmentID }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Text(cleanupMode ? "Clean up" : focusedSegment.map {
                    "\(service.metadata[$0.port.id]?.project ?? $0.port.command) :\($0.port.port)"
                } ?? "Servers")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            VStack(spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: focusedSegment?.memoryBytes
                    ?? (showingMacMemory && !cleanupMode ? service.systemMemoryUsedBytes : overviewMemory),
                    countStyle: .memory))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Text(cleanupMode
                     ? "freed by stopping \(selectedCleanupProcesses.count) server\(selectedCleanupProcesses.count == 1 ? "" : "s")"
                     : focusedSegment.map {
                        "\(String(format: "%.1f", Double($0.memoryBytes) / Double(max(1, ProcessInfo.processInfo.physicalMemory)) * 100))% of RAM · \(String(format: "%.1f", $0.cpuPercent))% CPU"
                     } ?? (showingMacMemory ? "used by this Mac"
                          : "used by \(uniquePorts.count) server\(uniquePorts.count == 1 ? "" : "s")"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !cleanupMode {
                    Picker("Memory scope", selection: $showingMacMemory) {
                        Text("Servers").tag(false)
                        Text("Mac").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Memory scope")
                    .controlSize(.mini)
                    .frame(width: 130)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)

            memoryBreakdown

            if service.localPorts.isEmpty {
                ContentUnavailableView("No servers listening", systemImage: "network",
                                       description: Text("Local development ports \(String(PortmanPreferences.scanRange.lowerBound))–\(String(PortmanPreferences.scanRange.upperBound)) will appear here."))
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
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(selectedCleanupProcesses.isEmpty)
                    } else {
                        Text("\(uniquePorts.count) server\(uniquePorts.count == 1 ? "" : "s") · \(String(format: "%.1f", overviewCPU))% CPU")
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
                .accessibilityLabel("Select process \(String(port.pid)) for cleanup")
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
                        Text(String(port.port))
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
            .buttonStyle(.plain)
            .help(cleanupMode ? "Select port \(String(port.port)) for cleanup" : "Show port \(String(port.port)) details")
            if hoveredRowID == port.id && !cleanupMode {
                Button { openLocal(port.port) } label: {
                    Image(systemName: "link").frame(width: 24, height: 24)
                }
                .help("Open localhost:\(String(port.port))")
                .accessibilityLabel("Open localhost port \(String(port.port))")
                if port.canStop {
                    Button { pendingStop = port } label: {
                        Image(systemName: "stop.fill").frame(width: 24, height: 24)
                    }
                    .foregroundStyle(hoveredStopPortID == port.id ? .red : .secondary)
                    .onHover { hoveredStopPortID = $0 ? port.id : nil }
                    .help("Stop port \(String(port.port)) process tree")
                    .accessibilityLabel("Stop process tree for port \(String(port.port))")
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
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(hoveredRowID == port.id ? Color.primary.opacity(0.07) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .opacity(highlightedProcessID == nil || highlightedProcessID == port.processID ? 1 : 0.45)
        .onHover { inside in
            hoveredRowID = inside ? port.id : nil
            highlightedProcessID = inside ? port.processID : nil
        }
        .task(id: port.id) { await service.loadMetadata(for: port) }
        .contextMenu {
            Button("Open localhost:\(String(port.port))") { openLocal(port.port) }
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
        service.suggestedCleanupIDs
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
                            .onHover { inside in
                                hoveredSegmentID = inside ? segment.port.processID : nil
                                highlightedProcessID = inside ? segment.port.processID : nil
                            }
                            .help("Port \(String(segment.port.port)): \(memoryString(segment.memoryBytes))")
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
                    Text(":\(String(segment.port.port)) · \(memoryString(segment.memoryBytes))")
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
        .accessibilityLabel("Recent memory use for port \(String(port.port))")
    }

    private var overviewMemory: Int64 {
        displayedUsageSegments.reduce(0) { $0 + $1.memoryBytes }
    }

    private var overviewCPU: Double {
        displayedUsageSegments.reduce(0) { $0 + $1.cpuPercent }
    }

    private func localDetail(_ port: PortmanLocalPort) -> some View {
        let samples = service.history[port.id] ?? []
        let chartEnd = (samples.last?.date ?? Date()).addingTimeInterval(10)
        let chartStart = chartEnd.addingTimeInterval(-600)
        let hovered = hoveredTime.flatMap { time in
            samples.min { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }
        }
        let cpuCeiling = max(100, ceil((samples.map(\.cpuPercent).max() ?? 0) / 50) * 50)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { selectedPortID = nil } label: { Label("Servers", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                Spacer()
                Text(service.metadata[port.id]?.project ?? port.command)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Button { openLocal(port.port) } label: {
                    Image(systemName: "link").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Open localhost:\(String(port.port))")
                .accessibilityLabel("Open localhost port \(String(port.port))")
                Menu {
                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("http://127.0.0.1:\(port.port)/", forType: .string)
                    }
                    Button("Copy command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(port.launchCommand, forType: .string)
                    }
                    if let details = service.metadata[port.id],
                       FileManager.default.fileExists(atPath: details.root ?? details.folder) {
                        Button("Open in editor") {
                            PortmanEditor.open(details.root ?? details.folder, preferred: editor)
                        }
                        Button("Show folder in Finder") {
                            NSWorkspace.shared.selectFile(
                                nil, inFileViewerRootedAtPath: details.root ?? details.folder
                            )
                        }
                    }
                    if port.canStop {
                        Button("Restart with saved command…") { pendingRestart = port }
                            .disabled(!service.restartableIDs.contains(port.id))
                        Button("Stop process tree…", role: .destructive) { pendingStop = port }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("More actions for port \(String(port.port))")
            }

            HStack(alignment: .firstTextBaseline) {
                Text(":\(String(port.port))")
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(portColor(port))
                Spacer()
                Text("up \(port.uptime)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                if port.canStop {
                    Button { pendingRestart = port } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .disabled(!service.restartableIDs.contains(port.id)
                              || service.restartingIDs.contains(port.id))
                    .help(service.restartableIDs.contains(port.id)
                          ? "Restart with the original command and environment"
                          : "Restart requires the original command, environment, and folder")
                    .accessibilityLabel("Restart process for port \(String(port.port))")
                    Button { pendingStop = port } label: {
                        Image(systemName: "stop.circle").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .foregroundStyle(hoveredStopPortID == port.id ? .red : .secondary)
                    .onHover { hoveredStopPortID = $0 ? port.id : nil }
                    .help("Stop port \(String(port.port)) process tree")
                    .accessibilityLabel("Stop process tree for port \(String(port.port))")
                }
            }
            if let attention = service.warning(for: port) {
                Label(attention, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            if let metadata = service.metadata[port.id], let branch = metadata.branch {
                detailRow("Branch", branch)
            }
            if let session = service.sessions[port.id] {
                HStack {
                    Text("Session").foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                    Text(session.label).lineLimit(1)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.resumeCommand, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Copy \(session.label) resume command")
                    .accessibilityLabel("Copy \(session.label) resume command")
                }
                .font(.system(size: 12))
            }
            if let links = service.githubLinks[port.id],
               let url = links.pullRequestURL, let number = links.pullRequestNumber {
                HStack {
                    Text("Pull request").foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                    Button("#\(String(number)) ↗") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                }
                .font(.system(size: 12))
            }
            Button(showingMore ? "Less" : "More details") { showingMore.toggle() }
                .font(.system(size: 11)).buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(.secondary)
            if showingMore {
                detailRow("Process", "\(port.pid)")
                detailRow("Address", port.address)
                if let metadata = service.metadata[port.id] {
                    detailRow("Project", metadata.project)
                    detailRow("Folder", metadata.folder)
                }
                detailRow("Command", port.launchCommand)
                if let session = service.sessions[port.id] {
                    detailRow("Session ID", session.id.uuidString.lowercased())
                }
                detailRow("Running", port.uptime)
                if let note = service.githubLinks[port.id]?.note {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            QuietDivider()
            HStack(alignment: .firstTextBaseline) {
                Text("Memory").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(memoryString(hovered?.memoryBytes ?? port.memoryBytes))
                    .font(.system(size: 13, design: .monospaced))
                    .monospacedDigit()
            }
            if !samples.isEmpty {
                Chart {
                    ForEach(samples) { sample in
                        LineMark(x: .value("Time", sample.date),
                                 y: .value("Memory", sample.memoryBytes))
                            .foregroundStyle(portColor(port))
                    }
                    if let latest = samples.last {
                        PointMark(x: .value("Time", latest.date),
                                  y: .value("Memory", latest.memoryBytes))
                            .foregroundStyle(portColor(port))
                            .symbolSize(25)
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
                .chartXScale(domain: chartStart...chartEnd)
                .chartYScale(domain: 0...max(PortmanPreferences.memoryAlertBytes * 11 / 10,
                                             (samples.map(\.memoryBytes).max() ?? 1) * 12 / 10))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bytes = value.as(Int64.self) {
                                Text(bytes == 0 ? "0" : memoryString(bytes))
                                    .frame(width: 56, alignment: .leading)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.clipped() }
                .chartOverlay { proxy in chartHover(proxy) }
                .frame(height: 100)
                .accessibilityLabel("Memory history for port \(String(port.port))")

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
                            .width(.fixed(2))
                            .foregroundStyle(hovered?.date == sample.date ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    if let hovered {
                        RuleMark(x: .value("Time", hovered.date))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: chartStart...chartEnd)
                .chartYScale(domain: 0...cpuCeiling)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, cpuCeiling / 2, cpuCeiling]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let cpu = value.as(Double.self) {
                                Text(String(format: "%.0f", cpu))
                                    .frame(width: 56, alignment: .leading)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.clipped() }
                .chartOverlay { proxy in chartHover(proxy) }
                .frame(height: 50)
                .accessibilityLabel("CPU history for port \(String(port.port))")
            }
            HStack {
                Text("10m history")
                Spacer()
                Text((hovered?.date ?? samples.last?.date)?.formatted(date: .omitted, time: .standard) ?? "—")
                    .monospacedDigit()
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: 14)
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
            if let preview = service.githubLinks[port.id]?.previewURL {
                Button("Open preview") { NSWorkspace.shared.open(preview) }
                    .buttonStyle(.bordered)
                    .help(preview.absoluteString)
            }
            if let error = service.controlError { errorText(error) }
        }
    }

    private func processRow(pid: Int32, command: String, memoryBytes: Int64, totalBytes: Int64) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(command).lineLimit(1)
                Spacer()
                Text(String(pid)).foregroundStyle(.secondary)
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
                        Text(":\(String(port.port)) · \(service.metadata[port.id]?.project ?? port.command)")
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
                        Text(":\(String(port.port)) · \(service.warning(for: port) ?? "")")
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
                    Text("Hosts")
                }
                .help("Choose an SSH host")
                .controlSize(.small)
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

            if !host.isEmpty && discoveredHost == host && !service.remotePorts.isEmpty {
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
                .tint(selectedRemotePorts.isEmpty || host.isEmpty ? .gray : .accentColor)
                .controlSize(.small)
                .disabled(selectedRemotePorts.isEmpty || host.isEmpty)

            if let error = service.forwardingError { errorText(error) }
            if service.tunnels.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "network").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No active forwards").font(.system(size: 12, weight: .medium))
                        Text("Local port mappings will appear here.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func remoteRow(_ port: UInt16) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { selectedRemotePorts.contains(port) },
                set: { if $0 { selectedRemotePorts.insert(port) } else { selectedRemotePorts.remove(port) } }
            )) {
                Text(":\(String(port))").font(.system(size: 12, design: .monospaced))
            }
            .toggleStyle(.checkbox)
            Spacer()
            TextField(String(port), text: Binding(
                get: { localPortInputs[port] ?? String(port) },
                set: { localPortInputs[port] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)
            .accessibilityLabel("Local port for remote port \(String(port))")
        }
        .frame(minHeight: 28)
    }

    private func tunnelRow(_ tunnel: PortmanTunnel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tunnelSymbol(tunnel.state))
                .foregroundStyle(tunnelColor(tunnel.state))
            VStack(alignment: .leading, spacing: 2) {
                Text("localhost:\(String(tunnel.localPort))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                if case .failed(let message) = tunnel.state {
                    Text("\(tunnel.host):\(String(tunnel.remotePort))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Text(message)
                        .font(.system(size: 11)).foregroundStyle(tunnelColor(tunnel.state))
                        .lineLimit(2)
                } else {
                    Text("\(tunnel.host):\(String(tunnel.remotePort)) · \(tunnelStatus(tunnel.state))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .help("localhost:\(String(tunnel.localPort)) → \(tunnel.host):\(String(tunnel.remotePort)) · \(tunnelStatus(tunnel.state))")
            Spacer(minLength: 4)
            if case .running = tunnel.state {
                Button { openLocal(tunnel.localPort) } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open localhost:\(String(tunnel.localPort))")
                .accessibilityLabel("Open tunnel on port \(String(tunnel.localPort))")
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
    @State private var service = PortmanService.shared
    @State private var pendingAutomaticCleanup = false
    @AppStorage("portman.scanLowerPort") private var lowerPort = 3000
    @AppStorage("portman.scanUpperPort") private var upperPort = 9999
    @AppStorage("portman.scanInterval") private var scanInterval = 2.0
    @AppStorage("portman.memoryAlertMB") private var memoryAlertMB = 2_048
    @AppStorage("portman.growthAlertMB") private var growthAlertMB = 500
    @AppStorage("portman.idleHours") private var idleHours = 4.0
    @AppStorage("portman.runningDays") private var runningDays = 3.0
    @AppStorage("portman.forceQuitSeconds") private var forceQuitSeconds = 3.0
    @AppStorage("portman.cleanupMode") private var cleanupMode = PortmanCleanupMode.ask.rawValue
    @AppStorage("portman.includeDeletedFolders") private var includeDeletedFolders = true
    @AppStorage("portman.cleanupNotifications") private var cleanupNotifications = true
    @AppStorage("portman.protectedCommands") private var protectedCommands = ""
    @AppStorage("portman.showAllListeners") private var showAllListeners = false
    @AppStorage("portman.notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("portman.sessionLinksEnabled") private var sessionLinksEnabled = false
    @AppStorage("portman.publicGitHubLinksEnabled") private var publicGitHubLinksEnabled = false
    @AppStorage("portman.editor") private var editor = "auto"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.system(size: 13, weight: .semibold))
            HStack {
                Text("Keyboard shortcut")
                Spacer()
                ShortcutRecorderField(action: .portman)
            }
            HStack {
                Text("Open folders in")
                Spacer()
                Picker("Open folders in", selection: $editor) {
                    Text("Automatic").tag("auto")
                    ForEach(PortmanEditor.installed, id: \.id) { choice in
                        Text(choice.name).tag(choice.id)
                    }
                    Text("Finder").tag("finder")
                }
                .labelsHidden().frame(width: 180)
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
            HStack {
                Text("Mode")
                Spacer()
                Picker("Cleanup mode", selection: Binding(
                    get: { cleanupMode },
                    set: { value in
                        if value == PortmanCleanupMode.automatic.rawValue
                            && cleanupMode != PortmanCleanupMode.automatic.rawValue {
                            pendingAutomaticCleanup = true
                        } else { cleanupMode = value }
                    }
                )) {
                    Text("Off").tag(PortmanCleanupMode.off.rawValue)
                    Text("Ask").tag(PortmanCleanupMode.ask.rawValue)
                    Text("Automatic").tag(PortmanCleanupMode.automatic.rawValue)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 210)
            }
            Toggle("Include deleted folders", isOn: $includeDeletedFolders)
            Stepper("Suggest after \(Int(idleHours)) idle hours", value: $idleHours, in: 1...72, step: 1)
            Stepper("Suggest after \(Int(runningDays)) running days", value: $runningDays, in: 1...30, step: 1)
            Stepper("Force quit after \(Int(forceQuitSeconds)) seconds", value: $forceQuitSeconds, in: 1...30, step: 1)
            Toggle("Notify about cleanup", isOn: $cleanupNotifications)
            Group {
                if cleanupMode == PortmanCleanupMode.automatic.rawValue {
                    Text("Automatic stops eligible servers without another prompt and force quits any still running after the grace period. Protected servers and warnings stay excluded.")
                } else if cleanupMode == PortmanCleanupMode.off.rawValue {
                    Text("Manual cleanup remains available from the server list.")
                } else {
                    Text("Ask suggests eligible servers. Mac notifications appear only when enabled above.")
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            QuietDivider()
            Text("Integrations").font(.system(size: 12, weight: .medium))
            Toggle("Link coding sessions", isOn: $sessionLinksEnabled)
            Text("When you open a server, Portman checks its process for a Claude Code session and recent local Codex sessions for a folder match. A link copies a resume command.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Toggle("Find public GitHub links", isOn: $publicGitHubLinksEnabled)
            Text("Checks public pull requests and previews for this project's branch. Private repositories and saved GitHub credentials are not used.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await service.refreshNotificationStatus() }
        .onChange(of: notificationsEnabled) { service.resetNotificationDelivery() }
        .confirmationDialog("Stop eligible servers automatically?", isPresented: $pendingAutomaticCleanup) {
            Button("Enable Automatic", role: .destructive) {
                cleanupMode = PortmanCleanupMode.automatic.rawValue
            }
        } message: {
            Text("Portman will send stop requests for eligible servers, including long-running ones, without asking again.")
        }
    }
}

enum PortmanEditor {
    static let choices: [(id: String, name: String)] = [
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("com.microsoft.VSCode", "Visual Studio Code"),
        ("dev.zed.Zed", "Zed"),
        ("com.sublimetext.4", "Sublime Text")
    ]

    static var installed: [(id: String, name: String)] {
        choices.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    static func bundleIDs(for preferred: String) -> [String] {
        let ids = choices.map(\.id)
        return ids.contains(preferred) ? [preferred] + ids.filter { $0 != preferred } : ids
    }

    static func open(_ path: String, preferred: String) {
        if preferred != "finder" {
            for id in bundleIDs(for: preferred) {
                if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app,
                                            configuration: NSWorkspace.OpenConfiguration())
                    return
                }
            }
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
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
            PortmanService.shared.stopAll()
        }
    }

    private func updateButton() {
        guard let button = item?.button else { return }
        let ports = PortmanService.shared.localPorts
        let image = NSImage(named: "PortmanStatusGlyph")?.copy() as? NSImage
        image?.size = NSSize(width: 18, height: 18)
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
