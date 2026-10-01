import AppKit
import Charts
import Observation
import SwiftUI
import OnePlusUI

nonisolated struct PortmanOverviewRow: Identifiable, Sendable {
    let port: PortmanLocalPort
    let canStop: Bool
    let title: String
    let subtitle: String
    let memoryText: String
    let sparklineValues: [Double]
    let sparklineRange: ClosedRange<Double>
    var id: String { port.id }
}

nonisolated struct PortmanUsagePresentation: Identifiable, Sendable {
    let port: PortmanLocalPort
    let memoryBytes: Int64
    let cpuPercent: Double
    var id: String { port.id }
}

nonisolated struct PortmanOverviewPresentation: Sendable {
    let rows: [PortmanOverviewRow]
    let segments: [PortmanUsagePresentation]
    let uniquePortCount: Int
    let memoryBytes: Int64
    let cpuPercent: Double
    let suggestedCleanupIDs: Set<String>
    let scanRangeText: String

    static let empty = PortmanOverviewPresentation(
        rows: [], segments: [], uniquePortCount: 0,
        memoryBytes: 0, cpuPercent: 0, suggestedCleanupIDs: [], scanRangeText: "3000–9999"
    )
}

nonisolated func portmanMemoryString(_ bytes: Int64) -> String {
    bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
}

nonisolated func portmanServerName(project: String?, processName: String) -> String {
    guard let project, !project.isEmpty, project != "/" else { return processName }
    return project
}

nonisolated func portmanOverviewPresentation(
    ports: [PortmanLocalPort], history: [String: [PortmanSample]],
    metadata: [String: PortmanMetadata], lastConnectionAt: [String: Date],
    sort: PortmanServerSort, selectedProcessIDs: Set<String>, cleanupMode: Bool,
    idleHours: Double, runningDays: Double, policyMode: PortmanCleanupMode,
    includeDeletedFolders: Bool, scanRange: ClosedRange<UInt16>, now: Date = Date()
) -> PortmanOverviewPresentation {
    var uniqueProcessIDs = Set<String>()
    let uniquePorts = ports.filter { uniqueProcessIDs.insert($0.processID).inserted }
    var seenPIDs = Set<Int32>()
    let segments = uniquePorts.filter {
        !cleanupMode || selectedProcessIDs.contains($0.processID) && $0.canStop
    }.map { port in
        let childMemory = port.processes.reduce(Int64(0)) { $0 + $1.memoryBytes }
        let childCPU = port.processes.reduce(0.0) { $0 + $1.cpuPercent }
        var memory: Int64 = 0
        var cpu = 0.0
        if seenPIDs.insert(port.pid).inserted {
            memory += max(0, port.memoryBytes - childMemory)
            cpu += max(0, port.cpuPercent - childCPU)
        }
        for child in port.processes {
            if cleanupMode && PortmanPreferences.protectedCommands.contains(
                URL(fileURLWithPath: child.command).lastPathComponent.lowercased()) { continue }
            guard seenPIDs.insert(child.pid).inserted else { continue }
            memory += child.memoryBytes
            cpu += child.cpuPercent
        }
        return PortmanUsagePresentation(port: port, memoryBytes: memory, cpuPercent: cpu)
    }
    let suggested = Set(ports.filter { port in
        PortmanCleanupPolicy.suggested(
            port: port,
            highUsage: PortmanCleanupPolicy.highUsage(in: history[port.id] ?? []),
            folder: metadata[port.id]?.folder,
            lastConnectionAt: lastConnectionAt[port.processID],
            now: now,
            idleHours: idleHours,
            runningDays: runningDays,
            mode: policyMode,
            includeDeletedFolders: includeDeletedFolders
        )
    }.map(\.processID))
    var rows = (sort == .name ? ports : sort.sorted(ports)).map { port in
        let values = (history[port.id] ?? []).map { Double($0.memoryBytes) }
        let details = metadata[port.id]
        let title = portmanServerName(project: details?.project,
                                      processName: port.launchCommand.isEmpty ? port.command : port.launchCommand)
        let branch = details?.branch.flatMap { $0.isEmpty || $0 == title ? nil : $0 }
        return PortmanOverviewRow(
            port: port,
            canStop: port.canStop,
            title: title,
            subtitle: branch ?? "",
            memoryText: portmanMemoryString(port.memoryBytes),
            sparklineValues: values,
            sparklineRange: (values.min() ?? 0)...max(1, values.max() ?? 1)
        )
    }
    if sort == .name {
        rows.sort {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.port.port < $1.port.port : order == .orderedAscending
        }
    }
    return PortmanOverviewPresentation(
        rows: rows,
        segments: segments,
        uniquePortCount: uniquePorts.count,
        memoryBytes: segments.reduce(Int64(0)) { $0 + $1.memoryBytes },
        cpuPercent: segments.reduce(0.0) { $0 + $1.cpuPercent },
        suggestedCleanupIDs: suggested,
        scanRangeText: "\(scanRange.lowerBound)–\(scanRange.upperBound)"
    )
}

struct PortmanPanelView: View {
    private static let selectedPageKey = "portman.selectedPage"

    enum Page: String, CaseIterable {
        case local = "Servers", forward = "Forward", settings = "Settings"

        init?(panelID: String) {
            switch panelID {
            case "home", "servers": self = .local
            case "forward": self = .forward
            case "settings": self = .settings
            default: return nil
            }
        }

        var panelID: String {
            switch self {
            case .local: "servers"
            case .forward: "forward"
            case .settings: "settings"
            }
        }
    }

    init(initialPage: Page? = nil, initialHost: String? = nil, initialPortID: String? = nil,
         initialCleanupProcessID: String? = nil) {
        let savedPage = UserDefaults.standard.string(forKey: Self.selectedPageKey)
            .flatMap(Page.init(rawValue:)) ?? .local
        _page = State(initialValue: initialPage
                      ?? (initialPortID != nil || initialCleanupProcessID != nil ? .local : savedPage))
        _selectedPortID = State(initialValue: initialPortID)
        _host = State(initialValue: initialHost ?? "")
        _cleanupMode = State(initialValue: initialCleanupProcessID != nil)
        _selectedCleanupProcesses = State(initialValue: Set(initialCleanupProcessID.map { [$0] } ?? []))
    }

    @State private var service = PortmanService.shared
    @State private var page = Page.local
    @State private var settingsState = PortmanSettingsState()
    @State private var settingsSearch = ""
    @State private var focusSettingsSearch = 0
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
    @State private var refreshTask: Task<Void, Never>?
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
    @State private var hoveredRowID: String?
    @State private var hoveredLinkPortID: String?
    @State private var hoveredStopPortID: String?
    @State private var showingMore = false
    @State private var showingProcesses = false
    @State private var overviewGeneration = 0
    @State private var overviewPresentation = PortmanOverviewPresentation.empty
    @AppStorage("portman.sessionLinksEnabled") private var sessionLinksEnabled = false
    @AppStorage("portman.publicGitHubLinksEnabled") private var publicGitHubLinksEnabled = false
    @AppStorage("portman.editor") private var editor = "auto"
    @AppStorage("portman.serverSort") private var serverSort = PortmanServerSort.port.rawValue

