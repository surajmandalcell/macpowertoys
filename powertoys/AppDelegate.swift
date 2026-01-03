//
//  AppDelegate.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running in menu bar when window is closed
        return false
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // The app became active
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up resources
    }
}
