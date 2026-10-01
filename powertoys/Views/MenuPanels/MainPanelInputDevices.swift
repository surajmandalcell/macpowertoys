import OnePlusUI
import SwiftUI

struct InputDevicesTrayView: View {
    @State private var manager = InputDevicesManager.shared
    @Environment(\.onePlusIsVisible) private var isVisible
    @AppStorage("tray.inputDevices.devices.expanded") private var devicesExpanded = true
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            if showsHeader { TrayToolHeader(tab: .inputDevices) }
            deviceSection
            InputDevicesSettingsContent(collapsible: true)
        }
        .onChange(of: isVisible, initial: true) { _, visible in
            if visible { manager.refresh() }
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: OnePlusMenuMetrics.tileGap) {
            InputDisclosureHeader(title: "Devices", detail: "\(manager.devices.count) connected",
                                  isExpanded: $devicesExpanded)
            if devicesExpanded {
                OnePlusMenuSectionHeader("Connected devices", actionTitle: "Refresh") { manager.refresh() }
                if manager.devices.isEmpty {
                    Text("No pointing devices detected").onePlusText(.caption)
                } else {
                    ForEach(manager.devices) { device in deviceCard(device) }
                }
            }
        }
    }

    private func deviceCard(_ device: InputDeviceDescriptor) -> some View {
        let profile = InputScrollPolicy.profile(for: device.kind, settings: manager.settings)
        let state = InputControlState.state(settings: manager.settings, permissionGranted: manager.permissionGranted,
                                            interceptionActive: manager.interceptionActive,
                                            kind: device.kind)
        return OnePlusMenuCard {
            VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    Image(systemName: device.kind.icon).onePlusText(.row)
                    Text(device.name).onePlusText(.cardTitle).lineLimit(1).help(device.name)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    InputStateLabel(state: state)
                }
                HStack {
                    Text(device.connectionSummary.components(separatedBy: " · ").first ?? device.transport)
                        .onePlusText(.caption)
                    Spacer(minLength: OnePlusMenuMetrics.tileGap)
                    Text("\(profile.reverseVertical ? "Reversed" : "System") · \(profile.speed.formatted(.number.precision(.fractionLength(2))))×")
                        .onePlusText(.mono)
                }
                if let battery = device.batteryPercent {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        OnePlusUsageBar(value: Double(battery) / 100, color: battery <= 20 ? OnePlusColor.warn : OnePlusColor.dataBlue)
                        Text("\(battery)%").onePlusText(.mono)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Battery \(battery) percent")
                }
            }
        }
        .onePlusRowHover(radius: OnePlusMetrics.menuTileRadius)
    }
}
