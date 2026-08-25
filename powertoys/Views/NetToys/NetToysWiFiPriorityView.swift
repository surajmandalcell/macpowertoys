import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class NetToysWiFiPriorityViewModel {
    var configuration = NetToysConfigurationStore.load()
    var helperStatus = NetToysConfigurationStore.status()
    var savedNetworks: [String] = []
    var errorMessage: String?

    var availableNetworks: [String] {
        savedNetworks.filter { !configuration.wifiPriority.ssids.contains($0) }
    }

    func refresh() async {
        helperStatus = NetToysConfigurationStore.status()
        savedNetworks = await WiFiNetworkController.preferredNetworks()
    }

    func setEnabled(_ enabled: Bool) {
        configuration.wifiPriority.isEnabled = enabled
            && configuration.wifiPriority.ssids.count >= 2
        save()
    }

    func setThreshold(_ threshold: TimeInterval) {
        configuration.wifiPriority.outageThreshold = threshold
        save()
    }

    func add(_ ssid: String) {
        configuration.wifiPriority.ssids.append(ssid)
        save()
    }

    func remove(_ ssid: String) {
        configuration.wifiPriority.ssids.removeAll { $0 == ssid }
        if configuration.wifiPriority.ssids.count < 2 {
            configuration.wifiPriority.isEnabled = false
        }
        save()
    }

    func move(_ ssid: String, by offset: Int) {
        guard let index = configuration.wifiPriority.ssids.firstIndex(of: ssid) else { return }
        let destination = index + offset
        guard configuration.wifiPriority.ssids.indices.contains(destination) else { return }
        configuration.wifiPriority.ssids.swapAt(index, destination)
        save()
    }

    private func save() {
        do {
            try NetToysConfigurationStore.save(configuration)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NetToysWiFiPriorityView: View {
    @State private var model = NetToysWiFiPriorityViewModel()

    var body: some View {
        VStack(spacing: 0) {
            NetToysPageHeader(
                title: "Wi-Fi Priority",
                subtitle: model.helperStatus?.network?.displayName ?? "No active network"
            ) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
                    failoverSection
                    prioritySection
                    hotspotSection
                }
                .padding(.horizontal, UtilityLayout.horizontalInset)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScrollIndicators()
        }
        .task {
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.helperStatus = NetToysConfigurationStore.status()
            }
        }
        .alert("Wi-Fi Priority", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var failoverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUTOMATIC FAILOVER").utilitySectionHeader()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch when Internet access fails")
                            .font(.system(size: 13, weight: .medium))
                        Text(failoverMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.configuration.wifiPriority.isEnabled },
                        set: { model.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .disabled(model.configuration.wifiPriority.ssids.count < 2)
                }

                HStack {
                    Text("Failure duration")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { model.configuration.wifiPriority.outageThreshold },
                        set: { model.setThreshold($0) }
                    )) {
                        Text("5 seconds").tag(TimeInterval(5))
                        Text("10 seconds").tag(TimeInterval(10))
                        Text("15 seconds").tag(TimeInterval(15))
                        Text("30 seconds").tag(TimeInterval(30))
                        Text("60 seconds").tag(TimeInterval(60))
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 104)
                    .disabled(!model.configuration.wifiPriority.isEnabled)
                }
            }
            .controlSize(.small)
            .utilitySectionCard()
        }
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SAVED WI-FI ORDER").utilitySectionHeader()
                Spacer()
                Menu {
                    if model.availableNetworks.isEmpty {
                        Text("No other saved networks")
                    } else {
                        ForEach(model.availableNetworks, id: \.self) { ssid in
                            Button(ssid) { model.add(ssid) }
                        }
                    }
                } label: {
                    Label("Add Network", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if model.configuration.wifiPriority.ssids.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                    Text("Add at least two saved networks in failover order.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .utilitySectionCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(model.configuration.wifiPriority.ssids, id: \.self) { ssid in
                        priorityRow(ssid)
                        if ssid != model.configuration.wifiPriority.ssids.last { QuietDivider() }
                    }
                }
                .utilitySectionCard()
            }
        }
    }

    private func priorityRow(_ ssid: String) -> some View {
        let index = model.configuration.wifiPriority.ssids.firstIndex(of: ssid) ?? 0
        let isCurrent = model.helperStatus?.network?.ssid == ssid
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Image(systemName: isCurrent ? "wifi.circle.fill" : "wifi")
                .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                .frame(width: 18)
            Text(ssid)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if isCurrent {
                Text("Connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.move(ssid, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("Move up")
            Button { model.move(ssid, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == model.configuration.wifiPriority.ssids.count - 1)
            .help("Move down")
            Button(role: .destructive) { model.remove(ssid) } label: {
                Image(systemName: "minus.circle")
            }
            .help("Remove network")
        }
        .controlSize(.small)
        .padding(.vertical, 6)
    }

    private var hotspotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FINAL FALLBACK").utilitySectionHeader()
            HStack(spacing: 10) {
                Image(systemName: "iphone.and.arrow.forward")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhone Personal Hotspot")
                        .font(.system(size: 13, weight: .medium))
                    Text("macOS Auto-Join Hotspot can connect after saved Wi-Fi networks are unavailable.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Wi-Fi Settings") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")
                    else { return }
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
            }
            .utilitySectionCard()
        }
    }

    private var failoverMessage: String {
        model.helperStatus?.wifiFailover?.message
            ?? "The helper checks Internet access and uses the next nearby saved network."
    }
}
