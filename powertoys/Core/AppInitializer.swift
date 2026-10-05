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
    let modelStore = AppModelStore()
    @ObservationIgnored private var restorationTask: Task<Void, Never>?
    private var isShuttingDown = false
    private var didConfigureStorage = false
    private var restorationFinished = false
    @ObservationIgnored private var initializationWaiter: CheckedContinuation<Void, Never>?
    private let fanShutdown = AppShutdownStage()
    private let colorShutdown = AppShutdownStage()
    private let logShutdown = AppShutdownStage()
    private let cloudShutdown = AppShutdownStage()
    private(set) var formattingRevision = 0
    @ObservationIgnored private var formattingObservers: [NSObjectProtocol] = []

    private init() {
        formattingObservers = [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.formattingRevision &+= 1
                    SystemMonitorService.current?.refreshMenuFormatting()
                }
            }
        }
    }

    func initialize(routesReady: () -> Void) async {
        guard state == .idle else { return }

        state = .initializing

        LogManager.shared.info("App initializing...", source: "AppInitializer")

        let started = ContinuousClock.now
        if isShuttingDown {
            await withCheckedContinuation { initializationWaiter = $0 }
        }
        _ = SettingsManager.shared
        if SettingsManager.shared.isToolEnabled("awake") { _ = AwakeService.shared }
        _ = ColorPickerService.shared
        let textExtractor = TextExtractorService.shared
        if SettingsManager.shared.isToolEnabled("text-extractor") { textExtractor.prewarm() }
        _ = GlobalShortcutManager.shared
        IndividualMenuBarController.shared.start()
        PortmanMenuController.shared.start()
        if SettingsManager.shared.isToolEnabled("input-devices") {
            InputDevicesManager.shared.refresh()
        }
        SystemMonitorService.shared.startFromStoredSettings()
        if SettingsManager.shared.isToolEnabled("mac-tweaks") {
            MicLockService.shared.startIfNeeded()
        }

        applyStoredTheme()

        state = .ready
        routesReady()
        LogManager.shared.info("Built-in routes and status items ready in \(started.duration(to: .now))", source: "AppInitializer")

        restorationTask = Task { await restoreServices() }
        await openStorage()
    }

    private func restoreServices() async {
        guard !restorationFinished, !isShuttingDown, !Task.isCancelled else { return }
        await MarketplaceManager.shared.restore()
        guard !Task.isCancelled else { return }
        SettingsSyncManager.shared.startIfEnabled()
        await SettingsManager.shared.reconcileNetToysLifecycle()
        guard !Task.isCancelled else { return }
        await LocalChangeHistory.shared.restore()
        guard !Task.isCancelled else { return }
        let hasContinuousJobs = await RcloneJobManager.hasPersistedContinuousJobs()
        guard !Task.isCancelled else { return }
        let shouldStartRclone = UserDefaults.standard.bool(forKey: "tool.rclone.startAtLaunch") || hasContinuousJobs
        if shouldStartRclone && SettingsManager.shared.isToolEnabled("rclone") {
            await openStorage()
            guard !Task.isCancelled, !isShuttingDown, modelStore.container != nil else { return }
            await RcloneJobManager.shared.start()
        }
        if !Task.isCancelled { restorationFinished = true }
    }

    func openStorage() async {
        guard !isShuttingDown else { return }
        await modelStore.open()
        guard !isShuttingDown, !didConfigureStorage, let container = modelStore.container else { return }
        didConfigureStorage = true
        LogManager.shared.configurePersistence(container: container)
        RcloneJobManager.shared.modelContext = container.mainContext
        await LogManager.shared.loadPersistedLogs()
        await LogManager.shared.pruneOldLogs()
    }

    func shutdown() async throws {
        guard !isShuttingDown else { throw CocoaError(.userCancelled) }
        isShuttingDown = true
        let restoration = restorationTask
        restoration?.cancel()
        LogManager.shared.info("App shutting down...", source: "AppInitializer")
        do {
            try await fanShutdown.run(name: "Fan Auto restoration", timeout: .seconds(20)) {
                try await FanControlService.current?.restoreAutomaticOnExit()
            }
            try await colorShutdown.run(name: "Saving Color Picker history and projects", timeout: .seconds(10)) {
                try await ColorPickerService.shared.flushPersistence()
            }
            try await logShutdown.run(name: "Saving logs", timeout: .seconds(10)) {
                await LogManager.shared.flushPending()
                if let failure = LogManager.shared.persistenceError {
                    throw NSError(domain: "LogManager", code: 1, userInfo: [NSLocalizedDescriptionKey: failure])
                }
            }
            try await cloudShutdown.run(name: "Saving RSync UI and stopping its engine", timeout: .seconds(30)) {
                try await RcloneJobManager.shared.shutdownForTermination()
            }
        } catch {
            isShuttingDown = false
            initializationWaiter?.resume()
            initializationWaiter = nil
            restorationTask = Task {
                await restoration?.value
                guard state == .ready, !isShuttingDown else { return }
                await openStorage()
                await restoreServices()
            }
            throw error
        }
        IndividualMenuBarController.shared.stop()
        PortmanMenuController.shared.stop()
        MicLockService.shared.stop()
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

@MainActor
final class AppShutdownStage {
    private var operationTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var waiter: CheckedContinuation<Void, any Error>?

    func run(name: String, timeout: Duration, operation: @escaping @MainActor () async throws -> Void) async throws {
        guard waiter == nil else { throw CocoaError(.userCancelled) }
        try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
            if operationTask == nil {
                operationTask = Task {
                    do {
                        try await operation()
                        finish(.success(()))
                    } catch {
                        finish(.failure(NSError(domain: "AppShutdown", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "\(name): \(error.localizedDescription)",
                            NSUnderlyingErrorKey: error,
                        ])))
                    }
                    operationTask = nil
                }
            }
            deadlineTask = Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                operationTask?.cancel()
                finish(.failure(NSError(domain: "AppShutdown", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "\(name) did not finish before its shutdown deadline.",
                ])))
            }
        }
    }

    private func finish(_ result: Result<Void, any Error>) {
        deadlineTask?.cancel()
        deadlineTask = nil
        let continuation = waiter
        waiter = nil
        continuation?.resume(with: result)
    }
}

