import AppKit
import CoreLocation
import Observation
import OnePlusUI
import ServiceManagement
import SwiftUI

enum NetToysHistoryRange: TimeInterval, CaseIterable, Identifiable, Sendable {
    case day = 86_400
    case week = 604_800
    case month = 2_592_000

    var id: TimeInterval { rawValue }

    var title: String {
        switch self {
        case .day: "24 Hours"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }
}

nonisolated enum NetToysLocationAction: Equatable {
    case request
    case openSettings
    case none

    init(status: CLAuthorizationStatus, requestFailed: Bool) {
        if requestFailed || status == .denied || status == .restricted {
            self = .openSettings
        } else if status == .notDetermined {
            self = .request
        } else {
            self = .none
        }
    }
}

@Observable
@MainActor
final class NetToysHistoryViewModel: NSObject, CLLocationManagerDelegate {
    private struct Snapshot: Sendable {
        let history: NetworkHistory
        let helperStatus: NetToysHelperStatus?
        let recordsHistory: Bool
        let scanArchive: NetToysScanArchive
    }

    private static let exportDateFormatter = ISO8601DateFormatter()

    var history = NetworkHistory()
    var helperStatus: NetToysHelperStatus?
    var range = NetToysHistoryRange.day
    var searchText = ""
    var visibleEventRows: [NetToysHistoryEventRow] = []
    var recentScanRows: [NetToysHistoryScanRow] = []
    var availability: NetToysAvailabilityPresentation?
    var recordsHistory = true
    var scanArchive = NetToysScanArchive()
    var isLoading = true
    var isExporting = false
    var errorMessage: String?
    var locationAuthorizationStatus: CLAuthorizationStatus
    var locationRequestFailed = false

    @ObservationIgnored private let locationManager: CLLocationManager
    @ObservationIgnored private var refreshInProgress = false