    private let portColors = OnePlusColor.portmanSeries

    private nonisolated struct OverviewRequest: Hashable, Sendable {
        let generation: Int
        let sort: String
        let cleanupMode: Bool
        let selectedProcessIDs: Set<String>
    }

    private var overviewRequest: OverviewRequest {
        OverviewRequest(
            generation: overviewGeneration,
            sort: serverSort,
            cleanupMode: cleanupMode,
            selectedProcessIDs: selectedCleanupProcesses
        )
    }

    private var selectedPort: PortmanLocalPort? {
        service.localPorts.first { $0.id == selectedPortID }
    }

    private var activeTunnelCount: Int {
        service.tunnels.reduce(0) { count, tunnel in
            if case .running = tunnel.state { return count + 1 }
            return count
        }
    }

    private var showingStopConfirmation: Binding<Bool> {
        Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } })
    }

    private var showingRestartConfirmation: Binding<Bool> {
        Binding(get: { pendingRestart != nil }, set: { if !$0 { pendingRestart = nil } })
    }

    private var showingCleanupConfirmation: Binding<Bool> {
        Binding(get: { !pendingCleanupPorts.isEmpty }, set: { if !$0 { pendingCleanupPorts = [] } })
    }

    private var showingPasswordPrompt: Binding<Bool> {
        Binding(
            get: { passwordPromptHost != nil },
            set: { if !$0 { passwordPromptHost = nil; retryAfterPassword = nil } }
        )
    }

    private var selectedPortLoadID: String {
        "\(selectedPortID ?? "")|\(sessionLinksEnabled)|\(publicGitHubLinksEnabled)"
    }

    private let forwardActionWidth: CGFloat = 64

    var body: some View {
        panelDialogs
            .onOpenToolPage("portman") { id in
                if let destination = Page(panelID: id) { navigate(to: destination) }
            }
    }

    private var panel: some View {
        OnePlusMenuPanel(contentID: page.panelID) {
            OnePlusMenuTabStrip(tabs: [
                OnePlusMenuTab(.local, "Servers", systemImage: "server.rack", accessibilityIdentifier: "portman.page.Servers"),
                OnePlusMenuTab(.forward, "Forward", systemImage: "arrow.left.arrow.right", accessibilityIdentifier: "portman.page.Forward"),
                OnePlusMenuTab(.settings, "Settings", systemImage: "gearshape", accessibilityIdentifier: "portman.page.Settings")
            ], selection: Binding(get: { page }, set: navigate))
        } actions: {
            OnePlusMenuOpenApp {
                ToolActionRouter.shared.open(toolID: "main", page: "tool/portman")
            }
            .accessibilityIdentifier("portman.open-app")
            Button {
                refreshTask?.cancel()
                refreshTask = Task { await service.refreshLocal() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                .help("Refresh servers").accessibilityLabel("Refresh servers")
                .accessibilityIdentifier("portman.refresh")
        } toolbar: {
            panelToolbar
        } footer: {
            panelFooter
        } content: {
            Group {
                switch page {
                case .local:
                    if let selectedPort { localDetail(selectedPort) }
                    else { localOverview }
                case .forward: forwardingPage
                case .settings: PortmanSettingsView(search: settingsSearch, state: settingsState)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onOnePlusMenuHeightChange {
            PortmanMenuController.shared.setHeight($0)
        }
        .onePlusPanelTimings(panel: "portman", tab: page.panelID)
    }

    @ViewBuilder private var panelToolbar: some View {
        switch page {
        case .local:
            if let selectedPort {
                localDetailHeader(selectedPort)
                    .padding(.bottom, OnePlusMetrics.spacing[4] - OnePlusMenuMetrics.tileGap)
            } else {
                localOverviewHeader
                    .padding(.bottom, OnePlusMetrics.cardGap - OnePlusMenuMetrics.tileGap)
            }
        case .forward:
            forwardToolbar
                .padding(.bottom, OnePlusMetrics.cardGap - OnePlusMenuMetrics.tileGap)
        case .settings:
            OnePlusSearchField(prompt: "Search settings", text: $settingsSearch, width: nil,
                               focusTrigger: focusSettingsSearch, accessibilityIdentifier: "portman.settings.search")
                .background { Button("Search settings") { focusSettingsSearch += 1 }.keyboardShortcut("f").hidden() }
                .padding(.bottom, OnePlusMetrics.cardGap - OnePlusMenuMetrics.tileGap)
        }
    }

    @ViewBuilder private var panelFooter: some View {
        if page == .local, selectedPort == nil, !overviewPresentation.rows.isEmpty {
            localOverviewFooter
        }
    }

    private var panelWithLifecycle: some View {
        panel
        .onAppear {
            UserDefaults.standard.set(page.rawValue, forKey: Self.selectedPageKey)
            if page == .local {
                service.beginMonitoring()
                panelOwnsMonitoring = true
            }
        }
        .task {
            let load = Task.detached(priority: .utility) {
                let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
                let data = (try? Data(contentsOf: url)) ?? Data()
                let names = SSHConfigEditor.entries(in: data).flatMap(\.aliases)
                    .filter(SystemMonitorRemoteProtocol.validHost)
                return Array(Set(names)).sorted()
            }
            let names = await withTaskCancellationHandler { await load.value } onCancel: { load.cancel() }
            if !Task.isCancelled { aliases = names }
        }
        .task(id: overviewRequest) { await prepareOverview() }
        .onReceive(NotificationCenter.default.publisher(for: .portmanSnapshotChanged)) { _ in
            overviewGeneration &+= 1
        }
        .onChange(of: service.metadata.count) { overviewGeneration &+= 1 }
        .onDisappear {
            if panelOwnsMonitoring { service.endMonitoring() }
            panelOwnsMonitoring = false
            refreshTask?.cancel()
            remoteScanTask?.cancel()
            remoteDetailTask?.cancel()
            service.clearRemoteScan()
            sshPassword = nil
            passwordPromptHost = nil
            retryAfterPassword = nil
        }
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
                discoveredHost = ""
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
            discoveredHost = ""
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
        .task(id: selectedPortLoadID) { await loadSelectedPortDetails() }
    }

    private var panelDialogs: some View {
        panelWithLifecycle
        .confirmationDialog("Stop this server process?", isPresented: showingStopConfirmation,
                            presenting: pendingStop) { port in
            Button("Stop PID \(String(port.pid))", role: .destructive) { service.stopLocal(port) }
        } message: { port in
            Text("Port \(String(port.port)) and eligible children will stop. Any still running after the grace period will be force quit.")
        }
        .confirmationDialog("Restart this server?", isPresented: showingRestartConfirmation,
                            presenting: pendingRestart) { port in
            Button("Restart PID \(String(port.pid))") { service.restartLocal(port) }
        } message: { port in
            Text("Port \(String(port.port)) will stop, then Portman will run its saved command in the same folder. Output goes to Library/Logs/MacPowerToys/Portman.")
        }
        .confirmationDialog("Stop selected server processes?", isPresented: showingCleanupConfirmation,
                            titleVisibility: .visible) {
            Button("Stop \(Set(pendingCleanupPorts.map(\.processID)).count) Processes", role: .destructive) {
                service.stopLocalProcesses(pendingCleanupPorts)
                pendingCleanupPorts = []
                cleanupMode = false
                selectedCleanupProcesses = []
            }
        } message: {
            Text("Stopping these processes may interrupt open work. Any still running after the grace period will be force quit.")
        }
        .sheet(isPresented: showingPasswordPrompt) {
            if let passwordPromptHost {
                PortmanPasswordSheet(host: passwordPromptHost, errorMessage: passwordPromptError,
                                     onCancel: { self.passwordPromptHost = nil; retryAfterPassword = nil },
                                     onContinue: { password in submitPassword(password, for: passwordPromptHost) })
            }
        }
    }

    private func navigate(to destination: Page) {
        if destination != page, !OnePlusPanelTimings.shared.hasPending("portman") {
            OnePlusPanelTimings.shared.begin(panel: "portman", operation: .tabSwitch, tab: destination.panelID)
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            page = destination
            selectedPortID = nil
            cleanupMode = false
            selectedCleanupProcesses = []
        }
    }

    private func loadSelectedPortDetails() async {
        hoveredTime = nil
        guard let selectedPort else { return }
        await service.loadMetadata(for: selectedPort)
        await service.loadRestartAvailability(for: selectedPort)
        await service.loadSession(for: selectedPort)
        await service.loadGitHubLinks(for: selectedPort)
    }

    private func prepareOverview() async {
        let request = overviewRequest
        let ports = service.localPorts
        let history = service.history
        let metadata = service.metadata
        let lastConnectionAt = service.lastConnectionAt
        let work = Task.detached(priority: .userInitiated) {
            portmanOverviewPresentation(
                ports: ports,
                history: history,
                metadata: metadata,
                lastConnectionAt: lastConnectionAt,
                sort: PortmanServerSort(rawValue: request.sort) ?? .port,
                selectedProcessIDs: request.selectedProcessIDs,
                cleanupMode: request.cleanupMode,
                idleHours: PortmanPreferences.idleSuggestionHours,
                runningDays: PortmanPreferences.runningSuggestionDays,
                policyMode: PortmanPreferences.cleanupMode,
                includeDeletedFolders: PortmanPreferences.includeDeletedFolders,
                scanRange: PortmanPreferences.scanRange
            )
        }
        let presentation = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled, overviewRequest == request else { return }
        overviewPresentation = presentation
    }

    private var localOverviewHeader: some View {
        return VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            OnePlusSectionTitle(cleanupMode ? "Clean up" : "Servers")
            HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.actionSpacing) {
                Text(portmanMemoryString(overviewPresentation.memoryBytes))
                    .monospaced()
                    .onePlusText(.metric).onePlusDensity(.regular)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(cleanupMode
                     ? "\(selectedCleanupProcesses.count) selected"
                     : "\(overviewPresentation.uniquePortCount) server\(overviewPresentation.uniquePortCount == 1 ? "" : "s") · \(String(format: "%.1f", overviewPresentation.cpuPercent))% CPU")
                    .onePlusText(.caption)
                    .lineLimit(1)
            }
            .help(cleanupMode ? "Estimated memory freed by stopping selected processes"
                  : "Memory used by processes listening on scanned ports")
            memoryBreakdown
        }
    }

    private var localOverview: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            if overviewPresentation.rows.isEmpty {
                HStack(spacing: OnePlusMetrics.spacing[4]) {
                    Image(systemName: "network").foregroundStyle(OnePlusColor.secondary)
                    Text("No servers listening").onePlusText(.cardTitle)
                    Spacer()
                }
                .padding(OnePlusMetrics.actionSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Local development ports \(overviewPresentation.scanRangeText) will appear here.")
            } else {
                LazyVStack(spacing: OnePlusMetrics.spacing[1]) {
                    ForEach(overviewPresentation.rows) { row in localRow(row) }
                }
            }
            if let error = service.localError { errorText(error) }
            if let error = service.controlError { errorText(error) }
        }
    }

    private var localOverviewFooter: some View {
        VStack(spacing: OnePlusMetrics.actionSpacing) {
            OnePlusColor.lineSoft.frame(height: 1)
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                if cleanupMode {
                    Button("Cancel") { cleanupMode = false; selectedCleanupProcesses = [] }
                    Spacer()
                    Button("Stop \(selectedCleanupProcesses.count) · free \(portmanMemoryString(overviewPresentation.memoryBytes))", role: .destructive) {
                        pendingCleanupPorts = service.localPorts.filter {
                            selectedCleanupProcesses.contains($0.processID)
                        }
                    }
                    .buttonStyle(OnePlusButtonStyle(.destructive, size: .small))
                    .disabled(selectedCleanupProcesses.isEmpty)
                } else {
                    Text("\(overviewPresentation.uniquePortCount) server\(overviewPresentation.uniquePortCount == 1 ? "" : "s") · \(String(format: "%.1f", overviewPresentation.cpuPercent))% CPU")
                        .onePlusText(.mono)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    OnePlusSelect(
                        choices: PortmanServerSort.allCases.map { ($0.rawValue, $0.label) },
                        selection: $serverSort,
                        width: 96,
                        accessibilityLabel: "Sort by"
                    )
                    .accessibilityIdentifier("portman.sort")
                    Button(overviewPresentation.suggestedCleanupIDs.isEmpty
                           ? "Clean up"
                           : "Clean up \(overviewPresentation.suggestedCleanupIDs.count)") {
                        selectedCleanupProcesses = overviewPresentation.suggestedCleanupIDs
                        cleanupMode = true
                    }
                        .disabled(!overviewPresentation.rows.contains(where: \.canStop))
                }
            }
            .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
        }
        .padding(.top, OnePlusMetrics.actionSpacing - OnePlusMenuMetrics.tileGap)
    }

    private func localRow(_ row: PortmanOverviewRow) -> some View {
        let port = row.port
        let isHovered = hoveredRowID == port.id
        return HStack(spacing: OnePlusMetrics.actionSpacing) {
            if cleanupMode {
                Toggle(isOn: Binding(
                    get: { selectedCleanupProcesses.contains(port.processID) },
                    set: { if $0 { selectedCleanupProcesses.insert(port.processID) } else { selectedCleanupProcesses.remove(port.processID) } }
                )) { EmptyView() }
                .labelsHidden()
                .toggleStyle(OnePlusCheckboxStyle())
                .disabled(!row.canStop)
                .accessibilityLabel("Select process \(String(port.pid)) for cleanup")
            }
            HStack(spacing: OnePlusMetrics.spacing[1]) {
                Button {
                    if cleanupMode {
                        guard row.canStop else { return }
                        if selectedCleanupProcesses.contains(port.processID) {
                            selectedCleanupProcesses.remove(port.processID)
                        } else {
                            selectedCleanupProcesses.insert(port.processID)
                        }
                    } else { selectedPortID = port.id }
                } label: {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        HStack(spacing: OnePlusMetrics.spacing[1]) {
                            VStack(spacing: OnePlusMetrics.spacing[0]) {
                                Circle().fill(portColor(port)).frame(width: 3, height: 3)
                                Circle().fill(portColor(port)).frame(width: 3, height: 3)
                            }
                            Text(String(port.port))
                                .onePlusText(.mono, color: portColor(port))
                        }
                        .foregroundStyle(portColor(port))
                        .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                            Text(row.title)
                                .onePlusText(.cardTitle).lineLimit(1)
                            if !row.subtitle.isEmpty {
                                Text(row.subtitle).onePlusText(.caption).lineLimit(1)
                            }
                        }
                        Spacer(minLength: OnePlusMetrics.spacing[1])
                        HStack(spacing: OnePlusMetrics.spacing[2]) {
                            sparkline(for: row)
                                .frame(width: 24, height: 24)
                            Text(row.memoryText)
                                .onePlusText(.mono).foregroundStyle(OnePlusColor.ink)
                                .monospacedDigit()
                                .frame(width: 54, alignment: .trailing)
                            Text(port.uptime).onePlusText(.caption).lineLimit(1)
                                .frame(width: 48, alignment: .trailing)
                                .help("Running for \(port.uptime)")
                        }
                        .frame(width: 134, height: 28)
                    }
                    .padding(.horizontal, OnePlusMetrics.actionSpacing)
                    .frame(minHeight: 52)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.panelRadius))
                .accessibilityIdentifier("portman.local.\(String(port.port))")
                .accessibilityLabel(cleanupMode
                                    ? "Select port \(String(port.port)) for cleanup"
                                    : "Show port \(String(port.port)) details")
                .help("\(row.title)\(row.subtitle.isEmpty ? "" : " · \(row.subtitle)") · up \(port.uptime)")
                if !cleanupMode {
                    HStack(spacing: OnePlusMetrics.spacing[1]) {
                        Button { openLocal(port.port) } label: {
                            Image(systemName: "link").onePlusText(.caption)
                                .frame(width: OnePlusMetrics.compactControlHeight, height: OnePlusMetrics.compactControlHeight)
                        }
                        .foregroundStyle(hoveredLinkPortID == port.id ? OnePlusColor.portmanSeries[0] : OnePlusColor.secondary)
                        .background(hoveredLinkPortID == port.id ? OnePlusColor.raised : .clear,
                                    in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
                        .onHover { hoveredLinkPortID = $0 ? port.id : nil }
                        .help("Open localhost port \(String(port.port))")
                        .accessibilityLabel("Open localhost port \(String(port.port))")
                        .accessibilityIdentifier("portman.link.\(String(port.port))")
                        if row.canStop {
                            Button { pendingStop = port } label: {
                                Image(systemName: "stop.fill").onePlusText(.caption)
                                    .frame(width: OnePlusMetrics.compactControlHeight, height: OnePlusMetrics.compactControlHeight)
                            }
                            .foregroundStyle(hoveredStopPortID == port.id ? OnePlusColor.danger : OnePlusColor.secondary)
                            .background(hoveredStopPortID == port.id ? OnePlusColor.dangerFill : .clear,
                                        in: RoundedRectangle(cornerRadius: OnePlusMetrics.controlRadius))
                            .onHover { hoveredStopPortID = $0 ? port.id : nil }
                            .help("Stop process tree for port \(String(port.port))")
                            .accessibilityLabel("Stop process tree for port \(String(port.port))")
                            .accessibilityIdentifier("portman.stop.\(String(port.port))")
                        }
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .padding(.trailing, OnePlusMetrics.actionSpacing)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(isHovered ? OnePlusColor.raised : .clear,
                    in: RoundedRectangle(cornerRadius: OnePlusMetrics.panelRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portman.local.row.\(String(port.port))")
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
            if row.canStop {
                Button("Stop process tree…", role: .destructive) { pendingStop = port }
            }
        }
    }

    private func memoryString(_ bytes: Int64) -> String {
        portmanMemoryString(bytes)
    }

    private func portColor(_ port: PortmanLocalPort) -> Color {
        portColors[(Int(port.port) * 7 / 11) % portColors.count]
    }

    private var memoryBreakdown: some View {
        let physical = max(1, Int64(ProcessInfo.processInfo.physicalMemory))
        let segments = overviewPresentation.segments
        let total = overviewPresentation.memoryBytes
        return VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[2]) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle().fill(portColor(segment.port))
                            .frame(width: geometry.size.width * Double(segment.memoryBytes) / Double(max(1, total)))
                            .opacity(highlightedProcessID == nil || highlightedProcessID == segment.port.processID ? 1 : OnePlusMetrics.disabledOpacity)
                            .onHover { inside in
                                highlightedProcessID = inside ? segment.port.processID : nil
                            }
                            .help("Port \(String(segment.port.port)): \(memoryString(segment.memoryBytes))")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(OnePlusColor.track)
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack {
                Text(cleanupMode ? "Selected processes" : "Listening processes")
                Spacer()
                Text("\(String(format: "%.1f", Double(total) / Double(physical) * 100))% of RAM")
            }
            .onePlusText(.mono)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .help("Memory used only by processes listening on scanned ports")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("portman.memoryBreakdown")
    }

    private func sparkline(for row: PortmanOverviewRow) -> some View {
        OnePlusSparkline(values: row.sparklineValues, range: row.sparklineRange, color: portColor(row.port))
            .accessibilityLabel("Recent memory use for port \(String(row.port.port))")
    }

    private func localDetailHeader(_ port: PortmanLocalPort) -> some View {
        let canStop = overviewPresentation.rows.first { $0.id == port.id }?.canStop ?? false
        return HStack {
            Button { selectedPortID = nil } label: { Label("Servers", systemImage: "chevron.left") }
                .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
            Spacer()
            Text(portmanServerName(project: service.metadata[port.id]?.project,
                                   processName: port.command))
                .onePlusText(.sectionTitle).lineLimit(1)
            Spacer()
            Button { openLocal(port.port) } label: {
                Image(systemName: "link")
            }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .help("Open localhost:\(String(port.port))")
            .accessibilityLabel("Open localhost port \(String(port.port))")
            OnePlusMenuButton("More actions for port \(String(port.port))", variant: .borderedIcon) {
                var items: [OnePlusPopupMenuEntry] = [.item(OnePlusPopupMenuItem("Copy URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("http://127.0.0.1:\(port.port)/", forType: .string)
                }), .item(OnePlusPopupMenuItem("Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(port.launchCommand, forType: .string)
                })]
                if let details = service.metadata[port.id] {
                    items.append(.item(OnePlusPopupMenuItem("Open in editor") {
                        PortmanEditor.open(details.root ?? details.folder, preferred: editor)
                    }))
                    items.append(.item(OnePlusPopupMenuItem("Show folder in Finder") {
                        NSWorkspace.shared.selectFile(
                            nil, inFileViewerRootedAtPath: details.root ?? details.folder
                        )
                    }))
                }
                if canStop {
                    items.append(.item(OnePlusPopupMenuItem("Restart with saved command…",
                        isEnabled: service.restartableIDs.contains(port.id)) { pendingRestart = port }))
                    items.append(.item(OnePlusPopupMenuItem("Stop process tree…", role: .destructive) {
                        pendingStop = port
                    }))
                }
                return items
            }
            .accessibilityLabel("More actions for port \(String(port.port))")
        }
    }

    private func localDetail(_ port: PortmanLocalPort) -> some View {
        let samples = service.history[port.id] ?? []
        let chartEnd = (samples.last?.date ?? Date()).addingTimeInterval(10)
        let chartStart = chartEnd.addingTimeInterval(-600)
        let hovered = hoveredTime.flatMap { time in
            samples.min { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }
        }
        let cpuCeiling = max(100, ceil((samples.map(\.cpuPercent).max() ?? 0) / 50) * 50)
        let canStop = overviewPresentation.rows.first { $0.id == port.id }?.canStop ?? false
        return VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[4]) {
            HStack(alignment: .firstTextBaseline) {
                Text(":\(String(port.port))")
                    .monospaced()
                    .onePlusText(.metric).onePlusDensity(.regular)
                    .foregroundStyle(portColor(port))
                Spacer()
                Text("up \(port.uptime)")
                    .onePlusText(.mono)
                if canStop {
                    Button { pendingRestart = port } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .disabled(!service.restartableIDs.contains(port.id)
                              || service.restartingIDs.contains(port.id))
                    .help(service.restartableIDs.contains(port.id)
                          ? "Restart with the original command and environment"
                          : "Restart requires the original command, environment, and folder")
                    .accessibilityLabel("Restart process for port \(String(port.port))")
                    Button { pendingStop = port } label: {
                        Image(systemName: "stop.circle")
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .foregroundStyle(hoveredStopPortID == port.id ? OnePlusColor.danger : OnePlusColor.secondary)
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
                    Text("Session").foregroundStyle(OnePlusColor.secondary).frame(width: 72, alignment: .leading)
                    Spacer()
                    Text(session.label).lineLimit(1).help(session.label)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.resumeCommand, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .help("Copy \(session.label) resume command")
                    .accessibilityLabel("Copy \(session.label) resume command")
                }
                .onePlusText(.row)
                .onePlusRowHover()
            }
            if let links = service.githubLinks[port.id],
               let url = links.pullRequestURL, let number = links.pullRequestNumber {
                HStack {
                    Text("Pull request").foregroundStyle(OnePlusColor.secondary).frame(width: 72, alignment: .leading)
                    Spacer(minLength: 0)
                    Button("#\(String(number)) ↗") { NSWorkspace.shared.open(url) }
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                        .help(url.absoluteString)
                }
                .onePlusText(.row)
                .onePlusRowHover()
            }
            Button(showingMore ? "Less" : "More details") { showingMore.toggle() }
                .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                .foregroundStyle(OnePlusColor.secondary)
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
                    Image(systemName: "info.circle").foregroundStyle(OnePlusColor.secondary)
                        .help(note).accessibilityLabel(note)
                }
            }
            OnePlusColor.lineSoft.frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text("Memory").onePlusText(.sectionTitle)
                Spacer()
                Text(memoryString(hovered?.memoryBytes ?? port.memoryBytes))
                    .onePlusText(.mono)
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
                            .foregroundStyle(OnePlusColor.secondary)
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
                    Text("CPU").onePlusText(.sectionTitle)
                    Spacer()
                    Text(String(format: "%.1f%%", hovered?.cpuPercent ?? port.cpuPercent))
                        .onePlusText(.mono)
                }
                Chart {
                    ForEach(samples) { sample in
                        BarMark(x: .value("Time", sample.date),
                                y: .value("CPU", sample.cpuPercent),
                                width: .fixed(2))
                            .foregroundStyle(hovered?.date == sample.date ? OnePlusColor.ink : portColor(port))
                    }
                    if let hovered {
                        RuleMark(x: .value("Time", hovered.date))
                            .foregroundStyle(OnePlusColor.secondary)
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
            .onePlusText(.mono)
            .frame(height: 14)
            OnePlusColor.lineSoft.frame(height: 1)
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
                    Text("Processes").onePlusText(.sectionTitle)
                    Spacer()
                    Text("\(port.processes.count + 1) · \(memoryString(port.memoryBytes))")
                        .onePlusText(.mono)
                }
            }
            if let preview = service.githubLinks[port.id]?.previewURL {
                Button("Open preview") { NSWorkspace.shared.open(preview) }
                    .buttonStyle(OnePlusButtonStyle())
                    .help(preview.absoluteString)
            }
            if let error = service.controlError { errorText(error) }
        }
    }

    private func processRow(pid: Int32, command: String, memoryBytes: Int64, totalBytes: Int64) -> some View {
        VStack(spacing: OnePlusMetrics.spacing[1]) {
            HStack {
                Text(command).lineLimit(1)
                Spacer()
                Text(String(pid)).foregroundStyle(OnePlusColor.secondary)
                Text(memoryString(memoryBytes)).frame(width: 68, alignment: .trailing)
            }
            .onePlusText(.mono)
            ProgressView(value: min(1, Double(memoryBytes) / Double(max(1, totalBytes))))
                .progressViewStyle(.linear)
                .tint(OnePlusColor.portmanSeries[0])
            .frame(height: 3)
        }
        .padding(.vertical, OnePlusMetrics.spacing[1])
        .onePlusRowHover()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(OnePlusColor.secondary).frame(width: 72, alignment: .leading)
            Spacer(minLength: 0)
            Text(value).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing).help(value)
        }
        .onePlusText(.row)
        .onePlusRowHover()
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
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            forwardResults
        }
    }

    private var forwardToolbar: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusTextField("alias or user@IP", text: $host, onSubmit: scanRemote)
                    .accessibilityLabel("SSH alias or username at IP address")
                    .help(host.isEmpty ? "SSH alias or username at IP address" : host)
                if !aliases.isEmpty {
                    OnePlusSelect(
                        choices: [("", "Hosts")] + aliases.map { ($0, $0) },
                        selection: Binding(
                            get: { aliases.contains(host) ? host : "" },
                            set: { if !$0.isEmpty { host = $0 } }
                        ),
                        width: OnePlusMenuMetrics.actionColumn,
                        accessibilityLabel: "Choose an SSH host"
                    )
                }
                if service.isLoadingRemote {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Scanning ports on \(host)")
                    Button("Cancel", action: clearRemoteScan)
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small, minWidth: forwardActionWidth))
                } else {
                    Button("Scan", action: scanRemote)
                        .buttonStyle(OnePlusButtonStyle(
                            selectedRemotePorts.isEmpty ? .primary : .neutral,
                            size: .small,
                            minWidth: forwardActionWidth
                        ))
                        .disabled(host.isEmpty)
                }
            }
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusTextField("Remote port", text: $manualPort, onSubmit: addManualPort)
                    .accessibilityLabel("Remote port to add")
                Button("Add port", action: addManualPort).disabled(host.isEmpty)
                    .buttonStyle(OnePlusButtonStyle(.neutral, size: .small, minWidth: forwardActionWidth))
            }
        }
    }

    @ViewBuilder private var forwardResults: some View {
            if !service.tunnels.isEmpty {
                HStack {
                    OnePlusSectionTitle("Forwarded ports")
                    Text("\(activeTunnelCount) active").onePlusText(.caption)
                }
                ForEach(service.tunnels) { tunnelRow($0) }
            }
            if !host.isEmpty && discoveredHost == host {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    OnePlusSectionTitle(host)
                    Text("\(service.remotePorts.count) ports").onePlusText(.caption)
                    Button("Clear scan", action: clearRemoteScan)
                        .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                }
                if !service.remotePorts.isEmpty {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
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
                        Text("Local port").onePlusText(.caption)
                    }
                    .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    ForEach(service.remotePorts, id: \.self) { port in remoteRow(port) }
                } else {
                    Text("No listening ports found").onePlusText(.row)
                        .help("You can add a remote port manually.")
                }
            }
            ForEach(selectedRemotePorts.sorted().filter { !service.remotePorts.contains($0) || discoveredHost != host }, id: \.self) {
                remoteRow($0)
            }
            if !selectedRemotePorts.isEmpty {
                Button("Forward \(selectedRemotePorts.count) selected") { forwardSelected() }
                    .buttonStyle(OnePlusButtonStyle(.primary))
                    .disabled(host.isEmpty)
            }
            if passwordPromptHost == nil, let error = service.forwardingError { errorText(error) }
    }

    private func remoteRow(_ port: UInt16) -> some View {
        let detail = service.remoteDetails[port]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
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
                .toggleStyle(OnePlusCheckboxStyle())
                .accessibilityLabel("Select remote port \(String(port))")
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
                    HStack(spacing: OnePlusMetrics.spacing[2]) {
                        Text(":\(String(port))")
                            .onePlusText(.mono)
                        Text(detail?.displayName ?? "Unknown service")
                            .onePlusText(.row)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .onePlusText(.caption)
                            .rotationEffect(.degrees(expandedRemotePort == port ? 90 : 0))
                            .foregroundStyle(OnePlusColor.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.compactControlHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OnePlusInteractionStyle())
                .accessibilityLabel("Details for remote port \(String(port))")
                OnePlusTextField(String(port), text: Binding(
                    get: { localPortInputs[port] ?? String(port) },
                    set: { localPortInputs[port] = $0; selectedRemotePorts.insert(port) }
                ), onSubmit: forwardSelected)
                .frame(width: OnePlusMenuMetrics.actionColumn)
                .accessibilityLabel("Local port for remote port \(String(port))")
            }
            .padding(OnePlusMetrics.actionSpacing)
            .onePlusRowHover()
            if expandedRemotePort == port {
                HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.actionSpacing) {
                    if let command = detail?.command {
                        Text(command).lineLimit(2).textSelection(.enabled).help(command)
                    } else {
                        Image(systemName: "info.circle")
                            .help("Process command unavailable for this listener")
                            .accessibilityLabel("Process command unavailable for this listener")
                    }
                    Spacer(minLength: 0)
                    if let pid = detail?.pid { Text("PID \(String(pid))") }
                }
                .onePlusText(.mono)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OnePlusMetrics.actionSpacing)
                .onePlusRowHover()
                if let container = detail?.container { detailRow("Container", container) }
            }
        }
        .contextMenu {
            Button(selectedRemotePorts.contains(port) ? "Deselect" : "Select") {
                if selectedRemotePorts.contains(port) { selectedRemotePorts.remove(port) }
                else { selectedRemotePorts.insert(port) }
            }
            Button("Copy remote port") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(port), forType: .string)
            }
        }
    }

    private func tunnelRow(_ tunnel: PortmanTunnel) -> some View {
        HStack(spacing: OnePlusMetrics.actionSpacing) {
            Image(systemName: tunnelSymbol(tunnel.state))
                .foregroundStyle(tunnelColor(tunnel.state))
            Text(":\(String(tunnel.localPort)) → \(tunnel.host):\(String(tunnel.remotePort))")
                .onePlusText(.mono).lineLimit(1)
            Spacer(minLength: 0)
            Text(tunnelStateLabel(tunnel.state)).onePlusText(.caption, color: tunnelColor(tunnel.state))
                .lineLimit(1)
            if case .running = tunnel.state {
                Button("Link") { openLocal(tunnel.localPort) }
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
            }
            Button("Stop") { service.stopTunnel(tunnel.id) }
        }
        .buttonStyle(OnePlusButtonStyle(.neutral, size: .small, minWidth: OnePlusMetrics.compactControlHeight * 2))
        .padding(OnePlusMetrics.actionSpacing)
        .onePlusRowHover()
        .help("localhost:\(String(tunnel.localPort)) → \(tunnel.host):\(String(tunnel.remotePort)) · \(tunnelStatus(tunnel.state))")
        .contextMenu {
            if case .running = tunnel.state { Button("Open localhost") { openLocal(tunnel.localPort) } }
            Button("Stop forwarding") { service.stopTunnel(tunnel.id) }
        }
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
        guard !host.isEmpty, !service.isLoadingRemote else { return }
        let target = host
        remoteScanTask?.cancel()
        service.clearRemoteScan()
        selectedRemotePorts = []
        lastSelectedRemotePort = nil
        discoveredHost = ""
        expandedRemotePort = nil
        remoteScanTask = Task {
            await service.refreshRemote(host: target, password: password)
            guard !Task.isCancelled, page == .forward, host == target else { return }
            if service.forwardingError == nil {
                discoveredHost = target
                return
            }
            guard service.forwardingError?.contains("SSH password required.") == true else { return }
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
        OnePlusBanner(message, tone: .error).textSelection(.enabled)
            .accessibilityIdentifier("portman.forwarding.error")
    }

    private func tunnelSymbol(_ state: PortmanTunnel.State) -> String {
        switch state { case .connecting: "hourglass"; case .running: "circle.fill"; case .failed: "exclamationmark.triangle" }
    }

    private func tunnelColor(_ state: PortmanTunnel.State) -> Color {
        switch state { case .connecting: OnePlusColor.muted; case .running: OnePlusColor.secondary; case .failed: OnePlusColor.danger }
    }

    private func tunnelStatus(_ state: PortmanTunnel.State) -> String {
        switch state { case .connecting: "Connecting"; case .running: "Forwarding"; case .failed(let message): message }
    }

    private func tunnelStateLabel(_ state: PortmanTunnel.State) -> String {
        if case .failed = state { return "Failed" }
        return tunnelStatus(state)
    }
}

