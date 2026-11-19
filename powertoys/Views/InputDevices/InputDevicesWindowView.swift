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
        LinearToolWindow(canvas: .macTweaks) {
            sidebar
        } content: {
            LinearToolPane(page: $page, title: page.title) { toolbarActions } content: { pageContent }
        }
        .background(WindowAccessor(identifier: "input-devices"))
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
        OnePlusLinearSidebar {
            EmptyView()
        } navigation: {
            navRow(.devices)
            navRow(.scrolling)
        } bottom: {
            navRow(.about)
        }
        .linearSidebarTitle("Input Devices")
    }

    private func navRow(_ destination: InputDevicesPage) -> some View {
        OnePlusLinearNavRow(destination.title, systemImage: destination.icon, selected: page == destination) {
            page = destination
        }
    }

    @ViewBuilder
    private var toolbarActions: some View {
        switch page {
        case .devices:
            LinearCaption(deviceSubtitle)
            Button("Refresh", systemImage: "arrow.clockwise") { manager.refresh() }
                .buttonStyle(OnePlusLinearButtonStyle(.soft))
        case .scrolling:
            OnePlusStatus(manager.interceptionActive ? "Control active" : "Control inactive",
                          state: manager.interceptionActive ? .online : .offline)
        case .about:
            LinearCaption(appVersion)
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
        OnePlusLinearPaneBody {
            ForEach(manager.devices) { device in deviceCard(device) }
            if !manager.devices.contains(where: { $0.kind == .mouse }) { missingDeviceCard(.mouse) }
            if !manager.devices.contains(where: { $0.kind == .trackpad }) { missingDeviceCard(.trackpad) }
            InputKeyboardCard()
        }
    }

    private var deviceSubtitle: String {
        let count = manager.devices.count
        return count == 1 ? "1 pointing device found" : "\(count) pointing devices found"
    }

    private var scrollingPage: some View {
        VStack(spacing: 0) {
            OnePlusLinearPaneBody {
                InputDevicesSettingsContent(includesDeviceFooter: false)
            }
            LinearPaneFooter { InputScrollDeviceBar() }
        }
    }

    private var aboutPage: some View {
        OnePlusLinearPaneBody {
            OnePlusLinearAppletSection("Input Devices") {
                OnePlusLinearAppletRow("Profiles", detail: "Mouse and trackpad settings stay independent.") {
                    OnePlusStatus("Saved locally")
                }
                OnePlusLinearAppletRow(
                    "System control",
                    detail: "Accessibility permission is required only for system-wide scrolling."
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
