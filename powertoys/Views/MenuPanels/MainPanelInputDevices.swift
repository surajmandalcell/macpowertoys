import OnePlusUI
import SwiftUI

/// The Input Devices tab in Home's language: a Mouse and Trackpad tile pair, the scrolling switch, one floating
/// group per profile with a disclosure row, and the Open key. Rows use Home's 32 pt row and hover fill step.
struct InputDevicesTrayView: View {
    @State private var manager = InputDevicesManager.shared
    @Environment(\.onePlusIsVisible) private var isVisible
    @AppStorage("tray.inputDevices.mouse.expanded") private var mouseExpanded = false
    @AppStorage("tray.inputDevices.trackpad.expanded") private var trackpadExpanded = false
    @AppStorage("tray.inputDevices.scrollDevice.expanded") private var scrollDeviceExpanded = false
    var showsOpenKey = true

    var body: some View {
        VStack(alignment: .leading, spacing: TrayPopoverLayout.style.blockGap) {
            OnePlusLinearBento(style: .instrument) {
                InputDeviceKindTile(kind: .mouse, devices: devices(.mouse), state: state(.mouse))
            } trailing: {
                InputDeviceKindTile(kind: .trackpad, devices: devices(.trackpad), state: state(.trackpad))
            }
            scrollingGroup
            accessibilityBanner
            if let errorMessage = manager.errorMessage { OnePlusLinearBanner(.warning, title: errorMessage) }
            InputPanelProfileGroup(title: "Mouse", kind: .mouse, deviceCount: devices(.mouse).count,
                                   profile: profileBinding(\.mouse), isExpanded: $mouseExpanded)
            InputPanelProfileGroup(title: "Trackpad", kind: .trackpad, deviceCount: devices(.trackpad).count,
                                   profile: profileBinding(\.trackpad), isExpanded: $trackpadExpanded)
            scrollDeviceGroup
            if showsOpenKey {
                OnePlusLinearActionBar([OnePlusLinearAction("Open Input Devices", systemImage: TrayTab.inputDevices.symbol,
                                                            id: "tray.action.input-devices") {
                    ToolActionRouter.shared.open(toolID: TrayTab.inputDevices.rawValue)
                }])
            }
        }
        .modifier(MainPanelReveal(.inputDevices))
        .onChange(of: isVisible, initial: true) { _, visible in
            if visible { manager.refresh() }
        }
    }

    private var scrollingGroup: some View {
        OnePlusLinearList(style: .panel) {
            OnePlusLinearControlRow("Use custom scrolling", systemImage: "scroll", titleWidth: nil) {
                Toggle("Use custom scrolling", isOn: Binding(
                    get: { manager.settings.scrollControlEnabled },
                    set: { value in manager.update { $0.scrollControlEnabled = value } }
                ))
                .toggleStyle(OnePlusLinearSwitchStyle())
            }
            .help("Apply these profiles in every app.")
        }
    }

    @ViewBuilder
    private var accessibilityBanner: some View {
        if let problem = PermissionCenter.shared.accessibilityProblem {
            OnePlusLinearBanner(.warning, title: "Scrolling is off", message: problem) {
                Button("Fix") { manager.fixAccessibility() }.buttonStyle(OnePlusLinearKeyButtonStyle.compact)
            }
            .permissionWatch(.accessibility)
        }
    }

    private var scrollDeviceGroup: some View {
        OnePlusLinearList(style: .panel) {
            OnePlusLinearDisclosureRow("Scroll device", systemImage: "computermouse",
                                       detail: scrollDeviceExpanded ? nil : manager.settings.eventOverride.title,
                                       isExpanded: $scrollDeviceExpanded)
            if scrollDeviceExpanded {
                OnePlusLinearControlRow("Use profile", systemImage: "slider.horizontal.3", titleWidth: nil) {
                    OnePlusLinearSelect(
                        choices: InputEventOverride.allCases.map { ($0, $0.title) },
                        selection: Binding(
                            get: { manager.settings.eventOverride },
                            set: { value in manager.update { $0.eventOverride = value } }
                        ),
                        accessibilityLabel: "Scroll device"
                    )
                }
                .help("Automatic separates continuous trackpad events from mouse wheel steps.")
            }
        }
    }

    private func devices(_ kind: InputDeviceDescriptor.Kind) -> [InputDeviceDescriptor] {
        manager.devices.filter { $0.kind == kind }
    }

    private func state(_ kind: InputDeviceDescriptor.Kind) -> InputControlState {
        InputControlState.state(settings: manager.settings, permissionGranted: manager.permissionGranted,
                                interceptionActive: manager.interceptionActive, kind: kind)
    }

    private func profileBinding(_ keyPath: WritableKeyPath<InputDevicesSettings, InputScrollProfile>) -> Binding<InputScrollProfile> {
        Binding(get: { manager.settings[keyPath: keyPath] }, set: { value in manager.update { $0[keyPath: keyPath] = value } })
    }
}