private struct PortmanPasswordSheet: View {
    let host: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onContinue: (String) -> Void

    @State private var password = ""

    var body: some View {
        OnePlusSheet("SSH password for \(host)", width: .small, close: onCancel) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Image(systemName: "info.circle").foregroundStyle(OnePlusColor.secondary)
                    .help("The password stays in memory until you leave Forward. Portman uses it for the scan and selected forwards.")
                    .accessibilityLabel("The password stays in memory until you leave Forward.")
            }
            if let errorMessage {
                OnePlusBanner(errorMessage, tone: .error)
            }
            }
        } footer: {
            Button("Cancel", action: onCancel).buttonStyle(OnePlusButtonStyle(.ghost))
            Button("Continue", action: submit).buttonStyle(OnePlusButtonStyle(.primary)).disabled(password.isEmpty)
        }
        .onDisappear { password = "" }
        .onExitCommand(perform: onCancel)
    }

    private func submit() {
        guard !password.isEmpty else { return }
        let value = password
        password = ""
        onContinue(value)
    }
}

@MainActor @Observable
final class PortmanSettingsState {
    var pendingAutomaticCleanup = false
    var installedEditors: [(id: String, name: String)]?

    func loadEditors() async {
        guard installedEditors == nil else { return }
        let work = Task.detached(priority: .utility) { PortmanEditor.installed }
        let editors = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        installedEditors = editors
    }
}

