import Observation
import OnePlusUI
import ServiceManagement
import SwiftUI

enum SSHAnchorIdentityMode: String, CaseIterable, Identifiable {
    case stable = "Stable MAC"
    case randomized = "Randomized MAC"

    var id: String { rawValue }
}

enum NetToysAnchorSheetLayout {
    static let peerPickerWidth = OnePlusSheetWidth.small.rawValue
    static let titleRowHeight = OnePlusMetrics.cardHeader
    static let peerRowHeight = OnePlusMetrics.settingRow
    static let peerRowStride = peerRowHeight
    static let peerPickerBaseHeight = titleRowHeight + OnePlusMetrics.taskManagerGutter * 2
    static let peerPickerMaximumHeight = peerPickerBaseHeight + peerRowHeight * 5

    static func peerPickerHeight(peerCount: Int) -> CGFloat {
        min(peerPickerMaximumHeight, peerPickerContentHeight(peerCount: peerCount))
    }

    static func peerPickerNeedsScrolling(peerCount: Int) -> Bool {
        peerPickerContentHeight(peerCount: peerCount) > peerPickerMaximumHeight
    }

    private static func peerPickerContentHeight(peerCount: Int) -> CGFloat {
        peerPickerBaseHeight + CGFloat(max(0, peerCount)) * peerRowStride
    }
}

@Observable
@MainActor
final class NetToysAnchorViewModel {
    private struct Snapshot: Sendable {
        let entries: [SSHConfigEntry]
        let configuration: NetToysConfiguration
        let helperStatus: NetToysHelperStatus?
    }

    var entries: [SSHConfigEntry] = []
    var selectedAlias = ""
    var identityMode = SSHAnchorIdentityMode.stable
    var deviceMAC = ""
    var deviceHostname = ""
    var configuration = NetToysConfiguration()
    var helperStatus: NetToysHelperStatus?
    var errorMessage: String?
    var isInspecting = false
    var requestedAddress: String?
    var tailscalePeers: [TailscalePeer] = []
    var pendingTailscaleAnchorID: UUID?
    var tailscaleLoadingAnchorID: UUID?
    var pendingKeyAccessAnchorID: UUID?
    var keyAccessRetryAnchorID: UUID?
    var keyAccessRunningAnchorID: UUID?
    var keyAccessRemoteKind = SSHRemoteKind.unknown
    var keyAccessErrorMessage: String?

    private let scanner = NetToysScanner()
    private var keyAccessTask: Task<Void, Never>?
    private var savedConfiguration = NetToysConfiguration()

    var selectedEntry: SSHConfigEntry? {
        guard let entry = entries.first(where: { $0.aliases.contains(selectedAlias) }) else {
            return nil
        }
        guard let requestedAddress else { return entry }
        return SSHConfigEntry(
            aliases: entry.aliases,
            hostName: requestedAddress,
            port: entry.port
        )
    }

    var helperIsHealthy: Bool {
        NetToysLoginItemManager.shared.status == .enabled
            && NetToysLoginItemManager.hasFreshHeartbeat(helperStatus)
    }

    func refresh() async {
        let snapshot = await Task.detached(priority: .utility) {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
            let entries = (try? Data(contentsOf: url)).map(SSHConfigEditor.anchorEntries(in:)) ?? []
            return Snapshot(
                entries: entries,
                configuration: NetToysConfigurationStore.load(),
                helperStatus: NetToysConfigurationStore.status()
            )
        }.value
        guard !Task.isCancelled else { return }
        entries = snapshot.entries
        configuration = snapshot.configuration
        savedConfiguration = snapshot.configuration
        helperStatus = snapshot.helperStatus
        if !entries.contains(where: { $0.aliases.contains(selectedAlias) }) {
            selectedAlias = requestedAddress == nil ? entries.first?.aliases.first ?? "" : ""
        }
    }

    func apply(_ prefill: NetToysAnchorPrefill) async {
        requestedAddress = prefill.address
        await refresh()
        selectedAlias = prefill.matchingAlias(in: entries) ?? ""
        deviceMAC = prefill.macAddress ?? ""
        deviceHostname = prefill.hostname ?? ""
        identityMode = AnchorMatcher.normalizedMAC(deviceMAC).count == 12 ? .stable : .randomized
    }

