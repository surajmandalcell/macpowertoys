import Foundation

nonisolated struct ResourceCountSnapshot: Codable, Equatable {
    let timestampMilliseconds: Int64
    let sourceCommit: String
    let counts: [String: Int]
}

@MainActor
enum ResourceDiagnostics {
    static let maximumRecordCount = 256

    private static var fileURL: URL {
        AppDataLocation.directory
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("resource-counts.jsonl")
    }

    static func appendCurrentSnapshot() throws {
        try append(currentSnapshot(), to: fileURL, maxRecords: maximumRecordCount)
    }

    static func currentSnapshot(
        at date: Date = Date(),
        bundle: Bundle = .main
    ) -> ResourceCountSnapshot {
        let sourceCommit = (bundle.object(forInfoDictionaryKey: "MPTSourceCommit") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        let appDelegate = AppDelegate.current
        let awake = AwakeService.current
        let inputDevices = InputDevicesManager.current
        let projectManager = ProjectManager.current
        let cloudSync = RcloneJobManager.current
        let globalShortcuts = GlobalShortcutManager.current
        let menuBar = IndividualMenuBarController.current
        let settingsSync = SettingsSyncManager.current
        let systemMonitor = SystemMonitorService.current
        let windowState = WindowStateManager.current

        return ResourceCountSnapshot(
            timestampMilliseconds: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            sourceCommit: sourceCommit,
            counts: [
                "app.eventMonitors": appDelegate?.eventMonitorOwnerCount ?? 0,
                "app.observers": appDelegate?.observerOwnerCount ?? 0,
                "app.timers": appDelegate?.timerOwnerCount ?? 0,
                "awake.assertions": awake?.assertionOwnerCount ?? 0,
                "awake.timers": awake?.timerOwnerCount ?? 0,
                "cloudSync.daemons": cloudSync?.daemonOwnerCount ?? 0,
                "cloudSync.fileWatchers": cloudSync?.fileWatcherOwnerCount ?? 0,
                "cloudSync.longLivedTasks": cloudSync?.longLivedTaskOwnerCount ?? 0,
                "cloudSync.observers": cloudSync?.volumeObserverOwnerCount ?? 0,
                "cloudSync.pollTasks": cloudSync?.pollingOwnerCount ?? 0,
                "cloudSync.windowOwners": cloudSync?.visibleWindowOwnerCount ?? 0,
                "globalShortcuts.eventHandlers": globalShortcuts?.eventHandlerOwnerCount ?? 0,
                "globalShortcuts.eventTaps": globalShortcuts?.eventTapOwnerCount ?? 0,
                "globalShortcuts.hotKeys": globalShortcuts?.hotKeyOwnerCount ?? 0,
                "inputDevices.eventTaps": inputDevices?.eventTapOwnerCount ?? 0,
                "menuBar.observers": menuBar?.observerOwnerCount ?? 0,
                "menuBar.statusItems": menuBar?.statusItemOwnerCount ?? 0,
                "projectHistory.fileWatchers": projectManager?.fileWatcherOwnerCount ?? 0,
                "settingsSync.observers": settingsSync?.observerOwnerCount ?? 0,
                "systemMonitor.observers": systemMonitor?.wakeObserverOwnerCount ?? 0,
                "systemMonitor.statusItems": systemMonitor?.statusItemOwnerCount ?? 0,
                "systemMonitor.timers": systemMonitor?.timerOwnerCount ?? 0,
                "windowState.observers": windowState?.observerOwnerCount ?? 0,
            ]
        )
    }

    static func append(
        _ snapshot: ResourceCountSnapshot,
        to fileURL: URL,
        maxRecords: Int
    ) throws {
        let limit = max(1, maxRecords)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var records = (try? String(contentsOf: fileURL, encoding: .utf8))?
            .split(separator: "\n")
            .map(String.init) ?? []
        records.append(String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self))
        let bounded = records.suffix(limit).joined(separator: "\n") + "\n"
        try Data(bounded.utf8).write(to: fileURL, options: .atomic)
    }
}
