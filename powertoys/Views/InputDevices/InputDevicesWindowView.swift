import OnePlusUI
import SwiftUI

enum InputDevicesPage: String, CaseIterable, Identifiable {
    case devices
    case scrolling
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: "Devices"
        case .scrolling: "Scrolling"
        case .about: "About"
        }
    }

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
        OnePlusWindowRoot(canvas: .inputDevices) {
            sidebar
        } content: {
            pageContent
        }
        .background(WindowAccessor(identifier: "input-devices"))
        .buttonStyle(OnePlusButtonStyle())
        .task {
            await Task.yield()
            manager.refresh()
        }
        .onOpenToolPage("input-devices") { pageID in
            if let destination = InputDevicesPage(rawValue: pageID) {
                page = destination
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
            guard ToolActionRouter.windowIdentifier(NSApp.keyWindow?.identifier?.rawValue, matches: "input-devices") else { return }
            page = .scrolling
        }
        .background {
            ForEach(Array(InputDevicesPage.allCases.enumerated()), id: \.offset) { index, destination in
                Button("") { page = destination }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .hidden()
            }
        }
    }

    private var sidebar: some View {
        OnePlusSidebar(title: "Input Devices") {
            OnePlusNavRow(
                InputDevicesPage.devices.title,
                systemImage: InputDevicesPage.devices.icon,
                selected: page == .devices
            ) { page = .devices }
            OnePlusNavRow(
                InputDevicesPage.scrolling.title,
                systemImage: InputDevicesPage.scrolling.icon,
                selected: page == .scrolling
            ) { page = .scrolling }
        } bottom: {
            OnePlusNavRow(
                InputDevicesPage.about.title,
                systemImage: InputDevicesPage.about.icon,
                selected: page == .about
            ) { page = .about }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .devices:
            devicesPage
        case .scrolling:
            scrollingPage
        case .about:
            aboutPage
        }
    }

    private var devicesPage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Devices") {
                Text(deviceSubtitle).onePlusText(.caption)
                Button("Refresh", systemImage: "arrow.clockwise") { manager.refresh() }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
            }
        } content: {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: OnePlusMetrics.cardGap, alignment: .top),
                    count: 2
                ),
                alignment: .leading,
                spacing: OnePlusMetrics.cardGap
            ) {
                ForEach(manager.devices) { device in deviceCard(device) }
                if !manager.devices.contains(where: { $0.kind == .mouse }) { missingDeviceCard(.mouse) }
                if !manager.devices.contains(where: { $0.kind == .trackpad }) { missingDeviceCard(.trackpad) }
                InputKeyboardCard()
            }
        }
    }

    private var deviceSubtitle: String {
        let count = manager.devices.count
        return count == 1 ? "1 pointing device found" : "\(count) pointing devices found"
    }

    private var scrollingPage: some View {
        OnePlusPage(scrolls: false) {
            OnePlusPageHeader(title: "Scrolling") {
                OnePlusStatus(manager.interceptionActive ? "Control active" : "Control inactive",
                              state: manager.interceptionActive ? .online : .offline)
            }
        } footer: {
            InputScrollDeviceBar()
        } content: {
            ScrollView {
                InputDevicesSettingsContent(includesDeviceFooter: false)
            }
            .onePlusScrollIndicators()
        }
    }

    private var aboutPage: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "About") { Text(appVersion).onePlusText(.caption) }
        } content: {
            OnePlusCard {
                OnePlusCardHeader("Input Devices", systemImage: ToolGlyph.inputDevices.symbol)
                OnePlusSettingRow("Profiles", help: "Mouse and trackpad settings stay independent.") {
                    OnePlusStatus("Saved locally")
                }
                OnePlusSettingRow(
                    "System control",
                    help: "Accessibility permission is required only for system-wide scrolling.",
                    separator: false
                ) {
                    OnePlusStatus(manager.permissionGranted ? "Allowed" : "Permission needed",
                                  state: manager.permissionGranted ? .online : .warning)
                }
            }
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    private func profile(for kind: InputDeviceDescriptor.Kind) -> InputScrollProfile {
        InputScrollPolicy.profile(for: kind, settings: manager.settings)
    }

    private func deviceCard(_ device: InputDeviceDescriptor) -> some View {
        InputDeviceCard(
            device: device,
            profile: profile(for: device.kind),
            state: InputControlState.state(
                settings: manager.settings,
                permissionGranted: manager.permissionGranted,
                interceptionActive: manager.interceptionActive,
                kind: device.kind
            )
        )
    }

    private func missingDeviceCard(_ kind: InputDeviceDescriptor.Kind) -> some View {
        InputDeviceCard(
            device: nil,
            kind: kind,
            profile: profile(for: kind),
            state: .disabled
        )
    }
}

#Preview {
    InputDevicesWindowView()
}