    override init() {
        let locationManager = CLLocationManager()
        self.locationManager = locationManager
        locationAuthorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    var hasStoredHistory: Bool {
        !history.events.isEmpty || !scanArchive.runs.isEmpty
    }

    var helperSSIDUnavailable: Bool {
        guard helperStatus?.ssidAccess == .allowed,
              let snapshot = helperStatus?.network,
              snapshot.ssid == nil,
              let interfaceName = NetworkIdentity(
                  networkID: snapshot.networkID,
                  ssid: nil
              ).interfaceName
        else { return false }
        return NetworkSSID.isWiFi(interfaceName: interfaceName)
    }

    func refresh() async {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        defer { refreshInProgress = false }

        let snapshot = await Task.detached(priority: .utility) {
            Snapshot(
                history: NetToysConfigurationStore.history(),
                helperStatus: NetToysConfigurationStore.status(),
                recordsHistory: NetToysConfigurationStore.load().recordsNetworkHistory,
                scanArchive: NetToysScannerStore.archive()
            )
        }.value
        guard !Task.isCancelled else { return }
        history = snapshot.history
        helperStatus = snapshot.helperStatus
        recordsHistory = snapshot.recordsHistory
        scanArchive = snapshot.scanArchive
        locationAuthorizationStatus = locationManager.authorizationStatus
        isLoading = false
        await rebuildPresentation()
    }

    func setRange(_ range: NetToysHistoryRange) {
        self.range = range
        Task { await rebuildPresentation() }
    }

    func setSearchText(_ searchText: String) {
        self.searchText = searchText
        Task { await rebuildPresentation() }
    }

    func rebuildPresentation() async {
        let events = history.events
        let runs = scanArchive.runs
        let range = range
        let query = searchText
        let currentGateway = helperStatus?.network?.gateway ?? .unknown
        let currentInternet = helperStatus?.network?.internet ?? .unknown
        let currentNetwork = helperStatus?.network.map { $0.ssid ?? $0.displayName }
        let presentation = await Task.detached(priority: .utility) {
            netToysHistoryPresentation(
                events: events,
                runs: runs,
                range: range,
                query: query,
                currentGateway: currentGateway,
                currentInternet: currentInternet,
                currentNetwork: currentNetwork
            )
        }.value
        guard !Task.isCancelled, self.range == range, searchText == query else { return }
        visibleEventRows = presentation.events
        recentScanRows = presentation.scans
        availability = presentation.availability
    }

    func resolveSSIDAccess(forceSettings: Bool = false) {
        if forceSettings {
            openLocationSettings()
            return
        }
        locationAuthorizationStatus = locationManager.authorizationStatus
        switch NetToysLocationAction(
            status: locationAuthorizationStatus,
            requestFailed: locationRequestFailed
        ) {
        case .request:
            requestLocationAccess()
        case .openSettings:
            openLocationSettings()
        case .none:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorizationStatus = manager.authorizationStatus
        if locationAuthorizationStatus != .notDetermined {
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        manager.stopUpdatingLocation()
        if manager.authorizationStatus == .notDetermined,
           (error as? CLError)?.code == .denied {
            locationRequestFailed = true
        }
    }

    private func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func setRecordsHistory(_ enabled: Bool) {
        var configuration = NetToysConfigurationStore.load()
        configuration.recordsNetworkHistory = enabled
        do {
            try NetToysConfigurationStore.save(configuration)
            recordsHistory = enabled
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        do {
            try NetToysConfigurationStore.saveHistory(NetworkHistory())
            try NetToysScannerStore.clearArchive()
            history = NetworkHistory()
            scanArchive = NetToysScanArchive()
            isLoading = false
            Task { await rebuildPresentation() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NetToys Network History.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rows = visibleEventRows.map(\.event).map { event in
            [
                Self.exportDateFormatter.string(from: event.date),
                event.ssid ?? "",
                event.displayName,
                event.changes.map(Self.description).joined(separator: "; ")
            ].map(Self.csv).joined(separator: ",")
        }
        do {
            try (["Time,SSID,Network,Change"] + rows).joined(separator: "\n")
                .write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export(_ run: NetToysScanRun) {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NetToys Scan \(run.date.formatted(.iso8601)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try NetToysScanExport.csv(run.results).write(to: url, atomically: true, encoding: .utf8)
                }.value
                self?.errorMessage = nil
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isExporting = false
        }
    }

    nonisolated static func description(_ change: NetworkTransitionChange) -> String {
        switch change {
        case .network(let from, let to): "Network changed from \(from) to \(to)"
        case .gateway(let from, let to): "Gateway changed from \(from.rawValue) to \(to.rawValue)"
        case .internet(let from, let to): "Internet changed from \(from.rawValue) to \(to.rawValue)"
        }
    }

    nonisolated private static func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

nonisolated struct NetToysHistoryEventRow: Identifiable, Sendable {
    let id: String
    let event: NetworkTransitionEvent
    let message: String
    let network: String
    let time: String
    let isOutage: Bool
}

nonisolated struct NetToysHistoryScanRow: Identifiable, Sendable {
    var id: UUID { run.id }
    let run: NetToysScanRun
    let detail: String
    let time: String
}

nonisolated struct NetToysAvailabilityPresentation: Sendable {
    let start: Date
    let range: TimeInterval
    let startLabel: String
    let summaries: [NetToysAvailabilityRow]
    let outages: [NetToysOutageRow]
}

nonisolated struct NetToysAvailabilityRow: Identifiable, Sendable {
    var id: String { summary.network }
    let summary: NetworkAvailabilitySummary
    let label: String
}

nonisolated struct NetToysOutageRow: Identifiable, Sendable {
    var id: String { outage.id }
    let outage: NetworkAvailabilitySegment
    let title: String
    let time: String
}

nonisolated struct NetToysHistoryPresentation: Sendable {
    let events: [NetToysHistoryEventRow]
    let scans: [NetToysHistoryScanRow]
    let availability: NetToysAvailabilityPresentation
}

nonisolated func netToysHistoryPresentation(
    events: [NetworkTransitionEvent],
    runs: [NetToysScanRun],
    range: NetToysHistoryRange,
    query: String,
    currentGateway: NetworkReachability,
    currentInternet: NetworkReachability,
    currentNetwork: String?,
    now: Date = Date()
) -> NetToysHistoryPresentation {
    let end = now
    let start = end.addingTimeInterval(-range.rawValue)
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let visibleEvents = events.reversed().filter { event in
        guard event.date >= start else { return false }
        guard !query.isEmpty else { return true }
        return event.displayName.localizedCaseInsensitiveContains(query)
            || event.changes.map(NetToysHistoryViewModel.description).contains {
                $0.localizedCaseInsensitiveContains(query)
            }
    }
    let eventRows = visibleEvents.map { event in
        let descriptions = event.changes.map(NetToysHistoryViewModel.description)
        return NetToysHistoryEventRow(
            id: "\(event.date.timeIntervalSinceReferenceDate)|\(event.networkID)|\(descriptions.joined(separator: "|"))",
            event: event,
            message: descriptions.joined(separator: " · "),
            network: event.displayName,
            time: event.date.formatted(date: .abbreviated, time: .standard),
            isOutage: event.changes.contains { change in
                switch change {
                case .network(_, let to): to == "disconnected"
                case .gateway(_, let to), .internet(_, let to): to == .unreachable
                }
            }
        )
    }
    let scanRows = runs.reversed().filter { $0.date >= start }.prefix(10).map { run in
        NetToysHistoryScanRow(
            run: run,
            detail: "\(run.results.count) results  ·  \(run.results.filter(\.isReachable).count) alive  ·  ports \(run.ports.map(String.init).joined(separator: ", "))  ·  \(run.duration.formatted(.number.precision(.fractionLength(1)))) s",
            time: run.date.formatted(date: .abbreviated, time: .shortened)
        )
    }
    let summaries = networkAvailabilitySummaries(
        events: events,
        from: start,
        to: end,
        currentGateway: currentGateway,
        currentInternet: currentInternet,
        currentNetwork: currentNetwork
    )
    let outages = summaries.flatMap(\.outages).sorted { $0.start > $1.start }
    return NetToysHistoryPresentation(
        events: eventRows,
        scans: Array(scanRows),
        availability: NetToysAvailabilityPresentation(
            start: start,
            range: range.rawValue,
            startLabel: start.formatted(date: .abbreviated, time: .shortened),
            summaries: summaries.map {
                NetToysAvailabilityRow(summary: $0, label: netToysSummaryLabel($0))
            },
            outages: outages.map { outage in
                let ongoing = outage.end == end
                return NetToysOutageRow(
                    outage: outage,
                    title: ongoing
                        ? "\(outage.network) has been unavailable for \(netToysDurationLabel(outage.duration))"
                        : "\(outage.network) was unavailable for \(netToysDurationLabel(outage.duration))",
                    time: ongoing
                        ? "Since \(outage.start.formatted(date: .abbreviated, time: .shortened))"
                        : "\(outage.start.formatted(date: .abbreviated, time: .shortened)) to \(outage.end.formatted(date: .omitted, time: .shortened))"
                )
            }
        )
    )
}

nonisolated private func netToysSummaryLabel(_ summary: NetworkAvailabilitySummary) -> String {
    guard let uptime = summary.uptime else { return "No availability data" }
    let outageText = summary.outages.count == 1 ? "1 outage" : "\(summary.outages.count) outages"
    return "\(uptime.formatted(.percent.precision(.fractionLength(1)))) uptime  ·  \(outageText)  ·  \(netToysDurationLabel(summary.unavailableDuration)) down"
}

nonisolated private func netToysDurationLabel(_ duration: TimeInterval) -> String {
    guard duration >= 1 else { return "0 secs" }
    return Duration.seconds(max(1, duration.rounded()))
        .formatted(.units(
            allowed: [.hours, .minutes, .seconds],
            width: .abbreviated,
            maximumUnitCount: 2
        ))
}

struct NetToysHistoryView: View {
    @State private var model = NetToysHistoryViewModel()
    @State private var confirmClear = false
    @State private var searchFocus = 0

    var body: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(
                title: "Network History",
                subtitle: model.helperStatus?.network?.displayName ?? "Waiting for the helper"
            ) {
                if model.isLoading { ProgressView().controlSize(.small).accessibilityLabel("Loading network history") }
                Toggle("Record history", isOn: Binding(
                    get: { model.recordsHistory },
                    set: { model.setRecordsHistory($0) }
                ))
                .toggleStyle(OnePlusSwitchStyle()).fixedSize()
                .accessibilityLabel("Record network history")

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

        } content: {
            currentStatus
            availabilityGraph
            recentScans
            eventList
        }
        .background {
            Button("") { searchFocus += 1 }.keyboardShortcut("f").hidden()
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .confirmationDialog("Clear network history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved uptime, transition, and IP scan records from this Mac.")
        }
        .alert("Network History", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var currentStatus: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusCardHeader("Current status")
                HStack(spacing: 0) {
                    statusCell(
                        title: "Gateway",
                        state: model.helperStatus?.network?.gateway ?? .unknown,
                        symbol: "network"
                    )
                    OnePlusRule(vertical: true)
                    statusCell(
                        title: "Internet",
                        state: model.helperStatus?.network?.internet ?? .unknown,
                        symbol: "globe"
                    )
                    OnePlusRule(vertical: true)
                    VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                        Label("Network", systemImage: "wifi")
                            .onePlusText(.cardTitle).foregroundStyle(OnePlusColor.secondary)
                        Text(model.helperStatus?.network?.displayName ?? "Unknown")
                            .onePlusText(.mono).lineLimit(1).truncationMode(.middle)
                            .help(model.helperStatus?.network?.displayName ?? "Unknown")
                        Text(model.helperStatus?.network?.checkedAt.formatted(date: .omitted, time: .standard) ?? "Not checked")
                            .onePlusText(.caption).foregroundStyle(OnePlusColor.muted)
                    }
                    .padding(.horizontal, OnePlusMetrics.cardPadding)
                    .frame(maxWidth: .infinity,
                           minHeight: OnePlusMetrics.captionedSettingRow + OnePlusMetrics.navPadding,
                           alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let message = ssidAccessMessage {
                OnePlusBanner(message, tone: .warning) {
                    if let title = ssidAccessActionTitle {
                        Button(title) {
                            model.resolveSSIDAccess(
                                forceSettings: model.helperSSIDUnavailable
                                    || model.helperStatus?.ssidAccess != nil
                                    && model.helperStatus?.ssidAccess != .allowed
                            )
                        }
                    }
                }
            }
        }
    }

    private func statusCell(title: String, state: NetworkReachability, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            Label(title, systemImage: symbol)
                .onePlusText(.cardTitle).foregroundStyle(OnePlusColor.secondary)
            OnePlusStatus(state.rawValue.capitalized,
                          state: state == .reachable ? .online : state == .unreachable ? .warning : .offline,
                          textRole: .row)
            Text("Updated by NetToys Helper")
                .onePlusText(.caption).foregroundStyle(OnePlusColor.muted)
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(maxWidth: .infinity,
               minHeight: OnePlusMetrics.captionedSettingRow + OnePlusMetrics.navPadding,
               alignment: .leading)
    }

    private var availabilityGraph: some View {
        OnePlusCard {
            OnePlusCardHeader("Network uptime") {
                OnePlusSegmented(choices: NetToysHistoryRange.allCases.map { ($0, $0.title) },
                                 selection: Binding(get: { model.range }, set: model.setRange)).fixedSize()
            }
            if let availability = model.availability {
                NetworkUptimeTimeline(presentation: availability)
            } else {
                OnePlusEmptyState("Loading uptime", systemImage: "clock") {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var eventList: some View {
        let events = model.visibleEventRows
        return OnePlusCard {
            OnePlusCardHeader("Transitions") {
                OnePlusSearchField(prompt: "Find network or state",
                                   text: Binding(get: { model.searchText }, set: model.setSearchText),
                                   width: OnePlusMetrics.controlColumn * 2, focusTrigger: searchFocus)
                Button("Export") { model.export() }
                    .disabled(events.isEmpty)
                Button("Clear", role: .destructive) { confirmClear = true }
                    .disabled(!model.hasStoredHistory)
            }
            if events.isEmpty {
                OnePlusEmptyState("No transitions", systemImage: "clock", caption: model.recordsHistory
                        ? "No network state changes are recorded in this range."
                        : "Network history recording is off.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(events) { row in
                            HStack(spacing: OnePlusMetrics.navIconGap) {
                                Image(systemName: row.isOutage ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(row.isOutage ? OnePlusColor.warn : OnePlusColor.secondary)
                                    .frame(width: OnePlusMetrics.navIcon)
                                VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                                    Text(row.message).onePlusText(.row)
                                    Text(row.network)
                                        .onePlusText(.mono).foregroundStyle(OnePlusColor.secondary)
                                }
                                Spacer()
                                Text(row.time)
                                    .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                            }
                            .padding(.horizontal, OnePlusMetrics.cardPadding)
                            .frame(height: OnePlusMetrics.captionedSettingRow)
                            if row.id != events.last?.id { OnePlusRule() }
                        }
                    }
                }
                .onePlusScrollIndicators()
                .frame(minHeight: OnePlusMetrics.captionedSettingRow * 3 + 2, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var recentScans: some View {
        let rows = model.recentScanRows
        let visibleRowCount = min(ssidAccessMessage == nil ? 2 : 1, rows.count)
        return OnePlusCard {
            OnePlusCardHeader("Recent IP scans")
            if rows.isEmpty {
                OnePlusEmptyState("No saved scans", systemImage: "dot.radiowaves.left.and.right",
                                  caption: "Completed IP Scanner runs appear here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            let run = row.run
                            HStack(spacing: OnePlusMetrics.navIconGap) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(OnePlusColor.secondary)
                                    .frame(width: OnePlusMetrics.navIcon)
                                VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                                    Text(run.target)
                                        .onePlusText(.mono)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(row.detail)
                                        .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                                }
                                Spacer()
                                Text(row.time)
                                    .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                                Button { model.export(run) } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                    .buttonStyle(OnePlusButtonStyle(.icon))
                                    .help("Export scan")
                                    .accessibilityLabel("Export scan")
                                    .disabled(model.isExporting)
                                Button {
                                    NotificationCenter.default.post(name: .netToysRescanRun, object: run)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(OnePlusButtonStyle(.icon))
                                .help("Scan again")
                                .accessibilityLabel("Scan again")
                            }
                            .padding(.horizontal, OnePlusMetrics.cardPadding)
                            .frame(height: OnePlusMetrics.captionedSettingRow)
                            .contextMenu {
                                Button("Export") { model.export(run) }
                                    .disabled(model.isExporting)
                                Button("Scan Again") {
                                    NotificationCenter.default.post(name: .netToysRescanRun, object: run)
                                }
                            }
                            if row.id != rows.last?.id { OnePlusRule() }
                        }
                    }
                }
                .onePlusScrollIndicators()
                .frame(height: CGFloat(visibleRowCount) * OnePlusMetrics.captionedSettingRow
                       + CGFloat(max(0, visibleRowCount - 1)))
            }
        }
    }

    private var ssidAccessMessage: String? {
        guard let snapshot = model.helperStatus?.network,
              snapshot.ssid == nil,
              snapshot.networkID != "disconnected"
        else { return nil }
        if model.helperStatus?.ssidAccess == .notDetermined {
            return "NetToys Helper is waiting for its Location permission. Respond to the macOS prompt or open Location Settings."
        }
        if model.helperStatus?.ssidAccess == .denied || model.helperStatus?.ssidAccess == .restricted {
            return "Allow NetToys Helper in Location Services so background history can record Wi-Fi names."
        }
        if model.locationRequestFailed {
            return "macOS blocked the Location request. Open Location Services to allow MacPowerToys."
        }
        switch model.locationAuthorizationStatus {
        case .denied, .restricted:
            return "Allow Location access in System Settings to label Wi-Fi history with the network name."
        case .authorized, .authorizedAlways:
            return "The Wi-Fi network name is not available from the background helper."
        default:
            return "Allow Location access to label Wi-Fi history with the network name."
        }
    }

    private var ssidAccessActionTitle: String? {
        if model.helperSSIDUnavailable
            || model.helperStatus?.ssidAccess != nil && model.helperStatus?.ssidAccess != .allowed
        {
            return "Open Location Settings"
        }
        return switch NetToysLocationAction(
            status: model.locationAuthorizationStatus,
            requestFailed: model.locationRequestFailed
        ) {
        case .request: "Allow Access"
        case .openSettings: "Open System Settings"
        case .none: nil
        }
    }
}

struct NetToysSettingsView: View {
    @State private var model = NetToysHistoryViewModel()
    @State private var settings = SettingsManager.shared
    @State private var localNetworkAccess = NetToysLocalNetworkAccess.shared
    @State private var neighborService = NetToysNeighborServiceManager.shared
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusCardHeader("Background helper") {
                    if model.isLoading {
                        ProgressView("Loading network settings...").controlSize(.small)
                            .onePlusText(.caption).accessibilityIdentifier("nettoys.settings-loading")
                    }
                }
                OnePlusSettingRow("Enable NetToys", caption: "Keep SSH Anchor, Wi-Fi failover, and network history available.", separator: false) {
                    Toggle("Enable NetToys", isOn: Binding(get: { settings.isToolEnabled("nettoys") },
                           set: { settings.setToolEnabled($0, for: "nettoys") }))
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .disabled(settings.isToolTransitioning("nettoys"))
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Permissions")
                OnePlusSettingRow("Wi-Fi network names", caption: locationStatusMessage,
                                  controlWidth: OnePlusMetrics.wideControlColumn) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        OnePlusStatus(locationStatusTitle, state: locationActionTitle == nil ? .online : .offline)
                            .fixedSize()
                        if let title = locationActionTitle {
                            Button(title == "Allow Location Access" ? "Allow access" : "Settings") {
                                model.resolveSSIDAccess(forceSettings: helperNeedsAccess)
                            }
                            .fixedSize()
                            .help(title)
                            .accessibilityLabel(title)
                        }
                    }
                }
                OnePlusSettingRow("Local network", caption: localNetworkStatusMessage,
                                  controlWidth: OnePlusMetrics.wideControlColumn) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        OnePlusStatus(localNetworkStatusTitle, state: localNetworkAccess.state == .allowed ? .online : .offline)
                            .fixedSize()
                        if localNetworkAccess.state == .denied {
                            Button("Settings") { localNetworkAccess.openSettings() }
                                .fixedSize()
                                .help("Open Local Network Settings")
                                .accessibilityLabel("Open Local Network Settings")
                        } else if localNetworkAccess.state == .unavailable {
                            Button("Try Again") { localNetworkAccess.request() }
                                .fixedSize()
                        }
                    }
                }
                OnePlusSettingRow("MAC addresses", caption: macAccessStatusMessage,
                                  controlWidth: OnePlusMetrics.wideControlColumn, separator: false) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        OnePlusStatus(macAccessStatusTitle, state: neighborService.isEnabled ? .online : .offline)
                            .fixedSize()
                        if !neighborService.isEnabled {
                            Button(neighborService.status == .requiresApproval ? "Settings" : "Enable") {
                                neighborService.enable()
                            }
                            .fixedSize()
                            .help(macAccessActionTitle)
                            .accessibilityLabel(macAccessActionTitle)
                        }
                    }
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Data")
                OnePlusSettingRow("Network history", caption: "Remove saved uptime, transition, and IP scan records from this Mac.", separator: false) {
                    Button("Clear History", role: .destructive) { confirmClear = true }
                        .buttonStyle(OnePlusButtonStyle(.destructive))
                        .disabled(!model.hasStoredHistory)
                }
            }
        }
        .task {
            await model.refresh()
            localNetworkAccess.request()
            neighborService.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
            localNetworkAccess.request()
            neighborService.refresh()
        }
        .confirmationDialog("Clear network history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved uptime, transition, and IP scan records from this Mac.")
        }
        .alert("Network settings", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var localNetworkStatusTitle: String {
        switch localNetworkAccess.state {
        case .checking: "Checking"
        case .allowed: "Allowed"
        case .denied: "Needs Attention"
        case .unavailable: "Unavailable"
        }
    }

    private var macAccessStatusTitle: String {
        _ = neighborService.revision
        return switch neighborService.status {
        case .enabled: "Allowed"
        case .requiresApproval: "Needs Approval"
        case .notRegistered: "Not Enabled"
        case .notFound: "Unavailable"
        @unknown default: "Unavailable"
        }
    }

    private var macAccessStatusMessage: String {
        switch neighborService.status {
        case .enabled:
            "The approved helper supplies neighboring MAC addresses automatically during scans."
        case .requiresApproval:
            "Turn on every MacPowerToys entry under System Settings > General > "
                + "Login Items & Extensions > Background App Activity, then return and scan again."
        case .notRegistered:
            "Enable the narrow privileged helper that reads the system neighbor cache."
        case .notFound:
            neighborService.errorMessage ?? "The installed app does not contain its MAC address helper."
        @unknown default:
            neighborService.errorMessage ?? "macOS could not determine the helper state."
        }
    }

    private var macAccessActionTitle: String {
        neighborService.status == .requiresApproval ? "Open Login Items" : "Enable MAC Access"
    }

    private var localNetworkStatusMessage: String {
        switch localNetworkAccess.state {
        case .checking:
            "Respond to the macOS prompt so IP Scanner can discover local devices."
        case .allowed:
            "Local Network access is allowed for IP scanning and device discovery."
        case .denied:
            "Allow MacPowerToys in Privacy & Security > Local Network to scan local devices."
        case .unavailable:
            "macOS could not check Local Network access. Check the network and try again."
        }
    }

    private var locationStatusTitle: String {
        if helperNeedsAccess { return "Needs Attention" }
        if model.locationRequestFailed { return "Needs Attention" }
        return switch model.locationAuthorizationStatus {
        case .notDetermined: "Not Requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .authorized, .authorizedAlways: "Allowed"
        @unknown default: "Unknown"
        }
    }

    private var locationStatusMessage: String {
        if model.helperStatus?.ssidAccess == .notDetermined {
            return "NetToys Helper is waiting for its Location permission so it can record SSIDs in the background."
        }
        if model.helperStatus?.ssidAccess == .denied || model.helperStatus?.ssidAccess == .restricted {
            return "Enable NetToys Helper in Privacy & Security > Location Services to record SSIDs in the background."
        }
        if model.helperSSIDUnavailable {
            return "Location access is allowed, but NetToys Helper could not read the current Wi-Fi name. Check Location Services and try again."
        }
        if model.locationRequestFailed {
            return "macOS blocked the Location request. Open Privacy & Security > Location Services and allow MacPowerToys."
        }
        return switch model.locationAuthorizationStatus {
        case .notDetermined:
            "Allow Location access so Network History can identify Wi-Fi networks by SSID."
        case .denied:
            "Location access is off. Enable MacPowerToys in Privacy & Security > Location Services."
        case .restricted:
            "macOS policy prevents Location access for MacPowerToys."
        case .authorized, .authorizedAlways:
            "Location access is allowed. New Wi-Fi samples can include the SSID."
        @unknown default:
            "macOS did not report the Location access state."
        }
    }

    private var locationActionTitle: String? {
        if helperNeedsAccess { return "Open Location Settings" }
        return switch NetToysLocationAction(
            status: model.locationAuthorizationStatus,
            requestFailed: model.locationRequestFailed
        ) {
        case .request: "Allow Location Access"
        case .openSettings: "Open Location Settings"
        case .none: nil
        }
    }

    private var helperNeedsAccess: Bool {
        guard let state = model.helperStatus?.ssidAccess else { return false }
        return state != .allowed || model.helperSSIDUnavailable
    }
}

nonisolated struct NetworkAvailabilitySegment: Equatable, Identifiable, Sendable {
    let network: String
    let state: NetworkReachability
    let start: Date
    let end: Date

    var id: String {
        "\(network)|\(state.rawValue)|\(start.timeIntervalSinceReferenceDate)|\(end.timeIntervalSinceReferenceDate)"
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

nonisolated struct NetworkAvailabilitySummary: Equatable, Sendable {
    let network: String
    let segments: [NetworkAvailabilitySegment]

    var knownDuration: TimeInterval {
        segments.filter { $0.state != .unknown }.reduce(0) { $0 + $1.duration }
    }

    var unavailableDuration: TimeInterval {
        outages.reduce(0) { $0 + $1.duration }
    }

    var uptime: Double? {
        knownDuration > 0 ? (knownDuration - unavailableDuration) / knownDuration : nil
    }

    var outages: [NetworkAvailabilitySegment] {
        segments.filter { $0.state == .unreachable }
    }
}

nonisolated func networkAvailabilitySummaries(
    events: [NetworkTransitionEvent],
    from start: Date,
    to end: Date,
    currentGateway: NetworkReachability = .unknown,
    currentInternet: NetworkReachability = .unknown,
    currentNetwork: String? = nil
) -> [NetworkAvailabilitySummary] {
    let orderedEvents = events.filter { $0.date <= end }.sorted { $0.date < $1.date }
    var gateway = NetworkReachability.unknown
    var internet = NetworkReachability.unknown
    var network: String?
    var cursor = start
    var segments: [NetworkAvailabilitySegment] = []
    let lastReachability = orderedEvents.last { event in
        event.changes.contains { change in
            switch change {
            case .gateway, .internet: true
            case .network: false
            }
        }
    }
    let currentStateIsKnown = currentGateway != .unknown || currentInternet != .unknown
    let repairDate = currentStateIsKnown ? orderedEvents.last { event in
        guard let lastReachability, event.date > lastReachability.date else { return false }
        return event.changes.contains { if case .network = $0 { true } else { false } }
    }?.date
        : nil

    func availabilityState() -> NetworkReachability {
        if gateway == .unreachable || internet == .unreachable { return .unreachable }
        if gateway == .reachable || internet == .reachable { return .reachable }
        return .unknown
    }

    func connectedName(_ value: String?) -> String? {
        guard let value, value.caseInsensitiveCompare("Disconnected") != .orderedSame else { return nil }
        return value
    }

    func appendSegment(until date: Date) {
        let segmentEnd = min(max(date, start), end)
        guard cursor < segmentEnd, let network else {
            cursor = max(cursor, segmentEnd)
            return
        }
        let state = availabilityState()
        if let last = segments.last,
           last.network == network,
           last.state == state,
           last.end == cursor {
            segments[segments.count - 1] = NetworkAvailabilitySegment(
                network: network,
                state: state,
                start: last.start,
                end: segmentEnd
            )
        } else {
            segments.append(NetworkAvailabilitySegment(
                network: network,
                state: state,
                start: cursor,
                end: segmentEnd
            ))
        }
        cursor = segmentEnd
    }

    for event in orderedEvents {
        let networkChange = event.changes.compactMap { change -> (String, String)? in
            if case .network(let from, let to) = change { return (from, to) }
            return nil
        }.last
        let internetChange = event.changes.compactMap { change -> (NetworkReachability, NetworkReachability)? in
            if case .internet(let from, let to) = change { return (from, to) }
            return nil
        }.last
        let gatewayChange = event.changes.compactMap { change -> (NetworkReachability, NetworkReachability)? in
            if case .gateway(let from, let to) = change { return (from, to) }
            return nil
        }.last

        if event.date >= start {
            if network == nil {
                network = connectedName(networkChange?.0)
                    ?? connectedName(event.ssid)
                    ?? (event.networkID == "disconnected" ? nil : event.displayName)
            }
            appendSegment(until: event.date)
        }

        if let networkChange {
            network = event.networkID == "disconnected"
                ? nil
                : connectedName(event.ssid) ?? connectedName(networkChange.1)
        } else if event.networkID == "disconnected" {
            network = nil
        } else if let ssid = connectedName(event.ssid) {
            network = ssid
        } else if network == nil {
            network = event.displayName
        }
        if let gatewayChange { gateway = gatewayChange.1 }
        if let internetChange { internet = internetChange.1 }
        if event.date == repairDate {
            if currentGateway != .unknown { gateway = currentGateway }
            if currentInternet != .unknown { internet = currentInternet }
            network = connectedName(currentNetwork) ?? network
        }
        if event.date < start { cursor = start }
    }
    appendSegment(until: end)

    return Dictionary(grouping: segments, by: \NetworkAvailabilitySegment.network)
        .map { NetworkAvailabilitySummary(network: $0.key, segments: $0.value) }
        .sorted {
            ($0.segments.last?.end ?? .distantPast, $0.network)
                > ($1.segments.last?.end ?? .distantPast, $1.network)
        }
}

private struct NetworkUptimeTimeline: View {
    let presentation: NetToysAvailabilityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryChart
            if !presentation.outages.isEmpty {
                recentOutages
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Network uptime by network name")
    }

    private var summaryChart: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            if presentation.summaries.isEmpty {
                OnePlusEmptyState("No uptime data", systemImage: "clock",
                                  caption: "Network uptime appears after the helper records a network change.")
            } else {
                if presentation.summaries.count == 1 {
                    summaryRows
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            summaryRows
                        }
                    }
                    .onePlusScrollIndicators()
                    .frame(height: OnePlusMetrics.settingRow)
                }
                HStack(spacing: OnePlusMetrics.cardGap) {
                    Text(presentation.startLabel)
                    Spacer()
                    legend
                    Spacer()
                    Text("Now")
                }
                .onePlusText(.caption).foregroundStyle(OnePlusColor.muted)
            }
        }
        .padding(OnePlusMetrics.cardPadding)
    }

    private var summaryRows: some View {
        ForEach(presentation.summaries) { row in
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.actionSpacing) {
                    Text(row.summary.network).onePlusText(.row).lineLimit(1)
                    Spacer()
                    Text(row.label).onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                }
                availabilityBar(row.summary, accessibilityValue: row.label)
            }
            .frame(height: OnePlusMetrics.settingRow)
        }
    }

    private var legend: some View {
        HStack(spacing: OnePlusMetrics.cardGap) {
            legendItem("Online", systemImage: "circle.fill", color: OnePlusColor.chartSeries[1])
            legendItem("Unavailable", systemImage: "circle.fill", color: OnePlusColor.warn)
            legendItem("Inactive or no data", systemImage: "circle", color: OnePlusColor.muted)
        }
    }

    private var recentOutages: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnePlusRule()
            Text("Recent outages").onePlusText(.cardTitle)
                .padding(.horizontal, OnePlusMetrics.cardPadding)
                .frame(height: OnePlusMetrics.controlHeight)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(presentation.outages) { row in
                        HStack(spacing: OnePlusMetrics.navIconGap) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(OnePlusColor.warn)
                                .frame(width: OnePlusMetrics.navIcon)
                            VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                                Text(row.title).onePlusText(.row).lineLimit(1)
                                Text(row.time).onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, OnePlusMetrics.cardPadding)
                        .frame(height: OnePlusMetrics.captionedSettingRow)
                        if row.id != presentation.outages.last?.id { OnePlusRule() }
                    }
                }
            }
            .onePlusScrollIndicators()
            .frame(height: OnePlusMetrics.captionedSettingRow)
        }
    }

    private func availabilityBar(
        _ summary: NetworkAvailabilitySummary,
        accessibilityValue: String
    ) -> some View {
        Canvas { context, size in
            for segment in summary.segments {
                guard segment.state != .unknown else { continue }
                let rect = CGRect(
                    x: size.width * segment.start.timeIntervalSince(presentation.start) / presentation.range,
                    y: 0,
                    width: max(1, size.width * segment.duration / presentation.range),
                    height: size.height
                )
                context.fill(Path(rect), with: .color(color(for: segment.state)))
            }
        }
        .frame(height: OnePlusMetrics.navPadding)
        .background(OnePlusColor.panel)
        .clipShape(RoundedRectangle(cornerRadius: OnePlusMetrics.segmentRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OnePlusMetrics.segmentRadius)
                .strokeBorder(OnePlusColor.line, lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel(summary.network)
        .accessibilityValue(accessibilityValue)
    }

    private func legendItem(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: OnePlusMetrics.spacing[2]) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(title).onePlusText(.caption).foregroundStyle(OnePlusColor.muted)
        }
    }

    private func color(for state: NetworkReachability) -> Color {
        switch state {
        case .reachable: OnePlusColor.chartSeries[1]
        case .unreachable: OnePlusColor.warn
        case .unknown: OnePlusColor.field
        }
    }
}
