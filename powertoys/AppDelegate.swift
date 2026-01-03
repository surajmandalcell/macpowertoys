//
//  AppDelegate.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
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
}