    func inspectSelectedDevice() {
        guard let entry = selectedEntry else { return }
        isInspecting = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                if let result = try await inspect(entry) {
                    deviceMAC = result.macAddress ?? ""
                    deviceHostname = result.hostname ?? ""
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isInspecting = false
        }
    }

    func enableAutomaticAnchor() {
        guard let entry = selectedEntry, let alias = entry.aliases.first else { return }
        isInspecting = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isInspecting = false }
            do {
                guard let result = try await inspect(entry),
                      result.openPorts.contains(entry.port)
                else {
                    errorMessage = "The selected SSH host is not reachable on port \(entry.port)."
                    return
                }
                deviceMAC = result.macAddress ?? ""
                deviceHostname = result.hostname ?? ""
                guard let identity = AnchorMatcher.automaticIdentity(
                    macAddress: result.macAddress,
                    hostname: result.hostname,
                    fallbackHostName: entry.hostName
                ) else {
                    errorMessage = "No stable MAC or hostname was detected. Use the manual identity fields."
                    return
                }

                var anchor = SSHAnchorConfiguration(
                    hostAlias: alias,
                    hostName: entry.hostName,
                    port: entry.port,
                    identity: identity,
                    localHostName: entry.hostName
                )
                if let index = configuration.anchors.firstIndex(where: {
                    $0.hostAlias.caseInsensitiveCompare(alias) == .orderedSame
                }) {
                    anchor.id = configuration.anchors[index].id
                    anchor.tailscaleFallback = configuration.anchors[index].tailscaleFallback
                    anchor.keyAccessVerifiedAt = configuration.anchors[index].keyAccessVerifiedAt
                    try prepareHostKeyPolicy(anchor)
                    configuration.anchors[index] = anchor
                } else {
                    try prepareHostKeyPolicy(anchor)
                    configuration.anchors.append(anchor)
                }
                configuration = try NetToysConfigurationStore.saveChanges(configuration, since: savedConfiguration)
                savedConfiguration = configuration
                guard await NetToysLoginItemManager.shared.setEnabled(true) else {
                    errorMessage = NetToysLoginItemManager.shared.errorMessage
                        ?? "The NetToys helper could not be enabled."
                    return
                }
                await refresh()
                requestedAddress = nil
                setUpKeyAccess(for: anchor.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addAnchor() {
        guard let entry = selectedEntry, let alias = entry.aliases.first else { return }
        let normalizedMAC = AnchorMatcher.normalizedMAC(deviceMAC)
        let identity: AnchorIdentity
        switch identityMode {
        case .stable:
            guard normalizedMAC.count == 12 else {
                errorMessage = "Enter the device MAC address or inspect the device first."
                return
            }
            identity = .stableMAC(normalizedMAC)
        case .randomized:
            let hostname = deviceHostname.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hostname.isEmpty || normalizedMAC.count == 12 else {
                errorMessage = "Enter a hostname or a known MAC address."
                return
            }
            identity = .randomizedMAC(
                hostname: hostname,
                learnedMACs: normalizedMAC.count == 12 ? [normalizedMAC] : []
            )
        }
        guard !configuration.anchors.contains(where: {
            $0.hostAlias.caseInsensitiveCompare(alias) == .orderedSame
        }) else {
            errorMessage = "This SSH host already has an anchor."
            return
        }
        let anchor = SSHAnchorConfiguration(
            hostAlias: alias,
            hostName: entry.hostName,
            port: entry.port,
            identity: identity,
            localHostName: entry.hostName
        )
        do {
            try prepareHostKeyPolicy(anchor)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        configuration.anchors.append(anchor)
        save()
        deviceMAC = ""
        deviceHostname = ""
        requestedAddress = nil
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = configuration.anchors.firstIndex(where: { $0.id == id }) else { return }
        configuration.anchors[index].isEnabled = enabled
        save()
    }

    func setFeatureEnabled(_ enabled: Bool) {
        configuration.sshAnchorEnabled = enabled
        save()
    }

    func tailscaleIsEnabled(for anchor: SSHAnchorConfiguration) -> Bool {
        anchor.tailscaleFallback?.isEnabled == true
    }

    func setTailscaleEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = configuration.anchors.firstIndex(where: { $0.id == id }) else { return }
        if !enabled {
            configuration.anchors[index].tailscaleFallback?.isEnabled = false
            save()
            return
        }
        let anchor = configuration.anchors[index]
        tailscaleLoadingAnchorID = id
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { tailscaleLoadingAnchorID = nil }
            do {
                let peers = try await TailscalePeerCatalog.load()
                if let nodeID = anchor.tailscaleFallback?.nodeID,
                   let endpoint = TailscalePeerCatalog.endpoint(nodeID: nodeID, peers: peers) {
                    guard let currentIndex = configuration.anchors.firstIndex(where: { $0.id == id }) else {
                        return
                    }
                    configuration.anchors[currentIndex].tailscaleFallback = endpoint
                    save()
                    return
                }
                var labels: [String] = []
                if case .randomizedMAC(let hostname, _) = anchor.identity {
                    labels.append(hostname)
                }
                if TailscalePeerCatalog.exactMatch(labels: labels, peers: peers) == nil,
                   let address = IPv4Address(anchor.hostName) {
                    let results = await scanner.scan(
                        targets: [address],
                        ports: [anchor.port],
                        timeoutMilliseconds: 600,
                        concurrency: 1
                    )
                    if let hostname = results.first?.hostname { labels.append(hostname) }
                }
                if let peer = TailscalePeerCatalog.exactMatch(labels: labels, peers: peers) {
                    applyTailscalePeer(peer, to: id)
                } else if peers.isEmpty {
                    errorMessage = "No Tailscale devices with an IPv4 address are available."
                } else {
                    tailscalePeers = peers
                    pendingTailscaleAnchorID = id
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func chooseTailscalePeer(_ peer: TailscalePeer) {
        guard let id = pendingTailscaleAnchorID else { return }
        applyTailscalePeer(peer, to: id)
        pendingTailscaleAnchorID = nil
        tailscalePeers = []
    }

    func cancelTailscaleSelection() {
        pendingTailscaleAnchorID = nil
        tailscalePeers = []
    }

    func remove(_ id: UUID) {
        configuration.anchors.removeAll { $0.id == id }
        if keyAccessRetryAnchorID == id { keyAccessRetryAnchorID = nil }
        save()
    }

    func setProbeInterval(_ value: TimeInterval) {
        configuration.probeInterval = min(max(value, 2), 3)
        save()
    }

    func status(for id: UUID) -> SSHAnchorStatus? {
        helperStatus?.anchors.first { $0.anchorID == id }
    }

    func setUpKeyAccess(for id: UUID) {
        guard let anchor = configuration.anchors.first(where: { $0.id == id }) else { return }
        keyAccessTask?.cancel()
        keyAccessRetryAnchorID = nil
        keyAccessRunningAnchorID = id
        keyAccessErrorMessage = nil
        keyAccessTask = Task { [weak self] in
            guard let self else { return }
            defer { keyAccessRunningAnchorID = nil }
            do {
                switch try await SSHKeyAccessInstaller.check(alias: anchor.hostAlias) {
                case .ready:
                    markKeyAccessVerified(id)
                case .needsPassword(let remoteKind):
                    clearKeyAccessVerification(id)
                    keyAccessRemoteKind = remoteKind
                    pendingKeyAccessAnchorID = id
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func installKeyAccess(password: String) {
        guard let id = pendingKeyAccessAnchorID,
              let anchor = configuration.anchors.first(where: { $0.id == id })
        else { return }
        keyAccessTask?.cancel()
        keyAccessRunningAnchorID = id
        keyAccessErrorMessage = nil
        let remoteKind = keyAccessRemoteKind
        keyAccessTask = Task { [weak self] in
            guard let self else { return }
            defer { keyAccessRunningAnchorID = nil }
            do {
                try await SSHKeyAccessInstaller.install(
                    alias: anchor.hostAlias,
                    password: password,
                    remoteKind: remoteKind
                )
                markKeyAccessVerified(id)
                keyAccessRetryAnchorID = nil
                pendingKeyAccessAnchorID = nil
            } catch is CancellationError {
                return
            } catch {
                keyAccessErrorMessage = error.localizedDescription
            }
        }
    }

    func cancelKeyAccess() {
        keyAccessTask?.cancel()
        keyAccessTask = nil
        keyAccessRunningAnchorID = nil
        keyAccessRetryAnchorID = pendingKeyAccessAnchorID ?? keyAccessRetryAnchorID
        pendingKeyAccessAnchorID = nil
        keyAccessErrorMessage = nil
    }

    func aliasLabel(for anchor: SSHAnchorConfiguration) -> String {
        entries.first { entry in
            entry.aliases.contains { $0.caseInsensitiveCompare(anchor.hostAlias) == .orderedSame }
        }?.aliases.joined(separator: ",") ?? anchor.hostAlias
    }

    private func save() {
        do {
            configuration = try NetToysConfigurationStore.saveChanges(configuration, since: savedConfiguration)
            savedConfiguration = configuration
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markKeyAccessVerified(_ id: UUID) {
        guard let index = configuration.anchors.firstIndex(where: { $0.id == id }) else { return }
        configuration.anchors[index].keyAccessVerifiedAt = Date()
        save()
    }

    private func clearKeyAccessVerification(_ id: UUID) {
        guard let index = configuration.anchors.firstIndex(where: { $0.id == id }),
              configuration.anchors[index].keyAccessVerifiedAt != nil
        else { return }
        configuration.anchors[index].keyAccessVerifiedAt = nil
        save()
    }

    private func applyTailscalePeer(_ peer: TailscalePeer, to id: UUID) {
        guard let index = configuration.anchors.firstIndex(where: { $0.id == id }) else { return }
        configuration.anchors[index].tailscaleFallback = TailscalePeerCatalog.endpoint(
            nodeID: peer.nodeID,
            peers: [peer]
        )
        if configuration.anchors[index].localHostName == nil,
           configuration.anchors[index].route == .local,
           !TailscalePeerCatalog.isTailscaleAddress(configuration.anchors[index].hostName) {
            configuration.anchors[index].localHostName = configuration.anchors[index].hostName
        }
        save()
    }

    private func inspect(_ entry: SSHConfigEntry) async throws -> NetToysScanResult? {
        let targets = try await NetToysTargetResolver.resolve(
            entry.hostName,
            defaultPorts: [entry.port],
            limit: 1
        )
        return await scanner.scan(
            targets: targets,
            timeoutMilliseconds: 900,
            concurrency: 1
        ).first
    }

    private func prepareHostKeyPolicy(_ anchor: SSHAnchorConfiguration) throws {
        _ = try SSHConfigFileUpdater.prepareAnchor(
            configURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config"),
            backupDirectory: NetToysPaths.backups,
            hostAlias: anchor.hostAlias,
            knownHostsAlias: anchor.knownHostsAlias,
            targetHostName: anchor.hostName
        )
    }
}

struct NetToysAnchorView: View {
    @State private var model = NetToysAnchorViewModel()
    @State private var pendingRemoval: UUID?

    var body: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(
                title: "SSH Anchor",
                subtitle: "Keep SSH aliases attached to local devices"
            ) {
                helperStatus
                Toggle("Monitor anchors", isOn: Binding(
                    get: { model.configuration.sshAnchorEnabled },
                    set: { model.setFeatureEnabled($0) }
                ))
                .toggleStyle(OnePlusSwitchStyle()).fixedSize()
                .help("Enable SSH Anchor monitoring")
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

        } content: {
            helperCard
            addAnchorSection
            anchorsSection
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .onDisappear { model.cancelKeyAccess() }
        .confirmationDialog("Remove this SSH Anchor?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Anchor", role: .destructive) {
                if let id = pendingRemoval { model.remove(id) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysApplyAnchorPrefill)) { notification in
            guard let prefill = notification.object as? NetToysAnchorPrefill else { return }
            Task { await model.apply(prefill) }
        }
        .alert("SSH Anchor", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { model.pendingTailscaleAnchorID != nil },
            set: { if !$0 { model.cancelTailscaleSelection() } }
        )) {
            tailscalePeerPicker
        }
        .sheet(isPresented: Binding(
            get: { model.pendingKeyAccessAnchorID != nil },
            set: { if !$0 { model.cancelKeyAccess() } }
        )) {
            SSHKeyAccessSheet(
                alias: keyAccessAlias,
                isInstalling: model.keyAccessRunningAnchorID != nil,
                errorMessage: model.keyAccessErrorMessage,
                onCancel: model.cancelKeyAccess,
                onContinue: model.installKeyAccess
            )
        }
    }

    private var helperStatus: some View {
        OnePlusStatus(model.helperIsHealthy ? "Helper Active" : "Helper Inactive",
                      state: model.helperIsHealthy ? .online : .offline)
    }

    private var helperCard: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            if !model.helperIsHealthy {
                OnePlusBanner("The login helper is not active. Enable it to monitor your saved anchors.", tone: .warning) {
                    Button("Enable helper") {
                        Task {
                            _ = await NetToysLoginItemManager.shared.setEnabled(true)
                            await model.refresh()
                        }
                    }
                }
            }
            OnePlusSettingRow("Check interval", help: "Each anchor checks its saved SSH port.", separator: false) {
                OnePlusSelect(choices: [(2.0, "2 seconds"), (2.5, "2.5 seconds"), (3.0, "3 seconds")],
                              selection: Binding(get: { model.configuration.probeInterval }, set: model.setProbeInterval),
                              accessibilityLabel: "Check interval")
            }
        }
    }

    private var addAnchorSection: some View {
        OnePlusCard {
            OnePlusCardHeader("Add anchor", systemImage: "link.badge.plus")
            anchorSettingRow("SSH host") {
                HStack(spacing: OnePlusMetrics.navIconGap) {
                    OnePlusSelect(choices: [("", model.entries.isEmpty ? "No SSH hosts" : "Select SSH host")]
                                  + model.entries.map { ($0.aliases[0], $0.aliases.joined(separator: ",")) },
                                  selection: $model.selectedAlias, width: OnePlusMetrics.wideControlColumn,
                                  accessibilityLabel: "SSH host")
                    Button {
                        model.inspectSelectedDevice()
                    } label: {
                        HStack(spacing: OnePlusMetrics.spacing[2]) {
                            if model.isInspecting {
                                ProgressView().controlSize(.small)
                                    .frame(width: OnePlusMetrics.navIcon, height: OnePlusMetrics.navIcon)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .frame(width: OnePlusMetrics.navIcon, height: OnePlusMetrics.navIcon)
                            }
                            Text("Inspect Device")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(model.selectedEntry == nil || model.isInspecting)
                    Spacer(minLength: 0)
                    Text(selectedHostDescription).onePlusText(.mono).lineLimit(1)
                }
            }
            anchorSettingRow(
                "Automatic",
                help: "Detect this device, enable monitoring, and repair its IP when the connection changes."
            ) {
                HStack {
                    Button {
                        model.enableAutomaticAnchor()
                    } label: {
                        HStack(spacing: OnePlusMetrics.spacing[2]) {
                            if model.isInspecting {
                                ProgressView().controlSize(.small)
                                    .frame(width: OnePlusMetrics.navIcon, height: OnePlusMetrics.navIcon)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .frame(width: OnePlusMetrics.navIcon, height: OnePlusMetrics.navIcon)
                            }
                            Text("Enable Automatically")
                        }
                    }
                    .buttonStyle(OnePlusButtonStyle(.primary))
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(model.selectedEntry == nil || model.isInspecting)
                    Spacer(minLength: 0)
                }
            }
            anchorSettingRow("Identity") {
                HStack {
                    OnePlusSegmented(choices: SSHAnchorIdentityMode.allCases.map { ($0, $0.rawValue) },
                                     selection: $model.identityMode, accessibilityLabel: "Device identity")
                        .fixedSize()
                    Spacer(minLength: 0)
                }
            }
            anchorSettingRow(
                "Device",
                help: model.identityMode == .stable
                    ? "Match this device by its fixed hardware MAC address."
                    : "Match loosely by hostname and learned MAC addresses.",
                separator: false
            ) {
                HStack(spacing: OnePlusMetrics.spacing[5]) {
                    OnePlusTextField("MAC address", text: $model.deviceMAC)
                    OnePlusTextField("Hostname", text: $model.deviceHostname)
                        .disabled(model.identityMode == .stable)
                    Button("Add Anchor") { model.addAnchor() }
                        .buttonStyle(OnePlusButtonStyle())
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(model.selectedEntry == nil)
                }
            }
        }
    }

    private func anchorSettingRow<Content: View>(
        _ title: String,
        help: String? = nil,
        separator: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: OnePlusMetrics.navIconGap) {
            HStack(spacing: OnePlusMetrics.spacing[1]) {
                Text(title).onePlusText(.row)
                if let help {
                    Image(systemName: "info.circle").foregroundStyle(OnePlusColor.muted)
                        .help(help).accessibilityLabel(help)
                }
            }
            .frame(width: OnePlusMetrics.controlColumn / 2, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(height: OnePlusMetrics.settingRow)
        .onePlusRowHover()
        .overlay(alignment: .bottom) {
            if separator { OnePlusRule() }
        }
    }

    private var anchorsSection: some View {
        let anchors = model.configuration.anchors
        return OnePlusCard {
            OnePlusCardHeader("Configured anchors", systemImage: "link")
            if anchors.isEmpty {
                OnePlusEmptyState("No anchors yet", systemImage: "link.badge.plus",
                                  caption: "Choose a literal SSH alias from ~/.ssh/config and inspect its device.")
            } else {
                if let retryID = model.keyAccessRetryAnchorID,
                   let retryAnchor = model.configuration.anchors.first(where: { $0.id == retryID }) {
                    OnePlusBanner("Key access was not finished for \(model.aliasLabel(for: retryAnchor)).", tone: .warning) {
                        Button("Retry") { model.setUpKeyAccess(for: retryID) }
                            .controlSize(.small)
                    }
                    .padding(OnePlusMetrics.cardPadding)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(anchors) { anchor in
                            anchorRow(anchor)
                            if anchor.id != anchors.last?.id { OnePlusRule() }
                        }
                    }
                }
                .onePlusScrollIndicators()
                .frame(height: CGFloat(min(5, anchors.count)) * OnePlusMetrics.settingRow)
            }
        }
    }

    private func anchorRow(_ anchor: SSHAnchorConfiguration) -> some View {
        let status = model.status(for: anchor.id)
        let aliasLabel = model.aliasLabel(for: anchor)
        return HStack(spacing: OnePlusMetrics.navIconGap) {
            Image(systemName: statusSymbol(status?.state))
                .foregroundStyle(statusColor(status?.state))
                .frame(width: OnePlusMetrics.navIcon)

            Text(aliasLabel).onePlusText(.row).lineLimit(1)
                .help(status?.message ?? identityDescription(anchor.identity))
            Spacer()
            Text("\(status?.currentHostName ?? anchor.hostName):\(anchor.port)")
                .onePlusText(.mono).lineLimit(1)

            OnePlusStatus(statusLabel(status?.state), state: statusState(status?.state))
                .lineLimit(1)
                .frame(width: OnePlusMetrics.controlColumn, alignment: .trailing)

            Group {
                if model.keyAccessRunningAnchorID == anchor.id {
                    ProgressView().controlSize(.small)
                } else if let verifiedAt = anchor.keyAccessVerifiedAt {
                    Image(systemName: "key.fill")
                        .foregroundStyle(OnePlusColor.secondary)
                        .accessibilityLabel("Key access verified for \(aliasLabel) at \(verifiedAt.formatted())")
                } else {
                    Button {
                        model.setUpKeyAccess(for: anchor.id)
                    } label: {
                        Image(systemName: "key")
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon))
                    .accessibilityLabel("Set up key access for \(aliasLabel)")
                }
            }
            .frame(width: OnePlusMetrics.controlHeight)

            Group {
                if model.tailscaleLoadingAnchorID == anchor.id {
                    HStack(spacing: OnePlusMetrics.spacing[2]) {
                        ProgressView().controlSize(.small)
                        Text("Tailscale")
                    }
                } else {
                    Toggle("Tailscale", isOn: Binding(
                        get: { model.tailscaleIsEnabled(for: anchor) },
                        set: { model.setTailscaleEnabled($0, for: anchor.id) }
                    ))
                    .toggleStyle(OnePlusCheckboxStyle())
                    .controlSize(.small)
                }
            }
            .frame(width: OnePlusMetrics.controlColumn, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { anchor.isEnabled },
                set: { model.setEnabled($0, for: anchor.id) }
            ))
            .labelsHidden()
            .toggleStyle(OnePlusSwitchStyle()).fixedSize()
            .controlSize(.small)
            .accessibilityLabel("Monitor \(aliasLabel)")

            Button(role: .destructive) {
                pendingRemoval = anchor.id
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(OnePlusButtonStyle(.icon))
            .accessibilityLabel("Remove \(aliasLabel)")
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding)
        .frame(height: OnePlusMetrics.settingRow)
        .onePlusRowHover()
        .contextMenu {
            Button("Set up key access") { model.setUpKeyAccess(for: anchor.id) }
            Button("Remove Anchor", role: .destructive) { pendingRemoval = anchor.id }
        }
    }

    private var tailscalePeerPicker: some View {
        OnePlusSheet("Choose Tailscale device", width: .small, close: model.cancelTailscaleSelection) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.tailscalePeers) { peer in
                        Button {
                            model.chooseTailscalePeer(peer)
                        } label: {
                            HStack(spacing: OnePlusMetrics.navIconGap) {
                                Text(peer.hostName).onePlusText(.row).lineLimit(1)
                                Spacer()
                                Text(peer.ipAddress).onePlusText(.mono).foregroundStyle(OnePlusColor.secondary)
                                OnePlusStatus(peer.isOnline ? "Online" : "Offline",
                                              state: peer.isOnline ? .online : .offline)
                            }
                            .padding(.horizontal, OnePlusMetrics.navPadding)
                            .frame(height: NetToysAnchorSheetLayout.peerRowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(OnePlusInteractionStyle())
                    }
                }
            }
            .onePlusScrollIndicators()
            .frame(height: NetToysAnchorSheetLayout.peerPickerHeight(peerCount: model.tailscalePeers.count)
                   - NetToysAnchorSheetLayout.peerPickerBaseHeight)
        }
    }

    private func identityDescription(_ identity: AnchorIdentity) -> String {
        switch identity {
        case .stableMAC(let mac): "Stable MAC  ·  \(mac)"
        case .randomizedMAC(let hostname, let macs):
            "Hostname \(hostname.isEmpty ? "unavailable" : hostname)  ·  \(macs.count) learned MAC"
        }
    }

    private var selectedHostDescription: String {
        guard let entry = model.selectedEntry else {
            return model.requestedAddress.map { "Select host for \($0)" } ?? "No host selected"
        }
        return "\(entry.hostName)  ·  TCP \(entry.port)"
    }

    private var keyAccessAlias: String {
        guard let id = model.pendingKeyAccessAnchorID,
              let anchor = model.configuration.anchors.first(where: { $0.id == id })
        else { return "SSH host" }
        return model.aliasLabel(for: anchor)
    }

    private func statusSymbol(_ state: SSHAnchorRuntimeState?) -> String {
        switch state {
        case .healthy, .recovered, .fallback: "checkmark.circle.fill"
        case .scanning: "arrow.triangle.2.circlepath"
        case .error, .notFound, .ambiguous, .unavailable, .fallbackUnavailable:
            "exclamationmark.circle.fill"
        default: "circle"
        }
    }

    private func statusColor(_ state: SSHAnchorRuntimeState?) -> Color {
        switch state {
        case .healthy, .recovered, .fallback: OnePlusColor.secondary
        case .scanning: OnePlusColor.secondary
        case .error, .notFound, .ambiguous, .unavailable, .fallbackUnavailable: OnePlusColor.warn
        default: OnePlusColor.muted
        }
    }

    private func statusState(_ state: SSHAnchorRuntimeState?) -> OnePlusStatus.State {
        switch state {
        case .healthy, .recovered, .fallback: .online
        case .error, .notFound, .ambiguous, .unavailable, .fallbackUnavailable: .warning
        default: .offline
        }
    }

    private func statusLabel(_ state: SSHAnchorRuntimeState?) -> String {
        switch state {
        case .fallbackUnavailable: "Needs Tailscale"
        case .fallback: "Tailscale"
        case let state?: state.rawValue.capitalized
        case nil: "Waiting"
        }
    }
}

private struct SSHKeyAccessSheet: View {
    let alias: String
    let isInstalling: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onContinue: (String) -> Void

    @State private var password = ""
    var body: some View {
        OnePlusSheet("Set up key access", width: .small, close: onCancel) {
            VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
                Text("Enter the SSH password for \(alias) once. MacPowerToys installs your public key and does not keep the password.")
                    .onePlusText(.row).foregroundStyle(OnePlusColor.secondary)
                OnePlusSecureField.focusedOnOpen("Password", text: $password)
                    .disabled(isInstalling)
                    .onSubmit(submit)
                if let errorMessage {
                    OnePlusBanner(errorMessage, tone: .error)
                }
                if isInstalling {
                    ProgressView("Installing and verifying key access...")
                        .controlSize(.small).onePlusText(.caption)
                }
            }
        } footer: {
            Button("Cancel", action: onCancel).buttonStyle(OnePlusButtonStyle(.ghost))
            Button("Continue", action: submit).buttonStyle(OnePlusButtonStyle(.primary))
                .keyboardShortcut(.defaultAction).disabled(password.isEmpty || isInstalling)
        }
    }

    private func submit() {
        guard !password.isEmpty, !isInstalling else { return }
        let submittedPassword = password
        password = ""
        onContinue(submittedPassword)
    }
}
