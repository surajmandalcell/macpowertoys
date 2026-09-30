import SwiftUI
import OnePlusUI
import ServiceManagement

struct MainSettingsView: View {
    @Binding var tab: MainSettingsTab
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
            case .about: MainAboutSettings()
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
    @State private var showSyncConflict = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: OnePlusMetrics.cardGap) {
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                appearanceCard
                launchCard
            }.fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                windowsCard
                syncCard
            }.fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: appearance) { _, value in value.apply(); changed() }
        .onChange(of: closeMainAfterOpen) { changed() }
        .onChange(of: showTray) { changed() }
        .onChange(of: sync.isEnabled) { changed() }
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
                OnePlusCardHeader("Appearance", systemImage: "circle.lefthalf.filled")
                OnePlusSettingRow("Appearance", controlWidth: OnePlusCatalogMetrics.placementWidth, separator: false) {
                    OnePlusSegmented(choices: AppAppearance.allCases.map { ($0, $0.title) },
                                     selection: $appearance, accessibilityLabel: "Appearance")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var windowsCard: some View {
        OnePlusPanel {
            VStack(spacing: 0) {
                OnePlusCardHeader("Windows", systemImage: "macwindow")
                OnePlusSettingRow("Close after opening a tool") {
                    Toggle("Close main window after opening a tool", isOn: $closeMainAfterOpen)
                        .labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                OnePlusSettingRow("Show the menu-bar icon", separator: false) {
                    Toggle("Show the menu-bar icon", isOn: $showTray).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var launchCard: some View {
        OnePlusPanel {
            VStack(spacing: 0) {
                OnePlusCardHeader("Launch", systemImage: "power")
                OnePlusSettingRow("Open at login", separator: false) {
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
                Spacer(minLength: 0)
            }
        }
    }

    private var syncCard: some View {
        OnePlusPanel {
            VStack(spacing: 0) {
                OnePlusCardHeader("iCloud", systemImage: "icloud")
                OnePlusSettingRow("Sync settings via iCloud", separator: false) {
                    Toggle("Sync settings via iCloud", isOn: Binding(get: { sync.isEnabled }, set: { enabled in
                        if enabled { showSyncConflict = sync.enable() == .conflict }
                        else { sync.disable() }
                    })).labelsHidden().toggleStyle(OnePlusSwitchStyle())
                }
                Text("Syncs safe preferences and marketplace sources. Credentials, histories, file paths, and installed apps stay on this Mac.")
                    .onePlusText(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OnePlusMetrics.cardPadding)
                    .padding(.bottom, OnePlusMetrics.cardPadding)
                Spacer(minLength: 0)
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
        changed()
    }
}

private struct MainAboutSettings: View {
    private let repository = "https://github.com/surajmandalcell/macpowertoys"
    private func metadata(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "Unavailable" }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) {
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
                metadataRow("Version", value: metadata("CFBundleShortVersionString"))
                metadataRow("Build", value: metadata("CFBundleVersion"))
                metadataRow("Source commit", value: metadata("MPTSourceCommit"))
                metadataRow("Developer", value: "Suraj Mandal", monospaced: false)
                linkRow("Contact", title: "surajmandalcell@gmail.com", url: "mailto:surajmandalcell@gmail.com")
            }
            HStack(alignment: .top, spacing: OnePlusMetrics.cardGap) {
                OnePlusPanel {
                    VStack(spacing: 0) {
                        OnePlusCardHeader("Links", systemImage: "link")
                        linkRow("Repository", title: "GitHub", url: repository)
                        linkRow("Privacy", title: "Privacy policy", url: repository + "/blob/main/PRIVACY.md")
                        linkRow("License", title: "MIT license", url: repository + "/blob/main/LICENSE")
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity)
                OnePlusPanel {
                    VStack(spacing: 0) {
                        OnePlusCardHeader("Acknowledgements", systemImage: "book")
                        linkRow("Cloud Sync engine", caption: "Free software by Nick Craig-Wood and contributors.",
                                title: "Powered by rclone", url: "https://rclone.org/")
                        linkRow("rclone license", title: "MIT license", url: "https://rclone.org/licence/")
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metadataRow(_ label: String, value: String, monospaced: Bool = true) -> some View {
        OnePlusSettingRow(label, controlWidth: OnePlusCatalogMetrics.placementWidth) {
            Text(value).onePlusText(monospaced ? .mono : .row).lineLimit(1)
                .truncationMode(.middle).help(value).textSelection(.enabled)
        }
    }

    private func linkRow(_ label: String, caption: String? = nil, title: String, url: String) -> some View {
        OnePlusSettingRow(label, caption: caption, controlWidth: OnePlusCatalogMetrics.placementWidth) {
            if let destination = URL(string: url) {
                Link(title, destination: destination)
                    .buttonStyle(OnePlusButtonStyle(.link, horizontalPadding: 0))
            }
        }
    }
}
