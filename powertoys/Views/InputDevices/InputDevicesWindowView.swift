import SwiftUI

private enum InputDevicesPage: String, CaseIterable, Identifiable {
    case devices = "Devices"
    case scrolling = "Scrolling"
    case appearance = "Appearance"
    case about = "About"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .devices: "computermouse"
        case .scrolling: "scroll"
        case .appearance: "paintpalette"
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
                .frame(width: 240)
            content
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
            .padding(.top, 52)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .devices: devicesPage
        case .scrolling: scrollingPage
        case .appearance: appearancePage
        case .about: ToolAboutView(toolId: "input-devices")
        }
    }

    private var devicesPage: some View {
        workspacePage(title: "Devices", subtitle: "Connected mice and trackpads detected by macOS") {
            if manager.devices.isEmpty {
                ContentUnavailableView(
                    "No Pointing Devices Found",
                    systemImage: "computermouse",
                    description: Text("Connect a mouse or trackpad, then refresh.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(manager.devices) { device in
                        deviceCard(device)
                    }
                }
            }

            HStack {
                Text("Scroll events do not expose a physical device identifier. Automatic mode uses macOS continuous-event metadata to keep mouse and trackpad profiles separate.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { manager.refresh() }
            }
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func deviceCard(_ device: InputDeviceDescriptor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind.icon)
                .font(.system(size: 22))
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(device.kind.rawValue) · \(device.isBuiltIn ? "Built in" : device.transport)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var scrollingPage: some View {
        workspacePage(title: "Scrolling", subtitle: "Independent mouse-like and trackpad-like behavior") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Input Control", isOn: setting(
                    get: { $0.scrollControlEnabled },
                    set: { $0.scrollControlEnabled = $1 }
                ))
                .font(.system(size: 13, weight: .medium))

                HStack {
                    Label(
                        manager.interceptionActive ? "Scroll control is active" : "Scroll control is inactive",
                        systemImage: manager.interceptionActive ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(manager.interceptionActive ? .green : .secondary)
                    Spacer()
                    if !manager.permissionGranted {
                        Button("Grant Permission") { manager.requestPermission() }
                        Button("Open Privacy Settings") { manager.openPrivacySettings() }
                    }
                }
                .font(.system(size: 12))

                if let errorMessage = manager.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(alignment: .top, spacing: 12) {
                profileCard(title: "Mouse", icon: "computermouse", profile: \.mouse, supportsSmoothing: true)
                profileCard(title: "Trackpad", icon: "rectangle.and.hand.point.up.left", profile: \.trackpad, supportsSmoothing: false)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("EVENT CLASSIFICATION").utilitySectionHeader()
                Picker("Treat scroll events as", selection: setting(
                    get: { $0.eventOverride },
                    set: { $0.eventOverride = $1 }
                )) {
                    ForEach(InputEventOverride.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Automatic is recommended: precise continuous events use the trackpad profile; coarse wheel events use the mouse profile.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func profileCard(
        title: String,
        icon: String,
        profile keyPath: WritableKeyPath<InputDevicesSettings, InputScrollProfile>,
        supportsSmoothing: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .medium))
            Toggle("Use this profile", isOn: profileSetting(keyPath, \.enabled))
            Toggle("Reverse vertical", isOn: profileSetting(keyPath, \.reverseVertical))
            Toggle("Reverse horizontal", isOn: profileSetting(keyPath, \.reverseHorizontal))
            Toggle("Allow horizontal scrolling", isOn: profileSetting(keyPath, \.horizontalEnabled))
            if supportsSmoothing {
                Toggle("Smooth wheel steps", isOn: profileSetting(keyPath, \.smooth))
            } else {
                Text("Trackpad events already use macOS precision scrolling.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Speed")
                Slider(value: profileSetting(keyPath, \.speed), in: 0.35...3, step: 0.05)
                Text(manager.settings[keyPath: keyPath].speed.formatted(.number.precision(.fractionLength(2))) + "×")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var appearancePage: some View {
        workspacePage(title: "Appearance", subtitle: "Choose the Input Devices icon") {
            HStack(spacing: 16) {
                iconChoice(asset: "InputDevicesLogoA", name: "Signal")
                iconChoice(asset: "InputDevicesLogoB", name: "Orbit")
                iconChoice(asset: "InputDevicesLogoC", name: "Precision")
                Spacer()
            }
            Text("The selected icon is used in the launcher the next time it refreshes.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func iconChoice(asset: String, name: String) -> some View {
        Button {
            manager.update { $0.iconAsset = asset }
        } label: {
            VStack(spacing: 8) {
                Image(asset).resizable().scaledToFit().frame(width: 72, height: 72)
                Text(name).font(.system(size: 12, weight: .medium))
                Image(systemName: manager.settings.iconAsset == asset ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(manager.settings.iconAsset == asset ? Color.accentColor : .secondary)
            }
            .padding(14)
            .background(Color.primary.opacity(manager.settings.iconAsset == asset ? 0.06 : 0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func workspacePage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 22, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                content()
            }
            .padding(20)
            .padding(.top, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .thinScrollIndicators()
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

    private func profileSetting<Value>(
        _ profile: WritableKeyPath<InputDevicesSettings, InputScrollProfile>,
        _ value: WritableKeyPath<InputScrollProfile, Value>
    ) -> Binding<Value> {
        Binding(
            get: { manager.settings[keyPath: profile][keyPath: value] },
            set: { newValue in
                manager.update { $0[keyPath: profile][keyPath: value] = newValue }
            }
        )
    }
}

#Preview {
    InputDevicesWindowView().frame(width: 980, height: 700)
}