@Observable
@MainActor
final class AppModelStore {
    private(set) var container: ModelContainer?
    private(set) var errorMessage: String?
    private(set) var isOpening = false
    var showsRecovery = false
    @ObservationIgnored private var openingTask: Task<Void, Never>?

    func open(create: @escaping @Sendable () throws -> ModelContainer = AppModelStore.createContainer) async {
        if let openingTask {
            await openingTask.value
            return
        }
        guard container == nil else { return }
        isOpening = true
        errorMessage = nil
        showsRecovery = false
        let task = Task {
            defer { isOpening = false; openingTask = nil }
            do {
                container = try await Task.detached(priority: .userInitiated, operation: create).value
            } catch {
                let failure = error as NSError
                errorMessage = "\(failure.localizedDescription)\n\(failure.domain) (\(failure.code))"
                showsRecovery = true
            }
        }
        openingTask = task
        await task.value
    }

    nonisolated static func createContainer() throws -> ModelContainer {
        if !AppRuntime.isRunningTests {
            let started = ContinuousClock.now
            AppDataLocation.migrateLegacyStoreIfNeeded()
            NSLog("Startup store migration completed in %@", String(describing: started.duration(to: .now)))
        }
        return try createContainer(at: AppRuntime.isRunningTests ? nil : AppDataLocation.storeURL)
    }

    nonisolated static func createContainer(at url: URL?) throws -> ModelContainer {
        let started = ContinuousClock.now
        let schema = Schema([LogEntry.self, TransferRecord.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        NSLog("Startup ModelContainer created in %@", String(describing: started.duration(to: .now)))
        return container
    }
}
