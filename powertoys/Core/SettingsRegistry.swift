import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement

@MainActor
enum SettingsRegistry {
    struct Entry: Identifiable {
        let id: String
        let key: String
        let toolID: String?
        let label: String

        fileprivate let defaultValue: Any
        fileprivate let readValue: (UserDefaults) -> Any
        fileprivate let formatValue: @MainActor (Any) -> String
        fileprivate let resetStoredValue: (UserDefaults) -> Void
        fileprivate let beforeReset: (() async -> Void)?
        fileprivate let afterReset: (() async -> Void)?
        fileprivate let runtimeOwnsStorage: Bool

        var defaultDisplay: String { formatValue(defaultValue) }

        func currentDisplay(defaults: UserDefaults = .standard) -> String {
            formatValue(readValue(defaults))
        }

        func isModified(defaults: UserDefaults = .standard) -> Bool {
            !SettingsRegistry.semanticallyEqual(readValue(defaults), defaultValue)
        }

        init(
            id: String,
            key: String,
            toolID: String? = nil,
            label: String,
            defaultValue: Any,
            readValue: @escaping (UserDefaults) -> Any,
            formatValue: @escaping @MainActor (Any) -> String = SettingsRegistry.defaultFormat,
            resetStoredValue: @escaping (UserDefaults) -> Void,
            beforeReset: (() async -> Void)? = nil,
            afterReset: (() async -> Void)? = nil,
            runtimeOwnsStorage: Bool = false
        ) {
            self.id = id
            self.key = key
            self.toolID = toolID
            self.label = label
            self.defaultValue = defaultValue
            self.readValue = readValue
            self.formatValue = formatValue
            self.resetStoredValue = resetStoredValue
            self.beforeReset = beforeReset
            self.afterReset = afterReset
            self.runtimeOwnsStorage = runtimeOwnsStorage
        }
    }

    struct Difference: Identifiable {
        let entry: Entry
        let currentDisplay: String
        let defaultDisplay: String

        var id: String { entry.id }
        var key: String { entry.key }
        var toolID: String? { entry.toolID }
        var label: String { entry.label }
    }

    static var entries: [Entry] {
        appEntries
            + enablementEntries
            + menuBarEntries
            + shortcutEntries
            + colorPickerEntries
            + awakeEntries
            + textExtractorEntries
            + inputDevicesEntries
            + systemMonitorEntries
            + rulerEntries
            + rcloneEntries
            + diskExplorerEntries
            + portmanEntries
            + netToysEntries
            + macTweaksEntries
            + systemCareEntries
            + logsEntries
            + switchEntries
    }

    static func entries(toolIDs: Set<String>) -> [Entry] {
        entries.filter { entry in
            guard let toolID = entry.toolID else { return false }
            return toolIDs.contains(toolID)
        }
    }

    static func modified(defaults: UserDefaults = .standard) -> [Difference] {
        modified(entries: entries, defaults: defaults)
    }

    static func modified(entries: [Entry], defaults: UserDefaults) -> [Difference] {
        entries.compactMap { entry in
            let current = entry.readValue(defaults)
            guard !semanticallyEqual(current, entry.defaultValue) else { return nil }
            return Difference(
                entry: entry,
                currentDisplay: entry.formatValue(current),
                defaultDisplay: entry.defaultDisplay
            )
        }
    }

    static func hasChanges(defaults: UserDefaults = .standard) -> Bool {
        entries.contains { $0.isModified(defaults: defaults) }
    }

    static func reset(_ difference: Difference, defaults: UserDefaults = .standard) async {
        await reset(difference.entry, defaults: defaults)
    }

    static func reset(_ entry: Entry, defaults: UserDefaults = .standard) async {
        let usesLiveRuntime = defaults === UserDefaults.standard
        if usesLiveRuntime { await entry.beforeReset?() }
        if !usesLiveRuntime || !entry.runtimeOwnsStorage {
            entry.resetStoredValue(defaults)
        }
        if usesLiveRuntime { await entry.afterReset?() }
    }

    static func resetAll(defaults: UserDefaults = .standard) async {
        for difference in modified(defaults: defaults) {
            guard !Task.isCancelled else { return }
            await reset(difference, defaults: defaults)
        }
    }
}

// MARK: - App and tool lifecycle

private extension SettingsRegistry {
    static var appEntries: [Entry] {
        [
            scalar(
                id: "app.appearance",
                key: AppAppearance.storageKey,
                label: "Appearance",
                defaultValue: AppAppearance.dark.rawValue,
                titles: Dictionary(uniqueKeysWithValues: AppAppearance.allCases.map { ($0.rawValue, $0.title) }),
                afterReset: { AppAppearance.dark.apply() }
            ),
            scalar(
                id: "app.closeMainWindowAfterOpeningTool",
                key: "app.closeMainWindowAfterOpeningTool",
                label: "Close MacPowerToys after opening a tool",
                defaultValue: false
            ),
            scalar(
                id: "app.showTray",
                key: "app.showTray",
                label: "Show MacPowerToys in the menu bar",
                defaultValue: true
            ),
            scalar(
                id: "settingsSync.enabled",
                key: SettingsSyncManager.enabledDefaultsKey,
                label: "Sync settings via iCloud",
                defaultValue: false,
                beforeReset: { SettingsSyncManager.current?.disable() }
            ),
            Entry(
                id: "app.openAtLogin",
                key: "app.openAtLogin",
                label: "Open at login",
                defaultValue: "disabled",
                readValue: { defaults in
                    guard defaults === UserDefaults.standard else { return "disabled" }
                    return switch SMAppService.mainApp.status {
                    case .enabled: "enabled"
                    case .requiresApproval: "requiresApproval"
                    case .notRegistered, .notFound: "disabled"
                    @unknown default: "disabled"
                    }
                },
                formatValue: {
                    switch $0 as? String {
                    case "enabled": "Enabled"
                    case "requiresApproval": "Needs approval"
                    default: "Disabled"
                    }
                },
                resetStoredValue: { _ in },
                beforeReset: {
                    if SMAppService.mainApp.status == .enabled
                        || SMAppService.mainApp.status == .requiresApproval {
                        try? await SMAppService.mainApp.unregister()
                    }
                }
            ),
            jsonString(
                id: "main.favorites",
                key: "main.favorites",
                label: "Favorite tools",
                defaultValue: "[]"
            ),
            scalar(
                id: "main.sort",
                key: "main.sort",
                label: "Tool sort order",
                defaultValue: "defaultOrder",
                titles: ["defaultOrder": "Default order", "name": "Name", "category": "Category"]
            ),
            scalar(
                id: "main.viewMode",
                key: "main.viewMode",
                label: "Tool view",
                defaultValue: "grid",
                titles: ["grid": "Grid", "list": "List"]
            ),
        ]
    }

