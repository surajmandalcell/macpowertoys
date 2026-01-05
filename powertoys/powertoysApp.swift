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

    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([LogEntry.self, CachedConversation.self, CachedMessage.self, CachedSessionMetadata.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView()
                .task {
                    await AppInitializer.shared.initialize(modelContext: modelContainer.mainContext)
                    DeepLinkHandler.shared.setOpenWindowAction(openWindow)
                    DeepLinkHandler.shared.handleCLIArguments()
                }
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 780, height: 700)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
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

        WindowGroup(id: "cc-history") {
            CCHistoryWindowView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["cc-history"]))

        WindowGroup(id: "logs") {
            LogsWindowView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 900, height: 600)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["logs"]))

        MenuBarExtra {
            Button("Open PowerToys") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "wrench.adjustable.fill")
        }
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
}
