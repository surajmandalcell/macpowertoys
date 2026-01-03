//
//  powertoysApp.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

@main
struct powertoysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var bookmarkManager = BookmarkManager()
    @StateObject private var selectionManager = SelectionManager()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 1000, height: 700)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Navigation") {
                Button("All Tools") {
                    NotificationCenter.default.post(name: .navigateToCategory, object: ToolCategory.all)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Dev Tools") {
                    NotificationCenter.default.post(name: .navigateToCategory, object: ToolCategory.dev)
                }
                .keyboardShortcut("2", modifiers: .command)

                Divider()

                Button("Global Search") {
                    NotificationCenter.default.post(name: .globalSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Search in Conversation") {
                    NotificationCenter.default.post(name: .conversationSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandGroup(after: .pasteboard) {
                Button("Copy Selected Messages") {
                    NotificationCenter.default.post(name: .copySelected, object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
            }
        }

        // CC History Tool Window
        WindowGroup(id: "cc-history") {
            CCHistoryWindowView()
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))

        MenuBarExtra {
            Button("Open PowerToys") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "wrench.adjustable.fill")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToCategory = Notification.Name("navigateToCategory")
    static let globalSearch = Notification.Name("globalSearch")
    static let conversationSearch = Notification.Name("conversationSearch")
    static let copySelected = Notification.Name("copySelected")
}
