import AppKit
import OnePlusUI
import SwiftUI

/// One of the owner's other Mac apps on the Apps by Sam page.
nonisolated struct SamApp: Identifiable, Sendable {
    let name: String
    let bundleID: String
    let summary: String
    let icon: String
    var price: String?
    var download: URL?
    var id: String { bundleID }

    // shortcut: only Hushpen, Switch, and NetToys have a public download page; add each app's link when it ships one.
    static let all: [Self] = [
        Self(name: "Task Manager Pro", bundleID: MainPanelTaskManager.pro.rawValue,
             summary: "See every process, its graphs, and startup items, laid out like Windows 11.",
             icon: "AppBySamTaskManagerPro", price: "Paid"),
        Self(name: "Task Manager Classic", bundleID: MainPanelTaskManager.classic.rawValue,
             summary: "A small task manager in the Windows 7 layout", icon: "AppBySamTaskManagerClassic", price: "Free"),
        Self(name: "Sam's Partition Manager", bundleID: "com.surajmandal.samspartitionmanager",
             summary: "Format and check external drives and SD cards", icon: "AppBySamPartitionManager"),
        Self(name: "Sam's System Cleaner", bundleID: "com.surajmandal.samscc",
             summary: "Find caches and leftovers to move to Trash", icon: "AppBySamSystemCleaner"),
        Self(name: "Sam's NetToys", bundleID: "com.surajmandal.nettoys",
             summary: "Scan networks and keep SSH hosts reachable", icon: "AppBySamNetToys",
             download: URL(string: "https://github.com/surajmandalcell/nettoys/releases/latest")),
        Self(name: "Hushpen", bundleID: "io.github.surajmandalcell.hushpen",
             summary: "Free dictation with no account and no word limit", icon: "AppBySamHushpen",
             download: URL(string: "https://hushpen.mandalsuraj.com/")),
        Self(name: "Switch", bundleID: "com.mandalsuraj.ai-manager",
             summary: "Coding accounts and usage in your menu bar", icon: "AppBySamSwitch",
             download: URL(string: "https://github.com/surajmandalcell/switch/releases/latest")),
        Self(name: "ThrottleControl", bundleID: "io.github.surajmandalcell.ThrottleControl",
             summary: "Share a background traffic budget and keep games unthrottled", icon: "AppBySamThrottleControl"),
    ]

    var image: Image { Image(icon) }

    nonisolated static func installedIDs() -> Set<String> {
        Set(all.map(\.bundleID).filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }

    @MainActor func action(installed: Bool) -> OnePlusLinearAppAction {
        if installed { return OnePlusLinearAppAction("Open") { open() } }
        guard let download else { return OnePlusLinearAppAction("Get", help: "Not available yet", action: nil) }
        return OnePlusLinearAppAction("Get") { NSWorkspace.shared.open(download) }
    }

    @MainActor private func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

/// The Apps by Sam page (owner pick "Featured Pro, then a list", 2026-11-19).
struct AppsBySamView: View {
    static let pageID = "apps-by-sam"
    static let title = "Apps by Sam"
    @State private var installed: Set<String> = []

    var body: some View {
        let featured = SamApp.all[0]
        OnePlusLinearEditorialBody {
            OnePlusLinearPageTitle(Self.title, subtitle: "My other Mac apps. Each one runs on its own.")
            OnePlusLinearFeaturedApp(featured.name, detail: featured.summary, icon: featured.image, price: featured.price,
                                     action: featured.action(installed: installed.contains(featured.bundleID)))
            OnePlusLinearSection("More apps") {
                ForEach(SamApp.all.dropFirst()) { app in
                    OnePlusLinearAppRow(app.name, summary: app.summary, icon: app.image, price: app.price,
                                        action: app.action(installed: installed.contains(app.bundleID)))
                }
            }
        }
        .task { installed = await Task.detached(priority: .userInitiated) { SamApp.installedIDs() }.value }
    }
}
