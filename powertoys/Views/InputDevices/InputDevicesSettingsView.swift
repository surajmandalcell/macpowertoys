import OnePlusUI
import SwiftUI

struct InputScrollDeviceBar: View {
    @State private var manager = InputDevicesManager.shared
    var isExpanded: Binding<Bool>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let isExpanded {
                InputDisclosureHeader(title: "Scroll device", detail: manager.settings.eventOverride.title,
                                      isExpanded: isExpanded)
            }
            if isExpanded?.wrappedValue != false {
                OnePlusSettingRow(
                    isExpanded == nil ? "Scroll device" : "Use profile",
                    help: "Automatic separates continuous trackpad events from mouse wheel steps.",
                    separator: false
                ) {
                    OnePlusSelect(
                        choices: InputEventOverride.allCases.map { ($0, $0.title) },
                        selection: Binding(
                            get: { manager.settings.eventOverride },
                            set: { value in manager.update { $0.eventOverride = value } }
                        ),
                        accessibilityLabel: "Scroll device"
                    )
                }
                .onePlusRowHover()
            }
        }
    }
}

struct InputDevicesSettingsContent: View {
    @State private var manager = InputDevicesManager.shared
    @Environment(\.onePlusDensity) private var density
    var includesDeviceFooter = true
    var collapsible = false
    @AppStorage("tray.inputDevices.mouse.expanded") private var mouseExpanded = false
    @AppStorage("tray.inputDevices.trackpad.expanded") private var trackpadExpanded = false
    @AppStorage("tray.inputDevices.scrollDevice.expanded") private var scrollDeviceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            scrollControlRows
            if density == .regular {
                HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                    mouseProfile
                    trackpadProfile
                }
            } else {
                mouseProfile
                trackpadProfile
            }
            if includesDeviceFooter { InputScrollDeviceBar(isExpanded: collapsible ? $scrollDeviceExpanded : nil) }
        }
    }

    private var scrollControlRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnePlusSettingRow(
                "Use custom scrolling",
                help: "Apply these profiles in every app.",
                controlWidth: OnePlusMetrics.contentControlHeight,
                separator: !manager.permissionGranted || manager.errorMessage != nil
            ) {
                Toggle(
                    "Use custom scrolling",
                    isOn: setting(
                        get: { $0.scrollControlEnabled },
                        set: { $0.scrollControlEnabled = $1 }
                    )
                )
                .labelsHidden()
                .toggleStyle(OnePlusSwitchStyle())
            }
            .onePlusRowHover()
            if !manager.permissionGranted {
                OnePlusSettingRow(
                    "Accessibility",
                    help: "Allow MacPowerToys to adjust scroll events.",
                    separator: manager.errorMessage != nil
                ) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Button("Grant") { manager.requestPermission() }
                            .buttonStyle(OnePlusButtonStyle(.neutral))
                        Button("Settings") { manager.openPrivacySettings() }
                            .buttonStyle(OnePlusButtonStyle(.ghost))
                    }
                }
                .onePlusRowHover()
            }
            if let errorMessage = manager.errorMessage {
                OnePlusBanner(errorMessage, tone: .error)
            }
        }
    }

    private var mouseProfile: some View {
        InputScrollProfileCard(
            title: "Mouse",
            icon: InputDeviceDescriptor.Kind.mouse.icon,
            deviceCount: deviceCount(of: .mouse),
            profile: profileBinding(\.mouse),
            isExpanded: collapsible ? $mouseExpanded : nil
        )
    }

    private var trackpadProfile: some View {
        InputScrollProfileCard(
            title: "Trackpad",
            icon: InputDeviceDescriptor.Kind.trackpad.icon,
            deviceCount: deviceCount(of: .trackpad),
            profile: profileBinding(\.trackpad),
            isExpanded: collapsible ? $trackpadExpanded : nil
        )
    }

    private func deviceCount(of kind: InputDeviceDescriptor.Kind) -> Int {
        manager.devices.filter { $0.kind == kind }.count
    }

    private func setting<Value>(
        get: @escaping (InputDevicesSettings) -> Value,
        set: @escaping (inout InputDevicesSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(manager.settings) },
            set: { value in manager.update { set(&$0, value) } }
        )
    }

    private func profileBinding(
        _ keyPath: WritableKeyPath<InputDevicesSettings, InputScrollProfile>
    ) -> Binding<InputScrollProfile> {
        setting(get: { $0[keyPath: keyPath] }, set: { $0[keyPath: keyPath] = $1 })
    }
}
