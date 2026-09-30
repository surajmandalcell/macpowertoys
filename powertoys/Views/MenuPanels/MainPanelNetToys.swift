import OnePlusUI
import SwiftUI

struct NetToysTraySnapshot: Sendable {
    var configuration = NetToysConfiguration()
    var helperStatus: NetToysHelperStatus?
    var recentAnchors: [SSHAnchorConfiguration] = []
    var recentIssues: [NetworkTransitionEvent] = []
    var route: DefaultRoute?
    var localNetwork: LocalIPv4Network?
    var ssid: String?
    var isWiFi = false
    var gatewayMilliseconds: Double?
    var isLoaded = false

    nonisolated static func load() async -> Self {
        var result = await Task.detached(priority: .utility) {
            let configuration = NetToysConfigurationStore.load()
            let status = NetToysConfigurationStore.status()
            return Self(configuration: configuration, helperStatus: status,
                        recentAnchors: TrayPopoverLayout.recentAnchors(configuration.anchors, statuses: status?.anchors ?? []),
                        recentIssues: TrayPopoverLayout.recentNetworkIssues(NetToysConfigurationStore.history().events),
                        isLoaded: true)
        }.value
        guard !Task.isCancelled else { return result }
        let routeData = try? await TailscalePeerCatalog.runStatusCommand(
            executableURL: URL(fileURLWithPath: "/sbin/route"), arguments: ["-n", "get", "default"],
            maximumOutputBytes: 8_192, timeout: 2
        )
        guard !Task.isCancelled else { return result }
        result.route = routeData.flatMap { DefaultRoute.parse(String(decoding: $0, as: UTF8.self)) }
        if let route = result.route {
            let local = await Task.detached(priority: .utility) {
                (LocalIPv4Network.active(preferredInterfaceName: route.interfaceName),
                 NetworkSSID.current(interfaceName: route.interfaceName),
                 NetworkSSID.isWiFi(interfaceName: route.interfaceName))
            }.value
            result.localNetwork = local.0?.interfaceName == route.interfaceName ? local.0 : nil
            result.ssid = local.1
            result.isWiFi = local.2
            guard !Task.isCancelled else { return result }
            let ping = try? await TailscalePeerCatalog.runStatusCommand(
                executableURL: URL(fileURLWithPath: "/sbin/ping"), arguments: ["-n", "-c", "1", "-W", "1000", route.gateway],
                environment: ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new },
                maximumOutputBytes: 8_192, timeout: 2
            )
            result.gatewayMilliseconds = ping.flatMap { PingProbe.parse(String(decoding: $0, as: UTF8.self))?.averageMilliseconds }
        }
        return result
    }
}

struct NetToysTrayView: View {
    @Binding var snapshot: NetToysTraySnapshot
    @Environment(\.onePlusIsVisible) private var isVisible
    @State private var loading = false
    @State private var refreshRequest = UUID()

