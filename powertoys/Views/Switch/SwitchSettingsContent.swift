import AIManagerCore
import AppKit
import OnePlusUI
import SwiftUI

struct SwitchSettingsContent: View {
    @AppStorage("switchUsageShowsUsed") private var showUsageAsUsed = true
    @AppStorage(SwitchTrayUsagePreferences.defaultKey) private var defaultShowTrayUsage = true
    @AppStorage(SwitchTrayUsagePreferences.periodKey) private var trayTokenPeriod = SwitchTrayTokenPeriod.sinceReset.rawValue
    @State private var settings = SettingsManager.shared
    private let paths: ManagerPaths

    init(paths: ManagerPaths = .environment()) {
        self.paths = paths
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            OnePlusCard {
                OnePlusCardHeader("App behavior")
                OnePlusSettingRow("Enable Switch", caption: "Show Switch in MacPowerToys.") {
                    Toggle("Enable Switch", isOn: Binding(get: { settings.isToolEnabled("switch") },
                           set: { settings.setToolEnabled($0, for: "switch") }))
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                        .disabled(settings.isToolTransitioning("switch"))
                }
                OnePlusSettingRow("Show percentage used", caption: "Turn off to show the percentage left.", separator: false) {
                    Toggle("Show percentage used", isOn: $showUsageAsUsed).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Menu bar defaults")
                OnePlusSettingRow("Show account usage", caption: "Used for accounts without their own choice.") {
                    Toggle("Show account usage", isOn: $defaultShowTrayUsage).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Token summary", caption: "The period shown beside each account's usage.", separator: false) {
                    OnePlusSelect(choices: SwitchTrayTokenPeriod.allCases.map { ($0.rawValue, $0.label) },
                                  selection: $trayTokenPeriod, accessibilityLabel: "Token summary")
                }
            }
            OnePlusCard {
                OnePlusCardHeader("Data locations")
                dataLocationRow("Codex home", url: paths.defaultHome)
                dataLocationRow("Codex account vault", url: paths.credentialStore)
                dataLocationRow("Grok Build home", url: paths.grokHome)
                dataLocationRow("Grok Build account vault", url: paths.grokCredentialStore)
            }
        }
        .buttonStyle(OnePlusButtonStyle())
    }

    private func dataLocationRow(_ title: String, url: URL) -> some View {
        OnePlusPathSettingRow(title, path: url.path) {
            Button("Reveal", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }.contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
        }
    }
}
