import OnePlusUI
import SwiftUI

enum InputControlState {
    case disabled
    case permissionNeeded
    case passthrough
    case active

    static func state(
        settings: InputDevicesSettings,
        permissionGranted: Bool,
        kind: InputDeviceDescriptor.Kind
    ) -> InputControlState {
        guard settings.scrollControlEnabled else { return .disabled }
        guard permissionGranted else { return .permissionNeeded }
        let profile = kind == .mouse ? settings.mouse : settings.trackpad
        return profile.enabled ? .active : .passthrough
    }

    var title: String {
        switch self {
        case .disabled: "Not controlled"
        case .permissionNeeded: "Permission needed"
        case .passthrough: "Passthrough"
        case .active: "Controlled"
        }
    }

    var status: OnePlusStatus.State {
        switch self {
        case .disabled, .passthrough: .offline
        case .permissionNeeded: .warning
        case .active: .success
        }
    }
}

struct InputStateLabel: View {
    let state: InputControlState

    var body: some View {
        OnePlusStatus(state.title, state: state.status)
    }
}

struct InputDeviceCard: View {
    let device: InputDeviceDescriptor?
    let kind: InputDeviceDescriptor.Kind
    let profile: InputScrollProfile
    let state: InputControlState

    init(
        device: InputDeviceDescriptor?,
        kind: InputDeviceDescriptor.Kind,
        profile: InputScrollProfile,
        state: InputControlState
    ) {
        self.device = device
        self.kind = kind
        self.profile = profile
        self.state = state
    }

    init(device: InputDeviceDescriptor, profile: InputScrollProfile, state: InputControlState) {
        self.init(device: device, kind: device.kind, profile: profile, state: state)
    }

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader(device?.name ?? "No \(kind.rawValue.lowercased()) detected", systemImage: kind.icon) {
                InputStateLabel(state: device == nil ? .disabled : state)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    OnePlusKeyValueRow(
                        row.label,
                        value: row.value ?? "Not reported",
                        monospaced: row.monospaced
                    )
                }
                OnePlusKeyValueRow("Scroll profile", value: profile.enabled ? "Enabled" : "Off")
            }
            .padding(OnePlusMetrics.cardPadding)
        }
    }

    var rows: [Row] {
        guard let device else {
            return [
                Row(label: "Model", value: nil),
                Row(label: "Vendor", value: nil),
                Row(label: "Device ID", value: nil, monospaced: true),
                Row(label: "Firmware", value: nil, monospaced: true),
                Row(label: "Serial", value: nil, monospaced: true),
                Row(label: "Connection", value: nil),
                Row(label: "Battery", value: nil),
                Row(label: "Buttons", value: nil),
                Row(label: "Resolution", value: nil),
                Row(label: "Polling", value: nil),
                Row(label: "Tracking", value: nil),
                Row(label: "Scroll speed", value: profile.speed.formatted(.number.precision(.fractionLength(2))) + "×")
            ]
        }
        return [
            Row(label: "Model", value: device.modelNumber),
            Row(label: "Vendor", value: device.vendorName),
            Row(label: "Device ID", value: String(format: "%04X:%04X", device.vendorID, device.productID), monospaced: true),
            Row(label: "Firmware", value: device.firmwareVersion, monospaced: true),
            Row(label: "Serial", value: device.serialNumber.flatMap { $0.isEmpty ? nil : $0 }, monospaced: true),
            Row(label: "Connection", value: device.connectionSummary.components(separatedBy: " · ").first),
            Row(label: "Battery", value: device.batteryPercent.map { "\($0)%" }),
            Row(label: "Buttons", value: device.buttonCount.flatMap { $0 > 0 ? $0.formatted() : nil }),
            Row(label: "Resolution", value: device.pointerResolutionDPI.map {
                $0.formatted(.number.precision(.fractionLength(0))) + " dpi"
            }),
            Row(label: "Polling", value: device.pollingRateHz.map {
                $0.formatted(.number.precision(.fractionLength(0))) + " Hz"
            }),
            Row(label: "Tracking", value: device.systemTrackingSpeed?.formatted(.number.precision(.fractionLength(2)))),
            Row(label: "Scroll speed", value: profile.speed.formatted(.number.precision(.fractionLength(2))) + "×")
        ]
    }

    struct Row {
        let label: String
        let value: String?
        var monospaced = false
    }

}