    static var enablementEntries: [Entry] {
        ToolRegistry.allTools.map { tool in
            let toolID = tool.id
            return Entry(
                id: "tool.\(toolID).enabled",
                key: "powertoys.disabledTools",
                toolID: toolID,
                label: "Enabled",
                defaultValue: true,
                readValue: { defaults in
                    let disabled = Set((defaults.stringArray(forKey: "powertoys.disabledTools") ?? [])
                        .map(SettingsManager.migratedDisabledToolID))
                    return !disabled.contains(toolID)
                },
                formatValue: enabledFormat,
                resetStoredValue: { defaults in
                    var disabled = defaults.stringArray(forKey: "powertoys.disabledTools") ?? []
                    disabled.removeAll { SettingsManager.migratedDisabledToolID($0) == toolID }
                    disabled.isEmpty
                        ? defaults.removeObject(forKey: "powertoys.disabledTools")
                        : defaults.set(disabled, forKey: "powertoys.disabledTools")
                },
                beforeReset: { SettingsManager.shared.setToolEnabled(true, for: toolID) },
                runtimeOwnsStorage: true
            )
        }
    }

    static var menuBarEntries: [Entry] {
        IndividualMenuBarTool.allCases.map { tool in
            let defaultMode: MenuBarDisplayMode = tool == .cloudSync || tool == .awake ? .combined : .none
            return Entry(
                id: "tool.\(tool.id).menuBarDisplayMode",
                key: tool.preferenceKey,
                toolID: tool.id,
                label: "Menu bar",
                defaultValue: defaultMode.rawValue,
                readValue: { tool.displayMode(in: $0).rawValue },
                formatValue: { value in
                    MenuBarDisplayMode(rawValue: value as? String ?? "")?.title ?? String(describing: value)
                },
                resetStoredValue: { defaults in
                    defaults.removeObject(forKey: tool.preferenceKey)
                    defaults.removeObject(forKey: tool.legacyPreferenceKey)
                },
                afterReset: { IndividualMenuBarController.current?.refresh() }
            )
        }
    }

    static var shortcutEntries: [Entry] {
        GlobalShortcutAction.allCases.flatMap { action in
            let prefix = "shortcut.\(action.defaultsName)"
            let defaultShortcut = action.defaultShortcut
            return [
                scalar(
                    id: "\(prefix).enabled",
                    key: "\(prefix).enabled",
                    toolID: action.toolID,
                    label: "Enable shortcut",
                    defaultValue: true,
                    beforeReset: { GlobalShortcutManager.current?.setEnabled(true, for: action) }
                ),
                Entry(
                    id: prefix,
                    key: prefix,
                    toolID: action.toolID,
                    label: "Keyboard shortcut",
                    defaultValue: shortcutData(defaultShortcut),
                    readValue: { shortcutData(storedShortcut(for: action, defaults: $0)) },
                    formatValue: { value in
                        (value as? Data).flatMap(shortcut(from:))?.display ?? "Default"
                    },
                    resetStoredValue: { defaults in
                        ["keyCode", "modifiers", "keyLabel", "key"].forEach {
                            defaults.removeObject(forKey: "\(prefix).\($0)")
                        }
                    },
                    beforeReset: { GlobalShortcutManager.current?.setShortcut(defaultShortcut, for: action) }
                ),
            ]
        }
    }
}

// MARK: - Service-backed settings

private extension SettingsRegistry {
    static var colorPickerEntries: [Entry] {
        [
            scalar(
                id: "color-picker.format",
                key: "color-picker.format.v1",
                toolID: "color-picker",
                label: "Copy format",
                defaultValue: ColorCopyFormat.hex.rawValue,
                titles: Dictionary(uniqueKeysWithValues: ColorCopyFormat.allCases.map { ($0.rawValue, $0.title) }),
                beforeReset: { ColorPickerService.shared.defaultFormat = .hex }
            ),
        ]
    }
}

// MARK: - Codable service settings

private extension SettingsRegistry {
    static var awakeEntries: [Entry] {
        let defaults = AwakeConfiguration()
        return [
            codableField(
                id: "awake.keepDisplayOn",
                key: "awake.configuration.v1",
                toolID: "awake",
                label: "Keep display on",
                defaultRoot: defaults,
                get: \AwakeConfiguration.keepDisplayOn,
                set: { $0.keepDisplayOn = $1 },
                display: enabledFormat,
                beforeReset: { AwakeService.current?.setKeepDisplayOn($0) }
            ),
            codableField(
                id: "awake.presets",
                key: "awake.configuration.v1",
                toolID: "awake",
                label: "Duration presets",
                defaultRoot: defaults,
                get: \AwakeConfiguration.presets,
                set: { $0.presets = $1 },
                display: { $0.map(AwakeService.presetLabel).joined(separator: ", ") },
                beforeReset: { AwakeService.current?.setPresets($0) }
            ),
        ]
    }

