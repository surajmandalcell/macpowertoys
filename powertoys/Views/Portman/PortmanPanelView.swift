import AppKit
import Observation
import SwiftUI
import OnePlusUI

nonisolated struct PortmanOverviewRow: Identifiable, Sendable {
    let port: PortmanLocalPort
    let canStop: Bool
    let title: String
    let subtitle: String
    let appBundlePath: String?
    let processSymbol: String
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
        let appBundlePath = SystemMonitorProcessHierarchy.appBundlePath(for: port.executablePath)
        return PortmanOverviewRow(
            port: port,
            canStop: port.canStop,
            title: title,
            subtitle: branch ?? "",
            appBundlePath: appBundlePath,
            processSymbol: appBundlePath == nil && port.executablePath.hasPrefix("/") ? "terminal" : "",
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
        case local = "Servers", forward = "Forward"

        init?(panelID: String) {
            switch panelID {
            case "home", "servers": self = .local
            case "forward": self = .forward
            default: return nil
            }
        }

        var panelID: String {
            switch self {
            case .local: "servers"
            case .forward: "forward"
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
    @State private var reveal: Double = PortmanEntrance.pending && !OnePlusMotion.reducesMotion ? 0 : 1
    @Environment(\.onePlusMenuMaximumHeight) private var suppliedCeiling
    @State private var showingMore = false
    @State private var showingProcesses = false
    @State private var overviewGeneration = 0
    @State private var overviewPresentation = PortmanOverviewPresentation.empty
    @State private var processIcons = SystemMonitorProcessIcons()
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

    var body: some View {
        panelDialogs
            .focusedValue(\.appOpenSettings) { ToolActionRouter.shared.openMainPage(toolID: "portman") }
            .onOpenToolPage("portman") { id in
                if let destination = Page(panelID: id) { navigate(to: destination) }
            }
    }

    /// The v15 Fill steps shell shared with the combined panel: tabs, gear, and the Open key in the top bar.
    private var panel: some View {
        OnePlusLinearPanel(style: TrayPopoverLayout.style) {
            OnePlusLinearPanelFooter(edge: .top) {
                OnePlusLinearIconTabs(tabs: [
                    OnePlusMenuTab(.local, "Servers", systemImage: ToolGlyph.portman.symbol, image: ToolGlyph.portman.assetImage, accessibilityIdentifier: "portman.page.Servers"),
                    OnePlusMenuTab(.forward, "Forward", systemImage: "arrow.left.arrow.right", accessibilityIdentifier: "portman.page.Forward")
                ], selection: Binding(get: { page }, set: navigate))
            } trailing: {
                AttentionBell()
                OnePlusLinearIconButton(systemImage: "gearshape", help: "Portman settings",
                                        busy: service.isLoadingRemote ? "Scanning" : nil) {
                    ToolActionRouter.shared.openMainPage(toolID: "portman")
                }
                .accessibilityIdentifier("portman.settings")
                Button("Open MacPowerToys") { ToolActionRouter.shared.open(toolID: "main", page: "tool/portman") }
                    .buttonStyle(OnePlusLinearButtonStyle(.filled))
                    .accessibilityIdentifier("portman.open-app")
            }
        } content: {
            MainPanelBodyLayout(maximumHeight: TrayPopoverLayout.maximumBodyHeight(panelCeiling: panelCeiling)) {
                fixedRegion
                MainPanelScrollBody {
                    Group {
                        switch page {
                        case .local:
                            if let selectedPort { localDetail(selectedPort) }
                            else { localOverview }
                        case .forward: forwardResults.portmanForwardLook()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onePlusDensity(.compact)
        .onePlusNeutralControls()
        .onePlusFocusPolicy()
        .onePlusAppAppearance()
        .onePlusLiveUpdates()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            if height > 0 { PortmanMenuController.shared.setHeight(height) }
        }
        .onePlusPanelTimings(panel: "portman", tab: page.panelID)
    }

    private var panelCeiling: CGFloat {
        suppliedCeiling ?? (NSScreen.main?.visibleFrame.height ?? 800) * OnePlusMenuMetrics.heightFraction
    }

    /// The detail header and the Forward toolbar stay put while the body below them scrolls.
    @ViewBuilder private var fixedRegion: some View {
        if page == .local, let selectedPort {
            localDetailHeader(selectedPort)
        } else if page == .forward {
            PortmanForwardInputs(host: $host, manualPort: $manualPort, aliases: aliases,
                                 scanning: service.isLoadingRemote, scan: scanRemote,
                                 cancel: clearRemoteScan, addPort: addManualPort)
                .portmanForwardLook()
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
                    .filter(PortmanSSHHost.isValid)
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
        if destination != page, !OnePlusPanelTimings.shared.hasPending("portman", tab: destination.panelID) {
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
        await processIcons.load(bundlePaths: Set(presentation.rows.compactMap(\.appBundlePath)))
    }

    /// Servers page (owner picks 2026-11-19): the hero ring, then the two-line rows. Sort, Refresh, and Clean up live
    /// in the right-click menu of the body and the rows until the owner picks their placement.
    private var localOverview: some View {
        VStack(alignment: .leading, spacing: TrayPopoverLayout.style.blockGap) {
            if !overviewPresentation.rows.isEmpty {
                PortmanHeroRing(presentation: overviewPresentation, caption: ringCaption)
                    .animation(.easeOut(duration: OnePlusMotion.chartScale), value: overviewPresentation.segments.map(\.memoryBytes))
                OnePlusLinearList(style: .panel) {
                    VStack(spacing: 0) {
                        ForEach(overviewPresentation.rows) { row in
                            serverRow(row).transition(PortmanRowPresence.transition)
                        }
                    }
                    .onePlusSteadyRows(count: overviewPresentation.rows.count, rowHeight: PortmanOverviewMetrics.rowHeight)
                    .animation(PortmanRowPresence.animation, value: overviewPresentation.rows.map(\.id))
                }
                if cleanupMode { cleanupActions }
            } else {
                OnePlusLinearList(style: .panel) {
                    OnePlusLinearControlRow("No servers listening", systemImage: "network", titleWidth: nil) { EmptyView() }
                }
                .help("Local development ports \(overviewPresentation.scanRangeText) will appear here.")
            }
            if let error = service.localError { errorText(error) }
            if let error = service.controlError { errorText(error) }
        }
        .environment(\.onePlusLinearReveal, reveal)
        .contentShape(Rectangle())
        .contextMenu { overviewMenu }
        .onChange(of: overviewPresentation.rows.isEmpty, initial: true) {
            guard !overviewPresentation.rows.isEmpty, reveal < 1 else { return }
            PortmanEntrance.pending = false
            withAnimation(OnePlusMotion.animation(OnePlusMotion.panelReveal)) { reveal = 1 }
        }
    }

    private var ringCaption: String {
        if cleanupMode { return "\(selectedCleanupProcesses.count) selected" }
        let physical = max(1, Double(ProcessInfo.processInfo.physicalMemory))
        return "\(String(format: "%.1f", Double(overviewPresentation.memoryBytes) / physical * 100))% of RAM"
    }

    /// Only while Clean up is on: Cancel and the confirmed stop of the selected processes.
    private var cleanupActions: some View {
        OnePlusLinearList(style: .panel) {
            OnePlusLinearControlRow("\(selectedCleanupProcesses.count) selected", systemImage: "sparkles",
                                    status: "frees \(portmanMemoryString(overviewPresentation.memoryBytes))", titleWidth: nil) {
                HStack(spacing: OnePlusLinearMetrics.rowGap / 2) {
                    Button("Cancel") { cleanupMode = false; selectedCleanupProcesses = [] }
                        .buttonStyle(OnePlusLinearKeyButtonStyle.compact)
                    Button("Stop", role: .destructive) {
                        pendingCleanupPorts = service.localPorts.filter { selectedCleanupProcesses.contains($0.processID) }
                    }
                    .buttonStyle(OnePlusLinearKeyButtonStyle.compact)
                    .disabled(selectedCleanupProcesses.isEmpty)
                    .accessibilityIdentifier("portman.cleanup.stop")
                }
            }
        }
    }

    @ViewBuilder private var overviewMenu: some View {
        Picker("Sort by", selection: $serverSort) {
            ForEach(PortmanServerSort.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
        }
        Button("Refresh Servers") {
            refreshTask?.cancel()
            refreshTask = Task { await service.refreshLocal() }
        }
        Button(overviewPresentation.suggestedCleanupIDs.isEmpty
               ? "Clean Up…" : "Clean Up \(overviewPresentation.suggestedCleanupIDs.count) Suggested…") {
            selectedCleanupProcesses = overviewPresentation.suggestedCleanupIDs
            cleanupMode = true
        }
        .disabled(cleanupMode || !overviewPresentation.rows.contains(where: \.canStop))
    }

    private func serverRow(_ row: PortmanOverviewRow) -> some View {
        let port = row.port
        return PortmanServerRow(
            row: row, icon: row.appBundlePath.flatMap { processIcons.images[$0] }, cleanupMode: cleanupMode,
            selected: Binding(get: { selectedCleanupProcesses.contains(port.processID) },
                              set: { if $0 { selectedCleanupProcesses.insert(port.processID) } else { selectedCleanupProcesses.remove(port.processID) } }),
            open: { selectedPortID = port.id }, openLocal: { openLocal(port.port) }, stop: { pendingStop = port })
        .accessibilityAction(named: "Open localhost:\(String(port.port))") { openLocal(port.port) }
        .task(id: port.id) { await service.loadMetadata(for: port) }
        .contextMenu {
            Button("Open localhost:\(String(port.port))") { openLocal(port.port) }
            Button("Show Details") { selectedPortID = port.id }
            if row.canStop {
                Button("Stop Process Tree…", role: .destructive) { pendingStop = port }
            }
            Divider()
            overviewMenu
        }
    }

    private func memoryString(_ bytes: Int64) -> String {
        portmanMemoryString(bytes)
    }

    private func portColor(_ port: PortmanLocalPort) -> Color {
        portColors[(Int(port.port) * 7 / 11) % portColors.count]
    }

    /// The detail header row: back, server name and port, and the open-in-browser key.
    private func localDetailHeader(_ port: PortmanLocalPort) -> some View {
        HStack(spacing: OnePlusLinearMetrics.rowGap) {
            OnePlusLinearIconButton(systemImage: "chevron.left", help: "Back to Servers") { selectedPortID = nil }
                .accessibilityIdentifier("portman.detail.back")
            Text(portmanServerName(project: service.metadata[port.id]?.project, processName: port.command))
                .linearText(weight: .semibold).lineLimit(1).truncationMode(.middle)
            Text(":\(String(port.port))").linearText(weight: .semibold, color: portColor(port)).fixedSize()
            Spacer(minLength: 0)
            OnePlusLinearIconButton(systemImage: "link", help: "Open localhost:\(String(port.port))") { openLocal(port.port) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Server details in Home's parts: the Memory and CPU tiles, the server group, the processes group, the action bar.
    private func localDetail(_ port: PortmanLocalPort) -> some View {
        VStack(alignment: .leading, spacing: TrayPopoverLayout.style.blockGap) {
            detailBento(port)
            serverGroup(port)
            processGroup(port)
            OnePlusLinearActionBar(detailActions(port))
            if let error = service.controlError { errorText(error) }
        }
        .environment(\.onePlusLinearReveal, reveal)
    }

    private func detailBento(_ port: PortmanLocalPort) -> some View {
        let samples = service.history[port.id] ?? []
        let color = portColor(port)
        let memory = samples.map { Double($0.memoryBytes) }
        let cpu = samples.map(\.cpuPercent)
        let (memoryValue, memoryUnit) = Self.valueAndUnit(memoryString(port.memoryBytes))
        return OnePlusLinearBento(style: .instrument) {
            OnePlusLinearTile(chart: OnePlusLinearChart([OnePlusLinearSeries(memory, color: color)],
                                                        range: 0...max(1, (memory.max() ?? 1) * 1.2)), tint: color) {
                OnePlusLinearTileLabel("Memory", systemImage: "memorychip", color: color, meta: "10 min")
                OnePlusLinearTileValue(memoryValue, unit: memoryUnit, color: color, pace: .memory)
            }
        } trailing: {
            OnePlusLinearTile(chart: OnePlusLinearChart([OnePlusLinearSeries(cpu, color: color)],
                                                        range: 0...max(100, ceil((cpu.max() ?? 0) / 50) * 50), order: 1), tint: color) {
                OnePlusLinearTileLabel("CPU", systemImage: "cpu", color: color, meta: "up \(port.uptime)")
                OnePlusLinearTileValue(String(format: "%.1f", port.cpuPercent), unit: "%", color: color, pace: .cpu)
            }
        }
        .accessibilityLabel("Memory and CPU history for port \(String(port.port))")
    }

    /// "312.4 MB" -> ("312.4", "MB").
    private static func valueAndUnit(_ text: String) -> (String, String) {
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }

    private func serverGroup(_ port: PortmanLocalPort) -> some View {
        let canStop = overviewPresentation.rows.first { $0.id == port.id }?.canStop ?? false
        let metadata = service.metadata[port.id]
        let session = service.sessions[port.id]
        return OnePlusLinearList(style: .panel) {
            OnePlusLinearControlRow("Server", systemImage: "server.rack", status: "up \(port.uptime)", titleWidth: nil) {
                if canStop {
                    HStack(spacing: OnePlusLinearMetrics.rowGap / 2) {
                        Button("Restart") { pendingRestart = port }
                            .buttonStyle(OnePlusLinearKeyButtonStyle.compact)
                            .disabled(!service.restartableIDs.contains(port.id) || service.restartingIDs.contains(port.id))
                            .help(service.restartableIDs.contains(port.id)
                                  ? "Restart with the original command and environment"
                                  : "Restart requires the original command, environment, and folder")
                        Button("Stop") { pendingStop = port }
                            .buttonStyle(OnePlusLinearKeyButtonStyle.compact)
                            .help("Stop port \(String(port.port)) process tree")
                    }
                }
            }
            if let branch = metadata?.branch { PortmanDetailRow("Branch", branch) }
            if let session {
                PortmanDetailRow("Session", session.label) {
                    OnePlusLinearIconButton(systemImage: "doc.on.doc", help: "Copy \(session.label) resume command",
                                            size: OnePlusLinearMetrics.panelAccessory) { copy(session.resumeCommand) }
                }
            }
            if let links = service.githubLinks[port.id], let url = links.pullRequestURL, let number = links.pullRequestNumber {
                PortmanDetailRow("Pull request", "#\(String(number))") {
                    OnePlusLinearIconButton(systemImage: "arrow.up.right", help: url.absoluteString,
                                            size: OnePlusLinearMetrics.panelAccessory) { NSWorkspace.shared.open(url) }
                }
            }
            OnePlusLinearDisclosureRow("Details", systemImage: "info.circle", isExpanded: $showingMore)
            if showingMore {
                PortmanDetailRow("Process", "\(port.pid)")
                PortmanDetailRow("Address", port.address)
                if let metadata {
                    PortmanDetailRow("Project", metadata.project)
                    PortmanDetailRow("Folder", metadata.folder)
                }
                PortmanDetailRow("Command", port.launchCommand) {
                    OnePlusLinearIconButton(systemImage: "doc.on.doc", help: "Copy command",
                                            size: OnePlusLinearMetrics.panelAccessory) { copy(port.launchCommand) }
                }
                if let session { PortmanDetailRow("Session ID", session.id.uuidString.lowercased()) }
                if let note = service.githubLinks[port.id]?.note { PortmanDetailRow("GitHub", note) }
            }
        }
    }

    private func processGroup(_ port: PortmanLocalPort) -> some View {
        let color = portColor(port)
        let rootBytes = max(0, port.memoryBytes - port.processes.reduce(0) { $0 + $1.memoryBytes })
        let total = Double(max(1, port.memoryBytes))
        return OnePlusLinearList(style: .panel) {
            OnePlusLinearDisclosureRow("Processes", systemImage: "square.stack.3d.up",
                                       detail: "\(port.processes.count + 1) · \(memoryString(port.memoryBytes))",
                                       isExpanded: $showingProcesses)
            if showingProcesses {
                PortmanProcessRow(command: port.command, pid: port.pid, memory: memoryString(rootBytes),
                                  fraction: Double(rootBytes) / total, color: color)
                ForEach(port.processes) { process in
                    PortmanProcessRow(command: process.command, pid: process.pid, memory: memoryString(process.memoryBytes),
                                      fraction: Double(process.memoryBytes) / total, color: color)
                }
            }
        }
    }

    private func detailActions(_ port: PortmanLocalPort) -> [OnePlusLinearAction] {
        var actions: [OnePlusLinearAction] = []
        if let details = service.metadata[port.id] {
            let folder = details.root ?? details.folder
            actions.append(OnePlusLinearAction("Editor", systemImage: "chevron.left.forwardslash.chevron.right") {
                PortmanEditor.open(folder, preferred: editor)
            })
            actions.append(OnePlusLinearAction("Finder", systemImage: "folder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
            })
        }
        actions.append(OnePlusLinearAction("Copy URL", systemImage: "link") { copy("http://127.0.0.1:\(port.port)/") })
        if let preview = service.githubLinks[port.id]?.previewURL {
            actions.append(OnePlusLinearAction("Preview", systemImage: "safari") { NSWorkspace.shared.open(preview) })
        }
        return actions
    }

    /// Scan results and added ports in one group (status, rows, Forward), then the forwarded ports in another.
    private var forwardResults: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearPanelStyle.fillSteps.blockGap) {
            let scanned = !host.isEmpty && discoveredHost == host
            if scanned || !manualRemotePorts.isEmpty {
                OnePlusLinearList(style: .panel) {
                    PortmanForwardRow {
                        let ports = (scanned ? service.remotePorts : []) + manualRemotePorts
                        Toggle(isOn: Binding(
                            get: { !ports.isEmpty && ports.allSatisfy(selectedRemotePorts.contains) },
                            set: { all in
                                if all { selectedRemotePorts.formUnion(ports) } else { selectedRemotePorts = [] }
                                lastSelectedRemotePort = nil
                            }
                        )) { EmptyView() }
                        .labelsHidden().toggleStyle(OnePlusCheckboxStyle()).disabled(ports.isEmpty)
                        .accessibilityLabel("Select all ports")
                        PortmanForwardStatus(scanned ? "\(host) · \(service.remotePorts.count) ports" : "\(host) · added ports")
                        if scanned { PortmanForwardKey("Clear", action: clearRemoteScan).help("Clear scan results") }
                    }
                    if scanned {
                        if service.remotePorts.isEmpty {
                            PortmanForwardRow {
                                Text("No listening ports found").linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .help("You can add a remote port manually.")
                        }
                        ForEach(service.remotePorts, id: \.self) { remoteRow($0) }
                    }
                    ForEach(manualRemotePorts, id: \.self) { remoteRow($0) }
                    PortmanForwardRow {
                        Text(selectedRemotePorts.isEmpty ? "No ports selected" : "\(selectedRemotePorts.count) selected")
                            .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PortmanForwardKey("Forward", action: forwardSelected)
                            .disabled(host.isEmpty || selectedRemotePorts.isEmpty)
                    }
                }
            }
            if !service.tunnels.isEmpty {
                OnePlusLinearList(style: .panel) {
                    PortmanForwardRow { PortmanForwardStatus("Forwarded ports · \(activeTunnelCount) active") }
                    ForEach(service.tunnels) { tunnelRow($0) }
                }
            }
            if passwordPromptHost == nil, let error = service.forwardingError { errorText(error) }
        }
    }

    private var manualRemotePorts: [UInt16] {
        selectedRemotePorts.sorted().filter { !service.remotePorts.contains($0) || discoveredHost != host }
    }

    private func remoteRow(_ port: UInt16) -> some View {
        let detail = service.remoteDetails[port]
        return VStack(alignment: .leading, spacing: 0) {
            PortmanForwardRow {
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
                    HStack(spacing: OnePlusLinearMetrics.rowGap) {
                        PortmanPortChip(port: port)
                        Text(detail?.displayName ?? "Unknown service")
                            .linearText(OnePlusLinearMetrics.control)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expandedRemotePort == port ? 90 : 0))
                            .foregroundStyle(OnePlusLinearColor.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: PortmanForwardMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Details for remote port \(String(port))")
                OnePlusLinearTextField(String(port), text: Binding(
                    get: { localPortInputs[port] ?? String(port) },
                    set: { localPortInputs[port] = $0; selectedRemotePorts.insert(port) }
                ), onSubmit: forwardSelected)
                .frame(width: PortmanForwardMetrics.column)
                .accessibilityLabel("Local port for remote port \(String(port))")
                .help("Local port")
            }
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
                .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
                .padding(.bottom, OnePlusMetrics.actionSpacing)
                if let container = detail?.container { 
                    OnePlusLinearAppletRow("Container") {
                        Text(container).textSelection(.enabled).lineLimit(1).help(container)
                    }
                }
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
        var actions: [OnePlusLinearAction] = []
        if case .running = tunnel.state {
            actions.append(OnePlusLinearAction("Open tunnel on port \(String(tunnel.localPort))", systemImage: "link") {
                openLocal(tunnel.localPort)
            })
        }
        if case .failed = tunnel.state {
            actions.append(OnePlusLinearAction("Retry forwarding", systemImage: "arrow.clockwise") {
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
            })
        }
        actions.append(OnePlusLinearAction("Stop forwarding", systemImage: "stop.fill") { service.stopTunnel(tunnel.id) })
        return PortmanForwardRow {
            Image(systemName: tunnelSymbol(tunnel.state))
                .font(.system(size: 11))
                .foregroundStyle(tunnelColor(tunnel.state))
                .accessibilityHidden(true)
            Text(":\(String(tunnel.localPort)) → \(tunnel.host):\(String(tunnel.remotePort))")
                .font(.system(size: OnePlusLinearMetrics.control, design: .monospaced)).foregroundStyle(OnePlusLinearColor.ink)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(tunnelStateLabel(tunnel.state)).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                .lineLimit(1).fixedSize()
            ForEach(actions) { action in
                OnePlusLinearIconButton(systemImage: action.systemImage, help: action.title, size: 22, action: action.action)
            }
        }
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
        OnePlusLinearBanner(.warning, title: message).textSelection(.enabled)
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
        // One column of groups, like the Ruler page (DESIGN.md "Tool page").
        VStack(alignment: .leading, spacing: OnePlusLinearEditorialMetrics.blockGap) {
            if !generalVisible && !portsVisible && !cleanupVisible && !integrationsVisible {
                OnePlusEmptyState("No matching settings", systemImage: "magnifyingglass")
            } else {
                if generalVisible { generalSettings }
                if portsVisible { portSettings }
                if cleanupVisible { cleanupSettings }
                if integrationsVisible { integrationSettings }
            }
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

    private var generalSettings: some View {
        OnePlusLinearAppletSection("General") {
            if shows("Keyboard shortcut") {
                OnePlusLinearAppletRow("Shortcut", systemImage: "keyboard") { ShortcutRecorderField(action: .portman) }
            }
            if shows("Open folders in", "editor") {
                OnePlusLinearAppletRow("Open folders in", systemImage: "folder") {
                    OnePlusLinearSelect(choices: [("auto", "Automatic")] + (state.installedEditors ?? []).map { ($0.id, $0.name) } + [("finder", "Finder")],
                                        selection: $editor, accessibilityLabel: "Open folders in", width: portControlWidth)
                        .accessibilityIdentifier("portman.settings.editor")
                }
            }
        }
    }

    private var portSettings: some View {
        OnePlusLinearAppletSection("Ports & processes") {
            if shows("Ports & processes", "All listeners", "Include other listening processes") {
                OnePlusLinearAppletRow("All listeners", detail: "Include other listening processes",
                                       systemImage: "antenna.radiowaves.left.and.right") {
                    Toggle("Include other listening processes", isOn: $showAllListeners)
                        .labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
                }
            }
            if shows("Ports & processes", "First port", "Scan ports") {
                OnePlusLinearAppletRow("First port", systemImage: "arrow.down.to.line") {
                    OnePlusStepperField("First scan port", value: $lowerPort, in: 1...max(1, min(upperPort, 65535)))
                }
            }
            if shows("Ports & processes", "Last port", "Scan ports") {
                OnePlusLinearAppletRow("Last port", systemImage: "arrow.up.to.line") {
                    OnePlusStepperField("Last scan port", value: $upperPort, in: max(1, min(lowerPort, 65535))...65535)
                }
            }
            if shows("Ports & processes", "Scan every") {
                OnePlusLinearAppletRow("Scan every", systemImage: "arrow.clockwise") {
                    OnePlusLinearSelect(choices: [2.0, 5.0, 10.0, 30.0].map { ($0, "\(Int($0)) seconds") },
                                        selection: $scanInterval, accessibilityLabel: "Scan every", width: portControlWidth)
                        .accessibilityIdentifier("portman.settings.interval")
                }
            }
            if shows("Ports & processes", "Protected apps", "Extra protected process names") {
                OnePlusLinearAppletRow("Protected apps", systemImage: "lock.shield") {
                    OnePlusLinearTextField("Process names", text: $protectedCommands)
                        .frame(width: portControlWidth)
                }
                .help("Extra protected process names, comma-separated. Databases, Docker, and SSH stay protected.")
            }
        }
    }

    private var cleanupSettings: some View {
        OnePlusLinearAppletSection("Clean up") {
            if shows("Clean up", "Cleanup mode") {
                OnePlusLinearAppletRow("Mode", detail: cleanupHelp, systemImage: "sparkles") {
                    OnePlusLinearSegmented(choices: [("off", "Off"), ("ask", "Ask"), ("automatic", "Auto")],
                                           selection: Binding(get: { cleanupMode }, set: { value in
                        if value == PortmanCleanupMode.automatic.rawValue && cleanupMode != value {
                            state.pendingAutomaticCleanup = true
                        } else { cleanupMode = value }
                    }), accessibilityLabel: "Cleanup mode")
                    .accessibilityIdentifier("portman.settings.cleanupMode")
                }
            }
            if shows("Clean up", "Include deleted folders") {
                OnePlusLinearAppletRow("Deleted folders", systemImage: "folder.badge.minus") {
                    Toggle("Include deleted folders", isOn: $includeDeletedFolders)
                        .labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
                }
            }
            if shows("Clean up", "Idle for", "Suggest after idle hours") {
                OnePlusLinearAppletRow("Idle for", systemImage: "zzz") {
                    OnePlusStepperField("Idle hours", value: integer($idleHours), in: 1...72, unit: "hours")
                }
            }
            if shows("Clean up", "Running for", "Suggest after running days") {
                OnePlusLinearAppletRow("Running for", systemImage: "clock") {
                    OnePlusStepperField("Running days", value: integer($runningDays), in: 1...30, unit: "days")
                }
            }
            if shows("Clean up", "Force quit after seconds") {
                OnePlusLinearAppletRow("Force quit after", systemImage: "xmark.octagon") {
                    OnePlusStepperField("Force quit seconds", value: integer($forceQuitSeconds), in: 1...30, unit: "sec")
                }
            }
        }
    }

    private var integrationSettings: some View {
        OnePlusLinearAppletSection("Integrations") {
            if shows("Integrations", "Link coding sessions") {
                OnePlusLinearAppletRow("Coding sessions",
                                       detail: "Copy a resume command for a matching Claude Code or Codex session.",
                                       systemImage: "terminal") {
                    Toggle("Link coding sessions", isOn: $sessionLinksEnabled)
                        .labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
                }
            }
            if shows("Integrations", "Find public GitHub links") {
                OnePlusLinearAppletRow("GitHub links",
                                       detail: "Find public pull requests and previews. Private repositories are excluded.",
                                       systemImage: "link") {
                    Toggle("Find public GitHub links", isOn: $publicGitHubLinksEnabled)
                        .labelsHidden().toggleStyle(OnePlusLinearSwitchStyle())
                }
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
final class PortmanMenuController: NSObject {
    static let shared = PortmanMenuController()
    private static let titleBaselineOffset: CGFloat = -1

    private var item: NSStatusItem?
    private let popover = OnePlusMenuPresenter()
    private var cachedHosting: NSHostingController<AnyView>?
    private var observers: [NSObjectProtocol] = []
    private var showTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    var isShown: Bool { popover.isShown }

    private override init() {
        super.init()
        popover.onClose = { [weak self] in self?.panelDidClose() }
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
        cachedHosting = nil
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
        let ceiling = (button.window?.screen?.visibleFrame.height ?? 800) * OnePlusMenuMetrics.heightFraction
        let content = AnyView(PortmanPanelView(initialPage: initialPage).utilityMotionPolicy()
            .environment(\.onePlusMenuMaximumHeight, ceiling))
        MenuPanelRelease.shared.cancel("portman")
        let hosting: NSHostingController<AnyView>
        if let existing = cachedHosting {
            hosting = existing
            hosting.rootView = content
            if let initialPage {
                ToolPageRouter.shared.post(tool: "portman", page: initialPage.panelID, recordTiming: false)
            }
        } else {
            hosting = NSHostingController(rootView: content)
            cachedHosting = hosting
        }
        hosting.view.appearance = NSApp.appearance
        let size = hosting.sizeThatFits(in: NSSize(width: OnePlusMenuMetrics.width, height: ceiling))
        hosting.view.setFrameSize(size)
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hosting
        popover.contentSize = size
        if activateApp {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            popover.showInBackground(relativeTo: button.bounds, of: button)
        }
        popover.contentViewController?.view.window?.appearance = NSApp.appearance
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
        if AppRuntime.isUITesting { NSLog("Portman popover shown: \(popover.isShown)") }
        return !activateApp || popover.isShown
    }

    private func panelDidClose() {
        OnePlusPanelTimings.shared.cancel(panel: "portman")
        popover.contentViewController = nil
        MenuPanelRelease.shared.schedule("portman") { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.cachedHosting = nil
        }
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
        // The digits' ink sat 0.75 pt above the glyph's ink center in a live capture; drop them to match.
        button.attributedTitle = NSAttributedString(string: " \(ports.count)", attributes: [
            .font: NSFont.menuBarFont(ofSize: 0), .baselineOffset: Self.titleBaselineOffset,
        ])
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