struct PortmanSettingsView: View {
    var search = ""
    @State var state = PortmanSettingsState()
    @Environment(\.onePlusDensity) private var density
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
        shows("Ports & processes", "All listeners", "Include other listening processes", "First port", "Last port",
              "Scan ports", "Scan every", "Protected apps", "Extra protected process names")
    }
    private var cleanupVisible: Bool {
        shows("Clean up", "Cleanup mode", "Include deleted folders", "Idle for", "Suggest after idle hours",
              "Running for", "Suggest after running days", "Force quit after seconds")
    }
    private var integrationsVisible: Bool {
        shows("Integrations", "Link coding sessions", "Find public GitHub links")
    }
    private var cleanupHelp: String {
        switch PortmanCleanupMode(rawValue: cleanupMode) {
        case .automatic: "Stops eligible servers automatically."
        case .off: "Manual cleanup stays available in Servers."
        default: "Highlights eligible servers in Servers."
        }
    }
    private var portControlWidth: CGFloat {
        density == .compact ? OnePlusMetrics.controlColumn : OnePlusMetrics.wideControlColumn
    }
    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            if !generalVisible && !portsVisible && !cleanupVisible && !integrationsVisible {
                OnePlusEmptyState("No matching settings", systemImage: "magnifyingglass")
            }
            if generalVisible {
                VStack(alignment: .leading, spacing: 0) {
                    OnePlusSectionTitle("General")
                    if shows("Keyboard shortcut") {
                        OnePlusSettingRow("Shortcut") { ShortcutRecorderField(action: .portman) }
                            .onePlusRowHover()
                    }
                    if shows("Open folders in", "editor") {
                        OnePlusSettingRow("Open folders in", separator: false) {
                            OnePlusSelect(choices: [("auto", "Automatic")] + (state.installedEditors ?? []).map { ($0.id, $0.name) } + [("finder", "Finder")],
                                          selection: $editor, accessibilityLabel: "Open folders in")
                                .accessibilityIdentifier("portman.settings.editor")
                        }
                        .onePlusRowHover()
                    }
                }
            }
            if portsVisible { portSettings }
            if cleanupVisible { cleanupSettings }
            if integrationsVisible { integrationSettings }
        }
        .confirmationDialog("Stop eligible servers automatically?", isPresented: $state.pendingAutomaticCleanup) {
            Button("Enable Automatic", role: .destructive) {
                cleanupMode = PortmanCleanupMode.automatic.rawValue
            }
        } message: {
            Text("Portman will send stop requests for eligible servers, including long-running ones, without asking again.")
        }
        .task { await state.loadEditors() }
    }

    private var portSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnePlusSectionTitle("Ports & processes")
            if shows("Ports & processes", "All listeners", "Include other listening processes") {
                OnePlusSettingRow("All listeners", help: "Include other listening processes", controlWidth: 29) {
                    Toggle("Include other listening processes", isOn: $showAllListeners)
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                .onePlusRowHover()
            }
            if shows("Ports & processes", "First port", "Scan ports") {
                OnePlusSettingRow("First port", controlWidth: portControlWidth) {
                    OnePlusStepperField("First scan port", value: $lowerPort, in: 1...max(1, min(upperPort, 65535)))
                        .frame(width: portControlWidth)
                }
                .onePlusRowHover()
            }
            if shows("Ports & processes", "Last port", "Scan ports") {
                OnePlusSettingRow("Last port", controlWidth: portControlWidth) {
                    OnePlusStepperField("Last scan port", value: $upperPort, in: max(1, min(lowerPort, 65535))...65535)
                        .frame(width: portControlWidth)
                }
                .onePlusRowHover()
            }
            if shows("Ports & processes", "Scan every") {
                OnePlusSettingRow("Scan every", controlWidth: portControlWidth) {
                    OnePlusSelect(choices: [2.0, 5.0, 10.0, 30.0].map { ($0, "\(Int($0)) seconds") },
                                  selection: $scanInterval, width: portControlWidth, accessibilityLabel: "Scan every")
                        .accessibilityIdentifier("portman.settings.interval")
                }
                .onePlusRowHover()
            }
            if shows("Ports & processes", "Protected apps", "Extra protected process names") {
                OnePlusSettingRow(
                    "Protected apps",
                    help: "Extra protected process names, comma-separated. Databases, Docker, and SSH stay protected.",
                    controlWidth: portControlWidth,
                    separator: false
                ) {
                    OnePlusTextField("Process names", text: $protectedCommands)
                        .frame(width: portControlWidth)
                }
                .onePlusRowHover()
            }
        }
    }

    private var cleanupSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnePlusSectionTitle("Clean up")
            if shows("Clean up", "Cleanup mode") {
                OnePlusSettingRow("Mode", help: cleanupHelp) {
                    OnePlusSegmented(choices: [("off", "Off"), ("ask", "Ask"), ("automatic", "Auto")],
                                     selection: Binding(get: { cleanupMode }, set: { value in
                        if value == PortmanCleanupMode.automatic.rawValue && cleanupMode != value {
                            state.pendingAutomaticCleanup = true
                        } else { cleanupMode = value }
                    }), accessibilityLabel: "Cleanup mode", width: OnePlusMetrics.controlColumn)
                    .accessibilityIdentifier("portman.settings.cleanupMode")
                }
                .onePlusRowHover()
            }
            if shows("Clean up", "Include deleted folders") {
                OnePlusSettingRow("Deleted folders", controlWidth: 29) {
                    Toggle("Include deleted folders", isOn: $includeDeletedFolders)
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                .onePlusRowHover()
            }
            if shows("Clean up", "Idle for", "Suggest after idle hours") {
                OnePlusSettingRow("Idle for") {
                    OnePlusStepperField("Idle hours", value: integer($idleHours), in: 1...72, unit: "hours")
                }
                .onePlusRowHover()
            }
            if shows("Clean up", "Running for", "Suggest after running days") {
                OnePlusSettingRow("Running for") {
                    OnePlusStepperField("Running days", value: integer($runningDays), in: 1...30, unit: "days")
                }
                .onePlusRowHover()
            }
            if shows("Clean up", "Force quit after seconds") {
                OnePlusSettingRow("Force quit after", separator: false) {
                    OnePlusStepperField("Force quit seconds", value: integer($forceQuitSeconds), in: 1...30, unit: "sec")
                }
                .onePlusRowHover()
            }
        }
    }

    private var integrationSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnePlusSectionTitle("Integrations")
            if shows("Integrations", "Link coding sessions") {
                OnePlusSettingRow(
                    "Coding sessions",
                    help: "Copy a resume command for a matching Claude Code or Codex session.",
                    controlWidth: 29
                ) {
                    Toggle("Link coding sessions", isOn: $sessionLinksEnabled)
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                .onePlusRowHover()
            }
            if shows("Integrations", "Find public GitHub links") {
                OnePlusSettingRow(
                    "GitHub links",
                    help: "Find public pull requests and previews. Private repositories are excluded.",
                    controlWidth: 29,
                    separator: false
                ) {
                    Toggle("Find public GitHub links", isOn: $publicGitHubLinksEnabled)
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                .onePlusRowHover()
            }
        }
    }

    private func integer(_ value: Binding<Double>) -> Binding<Int> {
        Binding(get: { Int(value.wrappedValue) }, set: { value.wrappedValue = Double($0) })
    }
}