    static var textExtractorEntries: [Entry] {
        let defaults = TextExtractorSettings()
        return [
            codableField(
                id: "text-extractor.recognitionQuality", key: "text-extractor.settings.v1",
                toolID: "text-extractor", label: "Recognition quality", defaultRoot: defaults,
                get: \TextExtractorSettings.speed, set: { $0.speed = $1 },
                display: \TextRecognitionSpeed.title,
                beforeReset: { TextExtractorService.shared.settings.speed = $0 }
            ),
            codableField(
                id: "text-extractor.languageCorrection", key: "text-extractor.settings.v1",
                toolID: "text-extractor", label: "Use language correction", defaultRoot: defaults,
                get: \TextExtractorSettings.languageCorrection, set: { $0.languageCorrection = $1 },
                display: enabledFormat,
                beforeReset: { TextExtractorService.shared.settings.languageCorrection = $0 }
            ),
            codableField(
                id: "text-extractor.detectCodes", key: "text-extractor.settings.v1",
                toolID: "text-extractor", label: "Detect QR codes and barcodes", defaultRoot: defaults,
                get: \TextExtractorSettings.detectCodes, set: { $0.detectCodes = $1 },
                display: enabledFormat,
                beforeReset: { TextExtractorService.shared.settings.detectCodes = $0 }
            ),
            codableField(
                id: "text-extractor.preferredLanguages", key: "text-extractor.settings.v1",
                toolID: "text-extractor", label: "Preferred languages", defaultRoot: defaults,
                get: \TextExtractorSettings.preferredLanguages, set: { $0.preferredLanguages = $1 },
                display: { $0.isEmpty ? "Automatic" : $0.joined(separator: ", ") },
                beforeReset: { TextExtractorService.shared.settings.preferredLanguages = $0 }
            ),
        ]
    }

    static var inputDevicesEntries: [Entry] {
        let defaults = InputDevicesSettings()
        var result = [
            codableField(
                id: "input-devices.scrollControlEnabled", key: "inputDevices.settings",
                toolID: "input-devices", label: "Adjust scrolling system wide", defaultRoot: defaults,
                get: \InputDevicesSettings.scrollControlEnabled, set: { $0.scrollControlEnabled = $1 },
                display: enabledFormat,
                beforeReset: { value in InputDevicesManager.current?.update { $0.scrollControlEnabled = value } }
            ),
            codableField(
                id: "input-devices.eventOverride", key: "inputDevices.settings",
                toolID: "input-devices", label: "Scroll device", defaultRoot: defaults,
                get: \InputDevicesSettings.eventOverride, set: { $0.eventOverride = $1 },
                display: \InputEventOverride.title,
                beforeReset: { value in InputDevicesManager.current?.update { $0.eventOverride = value } }
            ),
        ]
        result += inputProfileEntries(name: "Mouse", id: "mouse", keyPath: \InputDevicesSettings.mouse, defaults: defaults)
        result += inputProfileEntries(name: "Trackpad", id: "trackpad", keyPath: \InputDevicesSettings.trackpad, defaults: defaults)
        return result
    }

    static func inputProfileEntries(
        name: String,
        id: String,
        keyPath: WritableKeyPath<InputDevicesSettings, InputScrollProfile>,
        defaults: InputDevicesSettings
    ) -> [Entry] {
        func entry<Value: Codable & Equatable>(
            _ fieldID: String,
            _ label: String,
            _ field: WritableKeyPath<InputScrollProfile, Value>,
            _ display: @escaping (Value) -> String
        ) -> Entry {
            codableField(
                id: "input-devices.\(id).\(fieldID)", key: "inputDevices.settings",
                toolID: "input-devices", label: "\(name) \(label)", defaultRoot: defaults,
                get: { $0[keyPath: keyPath][keyPath: field] },
                set: { $0[keyPath: keyPath][keyPath: field] = $1 },
                display: display,
                beforeReset: { value in
                    InputDevicesManager.current?.update { $0[keyPath: keyPath][keyPath: field] = value }
                }
            )
        }
        return [
            entry("enabled", "profile", \.enabled, enabledFormat),
            entry("reverseVertical", "reverse vertical", \.reverseVertical, enabledFormat),
            entry("reverseHorizontal", "reverse horizontal", \.reverseHorizontal, enabledFormat),
            entry("horizontalEnabled", "horizontal scrolling", \.horizontalEnabled, enabledFormat),
            entry("shiftScrollsHorizontally", "Shift scrolls horizontally", \.shiftScrollsHorizontally, enabledFormat),
            entry("speed", "speed", \.speed, numberFormat),
            entry("smooth", "smooth scrolling", \.smooth, enabledFormat),
        ]
    }

