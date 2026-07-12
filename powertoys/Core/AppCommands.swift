//
//  AppCommands.swift
//  powertoys
//

import SwiftUI

extension Notification.Name {
    static let commandOpenSettings = Notification.Name("commandOpenSettings")
    static let commandNewTransfer = Notification.Name("commandNewTransfer")
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NotificationCenter.default.post(name: .commandOpenSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Transfer") {
                NotificationCenter.default.post(name: .commandNewTransfer, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
