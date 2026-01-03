//
//  powertoysApp.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

@main
struct powertoysApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 800, height: 600)

        MenuBarExtra {
            Button("Open PowerToys") {
                openWindow(id: "main")
            }

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