    static var systemMonitorEntries: [Entry] {
        let defaults = SystemMonitorMenuSettings()
        var result = [
            codableField(
                id: "system-monitor.menu.enabled", key: SystemMonitorService.settingsKey,
                toolID: "system-monitor", label: "Menu bar metrics", defaultRoot: defaults,
                readRoot: SystemMonitorService.storedMenuSettings(in:),
                aliases: [SystemMonitorService.legacySettingsKey],
                get: \SystemMonitorMenuSettings.enabled,
                set: { $0.enabled = $1; $0.normalize() }, display: enabledFormat,
                beforeReset: { value in SystemMonitorService.current?.updateMenuSettings { $0.enabled = value } }
            ),
            codableField(
                id: "system-monitor.menu.interval", key: SystemMonitorService.settingsKey,
                toolID: "system-monitor", label: "Menu refresh interval", defaultRoot: defaults,
                readRoot: SystemMonitorService.storedMenuSettings(in:),
                aliases: [SystemMonitorService.legacySettingsKey],
                get: \SystemMonitorMenuSettings.interval,
                set: { $0.interval = $1; $0.normalize() }, display: { "\(numberFormat($0)) s" },
                beforeReset: { value in SystemMonitorService.current?.updateMenuSettings { $0.interval = value } }
            ),
            codableField(
                id: "system-monitor.menu.order", key: SystemMonitorService.settingsKey,
                toolID: "system-monitor", label: "Menu metric order", defaultRoot: defaults,
                readRoot: SystemMonitorService.storedMenuSettings(in:),
                aliases: [SystemMonitorService.legacySettingsKey],
                get: { $0.items.map(\.metric) },
                set: { settings, order in
                    settings.items = order.compactMap { metric in settings.items.first { $0.metric == metric } }
                    settings.normalize()
                },
                display: { $0.map(\.title).joined(separator: ", ") },
                beforeReset: { order in
                    SystemMonitorService.current?.updateMenuSettings { settings in
                        settings.items = order.compactMap { metric in settings.items.first { $0.metric == metric } }
                    }
                }
            ),
        ]
        for defaultItem in SystemMonitorMenuSettings.defaultItems {
            let metric = defaultItem.metric
            result.append(codableField(
                id: "system-monitor.menu.\(metric.rawValue)", key: SystemMonitorService.settingsKey,
                toolID: "system-monitor", label: "\(metric.title) menu item", defaultRoot: defaults,
                readRoot: SystemMonitorService.storedMenuSettings(in:),
                aliases: [SystemMonitorService.legacySettingsKey],
                get: { $0.items.first(where: { $0.metric == metric }) ?? defaultItem },
                set: { settings, value in
                    if let index = settings.items.firstIndex(where: { $0.metric == metric }) {
                        settings.items[index] = value
                    }
                    settings.normalize()
                },
                display: menuItemFormat,
                beforeReset: { value in
                    SystemMonitorService.current?.updateMenuSettings { settings in
                        if let index = settings.items.firstIndex(where: { $0.metric == metric }) {
                            settings.items[index] = value
                        }
                    }
                }
            ))
        }
        result += [
            scalar(
                id: "system-monitor.historyMinutes", key: "systemMonitor.historyMinutes",
                toolID: "system-monitor", label: "Chart history", defaultValue: 2,
                formatter: { "\(numberFormat($0)) minutes" }
            ),
            scalar(
                id: "system-monitor.rememberTrayPage", key: "systemMonitor.rememberTrayPage",
                toolID: "system-monitor", label: "Remember menu page", defaultValue: true
            ),
        ]
        return result
    }
}

// MARK: - Direct UserDefaults settings

private extension SettingsRegistry {
    static var rcloneEntries: [Entry] {
        [
            scalar(id: "rclone.startAtLaunch", key: "tool.rclone.startAtLaunch", toolID: "rclone", label: "Start Cloud Sync at launch", defaultValue: false),
            scalar(id: "rclone.transfers", key: RcloneDefaults.transfersKey, toolID: "rclone", label: "Parallel transfers", defaultValue: RcloneDefaults.transfers),
            scalar(id: "rclone.checkers", key: RcloneDefaults.checkersKey, toolID: "rclone", label: "Checkers", defaultValue: RcloneDefaults.checkers),
            scalar(id: "rclone.bandwidthLimit", key: RcloneDefaults.bandwidthLimitKey, toolID: "rclone", label: "Bandwidth limit", defaultValue: RcloneDefaults.bandwidthLimit, emptyTitle: "Off"),
            scalar(id: "rclone.defaultOperation", key: RcloneDefaults.defaultOperationKey, toolID: "rclone", label: "Default operation", defaultValue: RcloneDefaults.defaultOperation, titles: Dictionary(uniqueKeysWithValues: RcloneOperation.allCases.map { ($0.rawValue, $0.displayName) })),
            scalar(id: "rclone.ignorePatterns", key: RcloneDefaults.ignorePatternsKey, toolID: "rclone", label: "Ignore patterns", defaultValue: RcloneDefaults.ignorePatterns, formatter: lineListFormat),
            scalar(id: "rclone.maxRetries", key: RcloneDefaults.maxRetriesKey, toolID: "rclone", label: "Max retries", defaultValue: RcloneDefaults.maxRetries),
            scalar(id: "rclone.retryBackoff", key: RcloneDefaults.retryBackoffKey, toolID: "rclone", label: "Retry backoff", defaultValue: RcloneDefaults.retryBackoff, formatter: { "\(numberFormat($0)) s" }),
            scalar(id: "rclone.lowLevelRetries", key: RcloneDefaults.lowLevelRetriesKey, toolID: "rclone", label: "Low-level retries", defaultValue: RcloneDefaults.lowLevelRetries),
            scalar(id: "rclone.maxConcurrentJobs", key: RcloneDefaults.maxConcurrentJobsKey, toolID: "rclone", label: "Concurrent jobs", defaultValue: RcloneDefaults.maxConcurrentJobs),
            scalar(id: "rclone.binaryPath", key: RcloneDefaults.binaryPathKey, toolID: "rclone", label: "rclone binary path", defaultValue: "", emptyTitle: "Auto-detected"),
        ]
    }

