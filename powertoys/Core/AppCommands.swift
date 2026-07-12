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

        CommandMenu("Utilities") {
            Button("New Horizontal Ruler") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerNewHorizontal))
            }
            .keyboardShortcut("r", modifiers: [.command, .option, .control])

            Button("Toggle Awake") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .awakeToggle))
            }
            .keyboardShortcut("a", modifiers: [.command, .option, .control])

            Button("Pick Color") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .colorPickerPick))
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .control])

            Button("Extract Text") {
                ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorCapture))
            }
            .keyboardShortcut("t", modifiers: [.command, .option, .control])
        }
    }
}
