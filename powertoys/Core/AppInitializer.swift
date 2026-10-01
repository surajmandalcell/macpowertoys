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
        if !AppRuntime.isRunningTests {
            await Task.detached(priority: .userInitiated) {
                AppIdentity.migrateLegacyData()
                AppDataLocation.migrateLegacyStoreIfNeeded()
            }.value
        }
        guard !isShuttingDown else { return }
        LogManager.shared.info("Startup migrations completed in \(started.duration(to: .now))", source: "AppInitializer")
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

        restorationTask = Task {
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
        }
        await openStorage()
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

    func shutdown() async {
        LogManager.shared.info("App shutting down...", source: "AppInitializer")
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
            let started = ContinuousClock.now
            do {
                container = try await Task.detached(priority: .userInitiated, operation: create).value
                NSLog("Startup ModelContainer created in %@", String(describing: started.duration(to: .now)))
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
        try createContainer(at: AppRuntime.isRunningTests ? nil : AppDataLocation.storeURL)
    }

    nonisolated static func createContainer(at url: URL?) throws -> ModelContainer {
        let schema = Schema([LogEntry.self, TransferRecord.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
