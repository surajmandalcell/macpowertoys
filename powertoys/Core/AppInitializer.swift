//
//  AppInitializer.swift
//  powertoys
//

import Foundation
import SwiftData
import AppKit

@Observable
@MainActor
final class AppInitializer {
    enum State: Equatable {
        case idle
        case initializing
        case ready
        case failed(String)
    }

    static let shared = AppInitializer()

    private(set) var state: State = .idle

    private init() {}

    func initialize(modelContext: ModelContext) async {
        guard state == .idle else { return }

        state = .initializing

        LogManager.shared.configurePersistence(container: modelContext.container)
        ConversationCacheService.shared.setModelContext(modelContext)

        LogManager.shared.info("App initializing...", source: "AppInitializer")

        await LogManager.shared.loadPersistedLogs()
        await LocalChangeHistory.shared.restore()

        Task.detached(priority: .background) {
            await LogManager.shared.pruneOldLogs()
            await MainActor.run {
                ConversationCacheService.shared.pruneStaleCache()
            }
        }

        _ = SettingsManager.shared
        await MarketplaceManager.shared.restore()
        SettingsSyncManager.shared.startIfEnabled()
        if SettingsManager.shared.isToolEnabled("awake") { _ = AwakeService.shared }
        _ = ColorPickerService.shared
        _ = TextExtractorService.shared
        _ = GlobalShortcutManager.shared
        IndividualMenuBarController.shared.start()
        if SettingsManager.shared.isToolEnabled("input-devices") {
            InputDevicesManager.shared.refresh()
        }
        SystemMonitorService.shared.startFromStoredSettings()

        applyStoredTheme()

        let hasContinuousJobs = await RcloneJobManager.hasPersistedContinuousJobs()
        let shouldStartRclone = UserDefaults.standard.bool(forKey: "tool.rclone.startAtLaunch") || hasContinuousJobs
        if shouldStartRclone && SettingsManager.shared.isToolEnabled("rclone") {
            Task { await RcloneJobManager.shared.start() }
        }

        LogManager.shared.info("App initialization complete", source: "AppInitializer")

        state = .ready
    }

    func shutdown() async {
        LogManager.shared.info("App shutting down...", source: "AppInitializer")
        IndividualMenuBarController.shared.stop()
    }

    private func applyStoredTheme() {
        let storedTheme = UserDefaults.standard.string(forKey: "appTheme") ?? "Automatic"
        switch storedTheme {
        case "Light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
        LogManager.shared.debug("Applied theme: \(storedTheme)", source: "AppInitializer")
    }
}
