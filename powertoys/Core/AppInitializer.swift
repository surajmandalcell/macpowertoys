//
//  AppInitializer.swift
//  powertoys
//

import Foundation
import SwiftData

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

        await LogManager.shared.loadPersistedLogs()

        Task.detached(priority: .background) {
            await LogManager.shared.pruneOldLogs()
        }

        _ = SettingsManager.shared

        LogManager.shared.info("App initialization complete", source: "AppInitializer")

        state = .ready
    }

    func shutdown() async {
        LogManager.shared.info("App shutting down...", source: "AppInitializer")
    }
}
