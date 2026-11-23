//
//  DemoMode.swift
//  powertoys
//

import Foundation

/// `make demo` sets MPT_DEMO. In every other build `isActive` is false and each guard folds away.
nonisolated enum DemoMode {
    #if MPT_DEMO
    static let isActive = true
    #else
    static let isActive = false
    #endif

    /// Site stills only: `-MPTDemoMainExtraWidth <pt>` widens the main window so a page crop never cuts a value.
    static var mainWindowExtraWidth: CGFloat {
        #if MPT_DEMO
        CGFloat(UserDefaults.standard.double(forKey: "MPTDemoMainExtraWidth"))
        #else
        0
        #endif
    }

    /// Site stills only: `-MPTDemoInputDevicesWidth 640 -MPTDemoInputDevicesHeight 880` gives Input Devices a tall tile shape.
    static var inputDevicesSize: CGSize? {
        #if MPT_DEMO
        let width = UserDefaults.standard.double(forKey: "MPTDemoInputDevicesWidth")
        let height = UserDefaults.standard.double(forKey: "MPTDemoInputDevicesHeight")
        return width > 0 && height > 0 ? CGSize(width: width, height: height) : nil
        #else
        nil
        #endif
    }

    /// Site stills only: `-MPTDemoHideSidebar YES` collapses a tool window's sidebar for a narrow tile.
    static var hidesToolSidebar: Bool {
        #if MPT_DEMO
        UserDefaults.standard.bool(forKey: "MPTDemoHideSidebar")
        #else
        false
        #endif
    }

    /// True when the demo build must skip this side effect. Use as `if DemoMode.blocks("x") { return }`.
    @inline(__always)
    static func blocks(_ effect: String) -> Bool {
        #if MPT_DEMO
        DemoSafety.record(effect)
        return true
        #else
        return false
        #endif
    }
}
