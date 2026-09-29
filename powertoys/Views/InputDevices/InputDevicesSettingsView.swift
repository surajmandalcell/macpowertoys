import OnePlusUI
import SwiftUI

struct InputDevicesSettingsView: View {
    var showsHeader = true
    var showsContainerScroll = true
    var contentTopInset: CGFloat = OnePlusMetrics.contentTop
    var density: OnePlusDensity = .compact

    @ViewBuilder
    var body: some View {
        VStack(spacing: 0) {
            if showsContainerScroll {
                ScrollView { settingsContent }.onePlusScrollIndicators()
            } else {
                settingsContent
            }
            InputScrollDeviceBar()
        }
        .onePlusDensity(density)
    }

    private var settingsContent: some View {
        InputDevicesScrollSettings(showsHeaders: showsHeader)
            .padding(.horizontal, density.gutter)
            .padding(.top, contentTopInset)
            .padding(.bottom, OnePlusMetrics.gutter)
    }
}

struct InputScrollDeviceBar: View {
    @State private var manager = InputDevicesManager.shared

    var body: some View {
        VStack(spacing: 0) {
            OnePlusColor.line.frame(height: 1)
            OnePlusSettingRow(
                "Scroll device",
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
        }
        .background(OnePlusColor.window)
    }
}

struct InputDevicesScrollSettings: View {
    var showsHeaders = true

    @State private var manager = InputDevicesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            if showsHeaders { OnePlusSectionTitle("Scroll control") }
            scrollControlCard
            if showsHeaders { OnePlusSectionTitle("Profiles") }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                    mouseProfile
                    trackpadProfile
                }
                VStack(spacing: OnePlusMetrics.cardGap) {
                    mouseProfile
                    trackpadProfile
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { manager.refresh() }
    }

    private var scrollControlCard: some View {
        OnePlusCard {
            OnePlusCardHeader("System-wide control", systemImage: "cursorarrow.motionlines") {
                OnePlusStatus(manager.interceptionActive ? "Active" : "Inactive",
                              state: manager.interceptionActive ? .success : .offline)
            }
            OnePlusSettingRow(
                "Adjust scrolling system wide",
                caption: "Use the mouse and trackpad profiles outside MacPowerToys.",
                separator: !manager.permissionGranted || manager.errorMessage != nil
            ) {
                Toggle(
                    "Adjust scrolling system wide",
                    isOn: setting(
                        get: { $0.scrollControlEnabled },
                        set: { $0.scrollControlEnabled = $1 }
                    )
                )
                .labelsHidden()
                .toggleStyle(OnePlusSwitchStyle())
            }
            if !manager.permissionGranted {
                OnePlusSettingRow(
                    "Accessibility permission",
                    caption: "Allow MacPowerToys to adjust scroll events.",
                    separator: manager.errorMessage != nil
                ) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Button("Grant") { manager.requestPermission() }
                            .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
                        Button("Settings") { manager.openPrivacySettings() }
                            .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    }
                }
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