    static var diskExplorerEntries: [Entry] {
        [
            scalar(id: "disk-explorer.chartStyle", key: "diskExplorer.chartStyle", toolID: "disk-explorer", label: "Chart style", defaultValue: DiskChartStyle.treemap.rawValue),
            scalar(id: "disk-explorer.chartMeasure", key: "diskExplorer.chartMeasure", toolID: "disk-explorer", label: "Chart measure", defaultValue: DiskChartMeasure.space.rawValue),
            scalar(id: "disk-explorer.apparentSize", key: "diskExplorer.apparentSize", toolID: "disk-explorer", label: "Use apparent size", defaultValue: false),
            scalar(id: "disk-explorer.includeHidden", key: "diskExplorer.includeHidden", toolID: "disk-explorer", label: "Include hidden files", defaultValue: true),
        ]
    }

    static var portmanEntries: [Entry] {
        [
            scalar(id: "portman.editor", key: "portman.editor", toolID: "portman", label: "Open folders in", defaultValue: "auto", titles: ["auto": "Automatic", "finder": "Finder"]),
            scalar(id: "portman.scanLowerPort", key: "portman.scanLowerPort", toolID: "portman", label: "First scan port", defaultValue: 3000),
            scalar(id: "portman.scanUpperPort", key: "portman.scanUpperPort", toolID: "portman", label: "Last scan port", defaultValue: 9999),
            scalar(id: "portman.scanInterval", key: "portman.scanInterval", toolID: "portman", label: "Scan interval", defaultValue: 2.0, formatter: { "\(numberFormat($0)) s" }),
            scalar(id: "portman.showAllListeners", key: "portman.showAllListeners", toolID: "portman", label: "Include other listening processes", defaultValue: false),
            scalar(id: "portman.protectedCommands", key: "portman.protectedCommands", toolID: "portman", label: "Extra protected process names", defaultValue: "", emptyTitle: "None"),
            scalar(id: "portman.cleanupMode", key: "portman.cleanupMode", toolID: "portman", label: "Cleanup mode", defaultValue: PortmanCleanupMode.ask.rawValue, titles: ["off": "Off", "ask": "Ask", "automatic": "Automatic"]),
            scalar(id: "portman.includeDeletedFolders", key: "portman.includeDeletedFolders", toolID: "portman", label: "Include deleted folders", defaultValue: true),
            scalar(id: "portman.idleHours", key: "portman.idleHours", toolID: "portman", label: "Suggest after idle", defaultValue: 4.0, formatter: { "\(numberFormat($0)) h" }),
            scalar(id: "portman.runningDays", key: "portman.runningDays", toolID: "portman", label: "Suggest after running", defaultValue: 3.0, formatter: { "\(numberFormat($0)) days" }),
            scalar(id: "portman.forceQuitSeconds", key: "portman.forceQuitSeconds", toolID: "portman", label: "Force quit delay", defaultValue: 3.0, formatter: { "\(numberFormat($0)) s" }),
            scalar(id: "portman.sessionLinksEnabled", key: "portman.sessionLinksEnabled", toolID: "portman", label: "Link coding sessions", defaultValue: false),
            scalar(id: "portman.publicGitHubLinksEnabled", key: "portman.publicGitHubLinksEnabled", toolID: "portman", label: "Find public GitHub links", defaultValue: false),
        ]
    }

    static var systemCareEntries: [Entry] {
        [scalar(
            id: "system-care.defaultMode", key: "systemCare.defaultMode", toolID: "system-care",
            label: "Default cleanup mode", defaultValue: SystemCareMode.quick.rawValue
        )]
    }

    static var logsEntries: [Entry] {
        [scalar(
            id: "logs.fontSize", key: "logs.fontSize", toolID: "logs",
            label: "Log font size", defaultValue: 11,
            titles: ["10": "Small", "11": "Medium", "12": "Default", "14": "Large"]
        )]
    }

    static var switchEntries: [Entry] {
        [
            scalar(id: "switch.showUsageAsUsed", key: "switchUsageShowsUsed", toolID: "switch", label: "Show percentage used", defaultValue: true),
            scalar(id: "switch.defaultShowTrayUsage", key: SwitchTrayUsagePreferences.defaultKey, toolID: "switch", label: "Show account usage", defaultValue: true),
            scalar(id: "switch.trayTokenPeriod", key: SwitchTrayUsagePreferences.periodKey, toolID: "switch", label: "Token summary", defaultValue: SwitchTrayTokenPeriod.sinceReset.rawValue, titles: Dictionary(uniqueKeysWithValues: SwitchTrayTokenPeriod.allCases.map { ($0.rawValue, $0.label) })),
        ]
    }
}

// MARK: - Ruler, NetToys, and Mac Tweaks

