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

    static let pro = Self(name: "Task Manager Pro", bundleID: MainPanelTaskManager.pro.rawValue,
                          summary: "See every process, its graphs, and startup items, laid out like Windows 11.",
                          icon: "AppBySamTaskManagerPro", price: "Paid")
    static let covered: [(app: Self, cover: String)] = [
        (Self(name: "Hushpen", bundleID: "io.github.surajmandalcell.hushpen",
              summary: "Free dictation with no account and no word limit", icon: "AppBySamHushpen",
              download: URL(string: "https://hushpen.mandalsuraj.com/")), "AppBySamHushpenCover"),
        (Self(name: "Switch", bundleID: "com.mandalsuraj.ai-manager",
              summary: "Coding accounts and usage in your menu bar", icon: "AppBySamSwitch",
              download: URL(string: "https://github.com/samhqapp/switch/releases/latest")), "AppBySamSwitchCover"),
    ]
    // shortcut: only Hushpen, Switch, and NetToys have a public download page; add each app's link when it ships one.
    static let listed: [Self] = [
        Self(name: "Task Manager Classic", bundleID: MainPanelTaskManager.classic.rawValue,
             summary: "A small task manager in the Windows 7 layout", icon: "AppBySamTaskManagerClassic"),
        Self(name: "Sam's System Cleaner", bundleID: "com.surajmandal.samscc",
             summary: "Find caches and leftovers to move to Trash", icon: "AppBySamSystemCleaner"),
        Self(name: "Sam's Partition Manager", bundleID: "com.surajmandal.samspartitionmanager",
             summary: "Format and check external drives and SD cards", icon: "AppBySamPartitionManager"),
        Self(name: "Sam's NetToys", bundleID: "com.surajmandal.nettoys",
             summary: "Scan networks and keep SSH hosts reachable", icon: "AppBySamNetToys",
             download: URL(string: "https://github.com/samhqapp/nettoys/releases/latest")),
        Self(name: "ThrottleControl", bundleID: "io.github.surajmandalcell.ThrottleControl",
             summary: "Share a background traffic budget and keep games unthrottled", icon: "AppBySamThrottleControl"),
    ]
    static let all: [Self] = [pro] + covered.map(\.app) + listed

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

/// The Apps by Sam page: the Pro banner, the Hushpen and Switch cover cards,
/// then the list of the other apps.
struct AppsBySamView: View {
    static let pageID = "apps-by-sam"
    static let title = "Apps by Sam"
    @State private var installed: Set<String> = []

    var body: some View {
        let pro = SamApp.pro
        OnePlusLinearEditorialBody {
            OnePlusLinearPageTitle(Self.title, subtitle: "My other Mac apps. Each one runs on its own.")
            OnePlusLinearAppShelf {
                OnePlusLinearFeaturedApp(pro.name, detail: pro.summary, icon: pro.image, price: pro.price,
                                         action: pro.action(installed: installed.contains(pro.bundleID)))
            } covers: {
                ForEach(SamApp.covered, id: \.app.id) { app, cover in
                    OnePlusLinearAppCoverCard(app.name, summary: app.summary, icon: app.image, cover: Image(cover),
                                              action: app.action(installed: installed.contains(app.bundleID)))
                }
            } rows: {
                ForEach(SamApp.listed) { app in
                    OnePlusLinearAppRow(app.name, summary: app.summary, icon: app.image,
                                        separator: app.id != SamApp.listed.first?.id,
                                        action: app.action(installed: installed.contains(app.bundleID)))
                }
            }
        }
        .task { installed = await Task.detached(priority: .userInitiated) { SamApp.installedIDs() }.value }
    }
}
