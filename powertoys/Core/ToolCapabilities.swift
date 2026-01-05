//
//  ToolCapabilities.swift
//  powertoys
//

import Foundation

struct ToolCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let hasWindow = ToolCapabilities(rawValue: 1 << 0)
    static let needsBackgroundService = ToolCapabilities(rawValue: 1 << 1)
    static let needsGlobalHotkeys = ToolCapabilities(rawValue: 1 << 2)
    static let needsAccessibility = ToolCapabilities(rawValue: 1 << 3)

    static let none: ToolCapabilities = []
}