private extension SettingsRegistry {
    static var rulerEntries: [Entry] {
        let defaultLengths = RulerLayoutState.defaultLengths()
        return [
            rulerScalar(id: "unit", label: "Default unit", defaultValue: Prefs.defaultUnit.rawValue, apply: { prefs.unit = Unit(rawValue: $0) ?? Prefs.defaultUnit }),
            rulerScalar(id: "defaultHorizontalLength", label: "Default horizontal length", defaultValue: Prefs.unsetDefaultRulerLength,
                        formatter: { rulerLengthFormat($0, fallback: defaultLengths.horizontal) }, apply: { prefs.defaultHorizontalLength = $0 }),
            rulerScalar(id: "defaultVerticalLength", label: "Default vertical length", defaultValue: Prefs.unsetDefaultRulerLength,
                        formatter: { rulerLengthFormat($0, fallback: defaultLengths.vertical) }, apply: { prefs.defaultVerticalLength = $0 }),
            rulerScalar(id: "foregroundOpacity", label: "Foreground opacity", defaultValue: Prefs.defaultForegroundOpacity, formatter: percentFormat, apply: { prefs.foregroundOpacity = $0 }),
            rulerScalar(id: "backgroundOpacity", label: "Background opacity", defaultValue: Prefs.defaultBackgroundOpacity, formatter: percentFormat, apply: { prefs.backgroundOpacity = $0 }),
            rulerScalar(id: "borderOpacity", label: "Border opacity", defaultValue: Prefs.defaultBorderOpacity, formatter: percentFormat, apply: { prefs.borderOpacity = $0 }),
            rulerScalar(id: "floatRulers", label: "Float rulers", defaultValue: Prefs.defaultFloatRulers, apply: { prefs.floatRulers = $0 }),
            rulerScalar(id: "rulerShadow", label: "Ruler shadow", defaultValue: Prefs.defaultRulerShadow, apply: { prefs.rulerShadow = $0 }),
            Entry(
                id: "ruler.rulerColor", key: "rulerColor", toolID: "ruler", label: "Ruler color",
                defaultValue: colorComponents(Prefs.defaultRulerFillColor),
                readValue: { colorComponents(Prefs.rulerFillColor(fromArchivedData: $0.data(forKey: "rulerColor"))) },
                formatValue: { ($0 as? [Int]).map { "RGB \($0.prefix(3).map(String.init).joined(separator: ", "))" } ?? "Default" },
                resetStoredValue: { $0.removeObject(forKey: "rulerColor") },
                beforeReset: { prefs.rulerColor = Prefs.defaultRulerFillColor }
            ),
        ]
    }

    static var netToysEntries: [Entry] {
        let defaultPreferences = NetToysScannerPreferences(
            portInput: "22, 80, 443", timeoutMilliseconds: 750, concurrency: 64,
            launchDelayMilliseconds: 0, collectPingDetails: false, pingProbeCount: 2,
            detectHTTPServer: false, detectHTTPProxy: false, detectNetBIOS: false,
            customTextEnabled: false, customTextPort: 22, customTextRequest: "", customTextPattern: ""
        )
        let defaultLiveness = NetToysLivenessPreferences(
            method: .tcp, pingTimeoutMilliseconds: 750,
            adaptiveTCPTimeout: false, scanUnresponsiveHosts: true
        )
        return [
            Entry(
                id: "nettoys.scanner.preferences", key: "nettoys.scanner.preferences",
                toolID: "nettoys", label: "Scanner settings",
                defaultValue: netToysPreferenceData(defaultPreferences),
                readValue: { defaults in
                    let saved = defaults.data(forKey: "nettoys.scanner.preferences")
                        .flatMap { try? JSONDecoder().decode(NetToysScannerPreferences.self, from: $0) }
                        ?? defaultPreferences
                    return netToysPreferenceData(saved)
                },
                formatValue: { _ in "Custom scanner settings" },
                resetStoredValue: { defaults in
                    let saved = defaults.data(forKey: "nettoys.scanner.preferences")
                        .flatMap { try? JSONDecoder().decode(NetToysScannerPreferences.self, from: $0) }
                        ?? defaultPreferences
                    let reset = NetToysScannerPreferences(
                        portInput: saved.portInput,
                        timeoutMilliseconds: defaultPreferences.timeoutMilliseconds,
                        concurrency: defaultPreferences.concurrency,
                        launchDelayMilliseconds: defaultPreferences.launchDelayMilliseconds,
                        collectPingDetails: defaultPreferences.collectPingDetails,
                        pingProbeCount: defaultPreferences.pingProbeCount,
                        detectHTTPServer: defaultPreferences.detectHTTPServer,
                        detectHTTPProxy: defaultPreferences.detectHTTPProxy,
                        detectNetBIOS: defaultPreferences.detectNetBIOS,
                        customTextEnabled: defaultPreferences.customTextEnabled,
                        customTextPort: defaultPreferences.customTextPort,
                        customTextRequest: defaultPreferences.customTextRequest,
                        customTextPattern: defaultPreferences.customTextPattern
                    )
                    if saved.portInput == defaultPreferences.portInput {
                        defaults.removeObject(forKey: "nettoys.scanner.preferences")
                    } else if let data = try? JSONEncoder().encode(reset) {
                        defaults.set(data, forKey: "nettoys.scanner.preferences")
                    }
                }
            ),
            dataEntry(
                id: "nettoys.scanner.liveness", key: "nettoys.scanner.liveness-preferences",
                toolID: "nettoys", label: "Host detection", defaultValue: defaultLiveness,
                display: { $0.method.rawValue }
            ),
            Entry(
                id: "nettoys.scanner.openers", key: "nettoys.scanner.openers",
                toolID: "nettoys", label: "Openers",
                defaultValue: openerData(NetToysOpener.defaults),
                readValue: { defaults in
                    let openers = defaults.data(forKey: "nettoys.scanner.openers")
                        .flatMap { try? JSONDecoder().decode([NetToysOpener].self, from: $0) }
                        ?? NetToysOpener.defaults
                    return openerData(openers)
                },
                formatValue: { value in
                    let count = (value as? Data).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Any] }?.count ?? 0
                    return "\(count) opener\(count == 1 ? "" : "s")"
                },
                resetStoredValue: { $0.removeObject(forKey: "nettoys.scanner.openers") }
            ),
        ]
    }

    static var macTweaksEntries: [Entry] {
        [
            scalar(
                id: "mac-tweaks.micLock.enabled", key: "macTweaks.micLock.enabled",
                toolID: "mac-tweaks", label: "Mic Lock", defaultValue: false,
                beforeReset: { MicLockService.shared.setEnabled(false) }
            ),
            Entry(
                id: "mac-tweaks.micLock.savedInputs", key: "macTweaks.micLock.savedInputs",
                toolID: "mac-tweaks", label: "Mic Lock preferred inputs",
                defaultValue: encode([SavedMicInput?](repeating: nil, count: 4)),
                readValue: { defaults in
                    let saved = defaults.data(forKey: "macTweaks.micLock.savedInputs")
                        .flatMap { try? JSONDecoder().decode([SavedMicInput?].self, from: $0) } ?? []
                    return (try? JSONEncoder().encode(Array((saved + Array(repeating: nil, count: 4)).prefix(4)))) ?? Data()
                },
                formatValue: { value in
                    let inputs = (value as? Data).flatMap { try? JSONDecoder().decode([SavedMicInput?].self, from: $0) } ?? []
                    let names = inputs.compactMap { $0?.name }
                    return names.isEmpty ? "None" : names.joined(separator: ", ")
                },
                resetStoredValue: { $0.removeObject(forKey: "macTweaks.micLock.savedInputs") },
                beforeReset: {
                    for index in 0..<4 { MicLockService.shared.setSavedInput(nil, at: index) }
                }
            ),
        ]
    }
}

