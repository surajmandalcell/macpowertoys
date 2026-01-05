//
//  AppDelegate.swift
//  powertoys
//

import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            powertoysApp.handleIncomingURL(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            await AppInitializer.shared.shutdown()
            await BackgroundServiceManager.shared.stopAll()
        }
    }
}
