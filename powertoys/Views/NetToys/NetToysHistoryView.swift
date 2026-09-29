import AppKit
import CoreLocation
import Observation
import OnePlusUI
import ServiceManagement
import SwiftUI

enum NetToysHistoryRange: TimeInterval, CaseIterable, Identifiable {
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

    var visibleEvents: [NetworkTransitionEvent] {
        let cutoff = Date().addingTimeInterval(-range.rawValue)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return history.events.reversed().filter { event in
            guard event.date >= cutoff else { return false }
            guard !query.isEmpty else { return true }
            return event.displayName.localizedCaseInsensitiveContains(query)
                || event.changes.map(Self.description).contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
        }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NetToys Network History.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rows = visibleEvents.map { event in
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

struct NetToysHistoryView: View {
    @State private var model = NetToysHistoryViewModel()
    @State private var confirmClear = false
    @State private var searchFocus = 0

    var body: some View {
        OnePlusPage {
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
                statusCard(
                    title: "Gateway",
                    state: model.helperStatus?.network?.gateway ?? .unknown,
                    symbol: "router"
                )
                    OnePlusRule(vertical: true)
                statusCard(
                    title: "Internet",
                    state: model.helperStatus?.network?.internet ?? .unknown,
                    symbol: "globe"
                )
                    OnePlusRule(vertical: true)
                    VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                        Text("Network").onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                        Text(model.helperStatus?.network?.displayName ?? "Unknown")
                            .onePlusText(.mono).lineLimit(1)
                            .help(model.helperStatus?.network?.displayName ?? "Unknown")
                        Text(model.helperStatus?.network?.checkedAt.formatted(date: .omitted, time: .standard) ?? "Not checked")
                            .onePlusText(.caption).foregroundStyle(OnePlusColor.muted)
                    }.padding(OnePlusMetrics.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
                }
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

    private func statusCard(title: String, state: NetworkReachability, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            Label(title, systemImage: symbol)
                .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
            OnePlusStatus(state.rawValue.capitalized, state: state == .reachable ? .online : .offline)
            Text("Updated by NetToys Helper")
                .onePlusText(.caption).foregroundStyle(OnePlusColor.muted)
        }
        .padding(OnePlusMetrics.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availabilityGraph: some View {
        OnePlusCard {
            OnePlusCardHeader("Network uptime") {
                OnePlusSegmented(choices: NetToysHistoryRange.allCases.map { ($0, $0.title) },
                                 selection: $model.range).fixedSize()
            }
                NetworkUptimeTimeline(
                    events: model.history.events,
                    range: model.range.rawValue,
                    currentState: model.helperStatus?.network?.internet ?? .unknown,
                    currentNetwork: model.helperStatus?.network.map {
                        $0.ssid ?? $0.displayName
                    }
                ).padding(OnePlusMetrics.cardPadding)
        }
    }

    private var eventList: some View {
        let events = model.visibleEvents
        return OnePlusCard {
            OnePlusCardHeader("Transitions") {
                OnePlusSearchField(prompt: "Find network or state", text: $model.searchText,
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
                LazyVStack(spacing: 0) {
                    ForEach(events, id: \.date) { event in
                        HStack(alignment: .top, spacing: OnePlusMetrics.navIconGap) {
                            Image(systemName: event.changes.contains(where: isOutage) ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(event.changes.contains(where: isOutage) ? OnePlusColor.warn : OnePlusColor.secondary)
                                .frame(width: OnePlusMetrics.navIcon)
                            VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                                Text(event.changes.map(NetToysHistoryViewModel.description).joined(separator: " · "))
                                    .onePlusText(.row)
                                Text(event.displayName)
                                    .onePlusText(.mono).foregroundStyle(OnePlusColor.secondary)
                            }
                            Spacer()
                            Text(event.date.formatted(date: .abbreviated, time: .standard))
                                .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                        }
                        .padding(OnePlusMetrics.cardPadding)
                        if event.date != events.last?.date { OnePlusRule() }
                    }
                }
            }
        }
    }

    private var recentScans: some View {
        let runs = scanArchiveRuns
        return OnePlusCard {
            OnePlusCardHeader("Recent IP scans")
            if runs.isEmpty {
                OnePlusEmptyState("No saved scans", systemImage: "dot.radiowaves.left.and.right",
                                  caption: "Completed IP Scanner runs appear here.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(runs) { run in
                        HStack(spacing: OnePlusMetrics.navIconGap) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(OnePlusColor.secondary)
                                .frame(width: OnePlusMetrics.navIcon)
                            VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                                Text(run.target)
                                    .onePlusText(.mono)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(run.results.count) results  ·  \(run.results.filter(\.isReachable).count) alive  ·  ports \(run.ports.map(String.init).joined(separator: ", "))  ·  \(run.duration.formatted(.number.precision(.fractionLength(1)))) s")
                                    .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                            }
                            Spacer()
                            Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                            Button("Export") { model.export(run) }
                                .disabled(model.isExporting)
                            Button("Scan Again") {
                                NotificationCenter.default.post(name: .netToysRescanRun, object: run)
                            }
                            .buttonStyle(OnePlusButtonStyle(.neutral))
                        }
                        .padding(OnePlusMetrics.cardPadding)
                        if run.id != runs.last?.id { OnePlusRule() }
                    }
                }
            }
        }
    }

    private var scanArchiveRuns: [NetToysScanRun] {
        let cutoff = Date().addingTimeInterval(-model.range.rawValue)
        return Array(model.scanArchive.runs.reversed().filter { $0.date >= cutoff }.prefix(10))
    }

    private func isOutage(_ change: NetworkTransitionChange) -> Bool {
        switch change {
        case .network(_, let to): to == "disconnected"
        case .gateway(_, let to), .internet(_, let to): to == .unreachable
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
            if model.isLoading {
                ProgressView("Loading network settings...").controlSize(.small)
                    .onePlusText(.caption).accessibilityIdentifier("nettoys.settings-loading")
            }
            OnePlusCard {
                OnePlusCardHeader("Background helper")
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
                    VStack(alignment: .trailing, spacing: OnePlusMetrics.navRowGap) {
                        OnePlusStatus(locationStatusTitle, state: locationActionTitle == nil ? .online : .offline)
                        if let title = locationActionTitle {
                            Button(title) { model.resolveSSIDAccess(forceSettings: helperNeedsAccess) }
                        }
                    }
                }
                OnePlusSettingRow("Local network", caption: localNetworkStatusMessage,
                                  controlWidth: OnePlusMetrics.wideControlColumn) {
                    VStack(alignment: .trailing, spacing: OnePlusMetrics.navRowGap) {
                        OnePlusStatus(localNetworkStatusTitle, state: localNetworkAccess.state == .allowed ? .online : .offline)
                        if localNetworkAccess.state == .denied {
                            Button("Open Settings") { localNetworkAccess.openSettings() }
                                .help("Open Local Network Settings")
                                .accessibilityLabel("Open Local Network Settings")
                        } else if localNetworkAccess.state == .unavailable {
                            Button("Try Again") { localNetworkAccess.request() }
                        }
                    }
                }
                OnePlusSettingRow("MAC addresses", caption: macAccessStatusMessage,
                                  controlWidth: OnePlusMetrics.wideControlColumn, separator: false) {
                    VStack(alignment: .trailing, spacing: OnePlusMetrics.navRowGap) {
                        OnePlusStatus(macAccessStatusTitle, state: neighborService.isEnabled ? .online : .offline)
                        if !neighborService.isEnabled {
                            Button(macAccessActionTitle) { neighborService.enable() }
                        }
                    }
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Data")
                OnePlusSettingRow("Network history", caption: "Remove saved uptime, transition, and IP scan records from this Mac.") {
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
    currentState: NetworkReachability = .unknown,
    currentNetwork: String? = nil
) -> [NetworkAvailabilitySummary] {
    let orderedEvents = events.filter { $0.date <= end }.sorted { $0.date < $1.date }
    var state = NetworkReachability.unknown
    var network: String?
    var cursor = start
    var segments: [NetworkAvailabilitySegment] = []
    let lastInternet = orderedEvents.last { event in
        event.changes.contains { if case .internet = $0 { true } else { false } }
    }
    let repairDate = currentState == .unknown ? nil : orderedEvents.last { event in
        guard let lastInternet, event.date > lastInternet.date else { return false }
        return event.changes.contains { if case .network = $0 { true } else { false } }
    }?.date

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

        if event.date >= start {
            if network == nil {
                network = connectedName(networkChange?.0)
                    ?? connectedName(event.ssid)
                    ?? (event.networkID == "disconnected" ? nil : event.displayName)
            }
            if state == .unknown, let internetChange { state = internetChange.0 }
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
        if let internetChange { state = internetChange.1 }
        if event.date == repairDate {
            state = currentState
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
    let events: [NetworkTransitionEvent]
    let range: TimeInterval
    let currentState: NetworkReachability
    let currentNetwork: String?

    var body: some View {
        let end = Date()
        let start = end.addingTimeInterval(-range)
        let summaries = networkAvailabilitySummaries(
            events: events,
            from: start,
            to: end,
            currentState: currentState,
            currentNetwork: currentNetwork
        )
        let outages = summaries.flatMap(\.outages).sorted { $0.start > $1.start }

        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            if summaries.isEmpty {
                OnePlusEmptyState("No uptime data", systemImage: "clock",
                                  caption: "Network uptime appears after the helper records a network change.")
            } else {
                ForEach(summaries, id: \.network) { summary in
                    if summary.network != summaries.first?.network { OnePlusRule() }
                    VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                        HStack(alignment: .firstTextBaseline, spacing: OnePlusMetrics.actionSpacing) {
                            Text(summary.network)
                                .onePlusText(.row).lineLimit(1).help(summary.network)
                            Spacer()
                            Text(summaryLabel(summary))
                                .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                        }
                        availabilityBar(summary, from: start)
                    }
                }
                HStack {
                    Text(startLabel(start))
                    Spacer()
                    Text("Now")
                }
                .onePlusText(.caption).foregroundStyle(OnePlusColor.muted)
            }

            HStack(spacing: OnePlusMetrics.cardGap) {
                Label("Online", systemImage: "circle.fill").foregroundStyle(OnePlusColor.chartSeries[1])
                Label("Unavailable", systemImage: "circle.fill").foregroundStyle(OnePlusColor.warn)
                Label("Inactive or no data", systemImage: "circle").foregroundStyle(OnePlusColor.muted)
                Spacer()
            }
            .onePlusText(.caption)

            if !outages.isEmpty {
                OnePlusRule()
                Text("Recent outages").onePlusText(.cardTitle)
                ForEach(outages.prefix(4)) { outage in
                    if outage.id != outages.first?.id { OnePlusRule() }
                    HStack(alignment: .top, spacing: OnePlusMetrics.navIconGap) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(OnePlusColor.warn)
                        VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                            Text(outage.end == end
                                ? "\(outage.network) has been unavailable for \(durationLabel(outage.duration))"
                                : "\(outage.network) was unavailable for \(durationLabel(outage.duration))")
                                .onePlusText(.row)
                            Text(outageTimeLabel(outage, ongoing: outage.end == end))
                                .onePlusText(.caption).foregroundStyle(OnePlusColor.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Network uptime by network name")
    }

    private func availabilityBar(
        _ summary: NetworkAvailabilitySummary,
        from start: Date
    ) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(OnePlusColor.field))
            for segment in summary.segments {
                let rect = CGRect(x: size.width * segment.start.timeIntervalSince(start) / range,
                                  y: 0, width: max(1, size.width * segment.duration / range), height: size.height)
                context.fill(Path(rect), with: .color(color(for: segment.state)))
            }
        }
        .frame(height: OnePlusMetrics.navPadding)
        .clipShape(RoundedRectangle(cornerRadius: OnePlusMetrics.segmentRadius))
        .accessibilityElement()
        .accessibilityLabel(summary.network)
        .accessibilityValue(summaryLabel(summary))
    }

    private func startLabel(_ date: Date) -> String {
        range <= NetToysHistoryRange.day.rawValue
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    private func summaryLabel(_ summary: NetworkAvailabilitySummary) -> String {
        guard let uptime = summary.uptime else { return "No availability data" }
        let outageText = summary.outages.count == 1 ? "1 outage" : "\(summary.outages.count) outages"
        return "\(uptime.formatted(.percent.precision(.fractionLength(1)))) uptime  ·  \(outageText)  ·  \(durationLabel(summary.unavailableDuration)) down"
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        guard duration >= 1 else { return "0 secs" }
        return Duration.seconds(max(1, duration.rounded()))
            .formatted(.units(
                allowed: [.hours, .minutes, .seconds],
                width: .abbreviated,
                maximumUnitCount: 2
            ))
    }

    private func outageTimeLabel(_ outage: NetworkAvailabilitySegment, ongoing: Bool) -> String {
        let start = outage.start.formatted(date: .abbreviated, time: .shortened)
        return ongoing
            ? "Since \(start)"
            : "\(start) to \(outage.end.formatted(date: .omitted, time: .shortened))"
    }

    private func color(for state: NetworkReachability) -> Color {
        switch state {
        case .reachable: OnePlusColor.chartSeries[1]
        case .unreachable: OnePlusColor.warn
        case .unknown: OnePlusColor.field
        }
    }
}
