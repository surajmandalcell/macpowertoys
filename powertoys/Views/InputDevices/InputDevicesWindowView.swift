import SwiftUI

private enum InputDevicesPage: String, CaseIterable, Identifiable {
    case devices = "Devices"
    case scrolling = "Scrolling"
    case about = "About"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .devices: "computermouse"
        case .scrolling: "scroll"
        case .about: "info.circle"
        }
    }
}

struct InputDevicesWindowView: View {
    @State private var manager = InputDevicesManager.shared
    @State private var page = InputDevicesPage.devices

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: UtilityLayout.compactSidebarWidth)
            content
                .utilityContentTransition(value: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(WindowAccessor(identifier: "input-devices"))
        .onAppear { manager.refresh() }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .sidebar)
            SidebarTitle(text: "Input Devices")
            VStack(spacing: 4) {
                ForEach(InputDevicesPage.allCases) { item in
                    SidebarRow(icon: item.icon, title: item.rawValue, isSelected: page == item) {
                        page = item
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, UtilityLayout.workspaceContentTopInset)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .devices: devicesPage
        case .scrolling: scrollingPage
        case .about: ToolAboutView(toolId: "input-devices")
        }
    }

    private var devicesPage: some View {
        WorkspacePage(
            "Devices",
            subtitle: deviceSubtitle,
            actions: {
                Button("Refresh", systemImage: "arrow.clockwise") { manager.refresh() }
            }
        ) {
            Group {
                if manager.devices.isEmpty {
                    ContentUnavailableView(
                        "No Pointing Devices Found",
                        systemImage: "computermouse",
                        description: Text("Connect a mouse or trackpad, then refresh.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                        ForEach(manager.devices) { device in
                            InputDeviceCard(
                                device: device,
                                profile: profile(for: device.kind),
                                state: InputControlState.state(
                                    settings: manager.settings,
                                    permissionGranted: manager.permissionGranted,
                                    kind: device.kind
                                )
                            )
                        }
                    }
                }
            }
            .utilityContentTransition(value: manager.devices.isEmpty)
        }
    }

    private var deviceSubtitle: String {
        let count = manager.devices.count
        return count == 1 ? "1 connected" : "\(count) connected"
    }

    private var scrollingPage: some View {
        WorkspacePage("Scrolling", subtitle: manager.interceptionActive ? "Control active" : "Control inactive") {
            section("Scroll Control", card: true) {
                InputSettingRow(
                    label: "Adjust scrolling system wide",
                    help: "Install the scroll event tap so these profiles apply outside MacPowerToys."
                ) {
                    Toggle("Adjust scrolling system wide", isOn: setting(
                        get: { $0.scrollControlEnabled },
                        set: { $0.scrollControlEnabled = $1 }
                    ))
                }
                InputSettingRow(
                    label: "Treat scroll events as",
                    help: "Automatic sends continuous events to Trackpad and wheel notches to Mouse."
                ) {
                    Picker("Treat scroll events as", selection: setting(
                        get: { $0.eventOverride },
                        set: { $0.eventOverride = $1 }
                    )) {
                        ForEach(InputEventOverride.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                if !manager.permissionGranted {
                    InputSettingRow(label: "Accessibility permission") {
                        HStack(spacing: 8) {
                            Button("Grant Permission") { manager.requestPermission() }
                            Button("Open Privacy Settings") { manager.openPrivacySettings() }
                        }
                    }
                }
                if let errorMessage = manager.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("Profiles") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    InputScrollProfileCard(
                        title: "Mouse",
                        icon: InputDeviceDescriptor.Kind.mouse.icon,
                        deviceCount: deviceCount(of: .mouse),
                        profile: profileBinding(\.mouse)
                    )
                    InputScrollProfileCard(
                        title: "Trackpad",
                        icon: InputDeviceDescriptor.Kind.trackpad.icon,
                        deviceCount: deviceCount(of: .trackpad),
                        profile: profileBinding(\.trackpad)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        card: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).utilitySectionHeader()
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .modifier(OptionalSectionCard(isEnabled: card))
        }
    }

    private func profile(for kind: InputDeviceDescriptor.Kind) -> InputScrollProfile {
        kind == .mouse ? manager.settings.mouse : manager.settings.trackpad
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

private struct OptionalSectionCard: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.utilitySectionCard()
        } else {
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    InputDevicesWindowView().frame(width: 980, height: 700)
}
