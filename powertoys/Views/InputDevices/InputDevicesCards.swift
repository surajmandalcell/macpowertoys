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
            OnePlusCardHeader("No \(kind.rawValue.lowercased()) detected", systemImage: kind.icon)
        } else {
            deviceContent
        }
    }

    private var deviceContent: some View {
        OnePlusCard {
            OnePlusCardHeader(device?.name ?? kind.rawValue, systemImage: kind.icon) {
                InputStateLabel(state: device == nil ? .disabled : state)
            }
            VStack(spacing: 0) {
                ForEach(rows, id: \.label) { row in
                    OnePlusKeyValueRow(
                        row.label,
                        value: row.value,
                        monospaced: row.monospaced
                    )
                    .onePlusRowHover()
                }
                OnePlusKeyValueRow("Scroll profile", value: profile.enabled ? "Enabled" : "Off")
                    .onePlusRowHover()
            }
            .padding(OnePlusMetrics.cardPadding)
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
        OnePlusCard {
            OnePlusCardHeader("Keyboard", systemImage: "keyboard") {
                OnePlusStatus("System managed", state: .online)
            }
            VStack(spacing: 0) {
                OnePlusKeyValueRow("Connection", value: "Managed by macOS")
                    .onePlusRowHover()
                OnePlusKeyValueRow("Key repeat", value: details.keyRepeat)
                    .onePlusRowHover()
                OnePlusKeyValueRow("Function keys", value: details.functionKeys)
                    .onePlusRowHover()
            }
            .padding(OnePlusMetrics.cardPadding)
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
    var isExpanded: Binding<Bool>? = nil

    @ViewBuilder
    var body: some View {
        if isExpanded == nil {
            OnePlusCard { profileContent }
        } else {
            profileContent
                .environment(\.onePlusCardPadding, 0)
        }
    }

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let isExpanded {
                InputDisclosureHeader(title: title, detail: headerDetail, isExpanded: isExpanded)
            } else {
                OnePlusCardHeader(title, systemImage: icon) {
                    OnePlusStatus(deviceDetail, state: deviceCount > 0 ? .online : .offline)
                }
            }
            if isExpanded?.wrappedValue != false {
                OnePlusSettingRow(
                    "Use this profile",
                    help: "Apply this profile to \(title.lowercased()) scroll events.",
                    controlWidth: OnePlusMetrics.contentControlHeight
                ) {
                    Toggle("Use \(title.lowercased()) profile", isOn: $profile.enabled)
                        .labelsHidden()
                        .toggleStyle(OnePlusSwitchStyle())
                }
                .onePlusRowHover()
                settingRows
            }
        }
    }

    @ViewBuilder
    private var settingRows: some View {
        Group {
            OnePlusSettingRow(
                "Direction",
                help: "Keep the macOS scroll direction or reverse it."
            ) {
                OnePlusSegmented(
                    choices: [(false, "System"), (true, "Reversed")],
                    selection: $profile.reverseVertical,
                    accessibilityLabel: "\(title) scroll direction"
                )
            }
            .onePlusRowHover()
            OnePlusSettingRow(
                "Scroll speed",
                help: "Multiply every scroll delta from this device type."
            ) {
                HStack(spacing: OnePlusMetrics.spacing[3]) {
                    Slider(value: $profile.speed, in: 0.35...3, step: 0.05)
                        .accessibilityLabel("\(title) scroll speed")
                    Text(profile.speed.formatted(.number.precision(.fractionLength(2))) + "×")
                        .onePlusText(.mono)
                }
            }
            .onePlusRowHover()
            OnePlusSettingRow(
                "Horizontal scrolling",
                help: "Pass horizontal scroll events through.",
                controlWidth: OnePlusMetrics.contentControlHeight
            ) {
                Toggle("\(title) horizontal scrolling", isOn: $profile.horizontalEnabled)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            .onePlusRowHover()
            OnePlusSettingRow(
                "Reverse horizontal",
                help: "Invert left and right scrolling.",
                controlWidth: OnePlusMetrics.contentControlHeight
            ) {
                Toggle("\(title) reverse horizontal", isOn: $profile.reverseHorizontal)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            .onePlusRowHover()
            .disabled(!profile.horizontalEnabled)
            OnePlusSettingRow(
                "Shift scrolls sideways",
                help: "Hold Shift and use the wheel to move sideways.",
                controlWidth: OnePlusMetrics.contentControlHeight
            ) {
                Toggle("\(title) Shift scrolls sideways", isOn: $profile.shiftScrollsHorizontally)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            .onePlusRowHover()
            .disabled(!profile.horizontalEnabled)
            OnePlusSettingRow(
                "Smoothing",
                help: "Split a coarse wheel notch into smaller steps.",
                controlWidth: OnePlusMetrics.contentControlHeight,
                separator: false
            ) {
                Toggle("\(title) smoothing", isOn: $profile.smooth)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
            }
            .onePlusRowHover()
        }
        .disabled(!profile.enabled)
    }

    var headerDetail: String {
        if isExpanded?.wrappedValue == false {
            let direction = profile.reverseVertical ? "Reversed" : "System"
            return "\(direction) \(profile.speed.formatted(.number.precision(.fractionLength(2))))×"
        }
        return deviceDetail
    }

    private var deviceDetail: String {
        switch deviceCount {
        case 0: "No device"
        case 1: "1 connected"
        default: "\(deviceCount) connected"
        }
    }
}

struct InputDisclosureHeader: View {
    let title: String
    var detail: String? = nil
    @Binding var isExpanded: Bool
    var refreshAction: (() -> Void)? = nil
    @Environment(\.onePlusCardPadding) private var cardPadding

    var body: some View {
        Button { isExpanded.toggle() } label: {
            OnePlusCardHeader(title) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    if let detail { Text(detail).onePlusText(.caption).lineLimit(1).help(detail) }
                    if refreshAction != nil {
                        Color.clear.frame(width: OnePlusMetrics.compactControlHeight)
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .onePlusText(.cardTitle)
                        .frame(width: refreshAction == nil ? nil : OnePlusMetrics.compactControlHeight)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.panelRadius))
        .accessibilityLabel("\(title) section")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hide controls and details" : "Show controls and details")
        .overlay(alignment: .trailing) {
            if let refreshAction {
                Button("Refresh devices", systemImage: "arrow.clockwise", action: refreshAction)
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .help("Refresh devices")
                    .padding(.trailing, cardPadding + OnePlusMetrics.compactControlHeight + OnePlusMetrics.actionSpacing)
            }
        }
    }
}
