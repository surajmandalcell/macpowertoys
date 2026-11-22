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
