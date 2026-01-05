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

        LogManager.shared.info("App initializing...", source: "AppInitializer")

        LogManager.shared.modelContext = modelContext
        ConversationCacheService.shared.setModelContext(modelContext)

        await LogManager.shared.loadPersistedLogs()

        Task.detached(priority: .background) {
            await LogManager.shared.pruneOldLogs()
            await MainActor.run {
                ConversationCacheService.shared.pruneStaleCache()
            }
        }

        _ = SettingsManager.shared

        applyStoredTheme()

        LogManager.shared.info("App initialization complete", source: "AppInitializer")

        state = .ready
    }

    func shutdown() async {
        LogManager.shared.info("App shutting down...", source: "AppInitializer")
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
