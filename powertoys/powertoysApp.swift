//
//  powertoysApp.swift
//  powertoys
//

import SwiftUI
import SwiftData

@main
struct powertoysApp: App {
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
            AppDataLocation.migrateLegacyStoreIfNeeded()
            let schema = Schema([LogEntry.self, CachedConversation.self, CachedMessage.self, CachedSessionMetadata.self, TransferRecord.self])
            let config = ModelConfiguration(schema: schema, url: AppDataLocation.storeURL)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        Window("PowerToys", id: "main") {
            MainWindowView()
                .task {
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    await AppInitializer.shared.initialize(modelContext: modelContainer.mainContext)
                    DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                    DeepLinkHandler.shared.handleCLIArguments()
                    for id in ["cc-history", "rclone"] where UserDefaults.standard.bool(forKey: "tool.\(id).startAtLaunch") {
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

        Window("RSync", id: "rclone") {
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

        Window("Ruler", id: "ruler") {
            RulerControlView()
        }
        .defaultSize(width: 680, height: 680)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["ruler"]))
        .restorationBehavior(.disabled)

        Window("Awake", id: "awake") {
            AwakeView()
        }
        .defaultSize(width: 680, height: 620)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["awake"]))
        .restorationBehavior(.disabled)

        Window("Color Picker", id: "color-picker") {
            ColorHistoryView()
        }
        .defaultSize(width: 620, height: 640)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["color-picker"]))
        .restorationBehavior(.disabled)

        Window("Text Extractor", id: "text-extractor") {
            TextExtractorView()
        }
        .defaultSize(width: 680, height: 620)
        .windowStyle(.hiddenTitleBar)
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

extension powertoysApp {
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
