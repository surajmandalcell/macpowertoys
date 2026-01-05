//
//  AppDelegate.swift
//  powertoys
//

import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var restoredWindows = Set<ObjectIdentifier>()

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @MainActor
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let windowId = ObjectIdentifier(window)
        guard !restoredWindows.contains(windowId) else { return }
        restoredWindows.insert(windowId)
        WindowStateManager.shared.restoreState(for: window)
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
