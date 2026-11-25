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
        let appBundlePath = port.appBundlePath
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

    static let lastClosedKey = "portman.lastClosedAt"
    /// A panel closed longer ago than this opens on Servers, not on the page it was left on.
    static let homeAfterClosed: TimeInterval = 5 * 60
    /// The Forward placeholder waits at most this long for hosts with no recent answer.
    static let forwardPlaceholderLimit: Duration = .seconds(3)

    static func startPage(saved: Page?, lastClosed: Date?, now: Date) -> Page {
        guard let saved, let lastClosed, now.timeIntervalSince(lastClosed) <= homeAfterClosed else { return .local }
        return saved
    }

    init(initialPage: Page? = nil, initialHost: String? = nil, initialPortID: String? = nil,
         initialCleanupProcessID: String? = nil) {
        let defaults = UserDefaults.standard
        let savedPage = Self.startPage(saved: defaults.string(forKey: Self.selectedPageKey).flatMap(Page.init(rawValue:)),
                                       lastClosed: defaults.object(forKey: Self.lastClosedKey) as? Date, now: Date())
        _page = State(initialValue: initialPage
                      ?? (initialPortID != nil || initialCleanupProcessID != nil ? .local : savedPage))
        _selectedPortID = State(initialValue: initialPortID)
        _host = State(initialValue: initialHost ?? "")
        _cleanupMode = State(initialValue: initialCleanupProcessID != nil)
        _selectedCleanupProcesses = State(initialValue: Set(initialCleanupProcessID.map { [$0] } ?? []))
    }

    @State private var service = PortmanService.shared
    @State private var hostList = PortmanHostList.shared
    @State private var serverMonitor = PortmanServerMonitor.shared
    @State private var newHostMode = PortmanHostMode.forward
    /// The open Add a server step, nil when the dialog is closed.
    @State private var addStep: PortmanAddServerStep?
    @State private var sshHostNames: [String: String] = [:]
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
    /// The host whose "Scan ports" sheet is open, and a scan that waits for `host` to settle on it.
    @State private var scanSheetHost: String?
    @State private var pendingScanHost: String?
    @State private var panelHeight: CGFloat = 0
    @State private var panelOwnsMonitoring = false
    @State private var cleanupMode = false
    @State private var selectedCleanupProcesses = Set<String>()
    @State private var pendingCleanupPorts: [PortmanLocalPort] = []
    @State private var pendingKill: KillRequest?
    @State private var pendingRestart: PortmanLocalPort?
    @State private var reveal: Double = PortmanEntrance.pending && !OnePlusMotion.reducesMotion ? 0 : 1
    @Environment(\.onePlusMenuMaximumHeight) private var suppliedCeiling
    @AppStorage("portman.detail.showDetails") private var showingMore = false
    @AppStorage("portman.detail.showProcesses") private var showingProcesses = false
    /// Bumped by every list to detail move; drives the push. Tab switches and vanished servers do not push.
    @State private var pushCount = 0
    @State private var pushEdge = OnePlusPushEdge.trailing
    /// Set once Forward has waited `forwardPlaceholderLimit` for its hosts to answer.
    @State private var forwardWaitOver = false
    @State private var overviewGeneration = 0
    @State private var overviewPresentation = PortmanOverviewPresentation.empty
    @State private var processIcons = SystemMonitorProcessIcons()
    /// Hosts whose chart tiles are open, one per line. The first-run value opens the first host.
    @AppStorage("portman.forward.openHosts") private var openHosts = PortmanPanelView.firstHostOpen
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

    private struct KillRequest {
        let action: PortmanKill.Action
        let port: PortmanLocalPort
        let parent: PortmanKill.Target?
        let blocked: String?
    }

    private var showingKillConfirmation: Binding<Bool> {
        Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })
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
            #if MPT_DEMO
            .onReceive(NotificationCenter.default.publisher(for: DemoPortman.scanPortsNotification)) {
                if let destination = $0.object as? String { scanPorts(on: destination) }
            }
            #endif
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
                OnePlusLinearIconTrack {
                    OnePlusLinearIconButton(systemImage: "gearshape", help: "Portman settings", size: OnePlusLinearMetrics.iconTab,
                                            busy: service.isLoadingRemote ? "Scanning" : nil) {
                        ToolActionRouter.shared.openFromPanel(toolID: "main", page: "tool/portman")
                    }
                    .accessibilityIdentifier("portman.settings")
                    OnePlusLinearIconButton(systemImage: "arrow.up.right", help: "Open MacPowerToys", size: OnePlusLinearMetrics.iconTab) {
                        ToolActionRouter.shared.openFromPanel(toolID: "portman")
                    }
                    .accessibilityIdentifier("portman.open-app")
                }
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
                        case .forward: forwardBody
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .onePlusPush(trigger: pushCount, from: pushEdge)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onePlusDensity(.compact)
        .onePlusNeutralControls()
        .onePlusFocusPolicy()
        .onePlusAppAppearance()
        .onePlusLiveUpdates()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            if height > 0 { PortmanMenuController.shared.setHeight(height); panelHeight = height }
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
        } else if page == .forward, firstCard == .jobSwitch {
            PortmanJobSwitch(host: $host, port: $manualPort, mode: $newHostMode, aliases: aliases,
                             scanning: service.isLoadingRemote, findPorts: scanRemote,
                             forwardPort: { addManualPort(); forwardAndSave() }, watch: addHost, cancel: clearRemoteScan)
                .portmanForwardLook()
        }
    }

    private var forwardGroups: [PortmanHostGroup] {
        PortmanForwardTree.groups(hosts: hostList.hosts, tunnels: service.tunnels)
    }

    private var firstCard: PortmanForwardFirstCard {
        .resolve(hasServers: !forwardGroups.isEmpty, adding: addStep != nil)
    }

    private var panelWithLifecycle: some View {
        panel
        .onAppear {
            UserDefaults.standard.set(page.rawValue, forKey: Self.selectedPageKey)
            serverMonitor.setPanel(open: true, forwardTab: page == .forward)
            if page == .local {
                service.beginMonitoring()
                panelOwnsMonitoring = true
            }
        }
        .task {
            let load = Task.detached(priority: .utility) {
                let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
                let data = (try? Data(contentsOf: url)) ?? Data()
                var hostNames: [String: String] = [:]
                for entry in SSHConfigEditor.entries(in: data) {
                    for alias in entry.aliases where PortmanSSHHost.isValid(alias) && hostNames[alias] == nil {
                        hostNames[alias] = entry.hostName
                    }
                }
                return hostNames
            }
            #if MPT_DEMO
            let hostNames = DemoPortman.sshHostNames
            #else
            let hostNames = await withTaskCancellationHandler { await load.value } onCancel: { load.cancel() }
            #endif
            if !Task.isCancelled {
                sshHostNames = hostNames
                aliases = hostNames.keys.sorted()
            }
        }
        .task(id: overviewRequest) { await prepareOverview() }
        .onReceive(NotificationCenter.default.publisher(for: .portmanSnapshotChanged)) { _ in
            overviewGeneration &+= 1
        }
        .onChange(of: service.metadata.count) { overviewGeneration &+= 1 }
        .onDisappear {
            serverMonitor.setPanel(open: false, forwardTab: false)
            if panelOwnsMonitoring { service.endMonitoring() }
            panelOwnsMonitoring = false
            refreshTask?.cancel()
            // The scan dies with the panel, so close every view that shows it, or it reopens empty.
            clearRemoteScan()
            scanSheetHost = nil
            pendingScanHost = nil
            if addStep == .setup { addStep = .pick }
            sshPassword = nil
            passwordPromptHost = nil
            retryAfterPassword = nil
        }
        .onChange(of: page) {
            UserDefaults.standard.set(page.rawValue, forKey: Self.selectedPageKey)
            serverMonitor.setPanel(open: true, forwardTab: page == .forward)
            if page == .local && !panelOwnsMonitoring {
                service.beginMonitoring()
                panelOwnsMonitoring = true
            } else if page != .local && panelOwnsMonitoring {
                service.endMonitoring()
                panelOwnsMonitoring = false
            }
            if page != .forward {
                addStep = nil
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
            if pendingScanHost == host {
                pendingScanHost = nil
                scanRemote()
            }
        }
        .onChange(of: passwordPromptHost) {
            // shortcut: a password scan reopens in the inline scan group, not the sheet; keep the sheet if owners ask.
            if passwordPromptHost != nil { scanSheetHost = nil }
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
        .confirmationDialog(pendingKill.map(killTitle) ?? "", isPresented: showingKillConfirmation,
                            titleVisibility: .visible, presenting: pendingKill) { request in
            Button(killButton(request), role: .destructive) {
                PortmanKill.run(request.action, port: request.port, parent: request.parent, service: service)
            }
        } message: { request in
            Text(killMessage(request))
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
        .sheet(isPresented: Binding(get: { scanSheetHost != nil }, set: { if !$0 { closeScanSheet() } })) {
            if let scanSheetHost { scanSheet(scanSheetHost) }
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

    /// Servers page: the hero ring, then the two-line rows. Sort, Refresh, and Clean up live
    /// in the right-click menu of the body and the rows.
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
            open: { showDetail(port.id) }, openLocal: { openLocal(port.port) }, stop: { ask(.stop, port) })
        .accessibilityAction(named: "Open localhost:\(String(port.port))") { openLocal(port.port) }
        .task(id: port.id) { await service.loadMetadata(for: port) }
        .contextMenu {
            Button("Open localhost:\(String(port.port))") { openLocal(port.port) }
            Button("Show Details") { showDetail(port.id) }
            Divider()
            ForEach(killActions, id: \.self) { action in
                let request = killRequest(action, port)
                Button("\(killKeyTitle(action))…", role: action == .forceKill ? .destructive : nil) { pendingKill = request }
                    .disabled(request.blocked != nil)
                    .help(request.blocked ?? killHelp(request))
            }
            Divider()
            overviewMenu
        }
    }

    private var killActions: [PortmanKill.Action] { [.stop, .forceKill, .killParent] }

    private func showDetail(_ id: String?) {
        pushEdge = id == nil ? .leading : .trailing
        pushCount &+= 1
        selectedPortID = id
    }

    private func killRequest(_ action: PortmanKill.Action, _ port: PortmanLocalPort) -> KillRequest {
        guard action == .killParent else {
            return KillRequest(action: action, port: port, parent: nil, blocked: PortmanKill.blockReason(port))
        }
        let parent = PortmanKill.parent(of: port.pid)
        return KillRequest(action: action, port: port, parent: parent,
                           blocked: parent.map(PortmanKill.blockReason) ?? "The parent process is gone")
    }

    private func ask(_ action: PortmanKill.Action, _ port: PortmanLocalPort) {
        let request = killRequest(action, port)
        if request.blocked == nil { pendingKill = request }
    }

    private func killKeyTitle(_ action: PortmanKill.Action) -> String {
        switch action {
        case .stop: "Stop"
        case .forceKill: "Force Kill"
        case .killParent: "Kill Parent"
        }
    }

    private func killHelp(_ request: KillRequest) -> String {
        let name = request.port.command
        switch request.action {
        case .stop: return request.port.canStop ? "Stop port \(String(request.port.port)) process tree" : "Ask \(name) to quit"
        case .forceKill: return "Kill \(name) and its child processes at once"
        case .killParent:
            return request.parent.map { "Ask \($0.command) (PID \(String($0.pid))), which started \(name), to quit" } ?? ""
        }
    }

    private func killTitle(_ request: KillRequest) -> String {
        let name = request.port.command
        switch request.action {
        case .stop: return "Stop \(name)?"
        case .forceKill: return "Force kill \(name)?"
        case .killParent: return "Stop \(request.parent?.command ?? "the parent"), the parent of \(name)?"
        }
    }

    private func killButton(_ request: KillRequest) -> String {
        switch request.action {
        case .stop: "Stop PID \(String(request.port.pid))"
        case .forceKill: "Force Kill PID \(String(request.port.pid))"
        case .killParent: "Stop PID \(String(request.parent?.pid ?? 0))"
        }
    }

    private func killMessage(_ request: KillRequest) -> String {
        let port = request.port, name = port.command
        switch request.action {
        case .stop where port.canStop:
            return "\(name) (PID \(String(port.pid))) on port \(String(port.port)) and eligible children will stop. Any still running after the grace period will be force quit."
        case .stop:
            return "\(name) (PID \(String(port.pid))) gets the normal quit request, like Quit in the Dock. If it keeps running, use Force Kill."
        case .forceKill:
            let children = port.processes.count
            return "\(name) (PID \(String(port.pid))) and its \(children) child \(children == 1 ? "process" : "processes") stop at once. Unsaved work in them is lost."
        case .killParent:
            let parent = request.parent
            return "\(parent?.command ?? "The parent") (PID \(String(parent?.pid ?? 0))) started \(name). It gets the normal quit request, and its other child processes may stop too."
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
            OnePlusLinearIconButton(systemImage: "chevron.left", help: "Back to Servers") { showDetail(nil) }
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
                    Button("Restart") { pendingRestart = port }
                        .buttonStyle(OnePlusLinearKeyButtonStyle.compact)
                        .disabled(!service.restartableIDs.contains(port.id) || service.restartingIDs.contains(port.id))
                        .help(service.restartableIDs.contains(port.id)
                              ? "Restart with the original command and environment"
                              : "Restart requires the original command, environment, and folder")
                }
            }
            OnePlusLinearControlRow("Process", systemImage: "xmark.octagon", titleWidth: nil) {
                HStack(spacing: OnePlusLinearMetrics.rowGap / 2) {
                    ForEach(killActions, id: \.self) { action in
                        let request = killRequest(action, port)
                        Button(killKeyTitle(action)) { pendingKill = request }
                            .buttonStyle(OnePlusLinearKeyButtonStyle.compact)
                            .disabled(request.blocked != nil)
                            .help(request.blocked ?? killHelp(request))
                            .accessibilityIdentifier("portman.detail.\(action)")
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

    /// A monitored host whose card would show "Connecting" or old numbers. It answers within a second or two
    /// once the panel asks every 2 s, so Forward shows placeholders shaped like its cards until then.
    private func awaitsAnswer(_ group: PortmanHostGroup) -> Bool {
        guard group.host.monitors else { return false }
        let health = PortmanHostCardModel(monitors: true, forwards: 0, state: serverMonitor.states[group.host.destination],
                                          now: Date()).health
        return health == .waiting || health == .stale
    }

    private var forwardBody: some View {
        let groups = forwardGroups
        let ready = firstCard != .jobSwitch || forwardWaitOver || !groups.contains(where: awaitsAnswer)
        return ZStack(alignment: .top) {
            if ready {
                forwardResults.transition(.opacity)
            } else {
                VStack(spacing: OnePlusLinearPanelStyle.fillSteps.blockGap) {
                    ForEach(groups) { OnePlusLinearTreeCardPlaceholder(children: $0.children.count) }
                }
                .transition(.opacity)
            }
        }
        .animation(OnePlusMotion.reducesMotion ? nil : OnePlusMotion.animation(OnePlusMotion.placeholderFade), value: ready)
        .portmanForwardLook()
        .task {
            forwardWaitOver = false
            try? await Task.sleep(for: Self.forwardPlaceholderLimit)
            if !Task.isCancelled { forwardWaitOver = true }
        }
    }

    /// Scan results and added ports in one group (status, rows, Forward), then the forwarded ports in another.
    private var forwardResults: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearPanelStyle.fillSteps.blockGap) {
            switch firstCard {
            case .empty: PortmanForwardEmpty(aliases: aliases) { addStep = .pick }
            case .adding: addServerDialog
            case .jobSwitch: forwardWork
            }
        }
    }

    /// The job switch's results: the inline scan group, the host cards, and the last error.
    @ViewBuilder private var forwardWork: some View {
            let scanned = !host.isEmpty && discoveredHost == host
            if scanSheetHost == nil, scanned || !manualRemotePorts.isEmpty {
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
                        PortmanForwardKey("Forward", action: forwardAndSave)
                            .disabled(host.isEmpty || selectedRemotePorts.isEmpty)
                    }
                }
            }
            let groups = forwardGroups
            if !groups.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    PortmanReorderStack(items: groups, movable: groups.filter(\.saved).count,
                                        spacing: OnePlusLinearPanelStyle.fillSteps.blockGap,
                                        name: \.host.destination,
                                        move: { hostList.moveHost($0.host.destination, to: $1) }) { group, index in
                        hostGroup(group, first: index == 0, now: context.date)
                    }
                }
            }
            if passwordPromptHost == nil, let error = service.forwardingError { errorText(error) }
    }

    /// Add a server, two steps in the panel: pick a host, then it connects, finds the ports, and asks for the job.
    @ViewBuilder private var addServerDialog: some View {
        if addStep == .pick {
            PortmanAddServerPick(hosts: aliases.map { ($0, sshHostNames[$0] ?? "") }, pick: { destination in
                service.forwardingError = nil
                addStep = .setup
                rescan(destination)
            }, back: closeAddServer)
        } else {
            let scanning = service.isLoadingRemote || pendingScanHost != nil
            let ready = !scanning && discoveredHost == host
            OnePlusLinearList(style: .panel) {
                PortmanAddServerHeader(title: host, step: .setup, back: backToPick)
                if ready {
                    let count = service.remotePorts.count
                    PortmanAddServerStatus(text: "Connected · \(count) \(count == 1 ? "port" : "ports") open", connected: true)
                    ForEach(service.remotePorts, id: \.self) { remoteRow($0, compact: true) }
                    PortmanJobPicker(mode: $newHostMode)
                    PortmanForwardRow {
                        Button(action: finishAddServer) { Text(addServerTitle).lineLimit(1).frame(maxWidth: .infinity) }
                            .buttonStyle(OnePlusLinearButtonStyle(.filled))
                            .disabled(newHostMode.forwards && selectedRemotePorts.isEmpty)
                    }
                } else if !scanning, let error = service.forwardingError, passwordPromptHost == nil {
                    PortmanAddServerError(message: error, back: backToPick, retry: { service.forwardingError = nil; rescan(host) })
                } else {
                    PortmanAddServerStatus(text: "Connecting to \(host) and finding ports…", connected: false)
                }
            }
        }
    }

    private var addServerTitle: String {
        let count = selectedRemotePorts.count
        let ports = "\(count) \(count == 1 ? "port" : "ports")"
        return switch newHostMode {
        case .forward: "Forward \(ports)"
        case .monitor: "Watch \(host)"
        case .both: "Forward \(ports) and watch"
        }
    }

    private func finishAddServer() {
        service.forwardingError = nil
        if newHostMode.forwards { forwardSelected() }
        guard service.forwardingError == nil, hostList.add(host, mode: newHostMode) else { return }
        closeAddServer()
    }

    private func backToPick() {
        clearRemoteScan()
        service.forwardingError = nil
        pendingScanHost = nil
        addStep = .pick
    }

    private func closeAddServer() {
        clearRemoteScan()
        service.forwardingError = nil
        pendingScanHost = nil
        addStep = nil
        host = ""
    }

    /// Forwards the ticked ports and keeps the host on the job picked in the job switch.
    private func forwardAndSave() {
        service.forwardingError = nil
        forwardSelected()
        guard service.forwardingError == nil, newHostMode == .both else { return }
        hostList.setMode(.both, for: host)
    }

    nonisolated static let firstHostOpen = "\u{1}first"

    nonisolated static func isOpen(_ destination: String, first: Bool, in stored: String) -> Bool {
        stored == firstHostOpen ? first : stored.split(separator: "\n").contains(Substring(destination))
    }

    nonisolated static func toggled(_ destination: String, open: Bool, in stored: String) -> String {
        var hosts = stored == firstHostOpen ? [] : stored.split(separator: "\n").map(String.init)
        hosts.removeAll { $0 == destination }
        if !open { hosts.append(destination) }
        return hosts.joined(separator: "\n")
    }

    /// One card per host: its row, chart tiles when open, and its forwards under a guide line.
    private func hostGroup(_ group: PortmanHostGroup, first: Bool, now: Date) -> some View {
        let destination = group.host.destination
        let open = Self.isOpen(destination, first: first, in: openHosts)
        let model = PortmanHostCardModel(monitors: group.host.monitors, forwards: group.children.count,
                                         state: serverMonitor.states[destination], now: now)
        return PortmanHostCard(group: group, model: model, expanded: open, actions: PortmanHostCardActions(
            toggleStats: { openHosts = Self.toggled(destination, open: open, in: openHosts) },
            retry: { child in reforward(group, child) },
            open: openLocal,
            stop: { child in if let id = child.tunnel?.id { service.stopTunnel(id) } },
            remove: { child in
                if let id = child.tunnel?.id { service.stopTunnel(id) }
                hostList.removeForward(host: destination, localPort: child.spec.localPort)
            },
            move: { child, index in hostList.moveForward(host: destination, localPort: child.spec.localPort, to: index) }
        ))
            .contextMenu {
                Button("Scan ports") { scanPorts(on: destination) }
                Button("Use this host") { host = group.host.destination }
                ForEach(PortmanHostMode.allCases, id: \.self) { mode in
                    Button(group.saved && group.host.mode == mode ? "✓ \(mode.title)" : mode.title) {
                        if group.saved { hostList.setMode(mode, for: group.host.destination) }
                        else { hostList.add(group.host.destination, mode: mode) }
                    }
                }
                if group.saved { Button("Remove host") { hostList.remove(group.host.destination) } }
            }
    }

    /// Re-forwards one down forward, or every down forward of the host when `child` is nil. An auth failure asks
    /// for the password first; submitting it restarts every down forward of that host.
    private func reforward(_ group: PortmanHostGroup, _ child: PortmanForwardChild?) {
        let destination = group.host.destination
        let steps = child.map { PortmanForwardRetry.plan(host: destination, child: $0).map { [$0] } ?? [] }
            ?? PortmanForwardRetry.plan(group: group)
        PortmanForwardRetry.run(steps, stop: { service.stopTunnel($0) }, forward: { host, remote, local in
            service.forward(host: host, remotePort: remote, localPort: local,
                            password: sshPasswordHost == host ? sshPassword : nil)
        }, askPassword: { id in
            guard let tunnel = service.tunnels.first(where: { $0.id == id }) else { return }
            retryAfterPassword = tunnel
            passwordPromptError = "Authentication failed. Enter the password again."
            passwordPromptHost = tunnel.host
        })
    }

    private func addHost() {
        guard hostList.add(host, mode: newHostMode) else {
            service.forwardingError = "Enter a valid SSH host or alias."
            return
        }
        service.forwardingError = nil
    }

    private var manualRemotePorts: [UInt16] {
        selectedRemotePorts.sorted().filter { !service.remotePorts.contains($0) || discoveredHost != host }
    }

    /// `added` marks a port already on the host's card: its box stays checked and off, and "Added" takes the local port field.
    /// `compact` (Add a server step 2) shows only the checkbox, port, and name; ports forward to the same local port.
    private func remoteRow(_ port: UInt16, added: Bool = false, compact: Bool = false) -> some View {
        let detail = service.remoteDetails[port]
        return VStack(alignment: .leading, spacing: 0) {
            PortmanForwardRow {
                Toggle(isOn: Binding(
                    get: { added || selectedRemotePorts.contains(port) },
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
                .disabled(added)
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
                        if !compact {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(expandedRemotePort == port ? 90 : 0))
                                .foregroundStyle(OnePlusLinearColor.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: PortmanForwardMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Details for remote port \(String(port))")
                if added {
                    Text("Added").linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                        .frame(width: PortmanForwardMetrics.column)
                        .help("Already on this host's card")
                } else if !compact {
                    OnePlusLinearTextField(String(port), text: Binding(
                        get: { localPortInputs[port] ?? String(port) },
                        set: { localPortInputs[port] = $0; selectedRemotePorts.insert(port) }
                    ), onSubmit: forwardSelected)
                    .frame(width: PortmanForwardMetrics.column)
                    .accessibilityLabel("Local port for remote port \(String(port))")
                    .help("Local port")
                }
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

    /// Right-click "Scan ports" on a host card: scans that host with the Forward scan and lists its ports in a sheet.
    private func scanPorts(on destination: String) {
        scanSheetHost = destination
        rescan(destination)
    }

    /// Scans `destination`; when the host field changes first, the scan waits for it to settle.
    private func rescan(_ destination: String) {
        if host == destination { clearRemoteScan(); scanRemote() }
        else { pendingScanHost = destination; host = destination }
    }

    private func closeScanSheet() {
        scanSheetHost = nil
        clearRemoteScan()
    }

    private func scanSheet(_ destination: String) -> some View {
        let added = PortmanForwardTree.addedRemotePorts(host: destination, hosts: hostList.hosts, tunnels: service.tunnels)
        let ready = discoveredHost == destination && !service.isLoadingRemote
        let rows = ready ? service.remotePorts : []
        let sheetChrome: CGFloat = 140
        let listCap = max(PortmanForwardMetrics.rowHeight * 3, panelHeight * OnePlusMenuMetrics.heightFraction - sheetChrome)
        return OnePlusLinearSheet("Ports on \(destination)", width: .panel, close: closeScanSheet) {
            VStack(alignment: .leading, spacing: OnePlusLinearPanelStyle.fillSteps.blockGap) {
                if rows.isEmpty {
                    OnePlusLinearList(style: .panel) {
                        PortmanForwardRow {
                            PortmanForwardStatus(ready ? "No listening ports found" : "Scanning \(destination)…")
                        }
                    }
                } else {
                    OnePlusLinearList(style: .panel, maxHeight: listCap) {
                        ForEach(rows, id: \.self) { remoteRow($0, added: added.contains($0)) }
                    }
                }
                if let error = service.forwardingError { errorText(error) }
            }
        } footer: {
            Button("Cancel", action: closeScanSheet)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(OnePlusLinearButtonStyle(.soft))
            Button(selectedRemotePorts.isEmpty ? "Add" : "Add \(selectedRemotePorts.count)") {
                forwardSelected()
                if selectedRemotePorts.isEmpty, service.forwardingError == nil { closeScanSheet() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(OnePlusLinearButtonStyle(.soft))
            .disabled(selectedRemotePorts.isEmpty)
        }
        .fixedSize(horizontal: false, vertical: true)
        .portmanForwardLook()
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
            hostList.recordForward(host: host, remotePort: remotePort, localPort: localPort)
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
            PortmanForwardRetry.run(PortmanForwardRetry.afterPassword(host: retry.host, tunnels: service.tunnels),
                                    stop: { service.stopTunnel($0) },
                                    forward: { service.forward(host: $0, remotePort: $1, localPort: $2, password: password) },
                                    askPassword: { _ in })
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

    var body: some View {
        OnePlusSheet("SSH password for \(host)", width: .panel, close: onCancel) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                OnePlusLinearTextField("Password", text: $password, secure: true, onSubmit: submit)
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
        PortmanServerMonitor.shared.stop()
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

    #if MPT_DEMO
    /// The capture Mac's menu bar can hide the demo's status item; the demo anchors the panel here instead.
    var demoAnchor: NSView?
    #endif

    private var anchorView: NSView? {
        #if MPT_DEMO
        if let demoAnchor { return demoAnchor }
        #endif
        return item?.button
    }

    private func present(initialPage: PortmanPanelView.Page?, activateApp: Bool) -> Bool {
        guard let button = anchorView, button.window?.isVisible == true,
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
        UserDefaults.standard.set(Date(), forKey: PortmanPanelView.lastClosedKey)
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
            if !AppRuntime.isRunningTests { PortmanServerMonitor.shared.start() }
            updateButton()
        } else if let item {
            popover.close()
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            PortmanService.shared.endMonitoring()
            PortmanService.shared.stopAll()
            PortmanServerMonitor.shared.stop()
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