    private var configuration: NetToysConfiguration {
        get { snapshot.configuration }
        nonmutating set { snapshot.configuration = newValue }
    }
    @State private var errorMessage: String?
    @AppStorage("tray.nettoys.anchor.expanded") private var anchorExpanded = false
    @AppStorage("tray.nettoys.wifi.expanded") private var wifiExpanded = false
    @AppStorage("tray.nettoys.history.expanded") private var historyExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToolHeader(tab: .netToys)
            VStack(spacing: OnePlusMenuMetrics.tileGap) {
                networkTiles
                OnePlusMenuSectionHeader("Network controls", actionTitle: "Refresh", compactAction: true) {
                    refreshRequest = UUID()
                }
                .disabled(loading)
                activitySection(
                    title: "SSH Anchor",
                    detail: configuration.anchors.isEmpty
                        ? "No configured anchors"
                        : "\(configuration.monitoredAnchors.count) of \(configuration.anchors.count) active",
                    symbol: "link",
                    isOn: Binding(
                        get: { configuration.sshAnchorEnabled },
                        set: { configuration.sshAnchorEnabled = $0; save() }
                    ),
                    disabled: configuration.anchors.isEmpty,
                    isExpanded: $anchorExpanded
                ) {
                    if snapshot.recentAnchors.isEmpty {
                        emptyActivity("No anchors to show")
                    } else {
                        ForEach(snapshot.recentAnchors) { anchor in
                            anchorRow(anchor)
                        }
                    }
                    openPageButton("Open all anchors", page: .anchor)
                }
                activitySection(
                    title: "Wi-Fi Priority",
                    detail: "\(configuration.wifiPriority.ssids.count) saved networks",
                    symbol: "wifi",
                    isOn: Binding(
                        get: { configuration.wifiPriority.isEnabled },
                        set: {
                            configuration.wifiPriority.isEnabled = $0
                                && configuration.wifiPriority.ssids.count >= 2
                            save()
                        }
                    ),
                    disabled: configuration.wifiPriority.ssids.count < 2,
                    isExpanded: $wifiExpanded
                ) {
                    if configuration.wifiPriority.ssids.isEmpty {
                        emptyActivity("No priority networks")
                    } else {
                        ForEach(Array(configuration.wifiPriority.ssids.prefix(5).enumerated()), id: \.offset) { index, ssid in
                            activityRow(
                                symbol: snapshot.helperStatus?.network?.ssid == ssid ? "wifi" : "line.3.horizontal",
                                title: ssid,
                                detail: snapshot.helperStatus?.network?.ssid == ssid ? "Connected" : "Priority \(index + 1)"
                            )
                        }
                    }
                    openPageButton("Open Wi-Fi Priority", page: .wifiPriority)
                }
                activitySection(
                    title: "Network History",
                    detail: configuration.recordsNetworkHistory ? "Recording changes" : "Not recording",
                    symbol: "chart.xyaxis.line",
                    isOn: Binding(
                        get: { configuration.recordsNetworkHistory },
                        set: { configuration.recordsNetworkHistory = $0; save() }
                    ),
                    isExpanded: $historyExpanded
                ) {
                    if snapshot.recentIssues.isEmpty {
                        emptyActivity("No recent network issues")
                    } else {
                        ForEach(Array(snapshot.recentIssues.enumerated()), id: \.offset) { _, event in
                            activityRow(
                                symbol: "exclamationmark.circle",
                                title: event.displayName,
                                detail: event.changes.map(NetToysHistoryViewModel.description).joined(separator: " · ")
                            )
                        }
                    }
                    openPageButton("Open Network History", page: .history)
                }
            }
            .disabled(!snapshot.isLoaded)
            if let errorMessage {
                Text(errorMessage)
                    .onePlusText(.caption, color: OnePlusColor.danger)
                    .padding(.top, OnePlusMenuMetrics.tileGap)
            }
        }
        .task(id: isVisible ? refreshRequest : nil) {
            guard isVisible else { loading = false; return }
            await refresh()
        }
    }

    private var helperDetail: String {
        guard let status = snapshot.helperStatus else { return "Background helper is not reporting" }
        return "Updated \(status.heartbeat.formatted(date: .omitted, time: .shortened))"
    }

    private var networkTiles: some View {
        let identity = NetworkIdentity(networkID: snapshot.route?.networkID ?? "disconnected", ssid: snapshot.ssid)
        let networkName = snapshot.isLoaded
            ? (snapshot.route == nil ? "Unavailable" : identity.displayName)
            : "Loading…"
        return VStack(spacing: OnePlusMenuMetrics.tileGap) {
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                OnePlusMenuTile(span: 2) {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.navRowGap) {
                        Label("Current network", systemImage: "network").onePlusText(.caption)
                        Text(networkName)
                            .onePlusText(.cardTitle, color: OnePlusColor.dataBlue).lineLimit(1).help(networkName)
                        if snapshot.isWiFi && identity.ssid == nil {
                            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                                Text("Name unavailable").onePlusText(.caption).lineLimit(1)
                                Button("Location access") { open(.settings) }
                                    .buttonStyle(OnePlusButtonStyle(.link, size: .small, horizontalPadding: 0))
                                    .accessibilityLabel("Manage Wi-Fi Location access in NetToys")
                                    .help("Open NetToys Location status and recovery actions")
                            }
                        } else {
                            Text(helperDetail).onePlusText(.caption).lineLimit(1)
                        }
                    }
                }
                if identity.ssid == nil {
                    networkTile("Connection", value: snapshot.route == nil ? "—" : snapshot.isWiFi ? "Wi-Fi" : "Active route", detail: reachability)
                } else {
                    networkTile("Interface", value: snapshot.route?.interfaceName ?? "—", detail: reachability)
                }
            }
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                networkTile("Local IP", value: snapshot.localNetwork?.address.description ?? "—", detail: "IPv4", span: 2)
                networkTile("Gateway", value: snapshot.gatewayMilliseconds.map {
                    $0.formatted(.number.precision(.fractionLength(1))) + " ms"
                } ?? (snapshot.route == nil ? "—" : "No reply"), detail: snapshot.route?.gateway ?? "—")
            }
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                Button("Scan network", systemImage: "magnifyingglass") {
                    open(.scanner)
                }
                Button("Copy IP", systemImage: "doc.on.doc") {
                    if let address = snapshot.localNetwork?.address.description {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(address, forType: .string)
                    }
                }
                .disabled(snapshot.localNetwork == nil)
                Spacer(minLength: 0)
            }
            .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
        }
    }

    private func networkTile(_ title: String, value: String, detail: String, span: Int = 1) -> some View {
        OnePlusMenuTile(span: span) {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                Text(title).onePlusText(.caption)
                Text(value).onePlusText(.cardTitle, color: OnePlusColor.dataBlue).lineLimit(1).help(value)
                Text(detail).onePlusText(.caption).lineLimit(1)
            }
        }
    }

    private var reachability: String {
        guard snapshot.helperStatus?.network?.networkID == snapshot.route?.networkID else { return "Unknown" }
        return switch snapshot.helperStatus?.network?.internet {
        case .reachable: "Online"
        case .unreachable: "Offline"
        default: "Unknown"
        }
    }

    private func refresh() async {
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        let savedConfiguration = configuration
        var result = await NetToysTraySnapshot.load()
        guard !Task.isCancelled else { return }
        if configuration != savedConfiguration { result.configuration = configuration }
        snapshot = result
    }

    private func activitySection<Content: View>(
        title: String,
        detail: String,
        symbol: String,
        isOn: Binding<Bool>,
        disabled: Bool = false,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        OnePlusMenuCard {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button { isExpanded.wrappedValue.toggle() } label: {
                        HStack(spacing: 9) {
                            Image(systemName: symbol)
                                .onePlusText(.row, color: OnePlusColor.secondary)
                                .frame(width: OnePlusMetrics.compactControlHeight)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).onePlusText(.row)
                                Text(detail).onePlusText(.caption).lineLimit(1).help(detail)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .onePlusText(.caption)
                                .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        }
                        .padding(.horizontal, TrayPopoverLayout.netToysDisclosureHorizontalPadding)
                        .padding(.vertical, TrayPopoverLayout.netToysDisclosureVerticalPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.controlRadius))
                    .accessibilityLabel("\(isExpanded.wrappedValue ? "Hide" : "Show") \(title) activity")
                    Toggle(title, isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(OnePlusSwitchStyle())
                        .disabled(disabled)
                }
                if isExpanded.wrappedValue {
                    VStack(spacing: 0) { content() }
                        .padding(.leading, OnePlusMetrics.compactControlHeight + OnePlusMenuMetrics.tileGap)
                        .padding(.bottom, OnePlusMenuMetrics.tileGap)
                }
            }
        }
    }

    private func anchorRow(_ anchor: SSHAnchorConfiguration) -> some View {
        let status = snapshot.helperStatus?.anchors.first { $0.anchorID == anchor.id }
        return activityRow(
            symbol: status?.state == .healthy ? "checkmark.circle" : "link",
            title: anchor.hostAlias,
            detail: status.map { "\($0.currentHostName) · \($0.lastCheck.formatted(date: .omitted, time: .shortened))" }
                ?? anchor.hostName
        )
    }

    private func activityRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .onePlusText(.caption)
                .frame(width: OnePlusMetrics.compactControlHeight)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).onePlusText(.row).lineLimit(1).help(title)
                Text(detail).onePlusText(.caption).lineLimit(1).help(detail)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, OnePlusMenuMetrics.tileGap)
    }

    private func emptyActivity(_ message: String) -> some View {
        Text(message)
            .onePlusText(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, OnePlusMenuMetrics.tileGap)
    }

    private func openPageButton(_ title: String, page: NetToysPage) -> some View {
        Button { open(page) } label: {
            Label(title, systemImage: "arrow.up.forward.square")
                .onePlusText(.caption, color: OnePlusColor.secondary)
                .frame(maxWidth: .infinity, minHeight: OnePlusMetrics.compactControlHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.controlRadius))
        .padding(.top, OnePlusMenuMetrics.tileGap)
    }

    private func open(_ page: NetToysPage) {
        ToolActionRouter.shared.open(toolID: "nettoys", page: page.pageID)
    }

    private func save() {
        do {
            try NetToysConfigurationStore.save(configuration)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
