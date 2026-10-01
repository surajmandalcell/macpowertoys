import NetToysCore
import NetToysKit
import SwiftUI

enum MacPowerToysNetToys {
    static let host = NetToysHost(id: .macPowerToys, requestsPermissions: !AppRuntime.isRunningTests)
    static var enabled: Binding<Bool> {
        Binding(get: { SettingsManager.shared.isToolEnabled("nettoys") },
                set: { SettingsManager.shared.setToolEnabled($0, for: "nettoys") })
    }
}

struct MacPowerToysNetToysView: View {
    @State private var page = NetToysPage.scanner
    @State private var settings = SettingsManager.shared

    var body: some View {
        NetToysWindowView(host: MacPowerToysNetToys.host, page: $page,
                         enabled: MacPowerToysNetToys.enabled,
                         isTransitioning: settings.isToolTransitioning("nettoys"),
                         consumePrefill: DeepLinkHandler.shared.takeNetToysPrefill)
            .background(WindowAccessor(identifier: "nettoys"))
            .onOpenToolPage("nettoys") { pageID in
                if let destination = NetToysPage.allCases.first(where: { $0.pageID == pageID }) { page = destination }
            }
    }
}

struct MacPowerToysNetToysSettingsView: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        NetToysSettingsView(host: MacPowerToysNetToys.host, enabled: MacPowerToysNetToys.enabled,
                           isTransitioning: settings.isToolTransitioning("nettoys"))
    }
}
