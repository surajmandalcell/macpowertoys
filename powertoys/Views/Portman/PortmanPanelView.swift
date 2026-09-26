import AppKit
import Charts
import SwiftUI

struct PortmanPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let selectedPageKey = "portman.selectedPage"

    enum Page: String, CaseIterable {
        case local = "Servers", forward = "Forward", settings = "Settings"
    }

    init(initialPage: Page? = nil, initialPortID: String? = nil,
         initialCleanupProcessID: String? = nil) {
        let savedPage = UserDefaults.standard.string(forKey: Self.selectedPageKey)
            .flatMap(Page.init(rawValue:)) ?? .local
        _page = State(initialValue: initialPage
                      ?? (initialPortID != nil || initialCleanupProcessID != nil ? .local : savedPage))
        _selectedPortID = State(initialValue: initialPortID)
        _cleanupMode = State(initialValue: initialCleanupProcessID != nil)
        _selectedCleanupProcesses = State(initialValue: Set(initialCleanupProcessID.map { [$0] } ?? []))
    }

    @State private var service = PortmanService.shared
    @State private var page = Page.local
    @State private var contentHeight: CGFloat = 0
    @State private var selectedPortID: String?
    @State private var host = ""
    @State private var aliases: [String] = []
    @State private var discoveredHost = ""
    @State private var selectedRemotePorts = Set<UInt16>()
    @State private var lastSelectedRemotePort: UInt16?
    @State private var localPortInputs: [UInt16: String] = [:]
    @State private var manualPort = ""
    @State private var remoteScanTask: Task<Void, Never>?
    @State private var remoteDetailTask: Task<Void, Never>?
    @State private var sshPassword: String?
    @State private var sshPasswordHost = ""
    @State private var passwordPromptHost: String?
    @State private var passwordPromptError: String?
    @State private var retryAfterPassword: PortmanTunnel?
    @State private var expandedRemotePort: UInt16?
    @State private var panelOwnsMonitoring = false
    @State private var cleanupMode = false
    @State private var selectedCleanupProcesses = Set<String>()
    @State private var pendingCleanupPorts: [PortmanLocalPort] = []
    @State private var pendingStop: PortmanLocalPort?
    @State private var pendingRestart: PortmanLocalPort?
    @State private var hoveredTime: Date?
    @State private var highlightedProcessID: String?
    @State private var hoveredSegmentID: String?
    @State private var hoveredRowID: String?
    @State private var hoveredLinkPortID: String?
    @State private var hoveredStopPortID: String?
    @State private var showingMore = false
    @State private var showingProcesses = false
    @AppStorage("portman.sessionLinksEnabled") private var sessionLinksEnabled = false
    @AppStorage("portman.publicGitHubLinksEnabled") private var publicGitHubLinksEnabled = false
    @AppStorage("portman.editor") private var editor = "auto"
    @AppStorage("portman.serverSort") private var serverSort = PortmanServerSort.port.rawValue

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
        let available = (NSScreen.main?.visibleFrame.height ?? 900) * 0.72
        return min(available, min(650, max(page == .settings ? 260 : 300, contentHeight + 66)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image("PortmanStatusGlyph").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 13, height: 13)
                Text("Portman").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { Task { await service.refreshLocal() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh servers")
                .accessibilityLabel("Refresh servers")
                .accessibilityIdentifier("portman.refresh")
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            HStack(spacing: 0) {
                ForEach(Page.allCases, id: \.self) { destination in
                    Button { navigate(to: destination) } label: {
                        Text(destination.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(page == destination ? Color.primary : Color.secondary)
                            .animation(UtilityMotion.animation(reduceMotion: reduceMotion),
                                       value: page == destination)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .opacity(page == destination ? 1 : 0)
                            .animation(UtilityMotion.animation(reduceMotion: reduceMotion),
                                       value: page == destination)
                            .allowsHitTesting(false)
                    }
                    .accessibilityAddTraits(page == destination ? .isSelected : [])
                    .accessibilityIdentifier("portman.page.\(destination.rawValue)")
                }
            }
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) { QuietDivider() }

            ScrollView {
                Group {
                    switch page {
                    case .local:
                        if let selectedPort { localDetail(selectedPort) }
                        else { localOverview }
                    case .forward: forwardingPage
                    case .settings: PortmanSettingsView()
                    }
                }
                .id(page)
                .padding(.horizontal, page == .local && selectedPort == nil ? 10 : 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    contentHeight = $0
                }
            }
            .thinScrollIndicators()
        }
        .frame(width: 400, height: panelHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            PortmanMenuController.shared.setHeight(panelHeight)
            if page == .local {
                service.beginMonitoring()
                panelOwnsMonitoring = true
            }
            Task.detached(priority: .utility) {
                let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
                let data = (try? Data(contentsOf: url)) ?? Data()
                let names = SSHConfigEditor.entries(in: data).flatMap(\.aliases)
                    .filter(SystemMonitorRemoteProtocol.validHost)
                await MainActor.run { aliases = Array(Set(names)).sorted() }
            }
        }
        .onDisappear {
            if panelOwnsMonitoring { service.endMonitoring() }
            remoteScanTask?.cancel()
            remoteDetailTask?.cancel()
            service.clearRemoteScan()
            sshPassword = nil
            passwordPromptHost = nil
            retryAfterPassword = nil
        }
        .onChange(of: panelHeight) { PortmanMenuController.shared.setHeight(panelHeight) }
        .onChange(of: page) {
            UserDefaults.standard.set(page.rawValue, forKey: Self.selectedPageKey)
            if page == .local && !panelOwnsMonitoring {
                service.beginMonitoring()
                panelOwnsMonitoring = true
            } else if page != .local && panelOwnsMonitoring {
                service.endMonitoring()
                panelOwnsMonitoring = false
            }
            if page != .forward {
                remoteScanTask?.cancel()
                remoteDetailTask?.cancel()
                service.clearRemoteScan()
                selectedRemotePorts = []
                lastSelectedRemotePort = nil
                localPortInputs = [:]
                manualPort = ""
                sshPassword = nil
                expandedRemotePort = nil
                passwordPromptHost = nil
                retryAfterPassword = nil
            }
        }
        .onChange(of: selectedPortID) {
            showingMore = false
            showingProcesses = false
            hoveredLinkPortID = nil
            hoveredStopPortID = nil
        }
        .onChange(of: host) {
            remoteScanTask?.cancel()
            remoteDetailTask?.cancel()
            service.clearRemoteScan()
            selectedRemotePorts = []
            lastSelectedRemotePort = nil
            localPortInputs = [:]
            service.forwardingError = nil
            sshPassword = nil
            expandedRemotePort = nil
        }
        .onChange(of: service.localPorts.map(\.processID)) {
            selectedCleanupProcesses.formIntersection(Set(service.localPorts.map(\.processID)))
        }
        .onChange(of: service.tunnels.map { "\($0.id):\(tunnelStatus($0.state))" }) { oldStates, newStates in
            guard page == .forward, passwordPromptHost == nil,
                  let tunnel = service.tunnels.first(where: {
                      if case .failed(let message) = $0.state {
                          return PortmanScanner.passwordAvailable(in: message)
                              && newStates.contains("\($0.id):\(message)")
                              && !oldStates.contains("\($0.id):\(message)")
                      }
                      return false
                  }) else { return }
            retryAfterPassword = tunnel
            passwordPromptError = nil
            passwordPromptHost = tunnel.host
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
        .sheet(isPresented: Binding(
            get: { passwordPromptHost != nil },
            set: { if !$0 { passwordPromptHost = nil; retryAfterPassword = nil } }
        )) {
            if let passwordPromptHost {
                PortmanPasswordSheet(host: passwordPromptHost, errorMessage: passwordPromptError,
                                     onCancel: { self.passwordPromptHost = nil; retryAfterPassword = nil },
                                     onContinue: { password in submitPassword(password, for: passwordPromptHost) })
            }
        }
    }

    private func navigate(to destination: Page) {
        page = destination
        selectedPortID = nil
        cleanupMode = false
        selectedCleanupProcesses = []
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
                Text(memoryString(focusedSegment?.memoryBytes ?? overviewMemory))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                Text(cleanupMode
                     ? "freed by stopping \(selectedCleanupProcesses.count) server\(selectedCleanupProcesses.count == 1 ? "" : "s")"
                     : focusedSegment.map {
                        "\(String(format: "%.1f", Double($0.memoryBytes) / Double(max(1, ProcessInfo.processInfo.physicalMemory)) * 100))% of RAM · \(String(format: "%.1f", $0.cpuPercent))% CPU"
                     } ?? "used by \(uniquePorts.count) listening server\(uniquePorts.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            memoryBreakdown

            if service.localPorts.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "network").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No servers listening").font(.system(size: 12, weight: .medium))
                        Text("Local development ports \(String(PortmanPreferences.scanRange.lowerBound))–\(String(PortmanPreferences.scanRange.upperBound)) will appear here.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    LazyVStack(spacing: 4) {
                        ForEach(sortedLocalPorts) { port in localRow(port) }
                    }
                    QuietDivider()
                    HStack(spacing: 8) {
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
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Menu {
                                ForEach(PortmanServerSort.allCases, id: \.self) { choice in
                                    Button {
                                        serverSort = choice.rawValue
                                    } label: {
                                        if serverSort == choice.rawValue {
                                            Label(choice.label, systemImage: "checkmark")
                                        } else {
                                            Text(choice.label)
                                        }
                                    }
                                }
                            } label: {
                                Text("Sort by")
                            }
                            .menuStyle(.borderlessButton)
                            .accessibilityIdentifier("portman.sort")
                            .accessibilityLabel("Sort by")
                            .accessibilityValue((PortmanServerSort(rawValue: serverSort) ?? .port).label)
                            Button(suggestedCleanupIDs.isEmpty ? "Clean up" : "Clean up \(suggestedCleanupIDs.count)") {
                                selectedCleanupProcesses = suggestedCleanupIDs
                                cleanupMode = true
                            }
                                .disabled(!service.localPorts.contains(where: \.canStop))
                        }
                    }
                    .controlSize(.small)
                }
            }
            if let error = service.localError { errorText(error) }
            if let error = service.controlError { errorText(error) }
        }
    }

    private func localRow(_ port: PortmanLocalPort) -> some View {
        let isHovered = hoveredRowID == port.id
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
            ZStack(alignment: .trailing) {
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
                            Text("\(service.metadata[port.id]?.project ?? port.command) · up \(port.uptime)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        HStack(spacing: 6) {
                            sparkline(for: port)
                                .frame(width: 42, height: 24)
                            Text(memoryString(port.memoryBytes))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                                .frame(width: 62, alignment: .trailing)
                        }
                        .frame(width: 110, height: 28)
                        .opacity(isHovered && !cleanupMode ? 0 : 1)
                        .accessibilityHidden(isHovered && !cleanupMode)
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 52)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityIdentifier("portman.local.\(String(port.port))")
                .help(cleanupMode ? "Select port \(String(port.port)) for cleanup" : "Show port \(String(port.port)) details")
                if isHovered && !cleanupMode {
                    HStack(spacing: 4) {
                        Button { openLocal(port.port) } label: {
                            Image(systemName: "link").font(.system(size: 10))
                                .frame(width: 24, height: 24)
                        }
                        .foregroundStyle(hoveredLinkPortID == port.id ? Color.accentColor : Color.secondary)
                        .background(hoveredLinkPortID == port.id ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .onHover { hoveredLinkPortID = $0 ? port.id : nil }
                        .utilityAnimation(value: hoveredLinkPortID, duration: UtilityMotion.interactionDuration)
                        .help("Open localhost:\(String(port.port))")
                        .accessibilityLabel("Open localhost port \(String(port.port))")
                        .accessibilityIdentifier("portman.link.\(String(port.port))")
                        if port.canStop {
                            Button { pendingStop = port } label: {
                                Image(systemName: "stop.fill").font(.system(size: 10))
                                    .frame(width: 24, height: 24)
                            }
                            .foregroundStyle(hoveredStopPortID == port.id ? Color.red : Color.secondary)
                            .background(hoveredStopPortID == port.id ? Color.red.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .onHover { hoveredStopPortID = $0 ? port.id : nil }
                            .utilityAnimation(value: hoveredStopPortID, duration: UtilityMotion.interactionDuration)
                            .help("Stop port \(String(port.port)) process tree")
                            .accessibilityLabel("Stop process tree for port \(String(port.port))")
                            .accessibilityIdentifier("portman.stop.\(String(port.port))")
                        }
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .padding(.trailing, 8)
                    .transition(.opacity.combined(with: .offset(x: 4)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .opacity(highlightedProcessID == nil || highlightedProcessID == port.processID ? 1 : 0.45)
        .utilityAnimation(value: hoveredRowID, duration: UtilityMotion.interactionDuration)
        .onHover { inside in
            hoveredRowID = inside ? port.id : nil
            highlightedProcessID = inside ? port.processID : nil
            if !inside {
                if hoveredLinkPortID == port.id { hoveredLinkPortID = nil }
                if hoveredStopPortID == port.id { hoveredStopPortID = nil }
            }
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

    private var sortedLocalPorts: [PortmanLocalPort] {
        (PortmanServerSort(rawValue: serverSort) ?? .port).sorted(service.localPorts)
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
        bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private func portColor(_ port: PortmanLocalPort) -> Color {
        portColors[(Int(port.port) * 7 / 11) % portColors.count]
    }

    private var memoryBreakdown: some View {
        let physical = max(1, Int64(ProcessInfo.processInfo.physicalMemory))
        let segments = displayedUsageSegments
        let total = segments.reduce(Int64(0)) { $0 + $1.memoryBytes }
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle().fill(portColor(segment.port))
                            .frame(width: geometry.size.width * Double(segment.memoryBytes) / Double(max(1, total)))
                            .opacity(highlightedProcessID == nil || highlightedProcessID == segment.port.processID ? 1 : 0.45)
                            .onHover { inside in
                                hoveredSegmentID = inside ? segment.port.processID : nil
                                highlightedProcessID = inside ? segment.port.processID : nil
                            }
                            .help("Port \(String(segment.port.port)): \(memoryString(segment.memoryBytes))")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 12)
            HStack {
                if let segment = segments.first(where: { $0.port.processID == highlightedProcessID }) {
                    Circle().fill(portColor(segment.port)).frame(width: 6, height: 6)
                    Text(":\(String(segment.port.port)) · \(memoryString(segment.memoryBytes))")
                } else {
                    Text(cleanupMode ? "Selected processes" : "Listening processes")
                }
                Spacer()
                Text("\(String(format: "%.1f", Double(total) / Double(physical) * 100))% of RAM")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .help("Memory used only by processes listening on scanned ports")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("portman.memoryBreakdown")
    }

    private func sparkline(for port: PortmanLocalPort) -> some View {
        let samples = service.history[port.id] ?? []
        return Chart(samples) { sample in
            LineMark(x: .value("Time", sample.date), y: .value("Memory", sample.memoryBytes))
                .foregroundStyle(portColor(port))
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
                    .focusEffectDisabled()
                    .font(.system(size: 11))
                Spacer()
                Text(service.metadata[port.id]?.project ?? port.command)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Button { openLocal(port.port) } label: {
                    Image(systemName: "link").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
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
                    if let hovered {
                        RuleMark(x: .value("Time", hovered.date))
                            .foregroundStyle(.secondary)
                        PointMark(x: .value("Time", hovered.date),
                                  y: .value("Memory", hovered.memoryBytes))
                            .foregroundStyle(portColor(port))
                    }
                }
                .chartXScale(domain: chartStart...chartEnd)
                .chartYScale(domain: 0...max(1, (samples.map(\.memoryBytes).max() ?? 1) * 12 / 10))
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
                                y: .value("CPU", sample.cpuPercent),
                                width: .fixed(2))
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
                TextField("alias or user@IP", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .accessibilityLabel("SSH alias or username at IP address")
                    .onSubmit { scanRemote() }
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
                Button("Scan") { scanRemote() }
                .disabled(host.isEmpty || service.isLoadingRemote)
                .controlSize(.small)
            }
            if service.isLoadingRemote { ProgressView("Checking remote ports…").controlSize(.small) }
            Text("Ports stay on the server. Portman binds each tunnel to 127.0.0.1 on this Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            if !host.isEmpty && discoveredHost == host {
                QuietDivider()
                HStack {
                    Text("Listening on \(host)").font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button("Clear scan") { clearRemoteScan() }
                        .controlSize(.small)
                }
                if !service.remotePorts.isEmpty {
                    HStack(spacing: 12) {
                        Button("Select all") {
                            selectedRemotePorts.formUnion(service.remotePorts)
                            lastSelectedRemotePort = nil
                        }
                        Button("Clear selection") {
                            selectedRemotePorts = []
                            lastSelectedRemotePort = nil
                        }
                        .disabled(selectedRemotePorts.isEmpty)
                        Spacer()
                        Text("Local port").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    ForEach(service.remotePorts, id: \.self) { port in remoteRow(port) }
                } else if !service.isLoadingRemote && service.forwardingError == nil {
                    Text("No listening ports found. You can add a remote port manually.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                TextField("Remote port", text: $manualPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Remote port to add")
                    .onSubmit { addManualPort() }
                Button("Add port") { addManualPort() }
                .disabled(host.isEmpty)
                .controlSize(.small)
            }
            ForEach(selectedRemotePorts.sorted().filter { !service.remotePorts.contains($0) || discoveredHost != host }, id: \.self) {
                remoteRow($0)
            }

            Button("Forward \(selectedRemotePorts.count) selected") { forwardSelected() }
                .buttonStyle(.borderedProminent)
                .tint(selectedRemotePorts.isEmpty || host.isEmpty ? .gray : .accentColor)
                .controlSize(.small)
                .disabled(selectedRemotePorts.isEmpty || host.isEmpty)

            if passwordPromptHost == nil, let error = service.forwardingError { errorText(error) }
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
        let detail = service.remoteDetails[port]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { selectedRemotePorts.contains(port) },
                    set: { selected in
                        selectedRemotePorts = Self.remoteSelection(
                            selectedRemotePorts, port: port, selecting: selected,
                            anchor: lastSelectedRemotePort, visible: service.remotePorts,
                            extendRange: NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                        )
                        lastSelectedRemotePort = port
                    }
                )) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Select remote port \(String(port))")
                .help("Shift-click to select a range of remote ports")
                Button {
                    expandedRemotePort = expandedRemotePort == port ? nil : port
                    if expandedRemotePort == port {
                        remoteDetailTask?.cancel()
                        remoteDetailTask = Task { await service.loadRemoteDetails(
                            host: host, port: port,
                            password: sshPasswordHost == host ? sshPassword : nil
                        ) }
                    } else {
                        remoteDetailTask?.cancel()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(":\(String(port))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text(detail?.displayName ?? "Unknown service")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expandedRemotePort == port ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(detail?.command ?? detail?.displayName ?? "Inspect remote port \(String(port))")
                .accessibilityLabel("Details for remote port \(String(port))")
                TextField(String(port), text: Binding(
                    get: { localPortInputs[port] ?? String(port) },
                    set: { localPortInputs[port] = $0; selectedRemotePorts.insert(port) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .accessibilityLabel("Local port for remote port \(String(port))")
                .onSubmit { forwardSelected() }
            }
            if expandedRemotePort == port {
                VStack(alignment: .leading, spacing: 3) {
                    if let pid = detail?.pid { Text("PID \(String(pid))") }
                    if let container = detail?.container { Text("Docker container: \(container)") }
                    Text(detail?.command ?? "Process command unavailable for this listener")
                        .textSelection(.enabled)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 25)
            }
        }
        .padding(.vertical, 3)
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
                    Image(systemName: "link").frame(width: 20)
                }
                .controlSize(.small)
                .help("Open localhost:\(String(tunnel.localPort))")
                .accessibilityLabel("Open tunnel on port \(String(tunnel.localPort))")
            }
            if case .failed = tunnel.state {
                Button("Retry") {
                    if case .failed(let message) = tunnel.state,
                       PortmanScanner.passwordAvailable(in: message) {
                        retryAfterPassword = tunnel
                        passwordPromptError = "Authentication failed. Enter the password again."
                        passwordPromptHost = tunnel.host
                    } else {
                        service.stopTunnel(tunnel.id)
                        _ = service.forward(host: tunnel.host, remotePort: tunnel.remotePort,
                                            localPort: tunnel.localPort,
                                            password: sshPasswordHost == tunnel.host ? sshPassword : nil)
                    }
                }
                .controlSize(.small)
            }
            Button("Stop") { service.stopTunnel(tunnel.id) }
                .controlSize(.small)
        }
        .frame(minHeight: 36)
    }

    nonisolated static func remoteSelection(
        _ current: Set<UInt16>, port: UInt16, selecting: Bool,
        anchor: UInt16?, visible: [UInt16], extendRange: Bool
    ) -> Set<UInt16> {
        var selected = current
        let ports: [UInt16]
        if extendRange, let anchor,
           let start = visible.firstIndex(of: anchor), let end = visible.firstIndex(of: port) {
            ports = Array(visible[min(start, end)...max(start, end)])
        } else {
            ports = [port]
        }
        if selecting { selected.formUnion(ports) } else { selected.subtract(ports) }
        return selected
    }

    private func scanRemote() {
        startRemoteScan(password: sshPasswordHost == host ? sshPassword : nil)
    }

    private func startRemoteScan(password: String?) {
        guard !host.isEmpty else { return }
        let target = host
        remoteScanTask?.cancel()
        service.cancelRemoteScan()
        selectedRemotePorts = []
        lastSelectedRemotePort = nil
        discoveredHost = target
        expandedRemotePort = nil
        remoteScanTask = Task {
            await service.refreshRemote(host: target, password: password)
            guard !Task.isCancelled, page == .forward, host == target,
                  service.forwardingError?.contains("SSH password required.") == true else { return }
            sshPassword = nil
            passwordPromptError = password == nil ? nil : "Authentication failed. Enter the password again."
            passwordPromptHost = target
        }
    }

    private func clearRemoteScan() {
        remoteScanTask?.cancel()
        remoteDetailTask?.cancel()
        service.clearRemoteScan()
        discoveredHost = ""
        selectedRemotePorts = []
        lastSelectedRemotePort = nil
        localPortInputs = [:]
        expandedRemotePort = nil
    }

    private func addManualPort() {
        guard !host.isEmpty else {
            service.forwardingError = "Enter an SSH host first."
            return
        }
        guard let port = UInt16(manualPort.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
            service.forwardingError = "Enter a port from 1 to 65535."
            return
        }
        selectedRemotePorts.insert(port)
        localPortInputs[port] = String(port)
        lastSelectedRemotePort = port
        manualPort = ""
        service.forwardingError = nil
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
            guard service.forward(host: host, remotePort: remotePort, localPort: localPort,
                                  password: sshPasswordHost == host ? sshPassword : nil) else { return }
            selectedRemotePorts.remove(remotePort)
        }
    }

    private func submitPassword(_ password: String, for target: String) {
        let retry = retryAfterPassword
        retryAfterPassword = nil
        passwordPromptHost = nil
        passwordPromptError = nil
        sshPasswordHost = target
        sshPassword = password
        if let retry {
            service.stopTunnel(retry.id)
            _ = service.forward(host: retry.host, remotePort: retry.remotePort,
                                localPort: retry.localPort, password: password)
        } else {
            startRemoteScan(password: password)
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

private struct PortmanPasswordSheet: View {
    let host: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onContinue: (String) -> Void

    @State private var password = ""
    @FocusState private var passwordIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SSH password for \(host)")
                .font(.system(size: 13, weight: .medium))
            Text("Portman uses this password for the scan and selected forwards. It stays in memory until you leave Forward.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($passwordIsFocused)
                .onSubmit(submit)
            if let errorMessage {
                Text(errorMessage).font(.system(size: 11)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Continue", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { passwordIsFocused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        let value = password
        password = ""
        onContinue(value)
    }
}

struct PortmanSettingsView: View {
    @State private var search = ""
    @State private var pendingAutomaticCleanup = false
    @AppStorage("portman.scanLowerPort") private var lowerPort = 3000
    @AppStorage("portman.scanUpperPort") private var upperPort = 9999
    @AppStorage("portman.scanInterval") private var scanInterval = 2.0
    @AppStorage("portman.idleHours") private var idleHours = 4.0
    @AppStorage("portman.runningDays") private var runningDays = 3.0
    @AppStorage("portman.forceQuitSeconds") private var forceQuitSeconds = 3.0
    @AppStorage("portman.cleanupMode") private var cleanupMode = PortmanCleanupMode.ask.rawValue
    @AppStorage("portman.includeDeletedFolders") private var includeDeletedFolders = true
    @AppStorage("portman.protectedCommands") private var protectedCommands = ""
    @AppStorage("portman.showAllListeners") private var showAllListeners = false
    @AppStorage("portman.sessionLinksEnabled") private var sessionLinksEnabled = false
    @AppStorage("portman.publicGitHubLinksEnabled") private var publicGitHubLinksEnabled = false
    @AppStorage("portman.editor") private var editor = "auto"

    private func shows(_ labels: String...) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || labels.contains { $0.localizedStandardContains(query) }
    }

    private var generalVisible: Bool { shows("Keyboard shortcut", "Open folders in", "editor") }
    private var portsVisible: Bool {
        shows("Ports & processes", "Include other listening processes", "Scan ports", "Scan every",
              "Extra protected process names")
    }
    private var cleanupVisible: Bool {
        shows("Clean up", "Cleanup mode", "Include deleted folders", "Suggest after idle hours",
              "Suggest after running days", "Force quit after seconds")
    }
    private var integrationsVisible: Bool {
        shows("Integrations", "Link coding sessions", "Find public GitHub links")
    }
    private var selectedEditorName: String {
        if editor == "auto" { return "Automatic" }
        if editor == "finder" { return "Finder" }
        return PortmanEditor.installed.first(where: { $0.id == editor })?.name ?? "Automatic"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.system(size: 13, weight: .semibold))
            NativeSearchField(text: $search, placeholder: "Search settings")
                .frame(maxWidth: .infinity, minHeight: 28)
                .accessibilityIdentifier("portman.settings.search")
            if !generalVisible && !portsVisible && !cleanupVisible && !integrationsVisible {
                Text("No matching settings")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
            if shows("Keyboard shortcut") {
                HStack {
                    Text("Keyboard shortcut")
                    Spacer()
                    ShortcutRecorderField(action: .portman)
                }
            }
            if shows("Open folders in", "editor") {
                HStack {
                    Text("Open folders in")
                    Spacer()
                    Menu {
                        Button("Automatic") { editor = "auto" }
                        ForEach(PortmanEditor.installed, id: \.id) { choice in
                            Button(choice.name) { editor = choice.id }
                        }
                        Button("Finder") { editor = "finder" }
                    } label: {
                        Text(selectedEditorName)
                            .frame(width: 148, alignment: .trailing)
                    }
                    .accessibilityIdentifier("portman.settings.editor")
                    .accessibilityLabel("Open folders in")
                    .accessibilityValue(selectedEditorName)
                }
            }
            if portsVisible {
                if generalVisible { QuietDivider() }
                Text("Ports & processes").font(.system(size: 12, weight: .medium))
            }
            if shows("Ports & processes", "Include other listening processes") {
                HStack {
                    Text("Include other listening processes")
                    Spacer()
                    Toggle("Include other listening processes", isOn: $showAllListeners).labelsHidden()
                }
            }
            if shows("Ports & processes", "Scan ports") {
                HStack {
                    Text("Scan ports")
                    Spacer()
                    TextField("From", value: $lowerPort, format: .number)
                        .frame(width: 60)
                    Text("–")
                    TextField("To", value: $upperPort, format: .number)
                        .frame(width: 60)
                }
            }
            if shows("Ports & processes", "Scan ports")
                && (lowerPort < 1 || upperPort < lowerPort || upperPort > 65_535) {
                Text("Choose ports between 1 and 65535, with the first no higher than the last.")
                    .foregroundStyle(.red)
            }
            if shows("Ports & processes", "Scan every") {
                HStack {
                    Text("Scan every")
                    Spacer()
                    Menu {
                        ForEach([2.0, 5.0, 10.0, 30.0], id: \.self) { seconds in
                            Button("\(Int(seconds)) seconds") { scanInterval = seconds }
                        }
                    } label: {
                        Text("\(Int(scanInterval)) seconds").frame(width: 98, alignment: .trailing)
                    }
                    .accessibilityIdentifier("portman.settings.interval")
                    .accessibilityLabel("Scan every")
                    .accessibilityValue("\(Int(scanInterval)) seconds")
                }
            }
            if shows("Ports & processes", "Extra protected process names") {
                TextField("Extra protected process names, comma-separated", text: $protectedCommands)
                    .accessibilityLabel("Extra protected process names")
                    .frame(maxWidth: .infinity)
                Text("Databases, Docker, and SSH are always protected.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if cleanupVisible {
                if generalVisible || portsVisible { QuietDivider() }
                Text("Clean up").font(.system(size: 12, weight: .medium))
            }
            if shows("Clean up", "Cleanup mode") {
                HStack {
                    Text("Mode")
                    Spacer()
                    Menu {
                        Button("Off") { cleanupMode = PortmanCleanupMode.off.rawValue }
                        Button("Ask") { cleanupMode = PortmanCleanupMode.ask.rawValue }
                        Button("Automatic") {
                            if cleanupMode != PortmanCleanupMode.automatic.rawValue {
                                pendingAutomaticCleanup = true
                            }
                        }
                    } label: {
                        Text(PortmanCleanupMode(rawValue: cleanupMode)?.rawValue.capitalized ?? "Ask")
                            .frame(width: 98, alignment: .trailing)
                    }
                    .accessibilityIdentifier("portman.settings.cleanupMode")
                    .accessibilityLabel("Cleanup mode")
                    .accessibilityValue(PortmanCleanupMode(rawValue: cleanupMode)?.rawValue.capitalized ?? "Ask")
                }
                Group {
                    if cleanupMode == PortmanCleanupMode.automatic.rawValue {
                        Text("Automatic stops eligible servers without another prompt and force quits any still running after the grace period. Protected and high-usage servers stay excluded.")
                    } else if cleanupMode == PortmanCleanupMode.off.rawValue {
                        Text("Manual cleanup remains available from the server list.")
                    } else {
                        Text("Ask highlights eligible servers in the server list.")
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if shows("Clean up", "Include deleted folders") {
                HStack {
                    Text("Include deleted folders")
                    Spacer()
                    Toggle("Include deleted folders", isOn: $includeDeletedFolders).labelsHidden()
                }
            }
            if shows("Clean up", "Suggest after idle hours") {
                HStack {
                    Text("Suggest after idle")
                    Spacer()
                    PortmanIntegerSettingField("Idle hours", value: $idleHours, range: 1...72)
                    Text("hours").frame(width: 46, alignment: .leading)
                }
            }
            if shows("Clean up", "Suggest after running days") {
                HStack {
                    Text("Suggest after running")
                    Spacer()
                    PortmanIntegerSettingField("Running days", value: $runningDays, range: 1...30)
                    Text("days").frame(width: 46, alignment: .leading)
                }
            }
            if shows("Clean up", "Force quit after seconds") {
                HStack {
                    Text("Force quit after")
                    Spacer()
                    PortmanIntegerSettingField("Force quit seconds", value: $forceQuitSeconds, range: 1...30)
                    Text("seconds").frame(width: 46, alignment: .leading)
                }
            }
            if integrationsVisible {
                if generalVisible || portsVisible || cleanupVisible { QuietDivider() }
                Text("Integrations").font(.system(size: 12, weight: .medium))
            }
            if shows("Integrations", "Link coding sessions") {
                HStack {
                    Text("Link coding sessions")
                    Spacer()
                    Toggle("Link coding sessions", isOn: $sessionLinksEnabled).labelsHidden()
                }
                Text("When you open a server, Portman checks its process for a Claude Code session and recent local Codex sessions for a folder match. A link copies a resume command.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if shows("Integrations", "Find public GitHub links") {
                HStack {
                    Text("Find public GitHub links")
                    Spacer()
                    Toggle("Find public GitHub links", isOn: $publicGitHubLinksEnabled).labelsHidden()
                }
                Text("Checks public pull requests and previews for this project's branch. Private repositories and saved GitHub credentials are not used.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .confirmationDialog("Stop eligible servers automatically?", isPresented: $pendingAutomaticCleanup) {
            Button("Enable Automatic", role: .destructive) {
                cleanupMode = PortmanCleanupMode.automatic.rawValue
            }
        } message: {
            Text("Portman will send stop requests for eligible servers, including long-running ones, without asking again.")
        }
    }
}

private struct PortmanIntegerSettingField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Int>
    @State private var draft = ""

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Int>) {
        self.label = label
        _value = value
        self.range = range
    }

    var body: some View {
        TextField(label, text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: 48)
            .multilineTextAlignment(.trailing)
            .onAppear { draft = String(Int(value)) }
            .onSubmit {
                if let number = Int(draft), range.contains(number) { value = Double(number) }
                draft = String(Int(value))
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
final class PortmanMenuController: NSObject {
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
        let createdStatusItem = item == nil
        start()
        Task { @MainActor [weak self] in
            if createdStatusItem { try? await Task.sleep(for: .milliseconds(200)) }
            guard let self else { return }
            for _ in 0..<200 {
                guard let button = self.item?.button, !self.popover.isShown else { return }
                if button.window != nil && button.bounds.width > 0 {
                    self.popover.contentViewController = NSHostingController(rootView: PortmanPanelView().utilityMotionPolicy())
                    self.popover.contentSize = NSSize(width: 400, height: 400)
                    self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    NSApp.activate(ignoringOtherApps: true)
                    self.popover.contentViewController?.view.window?.makeKey()
                    if AppRuntime.isUITesting { NSLog("Portman popover shown: \(self.popover.isShown)") }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            if AppRuntime.isUITesting { NSLog("Portman status item has no visible anchor") }
        }
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
        image?.size = NSSize(width: 14, height: 14)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = " \(ports.count)"
        let forwarded = PortmanService.shared.tunnels.reduce(0) { count, tunnel in
            if case .running = tunnel.state { return count + 1 }
            return count
        }
        button.toolTip = "Portman · \(ports.count) listening · \(forwarded) forwarded"
    }

    @objc private func toggle() {
        if popover.isShown { popover.close() } else { show() }
    }
}
