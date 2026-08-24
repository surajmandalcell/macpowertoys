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

    private let scanner = NetToysScanner()

    init() {
        refresh()
    }

    var selectedEntry: SSHConfigEntry? {
        entries.first { $0.aliases.contains(selectedAlias) }
    }

    var helperIsHealthy: Bool {
        NetToysLoginItemManager.shared.status == .enabled
            && NetToysLoginItemManager.hasFreshHeartbeat(helperStatus)
    }

    func refresh() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        if let data = try? Data(contentsOf: url) {
            entries = SSHConfigEditor.entries(in: data).filter { entry in
                entry.aliases.count == 1
                    && !entry.aliases[0].contains("*")
                    && !entry.aliases[0].contains("?")
                    && IPv4Address(entry.hostName) != nil
            }
        } else {
            entries = []
        }
        configuration = NetToysConfigurationStore.load()
        helperStatus = NetToysConfigurationStore.status()
        if !entries.contains(where: { $0.aliases.contains(selectedAlias) }) {
            selectedAlias = entries.first?.aliases.first ?? ""
        }
    }

    func inspectSelectedDevice() {
        guard let entry = selectedEntry, let address = IPv4Address(entry.hostName) else { return }
        isInspecting = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            let results = await scanner.scan(
                targets: [address],
                ports: [entry.port],
                timeoutMilliseconds: 900,
                concurrency: 1
            )
            if let result = results.first {
                deviceMAC = result.macAddress ?? ""
                deviceHostname = result.hostname ?? ""
            }
            isInspecting = false
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
        configuration.anchors.append(SSHAnchorConfiguration(
            hostAlias: alias,
            hostName: entry.hostName,
            port: entry.port,
            identity: identity
        ))
        save()
        deviceMAC = ""
        deviceHostname = ""
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = configuration.anchors.firstIndex(where: { $0.id == id }) else { return }
        configuration.anchors[index].isEnabled = enabled
        save()
    }

    func remove(_ id: UUID) {
        configuration.anchors.removeAll { $0.id == id }
        save()
    }

    func setProbeInterval(_ value: TimeInterval) {
        configuration.probeInterval = min(max(value, 2), 3)
        save()
    }

    func status(for id: UUID) -> SSHAnchorStatus? {
        helperStatus?.anchors.first { $0.anchorID == id }
    }

    private func save() {
        do {
            try NetToysConfigurationStore.save(configuration)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        .alert("SSH Anchor", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
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
                    Picker("", selection: $model.selectedAlias) {
                        if model.entries.isEmpty {
                            Text("No eligible hosts").tag("")
                        } else {
                            ForEach(model.entries, id: \.aliases) { entry in
                                Text(entry.aliases[0]).tag(entry.aliases[0])
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 160)

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

                    Text(selectedHostDescription)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 150, alignment: .trailing)
                }

                GridRow(alignment: .center) {
                    rowLabel("Identity")
                    Picker("", selection: $model.identityMode) {
                        ForEach(SSHAnchorIdentityMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .gridCellColumns(3)
                }

                GridRow(alignment: .center) {
                    rowLabel("Device")
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

                GridRow {
                    Color.clear.frame(width: 64, height: 1)
                    Text(model.identityMode == .stable
                        ? "Match this device by its fixed hardware MAC address."
                        : "Match loosely by hostname and learned MAC addresses.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 14, alignment: .leading)
                        .gridCellColumns(3)
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
        return HStack(spacing: 10) {
            Image(systemName: statusSymbol(status?.state))
                .foregroundStyle(statusColor(status?.state))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(anchor.hostAlias)
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

            Text(status?.state.rawValue.capitalized ?? "Waiting")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 74, alignment: .trailing)

            Toggle("", isOn: Binding(
                get: { anchor.isEnabled },
                set: { model.setEnabled($0, for: anchor.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("Monitor \(anchor.hostAlias)")

            Button(role: .destructive) {
                model.remove(anchor.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel("Remove \(anchor.hostAlias)")
            .help("Remove \(anchor.hostAlias)")
        }
        .padding(.vertical, 2)
    }

    private func identityDescription(_ identity: AnchorIdentity) -> String {
        switch identity {
        case .stableMAC(let mac): "Stable MAC  ·  \(mac)"
        case .randomizedMAC(let hostname, let macs):
            "Randomized MAC  ·  \(hostname.isEmpty ? "No hostname" : hostname)  ·  \(macs.count) learned MAC"
        }
    }

    private var selectedHostDescription: String {
        guard let entry = model.selectedEntry else { return "No host selected" }
        return "\(entry.hostName)  ·  TCP \(entry.port)"
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .trailing)
    }

    private func statusSymbol(_ state: SSHAnchorRuntimeState?) -> String {
        switch state {
        case .healthy, .recovered: "checkmark.circle.fill"
        case .scanning: "arrow.triangle.2.circlepath"
        case .error, .notFound, .ambiguous, .unavailable: "exclamationmark.circle.fill"
        default: "circle"
        }
    }

    private func statusColor(_ state: SSHAnchorRuntimeState?) -> Color {
        switch state {
        case .healthy, .recovered: .green
        case .scanning: .accentColor
        case .error, .notFound, .ambiguous, .unavailable: .orange
        default: .secondary
        }
    }
}