/// A Home-style short tile for one device kind: the control state, then the lowest battery as a bar, or the
/// device name when no device reports a battery.
struct InputDeviceKindTile: View {
    let kind: InputDeviceDescriptor.Kind
    let devices: [InputDeviceDescriptor]
    let state: InputControlState

    private var color: Color { kind == .mouse ? OnePlusLinearColor.cpu : OnePlusLinearColor.gpu }
    private var battery: Int? { devices.compactMap(\.batteryPercent).min() }
    private var summary: String {
        switch devices.count {
        case 0: "Not connected"
        case 1: devices[0].name
        default: "\(devices.count) connected"
        }
    }

    var body: some View {
        OnePlusLinearTile(height: OnePlusLinearMetrics.shortTile, usage: battery.map {
            OnePlusLinearUsage(Double($0) / 100, color: $0 <= 20 ? OnePlusLinearColor.warning : OnePlusLinearColor.battery,
                               caption: summary, pace: .battery)
        }, tint: color) {
            if let battery {
                OnePlusLinearTileLabel(kind.rawValue, systemImage: kind.icon, color: color) {
                    OnePlusLinearInlineValue(String(battery), unit: "%", color: OnePlusLinearColor.battery, pace: .battery)
                }
            } else {
                OnePlusLinearTileLabel(kind.rawValue, systemImage: kind.icon, color: color, meta: devices.isEmpty ? "" : state.title)
                Spacer(minLength: 0)
                Text(summary).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
                    .lineLimit(1).truncationMode(.middle).help(summary)
                    .padding(.bottom, OnePlusLinearMetrics.usageRowBottom - 2)
            }
        }
        .help(devices.isEmpty ? summary : "\(summary), \(state.title)")
    }
}

/// One profile as a floating group: the disclosure row (direction and speed while closed), then the profile rows.
struct InputPanelProfileGroup: View {
    let title: String
    let kind: InputDeviceDescriptor.Kind
    let deviceCount: Int
    @Binding var profile: InputScrollProfile
    @Binding var isExpanded: Bool

    var body: some View {
        OnePlusLinearList(style: .panel) {
            OnePlusLinearDisclosureRow(title, systemImage: kind.icon, detail: Self.detail(profile, expanded: isExpanded,
                                                                                         deviceCount: deviceCount),
                                       isExpanded: $isExpanded)
            if isExpanded { rows }
        }
    }

    static func detail(_ profile: InputScrollProfile, expanded: Bool, deviceCount: Int) -> String {
        if expanded {
            return switch deviceCount {
            case 0: "No device"
            case 1: "1 connected"
            default: "\(deviceCount) connected"
            }
        }
        return "\(profile.reverseVertical ? "Reversed" : "System") \(profile.speed.formatted(.number.precision(.fractionLength(2))))×"
    }

    @ViewBuilder
    private var rows: some View {
        let name = title.lowercased()
        OnePlusLinearControlRow("Use this profile", systemImage: "power", titleWidth: nil) {
            Toggle("Use \(name) profile", isOn: $profile.enabled).toggleStyle(OnePlusLinearSwitchStyle())
        }
        .help("Apply this profile to \(name) scroll events.")
        Group {
            OnePlusLinearControlRow("Direction", systemImage: "arrow.up.arrow.down", titleWidth: nil) {
                OnePlusLinearSegmented(choices: [(false, "System"), (true, "Reversed")], selection: $profile.reverseVertical,
                                       accessibilityLabel: "\(title) scroll direction", sizing: .fitted)
            }
            .help("Keep the macOS scroll direction or reverse it.")
            OnePlusLinearControlRow("Speed", systemImage: "speedometer", titleWidth: nil) {
                OnePlusLinearSlider("\(title) scroll speed", value: $profile.speed, in: 0.35...3, step: 0.05)
                OnePlusLinearNumberText(profile.speed.formatted(.number.precision(.fractionLength(2))) + "×", pace: .process)
                    .linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary).monospacedDigit()
                    .frame(width: OnePlusLinearMetrics.cpuColumn, alignment: .trailing)
            }
            .help("Multiply every scroll delta from this device type.")
            toggleRow("Horizontal scrolling", "arrow.left.arrow.right", $profile.horizontalEnabled,
                      help: "Pass horizontal scroll events through.")
            Group {
                toggleRow("Reverse horizontal", "arrow.uturn.left", $profile.reverseHorizontal,
                          help: "Invert left and right scrolling.")
                toggleRow("Shift scrolls sideways", "shift", $profile.shiftScrollsHorizontally,
                          help: "Hold Shift and use the wheel to move sideways.")
            }
            .disabled(!profile.horizontalEnabled)
            toggleRow("Smoothing", "water.waves", $profile.smooth, help: "Split a coarse wheel notch into smaller steps.")
        }
        .disabled(!profile.enabled)
    }

    private func toggleRow(_ label: String, _ glyph: String, _ isOn: Binding<Bool>, help: String) -> some View {
        OnePlusLinearControlRow(label, systemImage: glyph, titleWidth: nil) {
            Toggle("\(title) \(label.lowercased())", isOn: isOn).toggleStyle(OnePlusLinearSwitchStyle())
        }
        .help(help)
    }
}
