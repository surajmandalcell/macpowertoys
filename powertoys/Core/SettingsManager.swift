//
//  SettingsManager.swift
//  powertoys
//

import Foundation
import AppKit
import SwiftUI

extension Notification.Name {
    static let toolEnablementChanged = Notification.Name("toolEnablementChanged")
}

@Observable
@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let prefix = "powertoys"
    private(set) var disabledToolIDs: Set<String>
    private(set) var transitioningToolIDs: Set<String> = []

    private init() {
        disabledToolIDs = Set(UserDefaults.standard.stringArray(forKey: "powertoys.disabledTools") ?? [])
    }

    private func key(_ name: String, tool: String? = nil) -> String {
        if let tool {
            return "\(prefix).\(tool).\(name)"
        }
        return "\(prefix).\(name)"
    }

    func get<T>(_ name: String, tool: String? = nil, default defaultValue: T) -> T {
        let fullKey = key(name, tool: tool)
        return defaults.object(forKey: fullKey) as? T ?? defaultValue
    }

    func set<T>(_ name: String, tool: String? = nil, value: T) {
        let fullKey = key(name, tool: tool)
        defaults.set(value, forKey: fullKey)
    }

    func remove(_ name: String, tool: String? = nil) {
        let fullKey = key(name, tool: tool)
        defaults.removeObject(forKey: fullKey)
    }

    func getBool(_ name: String, tool: String? = nil, default defaultValue: Bool = false) -> Bool {
        let fullKey = key(name, tool: tool)
        if defaults.object(forKey: fullKey) != nil {
            return defaults.bool(forKey: fullKey)
        }
        return defaultValue
    }

    func getInt(_ name: String, tool: String? = nil, default defaultValue: Int = 0) -> Int {
        let fullKey = key(name, tool: tool)
        if defaults.object(forKey: fullKey) != nil {
            return defaults.integer(forKey: fullKey)
        }
        return defaultValue
    }

    func getDouble(_ name: String, tool: String? = nil, default defaultValue: Double = 0) -> Double {
        let fullKey = key(name, tool: tool)
        if defaults.object(forKey: fullKey) != nil {
            return defaults.double(forKey: fullKey)
        }
        return defaultValue
    }

    func getString(_ name: String, tool: String? = nil, default defaultValue: String = "") -> String {
        let fullKey = key(name, tool: tool)
        return defaults.string(forKey: fullKey) ?? defaultValue
    }

    func getData(_ name: String, tool: String? = nil) -> Data? {
        let fullKey = key(name, tool: tool)
        return defaults.data(forKey: fullKey)
    }

    func setData(_ name: String, tool: String? = nil, value: Data) {
        let fullKey = key(name, tool: tool)
        defaults.set(value, forKey: fullKey)
    }

    func getCodable<T: Codable>(_ name: String, tool: String? = nil, type: T.Type) -> T? {
        guard let data = getData(name, tool: tool) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setCodable<T: Codable>(_ name: String, tool: String? = nil, value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        setData(name, tool: tool, value: data)
    }

    func isToolEnabled(_ toolID: String) -> Bool {
        !disabledToolIDs.contains(toolID)
    }

    func isToolTransitioning(_ toolID: String) -> Bool {
        transitioningToolIDs.contains(toolID)
    }

    func setToolEnabled(_ enabled: Bool, for toolID: String) {
        guard enabled != isToolEnabled(toolID) else { return }
        if enabled {
            disabledToolIDs.remove(toolID)
        } else {
            disabledToolIDs.insert(toolID)
        }
        defaults.set(disabledToolIDs.sorted(), forKey: "powertoys.disabledTools")

        guard !AppRuntime.isRunningTests else { return }
        NotificationCenter.default.post(
            name: .toolEnablementChanged,
            object: toolID,
            userInfo: ["enabled": enabled]
        )
        applyLifecycle(enabled: enabled, toolID: toolID)
    }

    private func applyLifecycle(enabled: Bool, toolID: String) {
        switch toolID {
        case "awake":
            enabled ? AwakeService.shared.resume() : AwakeService.shared.shutdown()
        case "rclone":
            transitioningToolIDs.insert(toolID)
            Task {
                if enabled {
                    let hasOpenWindow = NSApp.windows.contains {
                        ToolActionRouter.windowIdentifier($0.identifier?.rawValue, matches: toolID)
                    }
                    if hasOpenWindow || UserDefaults.standard.bool(forKey: "tool.rclone.startAtLaunch") {
                        await RcloneJobManager.shared.start()
                    }
                } else {
                    await RcloneJobManager.shared.shutdown()
                }
                transitioningToolIDs.remove(toolID)
            }
        default:
            break
        }
    }
}

// MARK: - App Settings Keys

extension SettingsManager {
    var theme: String {
        get { getString("theme", default: "system") }
        set { set("theme", value: newValue) }
    }

}

// MARK: - Tool Settings Convenience

extension SettingsManager {
    func toolSetting<T>(_ name: String, for toolId: String, default defaultValue: T) -> T {
        get(name, tool: toolId, default: defaultValue)
    }

    func setToolSetting<T>(_ name: String, for toolId: String, value: T) {
        set(name, tool: toolId, value: value)
    }
}
