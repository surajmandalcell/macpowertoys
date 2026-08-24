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
                Text("AVAILABILITY CHANGES").utilitySectionHeader()
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
                NetworkTransitionGraph(events: Array(model.visibleEvents.reversed()), range: model.range.rawValue)
                    .frame(height: 130)
                HStack(spacing: 14) {
                    Label("Reachable", systemImage: "circle.fill").foregroundStyle(.green)
                    Label("Unavailable", systemImage: "circle.fill").foregroundStyle(.orange)
                    Spacer()
                    Text("Transitions are stored. Continuous samples are not stored.")
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

private struct NetworkTransitionGraph: View {
    let events: [NetworkTransitionEvent]
    let range: TimeInterval

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 8, y: 8, width: max(1, size.width - 16), height: max(1, size.height - 16))
            context.stroke(Path(CGRect(x: plot.minX, y: plot.midY, width: plot.width, height: 0)), with: .color(.secondary.opacity(0.25)))
            let cutoff = Date().addingTimeInterval(-range)
            var points: [(Date, Bool)] = []
            for event in events where event.date >= cutoff {
                for change in event.changes {
                    switch change {
                    case .internet(let from, let to):
                        points.append((event.date.addingTimeInterval(-0.01), from == .reachable))
                        points.append((event.date, to == .reachable))
                    case .network(_, let to) where to == "disconnected":
                        points.append((event.date, false))
                    default:
                        break
                    }
                }
            }
            guard !points.isEmpty else {
                context.draw(
                    Text("No transitions in this range").font(.system(size: 11)).foregroundStyle(.secondary),
                    at: CGPoint(x: plot.midX, y: plot.midY)
                )
                return
            }
            func point(_ value: (Date, Bool)) -> CGPoint {
                let elapsed = value.0.timeIntervalSince(cutoff)
                let x = plot.minX + plot.width * min(max(elapsed / range, 0), 1)
                return CGPoint(x: x, y: value.1 ? plot.minY + 8 : plot.maxY - 8)
            }
            var path = Path()
            path.move(to: point(points[0]))
            for value in points.dropFirst() {
                let next = point(value)
                path.addLine(to: CGPoint(x: next.x, y: path.currentPoint?.y ?? next.y))
                path.addLine(to: next)
            }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            for value in points {
                let center = point(value)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(value.1 ? .green : .orange))
            }
        }
        .accessibilityLabel("Internet availability transitions")
    }
}
