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

@Observable
@MainActor
final class NetToysHistoryViewModel {
    var history = NetToysConfigurationStore.history()
    var helperStatus = NetToysConfigurationStore.status()
    var range = NetToysHistoryRange.day
    var searchText = ""
    var recordsHistory = NetToysConfigurationStore.load().recordsNetworkHistory
    var scanArchive = NetToysScannerStore.archive()
    var errorMessage: String?
    var locationAuthorizationStatus: CLAuthorizationStatus

    @ObservationIgnored private let locationManager: CLLocationManager

    init() {
        let locationManager = CLLocationManager()
        self.locationManager = locationManager
        locationAuthorizationStatus = locationManager.authorizationStatus
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

    func refresh() {
        history = NetToysConfigurationStore.history()
        helperStatus = NetToysConfigurationStore.status()
        recordsHistory = NetToysConfigurationStore.load().recordsNetworkHistory
        scanArchive = NetToysScannerStore.archive()
        locationAuthorizationStatus = locationManager.authorizationStatus
    }

    func requestSSIDAccessIfNeeded() {
        guard locationAuthorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
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
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
                Text("INTERNET AVAILABILITY").utilitySectionHeader()
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
                NetworkTransitionGraph(
                    events: model.history.events,
                    range: model.range.rawValue,
                    currentState: model.helperStatus?.network?.internet ?? .unknown
                )
                    .frame(height: 130)
                HStack(spacing: 14) {
                    Label("Reachable", systemImage: "circle.fill").foregroundStyle(.green)
                    Label("Unavailable", systemImage: "circle.fill").foregroundStyle(.orange)
                    Label("No data", systemImage: "circle.fill").foregroundStyle(.secondary)
                    Spacer()
                    Text("State between recorded transitions is inferred.")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10))
            }
            .utilitySectionCard()
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TRANSITIONS").utilitySectionHeader()
                Spacer()
                SearchField(text: $model.searchText, placeholder: "Find network or state")
                    .frame(width: 240)
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
        switch model.locationAuthorizationStatus {
        case .denied, .restricted:
            return "Allow Location access in System Settings to label Wi-Fi history with the network name."
        case .authorized, .authorizedAlways:
            return "The Wi-Fi network name is not available from the background helper."
        default:
            return "Allow Location access to label Wi-Fi history with the network name."
        }
    }
}

nonisolated func internetAvailabilityTimeline(
    events: [NetworkTransitionEvent],
    from start: Date,
    to end: Date,
    currentState: NetworkReachability = .unknown
) -> [(date: Date, state: NetworkReachability)] {
    var state = NetworkReachability.unknown
    var baselineDate = Date.distantPast
    var transitions: [(date: Date, from: NetworkReachability, to: NetworkReachability)] = []
    for event in events where event.date <= end {
        for change in event.changes {
            if case .internet(let from, let to) = change {
                if event.date < start, event.date > baselineDate {
                    baselineDate = event.date
                    state = to
                } else if event.date >= start {
                    transitions.append((event.date, from, to))
                }
            }
        }
    }
    transitions.sort { $0.date < $1.date }
    guard let lastTransition = transitions.last else {
        return state == .unknown ? [] : [(start, state), (end, state)]
    }

    var points = [(date: start, state: state)]
    for transition in transitions {
        points.append((transition.date, state))
        if state != transition.from {
            state = transition.from
            points.append((transition.date, state))
        }
        if state != transition.to {
            state = transition.to
            points.append((transition.date, state))
        }
    }
    if currentState != .unknown,
       state != currentState,
       let networkDate = events.filter({ event in
           event.date > lastTransition.date && event.date <= end && event.changes.contains {
               if case .network = $0 { return true }
               return false
           }
       }).map(\.date).max() {
        points.append((networkDate, state))
        state = currentState
        points.append((networkDate, state))
    }
    points.append((end, state))
    return points
}

private struct NetworkTransitionGraph: View {
    let events: [NetworkTransitionEvent]
    let range: TimeInterval
    let currentState: NetworkReachability

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 8, y: 8, width: max(1, size.width - 16), height: max(1, size.height - 32))
            let end = Date()
            let cutoff = end.addingTimeInterval(-range)
            let points = internetAvailabilityTimeline(
                events: events,
                from: cutoff,
                to: end,
                currentState: currentState
            )
            let reachableY = plot.minY + 8
            let unknownY = plot.midY
            let unavailableY = plot.maxY - 8
            for y in [reachableY, unknownY, unavailableY] {
                context.stroke(
                    Path(CGRect(x: plot.minX, y: y, width: plot.width, height: 0)),
                    with: .color(.secondary.opacity(0.2))
                )
            }
            context.draw(
                Text(startLabel(cutoff)).font(.system(size: 10)).foregroundStyle(.tertiary),
                at: CGPoint(x: plot.minX, y: size.height - 5),
                anchor: .leading
            )
            context.draw(
                Text("Now").font(.system(size: 10)).foregroundStyle(.tertiary),
                at: CGPoint(x: plot.maxX, y: size.height - 5),
                anchor: .trailing
            )
            guard !points.isEmpty else {
                context.draw(
                    Text("No Internet changes in this range").font(.system(size: 11)).foregroundStyle(.secondary),
                    at: CGPoint(x: plot.midX, y: plot.midY)
                )
                return
            }
            func point(_ value: (date: Date, state: NetworkReachability)) -> CGPoint {
                let elapsed = value.date.timeIntervalSince(cutoff)
                let x = plot.minX + plot.width * min(max(elapsed / range, 0), 1)
                let y = switch value.state {
                case .reachable: reachableY
                case .unreachable: unavailableY
                case .unknown: unknownY
                }
                return CGPoint(x: x, y: y)
            }
            for (value, nextValue) in zip(points, points.dropFirst()) {
                let current = point(value)
                let next = point(nextValue)
                var horizontal = Path()
                horizontal.move(to: current)
                horizontal.addLine(to: CGPoint(x: next.x, y: current.y))
                context.stroke(
                    horizontal,
                    with: .color(color(for: value.state)),
                    style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                )
                if current.y != next.y {
                    var vertical = Path()
                    vertical.move(to: CGPoint(x: next.x, y: current.y))
                    vertical.addLine(to: next)
                    context.stroke(vertical, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2))
                }
            }
            for value in points.dropFirst().dropLast() {
                let center = point(value)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                    with: .color(color(for: value.state))
                )
            }
        }
        .accessibilityLabel("Internet availability transitions")
    }

    private func startLabel(_ date: Date) -> String {
        range <= NetToysHistoryRange.day.rawValue
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    private func color(for state: NetworkReachability) -> Color {
        switch state {
        case .reachable: .green
        case .unreachable: .orange
        case .unknown: .secondary
        }
    }
}
