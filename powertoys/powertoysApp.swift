//
//  powertoysApp.swift
//  powertoys
//

import SwiftUI
import SwiftData
import AppIntents
import OnePlusUI

@main
struct MacPowerToysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage("app.showTray") private var showTray = true
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark

    init() {
        if !AppRuntime.isRunningTests {
            let started = ContinuousClock.now
            AppIdentity.migrateLegacyPreferences()
            NSLog("Startup preferences migrated in %@", String(describing: started.duration(to: .now)))
        }
        PortmanShortcuts.updateAppShortcutParameters()
    }

    @MainActor
    private func configureApplication() {
        if !AppRuntime.isRunningTests || AppRuntime.isUITesting {
            MainMenuBarController.shared.configure(isInserted: showTray) {
                AnyView(TrayPopoverView().modifier(AppStorageRecovery()).utilityMotionPolicy())
            }
        }
        DiagnosticsMenuPanels.shared.makeCaptureContent = { panel, profiles, resize in
            switch panel {
            case .main:
                AnyView(TrayPopoverView(diagnostic: true).utilityMotionPolicy())
            case .systemMonitor:
                AnyView(SystemMonitorMenuPopoverView(remoteProfiles: profiles, diagnostic: true, onPreferredHeight: resize))
            case .portman: nil
            }
        }
        appearance.apply()
        appDelegate.configureApplication {
            if AppRuntime.isUITesting {
                await AppInitializer.shared.openStorage()
                DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                DeepLinkHandler.shared.handleCLIArguments()
                return
            }
            guard !AppRuntime.isRunningTests else {
                await AppInitializer.shared.openStorage()
                DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                return
            }
            await AppInitializer.shared.initialize {
                appearance.apply()
                DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                DeepLinkHandler.shared.handleCLIArguments()
            }
        }
    }

    var body: some Scene {
        let _ = configureApplication()

        Window("MacPowerToys", id: "main") {
            MainWindowView()
                .modifier(AppStorageRecovery())
                .utilityMotionPolicy()
                .environment(\.toolWindowID, "main")
                .onePlusFixedCanvas(.main)
                .onToolWindowURL("main")
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(OnePlusWindowCanvas.main.size)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: [])
        .commands {
            AppCommands()
            FreeRulerCommands()
        }

        Window("Cloud Sync", id: "rclone") {
            AppStorageContent {
                RcloneWindowView()
                    .utilityMotionPolicy()
            }
            .onToolWindowURL("rclone")
        }
        .defaultSize(OnePlusWindowCanvas.rclone.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Logs", id: "logs") {
            LogsWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.logs)
                .onToolWindowURL("logs")
        }
        .defaultSize(OnePlusWindowCanvas.logs.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Awake", id: "awake") {
            AwakeView()
                .utilityMotionPolicy()
                .background(WindowAccessor(identifier: "awake"))
                .onePlusFixedCanvas(.awake)
                .onToolWindowURL("awake")
        }
        .defaultSize(OnePlusWindowCanvas.awake.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Color Picker", id: "color-picker") {
            ColorHistoryView()
                .utilityMotionPolicy()
                .background(WindowAccessor(identifier: "color-picker"))
                .onePlusFixedCanvas(.colorPicker)
                .onToolWindowURL("color-picker")
        }
        .defaultSize(
            width: OnePlusWindowCanvas.colorPicker.size.width,
            height: ColorPickerLayout.historyBaseHeight + UtilityLayout.compactTitlebarHeight
        )
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Text Extractor", id: "text-extractor") {
            TextExtractorView()
                .utilityMotionPolicy()
                .background(WindowAccessor(identifier: "text-extractor"))
                .onePlusFixedCanvas(.textExtractor)
                .onToolWindowURL("text-extractor")
        }
        .defaultSize(
            width: OnePlusWindowCanvas.textExtractor.size.width,
            height: TextExtractorLayout.historyBaseHeight + UtilityLayout.compactTitlebarHeight
        )
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Input Devices", id: "input-devices") {
            InputDevicesWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.inputDevices)
                .onToolWindowURL("input-devices")
        }
        .defaultSize(OnePlusWindowCanvas.inputDevices.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("System Care", id: "system-care") {
            SystemCareWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.systemCare)
                .onToolWindowURL("system-care")
        }
        .defaultSize(OnePlusWindowCanvas.systemCare.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Diskman", id: "disk-explorer") {
            DiskExplorerWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.diskExplorer)
                .onToolWindowURL("disk-explorer")
        }
        .defaultSize(OnePlusWindowCanvas.diskExplorer.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Task Manager", id: "system-monitor") {
            SystemMonitorWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.systemMonitor)
                .onToolWindowURL("system-monitor")
        }
        .defaultSize(OnePlusWindowCanvas.systemMonitor.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("NetToys", id: "nettoys") {
            NetToysWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.netToys)
                .onToolWindowURL("nettoys")
        }
        .defaultSize(OnePlusWindowCanvas.netToys.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Switch", id: "switch") {
            SwitchWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.switchAccounts)
                .onToolWindowURL("switch")
        }
        .defaultSize(OnePlusWindowCanvas.switchAccounts.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        Window("Mac Tweaks", id: "mac-tweaks") {
            MacTweaksWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.macTweaks)
                .onToolWindowURL("mac-tweaks")
        }
        .defaultSize(OnePlusWindowCanvas.macTweaks.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

    }
}

