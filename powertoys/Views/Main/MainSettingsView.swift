import SwiftUI
import OnePlusUI
import ServiceManagement

struct MainSettingsView: View {
    @Binding var tab: MainSettingsTab
    var showManual: (String) -> Void = { _ in }
    let changed: () -> Void

    var body: some View {
        OnePlusPage {
            OnePlusPageHeader(title: "Settings")
        } tabs: {
            OnePlusTabStrip(tabs: MainSettingsTab.allCases.map { OnePlusTab($0, $0.title) }, selection: $tab)
        } content: {
            switch tab {
            case .general: MainGeneralSettings(changed: changed)
            case .marketplace: MarketplaceSettingsView()
            case .about: MainAboutSettings(showManual: showManual)
            }
        }
        .accessibilityIdentifier("main.settings.\(tab.rawValue)")
    }
}

private struct MainGeneralSettings: View {
    let changed: () -> Void
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark
    @AppStorage("app.closeMainWindowAfterOpeningTool") private var closeMainAfterOpen = false
    @AppStorage("app.showTray") private var showTray = true
    @State private var sync = SettingsSyncManager.shared
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var showSyncConflict = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                appearanceCard
                launchCard
            }.fixedSize(horizontal: false, vertical: true)
            shortcutCard
        }
        .onChange(of: appearance) { _, value in value.apply(); changed() }
        .onChange(of: closeMainAfterOpen) { changed() }
        .onChange(of: showTray) { changed() }
        .onChange(of: sync.isEnabled) { changed() }
        .onChange(of: loginStatus) { changed() }
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
        OnePlusPanel {
            VStack(spacing: 0) {
                OnePlusCardHeader("Appearance and windows", systemImage: "macwindow")
                OnePlusSettingRow("Appearance", controlWidth: OnePlusCatalogMetrics.placementWidth) {
                    OnePlusSegmented(choices: AppAppearance.allCases.map { ($0, $0.title) },
                                     selection: $appearance, accessibilityLabel: "Appearance")
                }
                OnePlusSettingRow("Close after opening a tool") {
                    Toggle("Close main window after opening a tool", isOn: $closeMainAfterOpen)
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
        OnePlusPanel {
            VStack(spacing: 0) {
                OnePlusCardHeader("Launch and iCloud", systemImage: "power")
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
        OnePlusPanel {
            VStack(spacing: 0) {
                OnePlusCardHeader("Quick Access shortcut", systemImage: "keyboard")
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
    private let metadata = HostAppMetadata.current
    private var repository: String { HostAppMetadata.repository.absoluteString }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
            updateCheck
            OnePlusCard {
                OnePlusCardHeader("MacPowerToys")
                HStack(spacing: OnePlusMetrics.cardGap) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                        .resizable().scaledToFit()
                        .frame(width: OnePlusCatalogMetrics.iconSize, height: OnePlusCatalogMetrics.iconSize)
                    Text("A collection of tools for your Mac.").onePlusText(.row)
                    Spacer()
                }
                .padding(OnePlusMetrics.cardPadding)
                .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
                metadataRow("Version", value: metadata.version)
                metadataRow("Build", value: metadata.build)
                metadataRow("Source commit", value: metadata.sourceCommit)
                metadataRow("Developer", value: HostAppMetadata.developer, monospaced: false)
                linkRow("Contact", title: HostAppMetadata.contact, url: "mailto:" + HostAppMetadata.contact)
            }
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                OnePlusCard {
                    VStack(spacing: 0) {
                        OnePlusCardHeader("Links", systemImage: "link")
                        linkRow("Repository", title: "GitHub", url: repository)
                        linkRow("Privacy", title: "Privacy policy", url: repository + "/blob/main/PRIVACY.md")
                        linkRow("License", title: "MIT license", url: repository + "/blob/main/LICENSE", separator: false)
                    }
                }.frame(maxWidth: .infinity)
                OnePlusCard {
                    VStack(spacing: 0) {
                        OnePlusCardHeader("Acknowledgements", systemImage: "book")
                        linkRow("Cloud Sync engine", help: "By Nick Craig-Wood and contributors",
                                title: "Powered by rclone", url: "https://rclone.org/")
                        linkRow("rclone license", title: "MIT license", url: "https://rclone.org/licence/", separator: false)
                    }
                }.frame(maxWidth: .infinity)
            }.fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
                HStack {
                    OnePlusSectionTitle("Using MacPowerToys")
                    Spacer()
                    Menu("Tool manuals") {
                        ForEach(ToolRegistry.allTools, id: \.id) { tool in
                            Button(tool.name) { showManual(tool.id) }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Text("Closing a window leaves enabled background tools running. Choose Quit MacPowerToys to stop them. Each tool's How to use page explains its actions and background work.")
                    .onePlusText(.row, color: OnePlusColor.secondary)
            }
        }
    }

    private var updateCheck: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.actionSpacing) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Button(updates.isChecking ? "Checking..." : "Check for Updates", action: updates.check)
                    .buttonStyle(OnePlusButtonStyle()).disabled(updates.isChecking)
                switch updates.state {
                case .checking: ProgressView().controlSize(.small).accessibilityLabel("Checking for updates")
                case .current: Text("MacPowerToys is up to date.").onePlusText(.row, color: OnePlusColor.secondary)
                case .available(let version, let url):
                    Text("Version \(version) is available.").onePlusText(.row, color: OnePlusColor.secondary)
                    Spacer()
                    Link("Release notes and download", destination: url).buttonStyle(OnePlusButtonStyle(.link))
                default: EmptyView()
                }
            }
            if case .failed(let message) = updates.state {
                OnePlusBanner(message, tone: .error) {
                    Button("Retry", action: updates.check).buttonStyle(OnePlusButtonStyle())
                }
            }
        }
    }

    private func metadataRow(_ label: String, value: String, monospaced: Bool = true) -> some View {
        OnePlusSettingRow(label, controlWidth: OnePlusCatalogMetrics.placementWidth) {
            Text(value).onePlusText(monospaced ? .mono : .row).lineLimit(1)
                .truncationMode(.middle).help(value).textSelection(.enabled)
        }
    }

    private func linkRow(_ label: String, help: String? = nil, title: String, url: String, separator: Bool = true) -> some View {
        OnePlusSettingRow(label, help: help, controlWidth: OnePlusCatalogMetrics.placementWidth, separator: separator) {
            if let destination = URL(string: url) {
                Link(title, destination: destination)
                    .buttonStyle(OnePlusButtonStyle(.link, horizontalPadding: 0))
            }
        }
    }
}
