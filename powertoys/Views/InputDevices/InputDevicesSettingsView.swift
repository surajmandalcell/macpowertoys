import OnePlusUI
import SwiftUI

struct InputScrollDeviceBar: View {
    @State private var manager = InputDevicesManager.shared
    var body: some View {
        OnePlusLinearAppletGroup {
            OnePlusLinearAppletRow("Scroll device", systemImage: "computermouse") { scrollDeviceSelect }
                .help("Automatic separates continuous trackpad events from mouse wheel steps.")
        }
    }

    private var scrollDeviceSelect: some View {
        OnePlusLinearSelect(
            choices: InputEventOverride.allCases.map { ($0, $0.title) },
            selection: Binding(
                get: { manager.settings.eventOverride },
                set: { value in manager.update { $0.eventOverride = value } }
            ),
            accessibilityLabel: "Scroll device"
        )
    }
}

struct InputDevicesSettingsContent: View {
    @State private var manager = InputDevicesManager.shared
    var includesDeviceFooter = true

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            linearScrollControl
            mouseProfile
            trackpadProfile
            if includesDeviceFooter { InputScrollDeviceBar() }
        }
    }

    private var linearScrollControl: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.appletSectionGap) {
            OnePlusLinearAppletSection("Scrolling") {
                OnePlusLinearAppletRow("Use custom scrolling", systemImage: "scroll") {
                    Toggle("Use custom scrolling", isOn: setting(
                        get: { $0.scrollControlEnabled },
                        set: { $0.scrollControlEnabled = $1 }
                    ))
                    .toggleStyle(OnePlusLinearSwitchStyle())
                }
                .help("Apply these profiles in every app.")
            }
            if let problem = PermissionCenter.shared.accessibilityProblem {
                OnePlusLinearBanner(.warning, title: "Scrolling is off", message: problem) {
                    Button("Fix") { manager.fixAccessibility() }.buttonStyle(OnePlusLinearButtonStyle(.soft))
                }
                .permissionWatch(.accessibility)
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
            profile: profileBinding(\.mouse)
        )
    }

    private var trackpadProfile: some View {
        InputScrollProfileCard(
            title: "Trackpad",
            icon: InputDeviceDescriptor.Kind.trackpad.icon,
            deviceCount: deviceCount(of: .trackpad),
            profile: profileBinding(\.trackpad)
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
