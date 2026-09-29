import AppKit
import Observation
import OnePlusUI
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
        configuration.wifiPriority.isEnabled = enabled && configuration.wifiPriority.ssids.count >= 2
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
        if configuration.wifiPriority.ssids.count < 2 { configuration.wifiPriority.isEnabled = false }
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
        do { try NetToysConfigurationStore.save(configuration) }
        catch { errorMessage = error.localizedDescription }
    }
}

struct NetToysWiFiPriorityView: View {
    @State private var model = NetToysWiFiPriorityViewModel()
    @State private var pendingRemoval: String?

    private var enabled: Binding<Bool> {
        Binding(get: { model.configuration.wifiPriority.isEnabled }, set: model.setEnabled)
    }

    var body: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Wi-Fi Priority",
                              subtitle: model.helperStatus?.network?.displayName ?? "No active network") {
                Toggle("Enable Wi-Fi Priority", isOn: enabled)
                    .toggleStyle(OnePlusSwitchStyle()).fixedSize()
                    .disabled(model.configuration.wifiPriority.ssids.count < 2)
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
            }
        } content: {
            failoverSection
            prioritySection
            hotspotSection
        }
        .task {
            await model.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled else { return }
                model.helperStatus = NetToysConfigurationStore.status()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .confirmationDialog("Remove this network from failover?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let ssid = pendingRemoval {
                Button("Remove \(ssid)", role: .destructive) { model.remove(ssid); pendingRemoval = nil }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
        .alert("Wi-Fi Priority", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }

    private var failoverSection: some View {
        OnePlusCard {
            OnePlusCardHeader("Automatic failover", systemImage: "wifi")
            OnePlusSettingRow("Switch when Internet access fails", caption: failoverMessage) {
                Toggle("Automatic failover", isOn: enabled).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    .disabled(model.configuration.wifiPriority.ssids.count < 2)
            }
            OnePlusSettingRow("Failure duration", separator: false) {
                OnePlusSelect(choices: [5, 10, 15, 30, 60].map { (TimeInterval($0), "\($0) seconds") },
                              selection: Binding(get: { model.configuration.wifiPriority.outageThreshold },
                                                 set: model.setThreshold), accessibilityLabel: "Failure duration")
                    .disabled(!model.configuration.wifiPriority.isEnabled)
            }
        }
    }

    private var prioritySection: some View {
        OnePlusCard {
            OnePlusCardHeader("Saved Wi-Fi order", systemImage: "list.number") {
                OnePlusActionMenu("Add Network") {
                    if model.availableNetworks.isEmpty { Text("No other saved networks") }
                    ForEach(model.availableNetworks, id: \.self) { ssid in Button(ssid) { model.add(ssid) } }
                }
            }
            if model.configuration.wifiPriority.ssids.isEmpty {
                OnePlusEmptyState("Choose your fallback networks", systemImage: "wifi",
                                  caption: "Add at least two saved networks in failover order.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.configuration.wifiPriority.ssids, id: \.self) { ssid in priorityRow(ssid) }
                }
            }
        }
    }

    private func priorityRow(_ ssid: String) -> some View {
        let index = model.configuration.wifiPriority.ssids.firstIndex(of: ssid) ?? 0
        let isCurrent = model.helperStatus?.network?.ssid == ssid
        return HStack(spacing: OnePlusMetrics.navIconGap) {
            Text("\(index + 1)").onePlusText(.mono).frame(width: OnePlusMetrics.controlHeight)
            Text(ssid).onePlusText(.row).lineLimit(1).help(ssid)
            Spacer()
            OnePlusStatus(isCurrent ? "Connected" : "Saved", state: isCurrent ? .online : .offline)
            Button { model.move(ssid, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(OnePlusButtonStyle(.icon)).disabled(index == 0)
                .help("Move up").accessibilityLabel("Move \(ssid) up")
            Button { model.move(ssid, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(OnePlusButtonStyle(.icon))
                .disabled(index == model.configuration.wifiPriority.ssids.count - 1)
                .help("Move down").accessibilityLabel("Move \(ssid) down")
            Button { pendingRemoval = ssid } label: { Image(systemName: "minus.circle") }
                .buttonStyle(OnePlusButtonStyle(.icon)).help("Remove network")
                .accessibilityLabel("Remove \(ssid)")
        }
        .padding(.horizontal, OnePlusMetrics.cardPadding).frame(height: OnePlusMetrics.settingRow)
        .overlay(alignment: .bottom) { OnePlusRule() }
        .contextMenu {
            Button("Move Up") { model.move(ssid, by: -1) }.disabled(index == 0)
            Button("Move Down") { model.move(ssid, by: 1) }
                .disabled(index == model.configuration.wifiPriority.ssids.count - 1)
            Button("Remove", role: .destructive) { pendingRemoval = ssid }
        }
    }

    private var hotspotSection: some View {
        OnePlusCard {
            OnePlusCardHeader("Final fallback", systemImage: "iphone.and.arrow.forward")
            OnePlusSettingRow("iPhone Personal Hotspot",
                              caption: "macOS Auto-Join Hotspot connects after saved networks are unavailable.", separator: false) {
                Button("Wi-Fi Settings") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") else { return }
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var failoverMessage: String {
        model.helperStatus?.wifiFailover?.message ?? "The next nearby saved network is used after this delay."
    }
}
