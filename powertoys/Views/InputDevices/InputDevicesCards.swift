import OnePlusUI
import SwiftUI

enum InputControlState {
    case disabled
    case permissionNeeded
    case passthrough
    case active
    case unavailable

    static func state(
        settings: InputDevicesSettings,
        permissionGranted: Bool,
        interceptionActive: Bool,
        kind: InputDeviceDescriptor.Kind
    ) -> InputControlState {
        guard settings.scrollControlEnabled else { return .disabled }
        guard permissionGranted else { return .permissionNeeded }
        let profile = InputScrollPolicy.profile(for: kind, settings: settings)
        guard profile.enabled else { return .passthrough }
        return interceptionActive ? .active : .unavailable
    }

    var title: String {
        switch self {
        case .disabled: "Not controlled"
        case .permissionNeeded: "Permission needed"
        case .passthrough: "Passthrough"
        case .active: "Controlled"
        case .unavailable: "Control inactive"
        }
    }

    var status: OnePlusStatus.State {
        switch self {
        case .disabled, .passthrough: .offline
        case .permissionNeeded, .unavailable: .warning
        case .active: .online
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

    @ViewBuilder
    var body: some View {
        if device == nil {
            OnePlusLinearAppletGroup {
                OnePlusLinearAppletRow("No \(kind.rawValue.lowercased()) detected") { EmptyView() }
            }
        } else {
            deviceContent
        }
    }

    private var deviceContent: some View {
        OnePlusLinearAppletSection(device?.name ?? kind.rawValue) {
            OnePlusLinearAppletRow("Control") { InputStateLabel(state: state) }
            ForEach(rows, id: \.label) { row in
                OnePlusLinearAppletRow(row.label, value: row.value)
            }
            OnePlusLinearAppletRow("Scroll profile", value: profile.enabled ? "Enabled" : "Off")
        }
    }

    var rows: [Row] {
        guard let device else {
            return []
        }
        return [
            device.modelNumber.map { Row(label: "Model", value: $0) },
            device.vendorName.map { Row(label: "Vendor", value: $0) },
            device.vendorID > 0 || device.productID > 0
                ? Row(label: "Device ID", value: String(format: "%04X:%04X", device.vendorID, device.productID), monospaced: true) : nil,
            device.locationID > 0 ? Row(label: "Location", value: String(format: "%08X", device.locationID), monospaced: true) : nil,
            device.firmwareVersion.map { Row(label: "Firmware", value: $0, monospaced: true) },
            device.serialNumber.flatMap { $0.isEmpty ? nil : Row(label: "Serial", value: $0, monospaced: true) },
            device.connectionSummary.components(separatedBy: " · ").first.map { Row(label: "Connection", value: $0) },
            device.batteryPercent.map { Row(label: "Battery", value: "\($0)%") },
            device.buttonCount.flatMap { $0 > 0 ? Row(label: "Buttons", value: $0.formatted()) : nil },
            device.maxInputReportSize.flatMap { $0 > 0 ? Row(label: "Input report", value: "\($0) bytes") : nil },
            device.pointerResolutionDPI.map {
                Row(label: "Resolution", value: $0.formatted(.number.precision(.fractionLength(0))) + " dpi")
            },
            device.pollingRateHz.map {
                Row(label: "Polling", value: $0.formatted(.number.precision(.fractionLength(0))) + " Hz")
            },
            device.systemTrackingSpeed.map {
                Row(label: "Tracking", value: $0.formatted(.number.precision(.fractionLength(2))))
            },
            Row(label: "Scroll speed", value: profile.speed.formatted(.number.precision(.fractionLength(2))) + "×")
        ].compactMap { $0 }
    }

    struct Row {
        let label: String
        let value: String
        var monospaced = false
    }

}

nonisolated struct InputKeyboardDetails: Equatable, Sendable {
    let keyRepeat: String
    let functionKeys: String

    init(keyRepeat: Int?, standardFunctionKeys: Bool?) {
        if let keyRepeat {
            self.keyRepeat = keyRepeat <= 2 ? "Fast" : keyRepeat >= 6 ? "Slow" : "Medium"
        } else {
            self.keyRepeat = "System default"
        }
        switch standardFunctionKeys {
        case true: functionKeys = "Standard F keys"
        case false: functionKeys = "Media keys"
        case nil: functionKeys = "System default"
        }
    }

    static func load() -> Self {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        return Self(
            keyRepeat: global["KeyRepeat"] as? Int,
            standardFunctionKeys: global["com.apple.keyboard.fnState"] as? Bool
        )
    }
}

struct InputKeyboardCard: View {
    @State private var details = InputKeyboardDetails(keyRepeat: nil, standardFunctionKeys: nil)

    var body: some View {
        OnePlusLinearAppletSection("Keyboard") {
            OnePlusLinearAppletRow("Control") { OnePlusStatus("System managed", state: .online) }
            OnePlusLinearAppletRow("Connection", value: "Managed by macOS")
            OnePlusLinearAppletRow("Key repeat", value: details.keyRepeat)
            OnePlusLinearAppletRow("Function keys", value: details.functionKeys)
        }
        .task {
            let loaded = await Task.detached(priority: .utility) {
                InputKeyboardDetails.load()
            }.value
            guard !Task.isCancelled else { return }
            details = loaded
        }
    }
}

struct InputScrollProfileCard: View {
    let title: String
    let icon: String
    let deviceCount: Int
    @Binding var profile: InputScrollProfile
    var body: some View { linearContent }

    private var linearContent: some View {
        OnePlusLinearAppletSection(title) {
            OnePlusLinearAppletRow("Use this profile", detail: deviceDetail, systemImage: "power") {
                Toggle("Use \(title.lowercased()) profile", isOn: $profile.enabled).toggleStyle(OnePlusLinearSwitchStyle())
            }
            .help("Apply this profile to \(title.lowercased()) scroll events.")
            OnePlusLinearAppletRow("Direction", systemImage: "arrow.up.arrow.down") {
                OnePlusLinearSegmented(choices: [(false, "System"), (true, "Reversed")], selection: $profile.reverseVertical,
                                       accessibilityLabel: "\(title) scroll direction", sizing: .fitted)
            }
            .help("Keep the macOS scroll direction or reverse it.")
            .disabled(!profile.enabled)
            OnePlusLinearAppletSliderRow("Scroll speed", value: $profile.speed, in: 0.35...3, step: 0.05,
                                         systemImage: "speedometer") {
                $0.formatted(.number.precision(.fractionLength(2)))
            }
            .help("Multiply every scroll delta from this device type.")
            .disabled(!profile.enabled)
            linearSwitch("Horizontal scrolling", "\(title) horizontal scrolling", $profile.horizontalEnabled, glyph: "arrow.left.arrow.right",
                         help: "Pass horizontal scroll events through.", enabled: profile.enabled)
            linearSwitch("Reverse horizontal", "\(title) reverse horizontal", $profile.reverseHorizontal, glyph: "arrow.uturn.left",
                         help: "Invert left and right scrolling.", enabled: profile.enabled && profile.horizontalEnabled)
            linearSwitch("Shift scrolls sideways", "\(title) Shift scrolls sideways", $profile.shiftScrollsHorizontally, glyph: "shift",
                         help: "Hold Shift and use the wheel to move sideways.", enabled: profile.enabled && profile.horizontalEnabled)
            linearSwitch("Smoothing", "\(title) smoothing", $profile.smooth, glyph: "water.waves",
                         help: "Split a coarse wheel notch into smaller steps.", enabled: profile.enabled)
        }
    }

    private func linearSwitch(_ label: String, _ accessibilityLabel: String, _ isOn: Binding<Bool>, glyph: String, help: String,
                              enabled: Bool) -> some View {
        OnePlusLinearAppletRow(label, systemImage: glyph) {
            Toggle(accessibilityLabel, isOn: isOn).toggleStyle(OnePlusLinearSwitchStyle())
        }
        .help(help)
        .disabled(!enabled)
    }

    private var deviceDetail: String {
        switch deviceCount {
        case 0: "No device"
        case 1: "1 connected"
        default: "\(deviceCount) connected"
        }
    }
}
