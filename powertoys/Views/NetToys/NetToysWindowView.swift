import AppKit
import Network
import Observation
import SwiftUI

nonisolated enum NetToysLocalNetworkAccessState: Equatable {
    case checking
    case allowed
    case denied
    case unavailable

    init(dnsErrorCode: Int32) {
        self = dnsErrorCode == -65_570 ? .denied : .unavailable
    }

    init(posixError: POSIXErrorCode) {
        self = posixError == .EPERM ? .denied : .unavailable
    }
}

@Observable
@MainActor
final class NetToysLocalNetworkAccess {
    static let shared = NetToysLocalNetworkAccess()

    private(set) var state = NetToysLocalNetworkAccessState.checking
    @ObservationIgnored private var browser: NWBrowser?

    func request() {
        browser?.cancel()
        state = .checking
        let browser = NWBrowser(
            for: .bonjour(type: "_macpowertoys-permission._tcp", domain: nil),
            using: .tcp
        )
        let observer = self
        browser.stateUpdateHandler = { browserState in
            Task { @MainActor in observer.update(browserState) }
        }
        self.browser = browser
        browser.start(queue: DispatchQueue(label: "com.surajmandal.macpowertoys.local-network"))
    }

    func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func update(_ browserState: NWBrowser.State) {
        switch browserState {
        case .ready:
            finish(.allowed)
        case .waiting(let error), .failed(let error):
            switch error {
            case .dns(let code): finish(.init(dnsErrorCode: code))
            case .posix(let code): finish(.init(posixError: code))
            case .tls, .wifiAware: finish(.unavailable)
            @unknown default: finish(.unavailable)
            }
        case .cancelled:
            break
        case .setup:
            state = .checking
        @unknown default:
            finish(.unavailable)
        }
    }

    private func finish(_ state: NetToysLocalNetworkAccessState) {
        browser?.stateUpdateHandler = nil
        browser?.cancel()
        browser = nil
        self.state = state
    }
}

enum NetToysPage: String, CaseIterable, Identifiable {
    case scanner = "IP Scanner"
    case anchor = "SSH Anchor"
    case wifiPriority = "Wi-Fi Priority"
    case history = "Network History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scanner: "dot.radiowaves.left.and.right"
        case .anchor: "link"
        case .history: "chart.xyaxis.line"
        case .wifiPriority: "wifi"
        }
    }
}

struct NetToysWindowView: View {
    @State private var page = NetToysPage.scanner
    @State private var showSettings = false
    @State private var scannerModel = NetToysScannerViewModel()
    @State private var localNetworkAccess = NetToysLocalNetworkAccess.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
                .utilityContentTransition(value: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .frame(minWidth: 860, minHeight: 600)
        .background(WindowAccessor(identifier: "nettoys"))
        .sheet(isPresented: $showSettings) {
            ToolAboutView(toolId: "nettoys")
                .frame(width: 540, height: 520)
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysRescanRun)) { notification in
            guard let run = notification.object as? NetToysScanRun else { return }
            page = .scanner
            Task { @MainActor in
                await Task.yield()
                NotificationCenter.default.post(name: .netToysStartScan, object: run)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysPrefill)) { _ in
            page = .scanner
        }
        .onReceive(NotificationCenter.default.publisher(for: .netToysOpenAnchor)) { notification in
            guard let prefill = notification.object as? NetToysAnchorPrefill else { return }
            page = .anchor
            Task { @MainActor in
                await Task.yield()
                NotificationCenter.default.post(name: .netToysApplyAnchorPrefill, object: prefill)
            }
        }
        .task { localNetworkAccess.request() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            localNetworkAccess.request()
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(NetToysPage.allCases) { item in
                        SidebarRow(
                            icon: item.icon,
                            title: item.rawValue,
                            isSelected: page == item
                        ) {
                            page = item
                        }
                        .accessibilityIdentifier("nettoys.page.\(item.id)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, UtilityLayout.workspaceContentTopInset)

                Spacer()

                SidebarRow(icon: "gearshape", title: "Settings") {
                    showSettings = true
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            SidebarTitle(text: "NetToys")
        }
        .frame(width: UtilityLayout.compactSidebarWidth)
        .background(VisualEffectBackground())
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .scanner:
            NetToysScannerView(model: scannerModel)
        case .anchor:
            NetToysAnchorView()
        case .history:
            NetToysHistoryView()
        case .wifiPriority:
            NetToysWiFiPriorityView()
        }
    }
}

extension Notification.Name {
    static let netToysRescanRun = Notification.Name("netToysRescanRun")
    static let netToysStartScan = Notification.Name("netToysStartScan")
    static let netToysOpenAnchor = Notification.Name("netToysOpenAnchor")
    static let netToysApplyAnchorPrefill = Notification.Name("netToysApplyAnchorPrefill")
}

struct NetToysPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }
                .controlSize(.small)
                .frame(height: UtilityLayout.workspaceActionHeight)
        }
        .padding(.horizontal, UtilityLayout.horizontalInset)
        .frame(height: UtilityLayout.workspaceTitlebarHeight)
        .overlay(alignment: .bottom) { QuietDivider() }
    }
}