nonisolated enum PortmanEditor {
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
final class PortmanMenuController: NSObject, NSPopoverDelegate {
    static let shared = PortmanMenuController()

    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var observers: [NSObjectProtocol] = []
    private var showTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    var isShown: Bool { popover.isShown }

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
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
        showTask?.cancel()
        refreshTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        popover.close()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        PortmanService.shared.endMonitoring()
    }

    func show(initialPage: PortmanPanelView.Page? = nil, activateApp: Bool = true) {
        start()
        showTask?.cancel()
        if popover.isShown {
            if let initialPage {
                ToolPageRouter.shared.post(tool: "portman", page: initialPage.panelID)
            }
            return
        }
        OnePlusPanelTimings.shared.beginOpenIfNeeded(panel: "portman")
        let request = ToolPageRouter.shared.take(tool: "portman")
        let destination = initialPage ?? request.flatMap { PortmanPanelView.Page(panelID: $0.page) }
        if present(initialPage: destination, activateApp: activateApp) { return }
        showTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<200 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, self.item != nil, !self.popover.isShown else { return }
                if self.present(initialPage: destination, activateApp: activateApp) { return }
            }
            OnePlusPanelTimings.shared.cancel(panel: "portman")
            if AppRuntime.isUITesting { NSLog("Portman status item has no visible anchor") }
        }
    }

    private func present(initialPage: PortmanPanelView.Page?, activateApp: Bool) -> Bool {
        guard let button = item?.button, button.window?.isVisible == true,
              !button.visibleRect.isEmpty, button.bounds.width > 0 else { return false }
        if activateApp { NSApp.activate(ignoringOtherApps: true) }
        popover.appearance = NSApp.appearance
        let hosting = NSHostingController(rootView: PortmanPanelView(initialPage: initialPage).utilityMotionPolicy())
        hosting.view.appearance = NSApp.appearance
        let ceiling = (button.window?.screen?.visibleFrame.height ?? 800) * OnePlusMenuMetrics.heightFraction
        let size = hosting.sizeThatFits(in: NSSize(width: OnePlusMenuMetrics.width, height: ceiling))
        hosting.view.setFrameSize(size)
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hosting
        popover.contentSize = size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.appearance = NSApp.appearance
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
        if AppRuntime.isUITesting { NSLog("Portman popover shown: \(popover.isShown)") }
        return popover.isShown
    }

    func popoverDidClose(_ notification: Notification) {
        OnePlusPanelTimings.shared.cancel(panel: "portman")
        popover.contentViewController = nil
    }

    func setHeight(_ height: CGFloat) {
        let size = NSSize(width: OnePlusMenuMetrics.width, height: height)
        if popover.contentSize != size { popover.contentSize = size }
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
        refreshTask?.cancel()
        refreshTask = Task { await PortmanService.shared.refreshLocal() }
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
            newItem.button?.setAccessibilityIdentifier("portman.statusItem")
            newItem.button?.sendAction(on: [.leftMouseDown])
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
        let image = StatusItemIcon.symbol(ToolGlyph.portman.symbol)
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
