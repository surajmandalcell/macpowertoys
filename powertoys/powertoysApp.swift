//
//  powertoysApp.swift
//  powertoys
//

import SwiftUI
import SwiftData
import AppIntents

@main
struct MacPowerToysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage("app.showTray") private var showTray = true

    private var trayBinding: Binding<Bool> {
        Binding(
            get: { showTray },
            set: { newValue in
                if newValue != showTray {
                    showTray = newValue
                }
            }
        )
    }

    let modelContainer: ModelContainer

    init() {
        PortmanShortcuts.updateAppShortcutParameters()
        do {
            let schema = Schema([LogEntry.self, TransferRecord.self])
            let config: ModelConfiguration
            if AppRuntime.isUITesting || !AppInstanceCoordinator.shared.ownsInstance {
                config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            } else {
                AppIdentity.migrateLegacyData()
                AppDataLocation.migrateLegacyStoreIfNeeded()
                config = ModelConfiguration(schema: schema, url: AppDataLocation.storeURL)
            }
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    @MainActor
    private func configureApplication() {
        appDelegate.configureApplication {
            DeepLinkHandler.shared.setOpenWindowAction(openWindow)
            if AppRuntime.isUITesting {
                if ProcessInfo.processInfo.environment["MACPOWERTOYS_UI_TEST_MONITOR_MENU"] == "1" {
                    SystemMonitorService.shared.updateMenuSettings {
                        $0 = SystemMonitorMenuSettings(enabled: true)
                    }
                }
                DeepLinkHandler.shared.handleCLIArguments()
                return
            }
            guard !AppRuntime.isRunningTests else { return }
            await AppInitializer.shared.initialize(modelContext: modelContainer.mainContext)
            DeepLinkHandler.shared.handleCLIArguments()
        }
    }

    var body: some Scene {
        let _ = configureApplication()

        Window("MacPowerToys", id: "main") {
            MainWindowView()
                .utilityMotionPolicy()
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: UtilityLayout.launcherWindowSize.width, height: UtilityLayout.launcherWindowSize.height)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: Set(["main"]))
        .commands {
            AppCommands()
            FreeRulerCommands()
            CommandMenu("Navigation") {
                Button("All Tools") { NotificationCenter.default.post(name: .navigateToCategory, object: ToolCategory.all) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Dev Tools") { NotificationCenter.default.post(name: .navigateToCategory, object: ToolCategory.dev) }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
                Button("Global Search") { NotificationCenter.default.post(name: .globalSearch, object: nil) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        Window("Cloud Sync", id: "rclone") {
            RcloneWindowView()
                .utilityMotionPolicy()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1000, height: 720)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["rclone"]))
        .restorationBehavior(.disabled)

        Window("Logs", id: "logs") {
            LogsWindowView()
                .utilityMotionPolicy()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 900, height: 600)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["logs"]))
        .restorationBehavior(.disabled)

        Window("Awake", id: "awake") {
            AwakeView()
                .utilityMotionPolicy()
                .background(WindowAccessor(identifier: "awake"))
        }
        .defaultSize(width: AwakeLayout.windowWidth, height: AwakeLayout.windowHeight)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["awake"]))
        .restorationBehavior(.disabled)

        Window("Color Picker", id: "color-picker") {
            ColorHistoryView()
                .utilityMotionPolicy()
                .background(WindowAccessor(identifier: "color-picker"))
        }
        .defaultSize(
            width: ColorPickerLayout.windowWidth,
            height: ColorPickerLayout.historyBaseHeight + UtilityLayout.compactTitlebarHeight
        )
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["color-picker"]))
        .restorationBehavior(.disabled)

        Window("Text Extractor", id: "text-extractor") {
            TextExtractorView()
                .utilityMotionPolicy()
                .background(WindowAccessor(identifier: "text-extractor"))
        }
        .defaultSize(
            width: TextExtractorLayout.windowWidth,
            height: TextExtractorLayout.historyBaseHeight + UtilityLayout.compactTitlebarHeight
        )
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["text-extractor"]))
        .restorationBehavior(.disabled)

        Window("Input Devices", id: "input-devices") {
            InputDevicesWindowView()
                .utilityMotionPolicy()
        }
        .defaultSize(width: 980, height: 700)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["input-devices"]))
        .restorationBehavior(.disabled)

        Window("System Care", id: "system-care") {
            SystemCareWindowView()
                .utilityMotionPolicy()
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["system-care"]))
        .restorationBehavior(.disabled)

        Window("Diskman", id: "disk-explorer") {
            DiskExplorerWindowView()
                .utilityMotionPolicy()
        }
        .defaultSize(width: 1240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["disk-explorer"]))
        .restorationBehavior(.disabled)

        Window("System Monitor", id: "system-monitor") {
            SystemMonitorWindowView()
                .utilityMotionPolicy()
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["system-monitor"]))
        .restorationBehavior(.disabled)

        Window("NetToys", id: "nettoys") {
            NetToysWindowView()
                .utilityMotionPolicy()
        }
        .defaultSize(
            width: UtilityLayout.netToysDefaultContentSize.width,
            height: UtilityLayout.netToysDefaultContentSize.height
        )
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["nettoys"]))
        .restorationBehavior(.disabled)

        Window("Switch", id: "switch") {
            SwitchWindowView()
                .utilityMotionPolicy()
        }
        .defaultSize(width: 1_120, height: 740)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["switch"]))
        .restorationBehavior(.disabled)

        Window("Mac Tweaks", id: "mac-tweaks") {
            MacTweaksWindowView()
                .utilityMotionPolicy()
        }
        .defaultSize(width: 900, height: 620)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["mac-tweaks"]))
        .restorationBehavior(.disabled)

        MenuBarExtra(isInserted: trayBinding) {
            TrayPopoverView()
                .utilityMotionPolicy()
                .modelContainer(modelContainer)
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.template)
                .frame(width: 14, height: 14)
                .accessibilityLabel("MacPowerToys")
                .accessibilityIdentifier("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
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