struct InputKeyboardCard: View {
    private let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader("Keyboard", systemImage: "keyboard") {
                OnePlusStatus("System managed", state: .online)
            }
            VStack(spacing: 0) {
                OnePlusKeyValueRow("Connection", value: "Managed by macOS")
                OnePlusKeyValueRow("Battery", value: "Not reported")
                OnePlusKeyValueRow("Key repeat", value: keyRepeatLabel)
                OnePlusKeyValueRow("Function keys", value: functionKeyLabel)
            }
            .padding(OnePlusMetrics.cardPadding)
        }
    }

    private var keyRepeatLabel: String {
        guard let value = global["KeyRepeat"] as? Int else { return "System default" }
        return value <= 2 ? "Fast" : value >= 6 ? "Slow" : "Medium"
    }

    private var functionKeyLabel: String {
        (global["com.apple.keyboard.fnState"] as? Bool) == true ? "Standard F keys" : "Media keys"
    }
}

struct InputSettingRow<Control: View>: View {
    let label: String
    var help: String?
    @ViewBuilder let control: Control

    var body: some View {
        OnePlusSettingRow(label, help: help, control: { control })
    }
}

struct InputScrollProfileCard: View {
    let title: String
    let icon: String
    let deviceCount: Int
    @Binding var profile: InputScrollProfile

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader(title, systemImage: icon) {
                OnePlusStatus(deviceDetail, state: deviceCount > 0 ? .online : .offline)
            }
            OnePlusSettingRow(
                "Use this profile",
                help: "Apply this profile to \(title.lowercased()) scroll events."
            ) {
                Toggle("Use this profile", isOn: $profile.enabled)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            settingRows
        }
    }

    @ViewBuilder
    private var settingRows: some View {
        Group {
            OnePlusSettingRow(
                "Direction",
                help: "Choose natural or reversed vertical scrolling."
            ) {
                OnePlusSegmented(
                    choices: [(false, "Natural"), (true, "Reversed")],
                    selection: $profile.reverseVertical,
                    accessibilityLabel: "\(title) scroll direction"
                )
            }
            OnePlusSettingRow(
                "Scroll speed",
                help: "Multiply every scroll delta from this device type."
            ) {
                HStack(spacing: OnePlusMetrics.spacing[3]) {
                    Slider(value: $profile.speed, in: 0.35...3, step: 0.05)
                    Text(profile.speed.formatted(.number.precision(.fractionLength(2))) + "×")
                        .onePlusText(.mono)
                }
            }
            OnePlusSettingRow(
                "Horizontal scrolling",
                help: "Pass horizontal scroll events through."
            ) {
                Toggle("Horizontal scrolling", isOn: $profile.horizontalEnabled)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow(
                "Reverse horizontal",
                help: "Invert left and right scrolling."
            ) {
                Toggle("Reverse horizontal", isOn: $profile.reverseHorizontal)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            .disabled(!profile.horizontalEnabled)
            OnePlusSettingRow(
                "Shift scrolls sideways",
                help: "Hold Shift and use the wheel to move sideways."
            ) {
                Toggle("Shift scrolls sideways", isOn: $profile.shiftScrollsHorizontally)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            .disabled(!profile.horizontalEnabled)
            OnePlusSettingRow(
                "Smoothing",
                help: "Split a coarse wheel notch into smaller steps.",
                separator: false
            ) {
                Toggle("Smoothing", isOn: $profile.smooth)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
        }
        .disabled(!profile.enabled)
    }

    private var deviceDetail: String {
        switch deviceCount {
        case 0: "No device"
        case 1: "1 connected"
        default: "\(deviceCount) connected"
        }
    }
}
