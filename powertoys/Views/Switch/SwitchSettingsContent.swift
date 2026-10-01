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
    private let showsEnableControl: Bool

    init(paths: ManagerPaths = .environment(), showsEnableControl: Bool = true) {
        self.paths = paths
        self.showsEnableControl = showsEnableControl
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            if showsEnableControl {
                HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                    appBehaviorCard
                    menuBarDefaultsCard
                }
            } else {
                usageDisplayRow.environment(\.onePlusCardPadding, 0)
                menuBarDefaultsCard
            }
            OnePlusCard {
                OnePlusCardHeader("Data locations")
                dataLocationRow("Codex home", url: paths.defaultHome)
                dataLocationRow("Codex account vault", url: paths.credentialStore)
                dataLocationRow("Grok Build home", url: paths.grokHome)
                dataLocationRow("Grok Build account vault", url: paths.grokCredentialStore)
                dataLocationRow("Claude Code profiles", url: paths.applicationSupport.appending(path: "claude-code-profiles"))
                dataLocationRow("Usage history", url: paths.applicationSupport.appending(path: "activity/daily.sqlite"))
                dataLocationRow("Recovery backups", url: paths.applicationSupport.appending(path: "backups"))
            }
        }
        .buttonStyle(OnePlusButtonStyle())
    }

    private var appBehaviorCard: some View {
        OnePlusCard {
            OnePlusCardHeader("App behavior")
            OnePlusSettingRow("Enable Switch", help: "Show Switch in MacPowerToys.") {
                Toggle("Enable Switch", isOn: Binding(get: { settings.isToolEnabled("switch") },
                       set: { settings.setToolEnabled($0, for: "switch") }))
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    .disabled(settings.isToolTransitioning("switch"))
            }
            usageDisplayRow
        }
    }

    private var menuBarDefaultsCard: some View {
        OnePlusCard {
            OnePlusCardHeader("Menu bar defaults")
            OnePlusSettingRow("Show account usage", help: "Used for accounts without their own choice.") {
                Toggle("Show account usage", isOn: $defaultShowTrayUsage).labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
            OnePlusSettingRow("Token summary", help: "The period shown beside each account's usage.", separator: false) {
                OnePlusSelect(choices: SwitchTrayTokenPeriod.allCases.map { ($0.rawValue, $0.label) },
                              selection: $trayTokenPeriod, accessibilityLabel: "Token summary")
            }
        }
    }

    private var usageDisplayRow: some View {
        OnePlusSettingRow("Show percentage used", help: "Turn off to show the percentage left.", separator: false) {
            Toggle("Show percentage used", isOn: $showUsageAsUsed).labelsHidden().toggleStyle(OnePlusSwitchStyle())
        }
    }

    private func dataLocationRow(_ title: String, url: URL) -> some View {
        OnePlusPathSettingRow(title, path: url.path, layout: .horizontal) {
            Button("Reveal", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }.contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
        }
    }
}
