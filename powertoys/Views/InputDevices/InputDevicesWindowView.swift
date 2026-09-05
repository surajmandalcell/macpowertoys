import SwiftUI

enum InputDevicesPage: String, CaseIterable, Identifiable {
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
    @State private var page: InputDevicesPage

    init(page: InputDevicesPage = .devices) {
        _page = State(initialValue: page)
    }

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
        WorkspacePage(
            "Scrolling",
            subtitle: manager.interceptionActive ? "Control active" : "Control inactive"
        ) {
            InputDevicesScrollSettings()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InputScrollDeviceBar()
        }
    }

    private func profile(for kind: InputDeviceDescriptor.Kind) -> InputScrollProfile {
        kind == .mouse ? manager.settings.mouse : manager.settings.trackpad
    }

}

#Preview {
    InputDevicesWindowView().frame(width: 980, height: 700)
}
