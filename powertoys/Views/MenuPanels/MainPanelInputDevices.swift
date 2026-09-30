import OnePlusUI
import SwiftUI

struct InputDevicesTrayView: View {
    @State private var manager = InputDevicesManager.shared
    @AppStorage("tray.inputDevices.controls.expanded") private var showsControls = false
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            if showsHeader { TrayToolHeader(tab: .inputDevices) }
            OnePlusMenuSectionHeader("Devices", actionTitle: "Refresh") { manager.refresh() }
            if manager.devices.isEmpty {
                OnePlusMenuCard { Text("No pointing devices detected").onePlusText(.caption) }
            } else {
                ForEach(manager.devices) { device in deviceCard(device) }
            }
            OnePlusMenuSectionHeader("Scrolling", actionTitle: showsControls ? "Hide controls" : "Show controls") {
                showsControls.toggle()
            }
            if showsControls {
                InputDevicesSettingsContent()
            } else {
                quickControl
            }
        }
    }

    private var quickControl: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            OnePlusMenuControlRow("Adjust scrolling", systemImage: "scroll") {
                Toggle("Adjust scrolling system wide", isOn: Binding(
                    get: { manager.settings.scrollControlEnabled },
                    set: { value in manager.update { $0.scrollControlEnabled = value } }
                )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            if !manager.permissionGranted {
                OnePlusMenuControlRow("Permission needed", systemImage: "hand.raised") {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Button("Grant") { manager.requestPermission() }
                            .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
                        Button("Settings") { manager.openPrivacySettings() }
                            .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    }
                }
            }
            if let error = manager.errorMessage {
                Text(error).onePlusText(.caption, color: OnePlusColor.danger)
            }
        }
    }

    private func deviceCard(_ device: InputDeviceDescriptor) -> some View {
        let profile = device.kind == .mouse ? manager.settings.mouse : manager.settings.trackpad
        let state = InputControlState.state(settings: manager.settings, permissionGranted: manager.permissionGranted,
                                            kind: device.kind)
        return OnePlusMenuCard(textured: true) {
            VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: device.kind.icon).onePlusText(.row)
                    Text(device.name).onePlusText(.cardTitle).lineLimit(1).help(device.name)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    if let battery = device.batteryPercent {
                        Text("\(battery)%").onePlusText(.mono, color: battery <= 20 ? OnePlusColor.warn : OnePlusColor.dataBlue)
                            .accessibilityLabel("Battery \(battery) percent")
                    }
                }
                Text(device.connectionSummary.components(separatedBy: " · ").first ?? device.transport)
                    .onePlusText(.caption)
                HStack {
                    Text(state.title).onePlusText(.caption)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    Text("\(profile.reverseVertical ? "Reversed" : "Natural") · \(profile.speed.formatted(.number.precision(.fractionLength(2))))×")
                        .onePlusText(.mono)
                }
                if let battery = device.batteryPercent {
                    OnePlusUsageBar(value: Double(battery) / 100, color: battery <= 20 ? OnePlusColor.warn : OnePlusColor.dataBlue)
                        .accessibilityLabel("Battery \(battery) percent")
                }
            }
        }
    }
}
