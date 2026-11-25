import SwiftUI
import OnePlusUI
import ServiceManagement

struct MainSettingsView: View {
    @Binding var tab: MainSettingsTab
    var showManual: (String) -> Void = { _ in }

    var body: some View {
        OnePlusLinearPaneBody {
            switch tab {
            case .general: MainGeneralSettings()
            case .marketplace: MarketplaceSettingsView()
            case .about: MainAboutSettings(showManual: showManual)
            }
        }
        .accessibilityIdentifier("main.settings.\(tab.rawValue)")
    }

    static let tabs = MainSettingsTab.allCases.map { OnePlusTab($0, $0.title) }
}

private struct MainGeneralSettings: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark
    @AppStorage("app.closeMainWindowAfterOpeningTool") private var closeMainAfterOpen = false
    @AppStorage("app.showTray") private var showTray = true
    @AppStorage(IndividualMenuBarController.animatedIconsKey) private var animatedIcons = true
    @AppStorage(DailyCounts.storageKey) private var shareDailyCounts = true
    @State private var sync = SettingsSyncManager.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var showSyncConflict = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.sectionGap) {
            appearanceCard
            launchCard
            shortcutCard
            privacyCard
        }
        .onChange(of: appearance) { _, value in value.apply() }
        .onChange(of: shareDailyCounts) { _, value in DailyCounts.setEnabled(value) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
        .confirmationDialog("iCloud already contains MacPowerToys settings", isPresented: $showSyncConflict,
                            titleVisibility: .visible) {
            Button("Use iCloud Settings") { sync.resolveConflict(useCloud: true) }
            Button("Replace iCloud with This Mac", role: .destructive) { sync.resolveConflict(useCloud: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the settings in iCloud, or replace them with this Mac's settings.")
        }
    }

    private var appearanceCard: some View {
        MainSection(title: "Appearance and windows") {
            VStack(spacing: 0) {
                OnePlusSettingRow("Appearance", controlWidth: OnePlusCatalogMetrics.placementWidth) {
                    OnePlusSegmented(choices: AppAppearance.allCases.map { ($0, $0.title) },
                                     selection: $appearance, accessibilityLabel: "Appearance")
                }
                OnePlusSettingRow("Close after opening a tool") {
                    Toggle("Close main window after opening a tool", isOn: $closeMainAfterOpen)
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Animated menu bar icons",
                                  help: "Lets a tool's menu bar icon move while it works, such as Awake's rays while it keeps the Mac awake. Each tool also has its own switch.") {
                    Toggle("Animated menu bar icons", isOn: $animatedIcons)
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Show the menu-bar icon",
                                  help: "This switch controls MacPowerToys. macOS can hide the icon in System Settings > Menu Bar > Allow in the Menu Bar. If the menu bar is full, hide or move other items to make room.",
                                  separator: false) {
                    HStack(spacing: OnePlusMetrics.actionSpacing) {
                        Button("System Settings") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(OnePlusButtonStyle(.link, horizontalPadding: 0))
                        .help("Open System Settings, then choose Menu Bar")
                        Toggle("Show the menu-bar icon", isOn: $showTray).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                    }
                }
            }
        }
    }

    private var launchCard: some View {
        MainSection(title: "Launch and iCloud") {
            VStack(spacing: 0) {
                OnePlusSettingRow("Open at login") {
                    Toggle("Open at login", isOn: Binding(
                        get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: setOpenAtLogin
                    )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                if loginStatus == .requiresApproval {
                    OnePlusBanner("Allow MacPowerToys in Login Items to finish setup.", tone: .warning) {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }.padding(OnePlusMetrics.cardPadding)
                }
                if let loginError {
                    OnePlusBanner(loginError, tone: .error).padding(OnePlusMetrics.cardPadding)
                }
                OnePlusSettingRow("Sync settings via iCloud",
                                  help: "Syncs safe preferences and marketplace sources. Credentials, histories, file paths, and installed apps stay on this Mac.",
                                  separator: false) {
                    Toggle("Sync settings via iCloud", isOn: Binding(get: { sync.isEnabled }, set: { enabled in
                        if enabled { showSyncConflict = sync.enable() == .conflict }
                        else { sync.disable() }
                    })).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
            }
        }
    }

    private var shortcutCard: some View {
        MainSection(title: "Quick Access shortcut") {
            VStack(spacing: 0) {
                OnePlusSettingRow("Enable shortcut") {
                    Toggle("Enable Quick Access shortcut", isOn: Binding(
                        get: { shortcuts.isEnabled(.mainPanel) },
                        set: { shortcuts.setEnabled($0, for: .mainPanel) }
                    )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Keyboard shortcut", help: "Assign a shortcut to open Quick Access from any app.",
                                  separator: false) {
                    ShortcutRecorderField(action: .mainPanel).disabled(!shortcuts.isEnabled(.mainPanel))
                }
                ShortcutPermissionNotice(action: .mainPanel)
            }
        }
    }

    private var privacyCard: some View {
        MainSection(title: "Privacy") {
            OnePlusSettingRow("Share anonymous usage",
                              help: "Once a day, sends the app version, macOS version, and chip to crumb.samhq.app. No name, email, files, or IP address.",
                              separator: false) {
                Toggle("Share anonymous usage", isOn: $shareDailyCounts)
                    .labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change Login Items: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}

private struct MainAboutSettings: View {
    let showManual: (String) -> Void
    @State private var updates = HostUpdateChecker.shared

    var body: some View {
        OnePlusAboutSettingsSection(info: MacPowerToysAbout.info, update: MacPowerToysAbout.update(updates)) {
            MainSection(title: "Using MacPowerToys") {
                OnePlusSettingRow("Tool manuals", controlWidth: OnePlusCatalogMetrics.placementWidth, separator: false) {
                    OnePlusMenuButton("Open a manual", variant: .raised, items: ToolRegistry.allTools.map { tool in
                        .item(OnePlusPopupMenuItem(tool.name) { showManual(tool.id) })
                    })
                }
            }
            Text("Closing a window leaves enabled background tools running. Choose Quit MacPowerToys to stop them. Each tool's How to use section explains its actions and background work.")
                .onePlusText(.caption)
        }
    }
}
