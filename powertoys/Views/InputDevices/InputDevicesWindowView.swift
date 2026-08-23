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
                .frame(width: UtilityLayout.compactSidebarWidth)
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
        WorkspacePage(
            "Devices",
            subtitle: "\(manager.devices.count) connected",
            actions: {
                Button("Refresh", systemImage: "arrow.clockwise") { manager.refresh() }
                    .controlSize(.small)
            }
        ) {
            if manager.devices.isEmpty {
                ContentUnavailableView(
                    "No Pointing Devices Found",
                    systemImage: "computermouse",
                    description: Text("Connect a mouse or trackpad, then refresh.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 12)], spacing: 12) {
                    ForEach(manager.devices) { device in
                        deviceCard(device)
                    }
                }
            }
        }
    }

    private func deviceCard(_ device: InputDeviceDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: device.kind.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(device.kind.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider()
            technicalRow("Connection", device.isBuiltIn ? "\(device.transport) · Built in" : device.transport)
            if let manufacturer = device.manufacturer, !manufacturer.isEmpty {
                technicalRow("Maker", manufacturer)
            }
            technicalRow("App speed", profile(for: device).speed.formatted(.number.precision(.fractionLength(2))) + "×")
            if let resolution = device.pointerResolutionDPI {
                technicalRow("Resolution", resolution.formatted(.number.precision(.fractionLength(0))) + " dpi")
            }
            if let rate = device.pollingRateHz {
                technicalRow("Polling", rate.formatted(.number.precision(.fractionLength(0))) + " Hz")
            }
            if let count = device.buttonCount, count > 0 {
                technicalRow("Buttons", count.formatted())
            }
            technicalRow("Device ID", String(format: "%04X:%04X", device.vendorID, device.productID), monospaced: true)
            if device.locationID > 0 {
                technicalRow("Location", String(format: "0x%08X", device.locationID), monospaced: true)
            }
            if let version = device.versionNumber {
                technicalRow("Firmware", String(format: "0x%04X", version), monospaced: true)
            }
            if let bytes = device.maxInputReportSize, bytes > 0 {
                technicalRow("Input report", "\(bytes) bytes")
            }
            if let serial = device.serialNumber, !serial.isEmpty {
                technicalRow("Serial", serial, monospaced: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func technicalRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }

    private func profile(for device: InputDeviceDescriptor) -> InputScrollProfile {
        device.kind == .mouse ? manager.settings.mouse : manager.settings.trackpad
    }

    private var scrollingPage: some View {
        WorkspacePage("Scrolling", subtitle: "Mouse and trackpad profiles") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        manager.interceptionActive ? "Scroll control is active" : "Scroll control is inactive",
                        systemImage: manager.interceptionActive ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(manager.interceptionActive ? .green : .secondary)
                    Spacer()
                    Toggle("Input control", isOn: setting(
                        get: { $0.scrollControlEnabled },
                        set: { $0.scrollControlEnabled = $1 }
                    ))
                    .font(.system(size: 12, weight: .medium))
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
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .top, spacing: 12) {
                profileCard(title: "Mouse", icon: "computermouse", profile: \.mouse, supportsSmoothing: true)
                profileCard(title: "Trackpad", icon: "rectangle.and.hand.point.up.left", profile: \.trackpad, supportsSmoothing: false)
            }

            HStack(spacing: 12) {
                Text("Scroll device")
                    .font(.system(size: 12))
                Spacer()
                Picker("Scroll device", selection: setting(
                    get: { $0.eventOverride },
                    set: { $0.eventOverride = $1 }
                )) {
                    ForEach(InputEventOverride.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 160)
            }
        }
    }

    private func profileCard(
        title: String,
        icon: String,
        profile keyPath: WritableKeyPath<InputDevicesSettings, InputScrollProfile>,
        supportsSmoothing: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .medium))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                Toggle("Use profile", isOn: profileSetting(keyPath, \.enabled))
                Toggle("Reverse vertical", isOn: profileSetting(keyPath, \.reverseVertical))
                Toggle("Reverse horizontal", isOn: profileSetting(keyPath, \.reverseHorizontal))
                Toggle("Horizontal scroll", isOn: profileSetting(keyPath, \.horizontalEnabled))
                if supportsSmoothing {
                    Toggle("Smooth wheel", isOn: profileSetting(keyPath, \.smooth))
                }
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
        WorkspacePage("Appearance", subtitle: "App icon") {
            HStack(spacing: 14) {
                Image(manager.settings.iconAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)

                Picker("Input Devices icon", selection: setting(
                    get: { $0.iconAsset },
                    set: { $0.iconAsset = $1 }
                )) {
                    Text("Signal").tag("InputDevicesLogoA")
                    Text("Orbit").tag("InputDevicesLogoB")
                    Text("Precision").tag("InputDevicesLogoC")
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 240)

                Spacer()
            }
        }
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