// MARK: - Entry factories

private extension SettingsRegistry {
    static func scalar(
        id: String,
        key: String,
        toolID: String? = nil,
        label: String,
        defaultValue: Any,
        titles: [String: String] = [:],
        emptyTitle: String? = nil,
        formatter: (@MainActor (Any) -> String)? = nil,
        beforeReset: (() async -> Void)? = nil,
        afterReset: (() async -> Void)? = nil
    ) -> Entry {
        Entry(
            id: id, key: key, toolID: toolID, label: label, defaultValue: defaultValue,
            readValue: { $0.object(forKey: key) ?? defaultValue },
            formatValue: formatter ?? { value in
                if let string = value as? String {
                    if string.isEmpty, let emptyTitle { return emptyTitle }
                    return titles[string] ?? string
                }
                let raw = defaultFormat(value)
                return titles[raw] ?? raw
            },
            resetStoredValue: { $0.removeObject(forKey: key) },
            beforeReset: beforeReset,
            afterReset: afterReset
        )
    }

    static func jsonString(
        id: String,
        key: String,
        toolID: String? = nil,
        label: String,
        defaultValue: String
    ) -> Entry {
        Entry(
            id: id, key: key, toolID: toolID, label: label, defaultValue: defaultValue,
            readValue: { $0.string(forKey: key) ?? defaultValue },
            formatValue: { value in
                guard let string = value as? String,
                      let data = string.data(using: .utf8),
                      let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
                else { return String(describing: value) }
                return array.isEmpty ? "None" : "\(array.count) selected"
            },
            resetStoredValue: { $0.removeObject(forKey: key) }
        )
    }

    static func codableField<Root: Codable & Equatable, Value: Codable & Equatable>(
        id: String,
        key: String,
        toolID: String,
        label: String,
        defaultRoot: Root,
        readRoot: ((UserDefaults) -> Root)? = nil,
        aliases: [String] = [],
        get: @escaping (Root) -> Value,
        set: @escaping (inout Root, Value) -> Void,
        display: @escaping (Value) -> String,
        beforeReset: ((Value) async -> Void)? = nil
    ) -> Entry {
        let readRoot = readRoot ?? { defaults in
            defaults.data(forKey: key)
                .flatMap { try? JSONDecoder().decode(Root.self, from: $0) } ?? defaultRoot
        }
        let defaultValue = get(defaultRoot)
        return Entry(
            id: id, key: key, toolID: toolID, label: label,
            defaultValue: encode(defaultValue),
            readValue: { encode(get(readRoot($0))) },
            formatValue: { raw in
                guard let data = raw as? Data,
                      let value = try? JSONDecoder().decode(Value.self, from: data)
                else { return "Default" }
                return display(value)
            },
            resetStoredValue: { defaults in
                var root = readRoot(defaults)
                set(&root, defaultValue)
                if root == defaultRoot {
                    defaults.removeObject(forKey: key)
                } else if let data = try? JSONEncoder().encode(root) {
                    defaults.set(data, forKey: key)
                }
                aliases.forEach(defaults.removeObject(forKey:))
            },
            beforeReset: beforeReset.map { reset in { await reset(defaultValue) } }
        )
    }

    static func dataEntry<Value: Codable & Equatable>(
        id: String,
        key: String,
        toolID: String,
        label: String,
        defaultValue: Value,
        display: @escaping (Value) -> String
    ) -> Entry {
        Entry(
            id: id, key: key, toolID: toolID, label: label,
            defaultValue: encode(defaultValue),
            readValue: { defaults in
                let value = defaults.data(forKey: key)
                    .flatMap { try? JSONDecoder().decode(Value.self, from: $0) } ?? defaultValue
                return encode(value)
            },
            formatValue: { raw in
                guard let data = raw as? Data,
                      let value = try? JSONDecoder().decode(Value.self, from: data)
                else { return "Default" }
                return display(value)
            },
            resetStoredValue: { $0.removeObject(forKey: key) }
        )
    }

    static func rulerScalar<Value>(
        id: String,
        label: String,
        defaultValue: Value,
        formatter: @escaping @MainActor (Any) -> String = defaultFormat,
        apply: @escaping (Value) -> Void
    ) -> Entry {
        scalar(
            id: "ruler.\(id)", key: id, toolID: "ruler", label: label,
            defaultValue: defaultValue, formatter: formatter,
            beforeReset: { apply(defaultValue) }
        )
    }
}

