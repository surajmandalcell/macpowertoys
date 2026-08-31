import Observation
import ServiceManagement
import SwiftUI

enum SSHAnchorIdentityMode: String, CaseIterable, Identifiable {
    case stable = "Stable MAC"
    case randomized = "Randomized MAC"

    var id: String { rawValue }
}

@Observable
@MainActor
final class NetToysAnchorViewModel {
    var entries: [SSHConfigEntry] = []
    var selectedAlias = ""
    var identityMode = SSHAnchorIdentityMode.stable
    var deviceMAC = ""
    var deviceHostname = ""
    var configuration = NetToysConfigurationStore.load()
    var helperStatus = NetToysConfigurationStore.status()
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

    init() {
        refresh()
    }

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

    func refresh() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        if let data = try? Data(contentsOf: url) {
            entries = SSHConfigEditor.anchorEntries(in: data)
        } else {
            entries = []
        }
        configuration = NetToysConfigurationStore.load()
        helperStatus = NetToysConfigurationStore.status()
        if !entries.contains(where: { $0.aliases.contains(selectedAlias) }) {
            selectedAlias = requestedAddress == nil ? entries.first?.aliases.first ?? "" : ""
        }
    }

    func apply(_ prefill: NetToysAnchorPrefill) {
        requestedAddress = prefill.address
        refresh()
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
                try NetToysConfigurationStore.save(configuration)
                refresh()

                guard await NetToysLoginItemManager.shared.setEnabled(true) else {
                    errorMessage = NetToysLoginItemManager.shared.errorMessage
                        ?? "The NetToys helper could not be enabled."
                    return
                }
                helperStatus = NetToysConfigurationStore.status()
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
            try NetToysConfigurationStore.save(configuration)
            refresh()
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

    var body: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(
                title: "SSH Anchor",
                subtitle: "Keep SSH aliases attached to local devices"
            ) {
                helperStatus
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
                    helperCard
                    addAnchorSection
                    anchorsSection
                }
                .padding(.horizontal, UtilityLayout.horizontalInset)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScrollIndicators()
        }
        .task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysApplyAnchorPrefill)) { notification in
            guard let prefill = notification.object as? NetToysAnchorPrefill else { return }
            model.apply(prefill)
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
        Label(
            model.helperIsHealthy ? "Helper Active" : "Helper Inactive",
            systemImage: model.helperIsHealthy ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .foregroundStyle(model.helperIsHealthy ? .green : .secondary)
        .font(.system(size: 11))
        .frame(minWidth: 92, alignment: .leading)
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HELPER AND CHECK INTERVAL").utilitySectionHeader()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.helperIsHealthy ? "Monitoring is active" : "The login helper is not active")
                        .font(.system(size: 13, weight: .medium))
                    Text("The helper checks each configured port. The main app does not run the monitor.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(1)
                Spacer()
                Text("Check interval")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Picker("", selection: Binding(
                    get: { model.configuration.probeInterval },
                    set: { model.setProbeInterval($0) }
                )) {
                    Text("2 s").tag(TimeInterval(2))
                    Text("2.5 s").tag(TimeInterval(2.5))
                    Text("3 s").tag(TimeInterval(3))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 72)
                .fixedSize(horizontal: true, vertical: false)
            }
            .utilitySectionCard()
        }
    }

    private var addAnchorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD ANCHOR").utilitySectionHeader()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow(alignment: .center) {
                    rowLabel("SSH host")
                    HStack(spacing: 10) {
                        Picker("", selection: $model.selectedAlias) {
                            if model.entries.isEmpty {
                                Text("No SSH hosts").tag("")
                            } else {
                                if model.selectedAlias.isEmpty {
                                    Text("Select SSH host").tag("")
                                }
                                ForEach(model.entries, id: \.aliases) { entry in
                                    Text(entry.aliases.joined(separator: ",")).tag(entry.aliases[0])
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180, alignment: .leading)

                        Button {
                            model.inspectSelectedDevice()
                        } label: {
                            HStack(spacing: 6) {
                                if model.isInspecting {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 13, height: 13)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                        .frame(width: 13, height: 13)
                                }
                                Text("Inspect Device")
                            }
                        }
                        .frame(minWidth: 122)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(model.selectedEntry == nil || model.isInspecting)

                        Spacer(minLength: 10)

                        Text(selectedHostDescription)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 190, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow(alignment: .center) {
                    rowLabel("Automatic")
                    HStack(spacing: 10) {
                        Text("Detect this device, enable monitoring, and repair its IP when the connection changes.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            model.enableAutomaticAnchor()
                        } label: {
                            HStack(spacing: 6) {
                                if model.isInspecting {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 13, height: 13)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .frame(width: 13, height: 13)
                                }
                                Text("Enable Automatically")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(model.selectedEntry == nil || model.isInspecting)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow(alignment: .center) {
                    rowLabel("Identity")
                    HStack {
                        Picker("", selection: $model.identityMode) {
                            ForEach(SSHAnchorIdentityMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 228)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow(alignment: .center) {
                    rowLabel("Device")
                    HStack(spacing: 10) {
                        TextField("MAC address", text: $model.deviceMAC)
                            .textFieldStyle(.roundedBorder)

                        TextField("Hostname", text: $model.deviceHostname)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.identityMode == .stable)

                        Button("Add Anchor") { model.addAnchor() }
                            .buttonStyle(.borderedProminent)
                            .frame(minWidth: 92)
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(model.selectedEntry == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow {
                    Color.clear.frame(width: 64, height: 1)
                    Text(model.identityMode == .stable
                        ? "Match this device by its fixed hardware MAC address."
                        : "Match loosely by hostname and learned MAC addresses.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 14, alignment: .leading)
                }
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .utilitySectionCard()
        }
    }

    private var anchorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONFIGURED ANCHORS").utilitySectionHeader()
            if model.configuration.anchors.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(.secondary)
                    Text("Add an explicit IPv4 HostName and Port entry from ~/.ssh/config.")
                        .foregroundStyle(.secondary)
                }
                .utilitySectionCard()
            } else {
                if let retryID = model.keyAccessRetryAnchorID,
                   let retryAnchor = model.configuration.anchors.first(where: { $0.id == retryID }) {
                    HStack(spacing: 8) {
                        Image(systemName: "key")
                        Text("Key access wasn't finished for \(model.aliasLabel(for: retryAnchor)).")
                        Spacer()
                        Button("Retry") { model.setUpKeyAccess(for: retryID) }
                            .controlSize(.small)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }

                VStack(spacing: 0) {
                    ForEach(Array(model.configuration.anchors.enumerated()), id: \.element.id) { index, anchor in
                        anchorRow(anchor)
                        if index < model.configuration.anchors.count - 1 { QuietDivider() }
                    }
                }
                .utilitySectionCard()
            }
        }
    }

    private func anchorRow(_ anchor: SSHAnchorConfiguration) -> some View {
        let status = model.status(for: anchor.id)
        let aliasLabel = model.aliasLabel(for: anchor)
        return HStack(spacing: 10) {
            Image(systemName: statusSymbol(status?.state))
                .foregroundStyle(statusColor(status?.state))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(aliasLabel)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(status?.currentHostName ?? anchor.hostName):\(anchor.port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(status?.message ?? identityDescription(anchor.identity))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(statusLabel(status?.state))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 74, alignment: .trailing)

            Group {
                if model.keyAccessRunningAnchorID == anchor.id {
                    ProgressView().controlSize(.small)
                } else if let verifiedAt = anchor.keyAccessVerifiedAt {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                        .help("Key access verified \(verifiedAt.formatted())")
                        .accessibilityLabel("Key access verified for \(aliasLabel)")
                } else {
                    Button {
                        model.setUpKeyAccess(for: anchor.id)
                    } label: {
                        Image(systemName: "key")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Set up key access")
                    .accessibilityLabel("Set up key access for \(aliasLabel)")
                }
            }
            .frame(width: 26)

            Group {
                if model.tailscaleLoadingAnchorID == anchor.id {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Tailscale")
                    }
                } else {
                    Toggle("Tailscale", isOn: Binding(
                        get: { model.tailscaleIsEnabled(for: anchor) },
                        set: { model.setTailscaleEnabled($0, for: anchor.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("Prefer the local connection and use Tailscale only while it is unavailable.")
                }
            }
            .frame(width: 94, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { anchor.isEnabled },
                set: { model.setEnabled($0, for: anchor.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("Monitor \(aliasLabel)")

            Button(role: .destructive) {
                model.remove(anchor.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel("Remove \(aliasLabel)")
            .help("Remove \(aliasLabel)")
        }
        .padding(.vertical, 6)
    }

    private var tailscalePeerPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Choose Tailscale Device")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                UtilityModalCloseButton(action: model.cancelTailscaleSelection)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 44)

            QuietDivider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.tailscalePeers) { peer in
                        Button {
                            model.chooseTailscalePeer(peer)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.hostName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(peer.ipAddress)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(peer.isOnline ? Color.green : Color.secondary)
                                        .frame(width: 6, height: 6)
                                    Text(peer.isOnline ? "Online" : "Offline")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 58, alignment: .leading)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
                        .focusEffectDisabled()

                        if peer.id != model.tailscalePeers.last?.id {
                            QuietDivider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .thinScrollIndicators()
        }
        .frame(
            width: 360,
            height: min(260, 52 + CGFloat(model.tailscalePeers.count) * 41)
        )
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

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .trailing)
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
        case .healthy, .recovered, .fallback: .green
        case .scanning: .accentColor
        case .error, .notFound, .ambiguous, .unavailable, .fallbackUnavailable: .orange
        default: .secondary
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
    @FocusState private var passwordIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Set Up Key Access")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                UtilityModalCloseButton(action: onCancel)
            }
            .padding(20)

            QuietDivider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Enter the SSH password for \(alias) once. MacPowerToys installs your public key and does not keep the password.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($passwordIsFocused)
                    .disabled(isInstalling)
                    .onSubmit(submit)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                HStack {
                    if isInstalling {
                        ProgressView().controlSize(.small)
                        Text("Installing and verifying key access...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Continue", action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(password.isEmpty || isInstalling)
                }
            }
            .padding(20)
        }
        .frame(width: 420)
        .onAppear { passwordIsFocused = true }
    }

    private func submit() {
        guard !password.isEmpty, !isInstalling else { return }
        let submittedPassword = password
        password = ""
        onContinue(submittedPassword)
    }
}
