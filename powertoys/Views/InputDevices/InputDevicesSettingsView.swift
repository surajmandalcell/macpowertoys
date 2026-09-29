import OnePlusUI
import SwiftUI

struct InputDevicesSettingsView: View {
    private let showsHeader: Bool
    private let showsContainerScroll: Bool
    private let contentTopInset: CGFloat
    private let density: OnePlusDensity
    private let embedsInPage: Bool

    init() {
        showsHeader = false
        showsContainerScroll = false
        contentTopInset = 0
        density = .regular
        embedsInPage = true
    }

    init(
        showsHeader: Bool,
        showsContainerScroll: Bool,
        contentTopInset: CGFloat = OnePlusMetrics.contentTop,
        density: OnePlusDensity = .compact
    ) {
        self.showsHeader = showsHeader
        self.showsContainerScroll = showsContainerScroll
        self.contentTopInset = contentTopInset
        self.density = density
        embedsInPage = false
    }

    @ViewBuilder
    var body: some View {
        if embedsInPage {
            InputDevicesSettingsContent()
        } else {
            panelContent
                .onePlusDensity(density)
        }
    }

    private var panelContent: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            if showsHeader { OnePlusSectionTitle("Scrolling") }
            Group {
                if showsContainerScroll {
                    ScrollView {
                        InputDevicesSettingsContent(includesDeviceFooter: false)
                    }
                    .onePlusScrollIndicators()
                } else {
                    InputDevicesSettingsContent(includesDeviceFooter: false)
                }
            }
            InputScrollDeviceBar()
        }
        .padding(.horizontal, density.gutter)
        .padding(.top, contentTopInset)
        .padding(.bottom, OnePlusMetrics.gutter)
    }
}

struct InputScrollDeviceBar: View {
    @State private var manager = InputDevicesManager.shared

    var body: some View {
        OnePlusCard {
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
    }
}

struct InputDevicesSettingsContent: View {
    @State private var manager = InputDevicesManager.shared
    var includesDeviceFooter = true

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            scrollControlCard
            mouseProfile
            trackpadProfile
            if includesDeviceFooter { InputScrollDeviceBar() }
        }
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
                            .buttonStyle(OnePlusButtonStyle(.neutral))
                        Button("Settings") { manager.openPrivacySettings() }
                            .buttonStyle(OnePlusButtonStyle(.ghost))
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
