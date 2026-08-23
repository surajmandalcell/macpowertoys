//
//  AppDelegate.swift
//  powertoys
//

import Foundation
import AppKit
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    static let openMainWindowSymbol = "arrow.up.forward.square"
    static weak var current: AppDelegate?
    static let statusItemEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown
    ]

    private var statusItemClickMonitor: Any?
    private var currentDockIconAssetName = "AppIcon"
    private var currentDockIconAppearanceName: NSAppearance.Name?
    private var dockIconAppearanceObservation: NSKeyValueObservation?
    private let statusItemClickCoordinator = StatusItemClickCoordinator(
        delay: NSEvent.doubleClickInterval
    )
    private var ownsInstance = true

    var freeRulerDidInitialize = false
    var freeRulerRoutingDidInstall = false
    var freeRulerObservers: [NSKeyValueObservation] = []
    var freeRulerKeyMonitor: Any?
    lazy var rulerManager: RulerManager = {
        let manager = RulerManager()
        manager.onActiveControllerChanged = { [weak self] controller in
            guard let self else { return }

            updateDisplay()
            guard let settingsController = rulerSettingsController,
                  settingsController.window?.isVisible == true else { return }

            if let controller {
                settingsController.show(attachedTo: controller, sender: self)
            } else {
                settingsController.close()
            }
        }
        manager.onStateChanged = { [weak self] manager in
            guard let self else { return }

            updateDisplay()
            saveRulerSetState()
            let activeController = manager.activeController
            guard let settingsController = rulerSettingsController,
                  settingsController.currentRulerController === activeController,
                  settingsController.window?.isVisible == true else { return }

            settingsController.updateView()
        }
        return manager
    }()
    var timer: Timer?
    var timerInterval: TimeInterval?
    let mouseTickDrawingSuppressedOwners = NSHashTable<AnyObject>.weakObjects()
    let foregroundTimerInterval: TimeInterval = 1 / 60
    let backgroundTimerInterval: TimeInterval = 1 / 30
    let rulerCursorController = RulerCursorController()
    lazy var mouseTickTimerPolicy = MouseTickTimerPolicy(
        foregroundInterval: foregroundTimerInterval,
        backgroundInterval: backgroundTimerInterval
    )
    var preferencesController: PreferencesController?
    var rulerSettingsController: RulerSettingsController?
    let hotkeyBezel = HotkeyBezel()

    override init() {
        super.init()
        Self.current = self
    }

    private static let dockIconAssets = [
        "main": "AppIcon",
        "cc-history": "ClaudeHistoryLogo",
        "rclone": "CloudSyncLogo",
        "logs": "LogsLogo",
        "ruler-window": "RulerLogo",
        "ruler-settings-window": "RulerLogo",
        "preferences-window": "RulerLogo",
        "ruler-color-panel": "RulerLogo",
        "awake": "AwakeLogo",
        "color-picker": "ColorPickerLogo",
        "text-extractor": "TextExtractorLogo"
    ]

    func applicationWillFinishLaunching(_ notification: Notification) {
        if !AppRuntime.isUITesting {
            UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        }
        ownsInstance = AppInstanceCoordinator.shared.ownsInstance
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ownsInstance {
            NSApp.terminate(nil)
            return
        }

        installFreeRulerRouting()
        dockIconAppearanceObservation = NSApp.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDockIcon(for: NSApp.effectiveAppearance)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        statusItemClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: Self.statusItemEventMask
        ) { event in
            let hitView = event.window?.contentView?.hitTest(event.locationInWindow)
            guard let statusButton = Self.statusItemButton(containing: hitView) else {
                return event
            }

            if event.type == .rightMouseDown {
                NSMenu.popUpContextMenu(
                    self.statusItemContextMenu(),
                    with: event,
                    for: statusButton
                )
                return nil
            }

            self.statusItemClickCoordinator.handle(
                clickCount: event.clickCount,
                singleClick: { [weak statusButton] in
                    statusButton?.performClick(nil)
                },
                doubleClick: self.openMainWindowFromStatusItem
            )
            return nil
        }
    }

    @MainActor
    func statusItemContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(statusItemMenuItem(
            title: "Open MacPowerToys",
            symbol: Self.openMainWindowSymbol,
            action: #selector(openMainWindowFromStatusItem)
        ))
        menu.addItem(statusItemMenuItem(
            title: "Quit",
            symbol: "power",
            action: #selector(quitFromStatusItem)
        ))
        return menu
    }

    @MainActor
    private func statusItemMenuItem(
        title: String,
        symbol: String,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )
        return item
    }

    @MainActor
    @objc func openMainWindowFromStatusItem() {
        DeepLinkHandler.shared.handle(url: URL(string: "macpowertoys://open/main")!)
    }

    @MainActor
    @objc func quitFromStatusItem() {
        NSApp.terminate(nil)
    }

    private static func statusItemButton(containing view: NSView?) -> NSStatusBarButton? {
        var candidate = view
        while let current = candidate {
            if let button = current as? NSStatusBarButton { return button }
            candidate = current.superview
        }
        return nil
    }

    @MainActor
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        updateDockIcon(for: window.identifier?.rawValue)
        updateFreeRulerMenuContext(for: window)
    }

    static func dockIconAsset(for windowIdentifier: String?) -> String {
        guard let windowIdentifier else { return "AppIcon" }
        return dockIconAssets.first { windowIdentifier.hasPrefix($0.key) }?.value ?? "AppIcon"
    }

    func dockIconAssetToApply(
        for windowIdentifier: String?,
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> String? {
        let nextAssetName = Self.dockIconAsset(for: windowIdentifier)
        return dockIconAssetToApply(named: nextAssetName, appearance: appearance)
    }

    private func dockIconAssetToApply(
        named nextAssetName: String,
        appearance: NSAppearance
    ) -> String? {
        let nextAppearanceName = nextAssetName == "AppIcon"
            ? nil
            : DockIconImage.resolvedAppearanceName(for: appearance)
        guard nextAssetName != currentDockIconAssetName
            || nextAppearanceName != currentDockIconAppearanceName else { return nil }

        currentDockIconAssetName = nextAssetName
        currentDockIconAppearanceName = nextAppearanceName
        return nextAssetName
    }

    private func updateDockIcon(for windowIdentifier: String?) {
        let appearance = NSApp.effectiveAppearance
        guard let assetName = dockIconAssetToApply(
            for: windowIdentifier,
            appearance: appearance
        ) else { return }

        NSApp.applicationIconImage = DockIconImage.image(
            named: assetName,
            appearance: appearance
        )
    }

    private func refreshDockIcon(for appearance: NSAppearance) {
        guard let assetName = dockIconAssetToApply(
            named: currentDockIconAssetName,
            appearance: appearance
        ) else { return }

        NSApp.applicationIconImage = DockIconImage.image(
            named: assetName,
            appearance: appearance
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            MacPowerToysApp.handleIncomingURL(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DeepLinkHandler.shared.handle(url: URL(string: "macpowertoys://open/main")!)
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updateFreeRulerForApplicationActivation(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        updateFreeRulerForApplicationActivation(false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareFreeRulerForTermination()
        AwakeService.shared.shutdown()
        GlobalShortcutManager.shared.shutdown()
        Task { @MainActor in
            await RcloneJobManager.shared.shutdown()
            await LogManager.shared.flushPending()
            await AppInitializer.shared.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor
final class StatusItemClickCoordinator {
    private let delay: TimeInterval
    private var pendingSingleClick: Task<Void, Never>?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func handle(
        clickCount: Int,
        singleClick: @escaping @MainActor () -> Void,
        doubleClick: @escaping @MainActor () -> Void
    ) {
        if clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            doubleClick()
            return
        }

        guard clickCount == 1 else { return }
        pendingSingleClick?.cancel()
        pendingSingleClick = Task { @MainActor [delay] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            singleClick()
        }
    }
}

@MainActor
final class AppInstanceCoordinator {
    static let shared = AppInstanceCoordinator()

    let ownsInstance: Bool
    private var instanceLock: ProcessInstanceLock?

    private init() {
        if AppRuntime.isRunningTests {
            ownsInstance = true
            return
        }

        let supportedBundleIDs = [AppIdentity.bundleIdentifier, AppIdentity.legacyBundleIdentifier]
        let runningApps = supportedBundleIDs.flatMap(NSRunningApplication.runningApplications(withBundleIdentifier:))
        if let existingApp = runningApps.first(where: { $0 != NSRunningApplication.current }) {
            existingApp.activate(options: [.activateAllWindows])
            ownsInstance = false
            return
        }

        let lock = ProcessInstanceLock(name: AppIdentity.bundleIdentifier)
        if lock.acquire() {
            instanceLock = lock
            ownsInstance = true
        } else {
            let candidates = supportedBundleIDs.flatMap(NSRunningApplication.runningApplications(withBundleIdentifier:))
            candidates.first(where: { $0 != NSRunningApplication.current })?.activate(options: [.activateAllWindows])
            ownsInstance = false
        }
    }
}

final class ProcessInstanceLock {
    private let path: String
    private var descriptor: Int32 = -1

    init(name: String) {
        path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name).instance.lock")
            .path
    }

    func acquire() -> Bool {
        guard descriptor == -1 else { return true }
        let fd = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        guard Darwin.lockf(fd, F_TLOCK, 0) == 0 else {
            Darwin.close(fd)
            return false
        }
        descriptor = fd
        return true
    }

    deinit {
        guard descriptor >= 0 else { return }
        _ = Darwin.lockf(descriptor, F_ULOCK, 0)
        Darwin.close(descriptor)
    }
}
