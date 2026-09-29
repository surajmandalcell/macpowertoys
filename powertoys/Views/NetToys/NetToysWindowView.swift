import AppKit
import Network
import Observation
import OnePlusUI
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
        guard !AppRuntime.isUITesting else { return }
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
    case settings = "Settings"
    case howToUse = "How to use"

    var id: String { rawValue }

    var pageID: String {
        switch self {
        case .scanner: "scanner"
        case .anchor: "ssh-anchor"
        case .wifiPriority: "wifi"
        case .history: "history"
        case .settings: "settings"
        case .howToUse: "how-to-use"
        }
    }

    var icon: String {
        switch self {
        case .scanner: "dot.radiowaves.left.and.right"
        case .anchor: "link"
        case .history: "chart.xyaxis.line"
        case .wifiPriority: "wifi"
        case .settings: "gearshape"
        case .howToUse: "questionmark.circle"
        }
    }
}

struct NetToysWindowView: View {
    @State private var page = NetToysPage.scanner
    @State private var settingsSection = "permissions"
    @State private var scannerModel = NetToysScannerViewModel()
    @State private var localNetworkAccess = NetToysLocalNetworkAccess.shared

    var body: some View {
        OnePlusWindowRoot(canvas: .netToys) { sidebar } content: { content }
        .background(WindowAccessor(identifier: "nettoys"))
        .buttonStyle(OnePlusButtonStyle())
        .onOpenToolPage("nettoys") { pageID in
            if let destination = NetToysPage.allCases.first(where: { $0.pageID == pageID }) {
                page = destination
            }
        }
        .background { Button("") { page = .settings }.keyboardShortcut("5").hidden() }
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
        .onReceive(NotificationCenter.default.publisher(for: .netToysOpenPage)) { notification in
            guard let requestedPage = notification.object as? NetToysPage else { return }
            page = requestedPage
        }
        .task { localNetworkAccess.request() }
        .onDisappear { scannerModel.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            localNetworkAccess.request()
        }
    }

    private var sidebar: some View {
        OnePlusSidebar(title: "NetToys") {
            OnePlusNavCaption("Tools")
            ForEach(Array(NetToysPage.allCases.prefix(4))) { item in
                OnePlusNavRow(item.rawValue, systemImage: item.icon, selected: page == item) {
                    page = item
                }
                .keyboardShortcut(KeyEquivalent(Character(String((NetToysPage.allCases.firstIndex(of: item) ?? 0) + 1))))
                .accessibilityIdentifier("nettoys.page.\(item.id)")
            }
        } bottom: {
            OnePlusNavRow("Settings", systemImage: "gearshape", selected: page == .settings) {
                page = .settings
            }.keyboardShortcut(",")
            OnePlusNavRow("How to use", systemImage: "questionmark.circle", selected: page == .howToUse) {
                page = .howToUse
            }.keyboardShortcut("6")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .scanner:
            NetToysScannerView(model: scannerModel) {
                settingsSection = "scanner"
                page = .settings
            }
        case .anchor:
            NetToysAnchorView()
        case .history:
            NetToysHistoryView()
        case .wifiPriority:
            NetToysWiFiPriorityView()
        case .settings:
            OnePlusPage {
                OnePlusPageHeader(title: "Settings", subtitle: "Permissions and scanner preferences")
            } tabs: {
                OnePlusTabStrip(tabs: [OnePlusTab("permissions", "Permissions"), OnePlusTab("scanner", "Scanner")],
                                selection: $settingsSection)
            } content: {
                if settingsSection == "scanner" { NetToysScannerSettingsView(model: scannerModel) }
                else { NetToysSettingsView() }
            }
        case .howToUse:
            OnePlusPage {
                OnePlusPageHeader(title: "How to use", subtitle: "Discover devices and keep your network available")
            } content: {
                ForEach(NetToysTool.shared.manual) { section in
                    howToCard(section.title, section.points.joined(separator: "\n\n"))
                }
                howToCard("Wi-Fi Priority", "Add at least two saved Wi-Fi networks, set their order, and enable failover. macOS manages the final Personal Hotspot fallback.")
                OnePlusBanner("Wi-Fi names need Location access. IP scanning needs Local Network access. Settings shows each permission and its recovery action.") {
                    Button("Open Settings") { settingsSection = "permissions"; page = .settings }
                }
            }
        }
    }

    private func howToCard(_ title: String, _ message: String) -> some View {
        OnePlusCard {
            OnePlusCardHeader(title)
            Text(message).onePlusText(.row).textSelection(.enabled).padding(OnePlusMetrics.cardPadding)
        }
    }
}

extension Notification.Name {
    static let netToysRescanRun = Notification.Name("netToysRescanRun")
    static let netToysStartScan = Notification.Name("netToysStartScan")
    static let netToysOpenAnchor = Notification.Name("netToysOpenAnchor")
    static let netToysApplyAnchorPrefill = Notification.Name("netToysApplyAnchorPrefill")
    static let netToysOpenPage = Notification.Name("netToysOpenPage")
}
