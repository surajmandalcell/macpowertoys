//
//  powertoysApp.swift
//  powertoys
//

import SwiftUI
import SwiftData

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
        do {
            let schema = Schema([LogEntry.self, CachedConversation.self, CachedMessage.self, CachedSessionMetadata.self, TransferRecord.self])
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

    var body: some Scene {
        Window("MacPowerToys", id: "main") {
            MainWindowView()
                .task {
                    DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                    guard !AppRuntime.isRunningTests else { return }
                    await AppInitializer.shared.initialize(modelContext: modelContainer.mainContext)
                    DeepLinkHandler.shared.handleCLIArguments()
                    for id in ["cc-history"] where UserDefaults.standard.bool(forKey: "tool.\(id).startAtLaunch") {
                        openWindow(id: id)
                    }
                }
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 780, height: 700)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .commands {
            AppCommands()
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

        Window("Claude History", id: "cc-history") {
            CCHistoryWindowView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["cc-history"]))
        .restorationBehavior(.disabled)

        Window("Cloud Sync", id: "rclone") {
            RcloneWindowView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1000, height: 720)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["rclone"]))
        .restorationBehavior(.disabled)

        Window("Logs", id: "logs") {
            LogsWindowView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 900, height: 600)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["logs"]))
        .restorationBehavior(.disabled)

        Window("Ruler Settings", id: "ruler") {
            RulerControlView()
                .background(WindowAccessor(identifier: "ruler"))
        }
        .defaultSize(width: 560, height: 600)
        .handlesExternalEvents(matching: Set(["ruler"]))
        .restorationBehavior(.disabled)

        Window("Awake", id: "awake") {
            AwakeView()
                .background(WindowAccessor(identifier: "awake"))
        }
        .defaultSize(width: 560, height: 500)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["awake"]))
        .restorationBehavior(.disabled)

        Window("Color Picker", id: "color-picker") {
            ColorHistoryView()
                .background(WindowAccessor(identifier: "color-picker"))
        }
        .defaultSize(
            width: ColorPickerLayout.windowWidth,
            height: ColorPickerLayout.historyBaseHeight
        )
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .handlesExternalEvents(matching: Set(["color-picker"]))
        .restorationBehavior(.disabled)

        Window("Text Extractor", id: "text-extractor") {
            TextExtractorView()
                .background(WindowAccessor(identifier: "text-extractor"))
        }
        .defaultSize(
            width: TextExtractorLayout.windowWidth,
            height: TextExtractorLayout.historyBaseHeight
        )
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .handlesExternalEvents(matching: Set(["text-extractor"]))
        .restorationBehavior(.disabled)

        MenuBarExtra(isInserted: trayBinding) {
            TrayPopoverView()
                .modelContainer(modelContainer)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}

extension MacPowerToysApp {
    static func handleIncomingURL(_ url: URL) {
        DeepLinkHandler.shared.handle(url: url)
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