// MARK: - Semantic values and formatting

private extension SettingsRegistry {
    indirect enum SemanticValue: Equatable {
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([SemanticValue])
        case object([String: SemanticValue])
        case data(Data)
        case null
    }

    static func semanticallyEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        semanticValue(lhs) == semanticValue(rhs)
    }

    static func semanticValue(_ value: Any) -> SemanticValue {
        if value is NSNull { return .null }
        if let data = value as? Data {
            if let object = try? JSONSerialization.jsonObject(with: data) {
                return semanticValue(object)
            }
            return .data(data)
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = trimmed.first, first == "[" || first == "{",
               let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return semanticValue(object)
            }
            return .string(string)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        }
        if let array = value as? [Any] { return .array(array.map(semanticValue)) }
        if let dictionary = value as? [String: Any] {
            return .object(dictionary.mapValues(semanticValue))
        }
        return .string(String(describing: value))
    }

    static func defaultFormat(_ value: Any) -> String {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return enabledFormat(number.boolValue) }
            return numberFormat(number)
        }
        if let boolean = value as? Bool { return enabledFormat(boolean) }
        if let array = value as? [String] { return array.isEmpty ? "None" : array.joined(separator: ", ") }
        return String(describing: value)
    }

    static func enabledFormat(_ value: Any) -> String {
        (value as? Bool) == true ? "Enabled" : "Disabled"
    }

    static func enabledFormat(_ value: Bool) -> String {
        value ? "Enabled" : "Disabled"
    }

    static func numberFormat(_ value: Any) -> String {
        guard let number = value as? NSNumber else { return String(describing: value) }
        return number.stringValue
    }

    static func numberFormat(_ value: Double) -> String {
        NSNumber(value: value).stringValue
    }

    static func lineListFormat(_ value: Any) -> String {
        guard let string = value as? String else { return String(describing: value) }
        let count = string.split(whereSeparator: \.isNewline).count
        return "\(count) pattern\(count == 1 ? "" : "s")"
    }

    static func percentFormat(_ value: Any) -> String {
        "\(numberFormat(value))%"
    }

    static func rulerLengthFormat(_ value: Any, fallback: CGFloat) -> String {
        guard let number = value as? NSNumber else { return defaultFormat(value) }
        if number.doubleValue > Prefs.unsetDefaultRulerLength {
            return "\(numberFormat(number)) pt"
        }
        return "Automatic (\(numberFormat(Double(fallback))) pt)"
    }

    static func menuItemFormat(_ item: SystemMonitorMenuItemConfiguration) -> String {
        guard item.enabled else { return "Off" }
        return "\(item.placement.title), \(item.style.title), \(item.interval.title)"
    }

    static func encode<Value: Encodable>(_ value: Value) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func shortcutData(_ shortcut: GlobalShortcut) -> Data {
        (try? JSONSerialization.data(withJSONObject: [
            "keyCode": shortcut.keyCode,
            "modifiers": shortcut.carbonModifiers,
            "label": shortcut.keyLabel,
        ], options: [.sortedKeys])) ?? Data()
    }

    static func shortcut(from data: Data) -> GlobalShortcut? {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keyCode = (value["keyCode"] as? NSNumber)?.uint32Value,
              let modifiers = (value["modifiers"] as? NSNumber)?.uint32Value,
              let label = value["label"] as? String
        else { return nil }
        return GlobalShortcut(keyCode: keyCode, carbonModifiers: modifiers, keyLabel: label)
    }

    static func storedShortcut(for action: GlobalShortcutAction, defaults: UserDefaults) -> GlobalShortcut {
        let prefix = "shortcut.\(action.defaultsName)"
        if let keyCode = defaults.object(forKey: "\(prefix).keyCode") as? NSNumber,
           let modifiers = defaults.object(forKey: "\(prefix).modifiers") as? NSNumber,
           let label = defaults.string(forKey: "\(prefix).keyLabel") {
            return GlobalShortcut(keyCode: keyCode.uint32Value, carbonModifiers: modifiers.uint32Value, keyLabel: label)
        }
        if let legacy = defaults.string(forKey: "\(prefix).key"),
           let key = GlobalShortcutKey(rawValue: legacy) {
            return GlobalShortcut(
                keyCode: key.keyCode,
                carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
                keyLabel: key.title
            )
        }
        return action.defaultShortcut
    }

    static func colorComponents(_ color: NSColor) -> [Int] {
        guard let color = color.usingColorSpace(.deviceRGB) else { return [] }
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    static func netToysPreferenceData(_ value: NetToysScannerPreferences) -> Data {
        (try? JSONSerialization.data(withJSONObject: [
            "timeoutMilliseconds": value.timeoutMilliseconds,
            "concurrency": value.concurrency,
            "launchDelayMilliseconds": value.launchDelayMilliseconds,
            "collectPingDetails": value.collectPingDetails,
            "pingProbeCount": value.pingProbeCount,
            "detectHTTPServer": value.detectHTTPServer,
            "detectHTTPProxy": value.detectHTTPProxy,
            "detectNetBIOS": value.detectNetBIOS,
            "customTextEnabled": value.customTextEnabled,
            "customTextPort": value.customTextPort,
            "customTextRequest": value.customTextRequest,
            "customTextPattern": value.customTextPattern,
        ], options: [.sortedKeys])) ?? Data()
    }

    static func openerData(_ openers: [NetToysOpener]) -> Data {
        let values = openers.map {
            ["name": $0.name, "urlTemplate": $0.urlTemplate, "requiredPort": $0.requiredPort] as [String: Any]
        }
        return (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])) ?? Data()
    }
}
