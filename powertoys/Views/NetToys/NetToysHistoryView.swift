import AppKit
import CoreLocation
import Observation
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
        if requestFailed || status == .denied {
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
    var history = NetToysConfigurationStore.history()
    var helperStatus = NetToysConfigurationStore.status()
    var range = NetToysHistoryRange.day
    var searchText = ""
    var recordsHistory = NetToysConfigurationStore.load().recordsNetworkHistory
    var scanArchive = NetToysScannerStore.archive()
    var errorMessage: String?
    var locationAuthorizationStatus: CLAuthorizationStatus
    var locationRequestFailed = false

    @ObservationIgnored private let locationManager: CLLocationManager

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

    func refresh() {
        history = NetToysConfigurationStore.history()
        helperStatus = NetToysConfigurationStore.status()
        recordsHistory = NetToysConfigurationStore.load().recordsNetworkHistory
        scanArchive = NetToysScannerStore.archive()
        locationAuthorizationStatus = locationManager.authorizationStatus
    }

    func requestSSIDAccessIfNeeded() {
        locationAuthorizationStatus = locationManager.authorizationStatus
        guard !locationRequestFailed else { return }
        guard locationAuthorizationStatus == .notDetermined else { return }
        guard NSApp.isActive else { return }
        requestLocationAccess()
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
            refresh()
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
                ISO8601DateFormatter().string(from: event.date),
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
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NetToys Scan \(run.date.formatted(.iso8601)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try NetToysScanExport.csv(run.results).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
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

    var body: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(
                title: "Network History",
                subtitle: model.helperStatus?.network?.displayName ?? "Waiting for the helper"
            ) {
                Toggle("", isOn: Binding(
                    get: { model.recordsHistory },
                    set: { model.setRecordsHistory($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Record network history")

                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
                    currentStatus
                    availabilityGraph
                    recentScans
                    eventList
                }
                .padding(.horizontal, UtilityLayout.horizontalInset)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScrollIndicators()
        }
        .task {
            model.requestSSIDAccessIfNeeded()
            while !Task.isCancelled {
                model.refresh()
                model.requestSSIDAccessIfNeeded()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.requestSSIDAccessIfNeeded()
        }
        .confirmationDialog("Clear network history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clear() }
        } message: {
            Text("This removes the stored transition records from this Mac.")
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
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT STATUS").utilitySectionHeader()
            HStack(spacing: 10) {
                statusCard(
                    title: "Gateway",
                    state: model.helperStatus?.network?.gateway ?? .unknown,
                    symbol: "router"
                )
                statusCard(
                    title: "Internet",
                    state: model.helperStatus?.network?.internet ?? .unknown,
                    symbol: "globe"
                )
                VStack(alignment: .leading, spacing: 4) {
                    Label("Network", systemImage: "network")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(model.helperStatus?.network?.displayName ?? "Unknown")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                    Text(model.helperStatus?.network?.checkedAt.formatted(date: .omitted, time: .standard) ?? "Not checked")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .utilitySectionCard()
            }
            if let message = ssidAccessMessage {
                HStack(spacing: 8) {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let title = ssidAccessActionTitle {
                        Button(title) {
                            model.resolveSSIDAccess(
                                forceSettings: model.helperSSIDUnavailable
                                    || model.helperStatus?.ssidAccess != nil
                                    && model.helperStatus?.ssidAccess != .allowed
                            )
                        }
                            .controlSize(.small)
                    }
                }
                .font(.system(size: 11))
            }
        }
    }

    private func statusCard(title: String, state: NetworkReachability, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: state))
                    .frame(width: 7, height: 7)
                Text(state.rawValue.capitalized)
                    .font(.system(size: 13, weight: .medium))
            }
            Text("Updated by NetToys Helper")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .utilitySectionCard()
    }

    private var availabilityGraph: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NETWORK UPTIME").utilitySectionHeader()
                Spacer()
                Picker("Range", selection: $model.range) {
                    ForEach(NetToysHistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 110)
            }

            VStack(alignment: .leading, spacing: 8) {
                NetworkUptimeTimeline(
                    events: model.history.events,
                    range: model.range.rawValue,
                    currentState: model.helperStatus?.network?.internet ?? .unknown,
                    currentNetwork: model.helperStatus?.network.map {
                        $0.ssid ?? $0.displayName
                    }
                )
            }
            .utilitySectionCard()
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TRANSITIONS").utilitySectionHeader()
                Spacer()
                NativeSearchField(text: $model.searchText, placeholder: "Find network or state")
                    .frame(width: 240)
                    .frame(height: UtilityLayout.workspaceActionHeight)
                Button("Export") { model.export() }
                    .disabled(model.visibleEvents.isEmpty)
                Button("Clear", role: .destructive) { confirmClear = true }
                    .disabled(model.history.events.isEmpty)
            }
            .controlSize(.small)

            if model.visibleEvents.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(model.recordsHistory
                        ? "No network state changes are recorded in this range."
                        : "Network history recording is off.")
                        .foregroundStyle(.secondary)
                }
                .utilitySectionCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.visibleEvents.enumerated()), id: \.element.date) { index, event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: event.changes.contains(where: isOutage) ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(event.changes.contains(where: isOutage) ? .orange : .green)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.changes.map(NetToysHistoryViewModel.description).joined(separator: " · "))
                                    .font(.system(size: 12, weight: .medium))
                                Text(event.displayName)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.date.formatted(date: .abbreviated, time: .standard))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                        if index < model.visibleEvents.count - 1 { QuietDivider() }
                    }
                }
                .utilitySectionCard()
            }
        }
    }

    private var recentScans: some View {
        let runs = scanArchiveRuns
        return VStack(alignment: .leading, spacing: 8) {
            Text("RECENT IP SCANS").utilitySectionHeader()
            if runs.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                    Text("Completed IP Scanner runs appear here.")
                        .foregroundStyle(.secondary)
                }
                .utilitySectionCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                        HStack(spacing: 10) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.tint)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.target)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(run.results.count) results  ·  \(run.results.filter(\.isReachable).count) alive  ·  ports \(run.ports.map(String.init).joined(separator: ", "))  ·  \(run.duration.formatted(.number.precision(.fractionLength(1)))) s")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Button("Export") { model.export(run) }
                            Button("Scan Again") {
                                NotificationCenter.default.post(name: .netToysRescanRun, object: run)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .controlSize(.small)
                        .padding(.vertical, 6)
                        if index < runs.count - 1 { QuietDivider() }
                    }
                }
                .utilitySectionCard()
            }
        }
    }

    private var scanArchiveRuns: [NetToysScanRun] {
        let cutoff = Date().addingTimeInterval(-model.range.rawValue)
        return Array(model.scanArchive.runs.reversed().filter { $0.date >= cutoff }.prefix(10))
    }

    private func color(for state: NetworkReachability) -> Color {
        switch state {
        case .reachable: .green
        case .unreachable: .orange
        case .unknown: .secondary
        }
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
    @State private var localNetworkAccess = NetToysLocalNetworkAccess.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("WI-FI NETWORK NAMES").utilitySectionHeader()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label("Location Access", systemImage: locationStatusSymbol)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(locationStatusTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(locationStatusColor)
                    }

                    Text(locationStatusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let title = locationActionTitle {
                        Button(title) { model.resolveSSIDAccess(forceSettings: helperNeedsAccess) }
                            .controlSize(.small)
                    }
                }
                .utilitySectionCard()

                Text("LOCAL NETWORK").utilitySectionHeader()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label("Local Network Access", systemImage: localNetworkStatusSymbol)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(localNetworkStatusTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(localNetworkStatusColor)
                    }

                    Text(localNetworkStatusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if localNetworkAccess.state == .denied {
                        Button("Open Local Network Settings") { localNetworkAccess.openSettings() }
                            .controlSize(.small)
                    } else if localNetworkAccess.state == .unavailable {
                        Button("Try Again") { localNetworkAccess.request() }
                            .controlSize(.small)
                    }
                }
                .utilitySectionCard()

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        }
        .thinScrollIndicators()
        .task {
            model.refresh()
            model.requestSSIDAccessIfNeeded()
            localNetworkAccess.request()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
            model.requestSSIDAccessIfNeeded()
            localNetworkAccess.request()
        }
    }

    private var localNetworkStatusTitle: String {
        switch localNetworkAccess.state {
        case .checking: "Checking"
        case .allowed: "Allowed"
        case .denied: "Needs Attention"
        case .unavailable: "Unavailable"
        }
    }

    private var localNetworkStatusMessage: String {
        switch localNetworkAccess.state {
        case .checking:
            "Respond to the macOS prompt so IP Scanner can discover local devices."
        case .allowed:
            "Local Network access is allowed. Device MAC addresses remain restricted by macOS."
        case .denied:
            "Allow MacPowerToys in Privacy & Security > Local Network to scan local devices."
        case .unavailable:
            "macOS could not check Local Network access. Check the network and try again."
        }
    }

    private var localNetworkStatusSymbol: String {
        switch localNetworkAccess.state {
        case .allowed: "checkmark.circle.fill"
        case .denied: "exclamationmark.triangle.fill"
        case .checking: "network"
        case .unavailable: "questionmark.circle"
        }
    }

    private var localNetworkStatusColor: Color {
        switch localNetworkAccess.state {
        case .allowed: .green
        case .denied: .orange
        case .checking, .unavailable: .secondary
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

    private var locationStatusSymbol: String {
        if helperNeedsAccess { return "exclamationmark.triangle.fill" }
        if model.locationRequestFailed { return "exclamationmark.triangle.fill" }
        return switch model.locationAuthorizationStatus {
        case .authorized, .authorizedAlways: "checkmark.circle.fill"
        case .denied, .restricted: "exclamationmark.triangle.fill"
        default: "location.circle"
        }
    }

    private var locationStatusColor: Color {
        if helperNeedsAccess { return .orange }
        if model.locationRequestFailed { return .orange }
        return switch model.locationAuthorizationStatus {
        case .authorized, .authorizedAlways: .green
        case .denied, .restricted: .orange
        default: .secondary
        }
    }

    private var helperNeedsAccess: Bool {
        guard let state = model.helperStatus?.ssidAccess else { return false }
        return state != .allowed || model.helperSSIDUnavailable
    }
}

nonisolated struct NetworkAvailabilitySegment: Equatable, Sendable {
    let network: String
    let state: NetworkReachability
    let start: Date
    let end: Date

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

        VStack(alignment: .leading, spacing: 12) {
            if summaries.isEmpty {
                Label("No network uptime data in this range.", systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            } else {
                ForEach(Array(summaries.enumerated()), id: \.element.network) { index, summary in
                    if index > 0 { QuietDivider() }
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(summary.network)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(summaryLabel(summary))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        availabilityBar(summary, from: start)
                    }
                }
                HStack {
                    Text(startLabel(start))
                    Spacer()
                    Text("Now")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            HStack(spacing: 14) {
                Label("Online", systemImage: "circle.fill").foregroundStyle(.green)
                Label("Unavailable", systemImage: "circle.fill").foregroundStyle(.orange)
                Label("Inactive or no data", systemImage: "circle.fill").foregroundStyle(.secondary)
                Spacer()
            }
            .font(.system(size: 10))

            if !outages.isEmpty {
                QuietDivider()
                Text("RECENT OUTAGES").utilitySectionHeader()
                ForEach(Array(outages.prefix(4).enumerated()), id: \.offset) { index, outage in
                    if index > 0 { QuietDivider() }
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outage.end == end
                                ? "\(outage.network) has been unavailable for \(durationLabel(outage.duration))"
                                : "\(outage.network) was unavailable for \(durationLabel(outage.duration))")
                                .font(.system(size: 11, weight: .medium))
                            Text(outageTimeLabel(outage, ongoing: outage.end == end))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
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
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.16))
                ForEach(Array(summary.segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: segment.state))
                        .frame(width: max(1, geometry.size.width * segment.duration / range))
                        .offset(x: geometry.size.width * segment.start.timeIntervalSince(start) / range)
                }
            }
        }
        .frame(height: 10)
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
        case .reachable: .green
        case .unreachable: .orange
        case .unknown: .secondary
        }
    }
}
