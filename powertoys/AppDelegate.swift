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
        if !ensureSingleInstance() {
            NSApp.terminate(nil)
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    private func ensureSingleInstance() -> Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }

        guard let bundleId = Bundle.main.bundleIdentifier else { return true }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        let otherInstances = runningApps.filter { $0 != NSRunningApplication.current }

        if let existingApp = otherInstances.first {
            existingApp.activate(options: [.activateAllWindows])
            return false
        }

        return true
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DeepLinkHandler.shared.handle(url: URL(string: "powertoys://open/main")!)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AwakeService.shared.shutdown()
        Task { @MainActor in
            await RcloneJobManager.shared.shutdown()
            await LogManager.shared.flushPending()
            await AppInitializer.shared.shutdown()
            await BackgroundServiceManager.shared.stopAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