private struct AppStorageRecovery: ViewModifier {
    private var store: AppModelStore { AppInitializer.shared.modelStore }

    func body(content: Content) -> some View {
        content.alert("Cannot open saved data", isPresented: Binding(
            get: { store.showsRecovery }, set: { store.showsRecovery = $0 }
        )) {
            Button("Retry") { Task { await AppInitializer.shared.openStorage() } }
            Button("Reveal Data Folder") { NSWorkspace.shared.open(AppDataLocation.directory) }
            Button("Keep open", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "The data store could not be opened.")
        }
    }
}

private struct AppStorageContent<Content: View>: View {
    @ViewBuilder let content: () -> Content
    private var store: AppModelStore { AppInitializer.shared.modelStore }

    var body: some View {
        Group {
            if let container = store.container {
                content().modelContainer(container)
            } else if let error = store.errorMessage {
                VStack(spacing: OnePlusMetrics.contentGap) {
                    Text("Cannot open saved data").onePlusText(.sectionTitle)
                    Text(error).onePlusText(.row).textSelection(.enabled)
                    HStack {
                        Button("Retry") { Task { await AppInitializer.shared.openStorage() } }
                        Button("Reveal Data Folder") { NSWorkspace.shared.open(AppDataLocation.directory) }
                    }
                    .buttonStyle(OnePlusButtonStyle(.neutral))
                }
                .padding(OnePlusMetrics.gutter)
            } else {
                ProgressView("Opening saved data")
            }
        }
        .modifier(AppStorageRecovery())
        .onePlusFixedCanvas(.rclone)
    }
}

extension MacPowerToysApp {
    static func handleIncomingURL(_ url: URL) {
        DeepLinkHandler.shared.handle(url: url)
    }
}

struct OpenPortmanIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Portman"
    static let description = IntentDescription("Show Portman in the menu bar.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { PortmanMenuController.shared.show() }
        return .result()
    }
}

struct PortmanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPortmanIntent(),
            phrases: ["Open Portman in \(.applicationName)", "Show Portman in \(.applicationName)"],
            shortTitle: "Portman",
            systemImageName: "circle.grid.2x2.fill"
        )
    }
}

extension Notification.Name {
    static let navigateToCategory = Notification.Name("navigateToCategory")
    static let globalSearch = Notification.Name("globalSearch")
    static let conversationSearch = Notification.Name("conversationSearch")
    static let copySelected = Notification.Name("copySelected")
    static let selectMainTab = Notification.Name("selectMainTab")
    static let openToolSettings = Notification.Name("openToolSettings")
    static let newTransferRequested = Notification.Name("newTransferRequested")
}
