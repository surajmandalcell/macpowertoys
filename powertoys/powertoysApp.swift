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
    @Environment(\.self) private var sceneEnvironment
    @AppStorage("app.showTray") private var showTray = true
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark

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
        DiagnosticsMenuPanels.shared.makeCaptureContent = { panel in
            switch panel {
            case .main:
                AnyView(TrayPopoverView().utilityMotionPolicy().modelContainer(modelContainer)
                    .environment(\.self, sceneEnvironment))
            case .systemMonitor:
                AnyView(SystemMonitorMenuPopoverView().environment(\.self, sceneEnvironment))
            case .portman: nil
            }
        }
        appearance.apply()
        appDelegate.configureApplication {
            DeepLinkHandler.shared.setOpenWindowAction(openWindow)
            if AppRuntime.isUITesting {
                DeepLinkHandler.shared.handleCLIArguments()
                return
            }
            #if DEBUG
            NSLog("[DEBUG-ci14] startup tests=\(AppRuntime.isRunningTests) active=\(NSApp.isActive)")
            #endif
            guard !AppRuntime.isRunningTests else { return }
            await AppInitializer.shared.initialize(modelContext: modelContainer.mainContext)
            appearance.apply()
            #if DEBUG
            NSLog("[DEBUG-ci14] initialized active=\(NSApp.isActive)")
            #endif
            DeepLinkHandler.shared.handleCLIArguments()
        }
    }

    var body: some Scene {
        let _ = configureApplication()

        Window("MacPowerToys", id: "main") {
            MainWindowView()
                .utilityMotionPolicy()
                .environment(\.toolWindowID, "main")
                .onePlusFixedCanvas(.main)
                .onNativeToolPageURL("main")
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(OnePlusWindowCanvas.main.size)
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
                .onePlusFixedCanvas(.rclone)
                .onNativeToolPageURL("rclone")
        }
        .modelContainer(modelContainer)
        .defaultSize(OnePlusWindowCanvas.rclone.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["rclone"]))
        .restorationBehavior(.disabled)

        Window("Logs", id: "logs") {
            LogsWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.logs)
                .onNativeToolPageURL("logs")
        }
        .modelContainer(modelContainer)
        .defaultSize(OnePlusWindowCanvas.logs.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["logs"]))
        .restorationBehavior(.disabled)

        Window("Awake", id: "awake") {
            AwakeView()
                .utilityMotionPolicy()
                .background(WindowAccessor(identifier: "awake"))
                .onePlusFixedCanvas(.awake)
                .onNativeToolPageURL("awake")
        }
        .defaultSize(OnePlusWindowCanvas.awake.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["awake"]))
        .restorationBehavior(.disabled)

        Window("Color Picker", id: "color-picker") {
            ColorHistoryView()
                .utilityMotionPolicy()
                .background(WindowAccessor(identifier: "color-picker"))
                .onePlusFixedCanvas(.colorPicker)
                .onNativeToolPageURL("color-picker")
        }
        .defaultSize(
            width: OnePlusWindowCanvas.colorPicker.size.width,
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
                .onePlusFixedCanvas(.textExtractor)
                .onNativeToolPageURL("text-extractor")
        }
        .defaultSize(
            width: OnePlusWindowCanvas.textExtractor.size.width,
            height: TextExtractorLayout.historyBaseHeight + UtilityLayout.compactTitlebarHeight
        )
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["text-extractor"]))
        .restorationBehavior(.disabled)

        Window("Input Devices", id: "input-devices") {
            InputDevicesWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.inputDevices)
                .onNativeToolPageURL("input-devices")
        }
        .defaultSize(OnePlusWindowCanvas.inputDevices.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["input-devices"]))
        .restorationBehavior(.disabled)

        Window("System Care", id: "system-care") {
            SystemCareWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.systemCare)
                .onNativeToolPageURL("system-care")
        }
        .defaultSize(OnePlusWindowCanvas.systemCare.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["system-care"]))
        .restorationBehavior(.disabled)

        Window("Diskman", id: "disk-explorer") {
            DiskExplorerWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.diskExplorer)
                .onNativeToolPageURL("disk-explorer")
        }
        .defaultSize(OnePlusWindowCanvas.diskExplorer.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["disk-explorer"]))
        .restorationBehavior(.disabled)

        Window("Task Manager", id: "system-monitor") {
            SystemMonitorWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.systemMonitor)
                .onNativeToolPageURL("system-monitor")
        }
        .defaultSize(OnePlusWindowCanvas.systemMonitor.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["system-monitor"]))
        .restorationBehavior(.disabled)

        Window("NetToys", id: "nettoys") {
            NetToysWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.netToys)
                .onNativeToolPageURL("nettoys")
        }
        .defaultSize(OnePlusWindowCanvas.netToys.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["nettoys"]))
        .restorationBehavior(.disabled)

        Window("Switch", id: "switch") {
            SwitchWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.switchAccounts)
                .onNativeToolPageURL("switch")
        }
        .defaultSize(OnePlusWindowCanvas.switchAccounts.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["switch"]))
        .restorationBehavior(.disabled)

        Window("Mac Tweaks", id: "mac-tweaks") {
            MacTweaksWindowView()
                .utilityMotionPolicy()
                .onePlusFixedCanvas(.macTweaks)
                .onNativeToolPageURL("mac-tweaks")
        }
        .defaultSize(OnePlusWindowCanvas.macTweaks.size)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["mac-tweaks"]))
        .restorationBehavior(.disabled)

        MenuBarExtra(isInserted: trayBinding) {
            TrayPopoverView()
                .utilityMotionPolicy()
                .modelContainer(modelContainer)
                .background(DiagnosticsMainMenuWindow())
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
