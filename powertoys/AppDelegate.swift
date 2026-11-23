//
//  AppDelegate.swift
//  powertoys
//

import Foundation
import AppKit
import CoreServices
import OnePlusUI
import Darwin
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    static let openMainWindowSymbol = "arrow.up.forward.square"
    static weak var current: AppDelegate?
    static let statusItemEventMask: NSEvent.EventTypeMask = [.rightMouseDown]

    private var statusItemClickMonitor: Any?
    private var statusItemTimingMonitor: Any?
    private var currentDockIconAssetName = "AppIcon"
    private var currentDockIconAppearanceName: NSAppearance.Name?
    private var dockIconAppearanceObservation: NSKeyValueObservation?
    private var didFinishLaunching = false
    private var didStartApplication = false
    private var applicationStartup: (@MainActor () async -> Void)?
    private var ownsInstance = true
    private var quitCommandCoordinator = QuitCommandCoordinator()

    var timerOwnerCount: Int { timer == nil ? 0 : 1 }
    var eventMonitorOwnerCount: Int {
        (statusItemClickMonitor == nil ? 0 : 1) + OnePlusFocusPolicy.shared.eventMonitorOwnerCount
            + (statusItemTimingMonitor == nil ? 0 : 1)
            + (freeRulerKeyMonitor == nil ? 0 : 1)
    }
    var observerOwnerCount: Int {
        freeRulerObservers.count + (dockIconAppearanceObservation == nil ? 0 : 1)
            + OnePlusFocusPolicy.shared.observerOwnerCount
    }

    static func shouldOpenMainWindowAfterLaunch(userInfo: [AnyHashable: Any]?,
                                              isRunningUnitTests: Bool = AppRuntime.isRunningUnitTests) -> Bool {
        !isRunningUnitTests && userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true
    }

    private static let nativeSceneToolIDs: Set<String> = [
        "main", "rclone", "logs", "color-picker",
        "text-extractor", "input-devices", "mac-tweaks",
    ]

    @MainActor
    func configureApplication(startup: @escaping @MainActor () async -> Void) {
        applicationStartup = startup
        startApplicationIfReady()
    }

    @MainActor
    private func startApplicationIfReady() {
        guard didFinishLaunching, !didStartApplication, let applicationStartup else { return }
        didStartApplication = true
        Task { await applicationStartup() }
    }

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
                settingsController.show(attachedTo: controller, sender: self, activateApp: NSApp.isActive)
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
        "rclone": "CloudSyncLogo",
        "logs": "LogsLogo",
        "ruler-window": "RulerLogo",
        "ruler-settings-window": "RulerLogo",
        "preferences-window": "RulerLogo",
        "ruler-color-panel": "RulerLogo",
        "color-picker": "ColorPickerLogo",
        "text-extractor": "TextExtractorLogo",
        "input-devices": "InputDevicesLogoA",
        "mac-tweaks": "MacTweaksLogo"
    ]

    func applicationWillFinishLaunching(_ notification: Notification) {
        if AppRuntime.isRunningUnitTests {
            NSApp.setActivationPolicy(.prohibited)
        }
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
        ActivationDiagnostics.install()
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
            if IndividualMenuBarController.shared.handleSecondaryClick(on: statusButton) { return nil }

            let menu = PortmanMenuController.shared.owns(button: statusButton)
                ? PortmanMenuController.shared.contextMenu()
                : self.statusItemContextMenu()
            NSMenu.popUpContextMenu(menu, with: event, for: statusButton)
            return nil
        }
        OnePlusFocusPolicy.shared.install()
        statusItemTimingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            let hit = event.window?.contentView?.hitTest(event.locationInWindow)
            if let button = Self.statusItemButton(containing: hit) {
                let identifier = button.identifier?.rawValue ?? ""
                let panel = identifier.hasPrefix("individual-menu.")
                    ? String(identifier.dropFirst("individual-menu.".count))
                    : DiagnosticsPanel.allCases.first { $0.matchingButton(in: [button]) != nil }?.rawValue
                if let panel {
                    OnePlusPanelTimings.shared.begin(panel: panel, input: "mouseDown", started: event.timestamp)
                }
            }
            return event
        }

        didFinishLaunching = true
        startApplicationIfReady()
        if !AppRuntime.isUITesting && !CommandLine.arguments.contains("--open") {
            beginLaunchMainWindow(userInfo: notification.userInfo, isActive: NSApp.isActive)
        }
    }

    static let launchActivationWindow: TimeInterval = 3
    var openMainWindowAfterLaunch: @MainActor () -> Void = { ToolActionRouter.shared.open(toolID: "main") }
    private(set) var opensMainWindowOnLaunchActivation = false

    // `open -g` and login items are default launches too; only a launch macOS activates may open Main.
    @MainActor
    func beginLaunchMainWindow(userInfo: [AnyHashable: Any]?, isActive: Bool,
                               isRunningUnitTests: Bool = AppRuntime.isRunningUnitTests) {
        guard Self.shouldOpenMainWindowAfterLaunch(userInfo: userInfo, isRunningUnitTests: isRunningUnitTests) else { return }
        guard !isActive else { openMainWindowAfterLaunch(); return }
        openMainWindowOnNextActivation()
    }

    // `open -g -a` on a running app sends a reopen without activation; only a reopen macOS activates (Dock click) opens Main.
    @MainActor
    func handleReopen(hasVisibleWindows: Bool, isActive: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        guard isActive else { openMainWindowOnNextActivation(); return false }
        openMainWindowAfterLaunch()
        return true
    }

    @MainActor
    private func openMainWindowOnNextActivation() {
        opensMainWindowOnLaunchActivation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchActivationWindow) { [weak self] in
            self?.endLaunchActivationWindow()
        }
    }

    @MainActor
    func endLaunchActivationWindow() {
        opensMainWindowOnLaunchActivation = false
    }

    @MainActor
    func openMainWindowIfLaunchActivated() {
        guard opensMainWindowOnLaunchActivation else { return }
        opensMainWindowOnLaunchActivation = false
        openMainWindowAfterLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItemTimingMonitor { NSEvent.removeMonitor(statusItemTimingMonitor) }
        statusItemTimingMonitor = nil
        OnePlusFocusPolicy.shared.stop()
        PortmanService.shared.stopAll()
        PortmanServerMonitor.shared.stop()
    }

    @MainActor
    static func dismissKeyboardFocus(in window: NSWindow, at point: NSPoint) {
        OnePlusFocusPolicy.dismissPointerFocus(in: window, at: point)
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
            title: "About MacPowerToys",
            symbol: "info.circle",
            action: #selector(openAboutFromStatusItem)
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
        ToolActionRouter.shared.open(toolID: "main")
    }

    @MainActor
    @objc func openAboutFromStatusItem() {
        MacPowerToysAbout.show()
    }

    @MainActor
    @objc func quitFromStatusItem() {
        NSApp.terminate(nil)
    }

    @MainActor
    @objc func handleQuitCommand() {
        let activeWindow = NSApp.keyWindow ?? NSApp.mainWindow
        switch quitCommandCoordinator.action(
            toolID: Self.quitCommandToolID(for: activeWindow),
            now: ProcessInfo.processInfo.systemUptime
        ) {
        case let .closeToolWindows(toolID):
            if toolID == "ruler" {
                closeFreeRulerToolWindows()
                return
            }
            Self.closeToolWindows(
                toolID,
                activeWindow: activeWindow,
                windows: NSApp.windows.filter(\.isVisible)
            )
        case .awaitMainWindowRepeat:
            hotkeyBezel.show("Press ⌘Q again to quit", on: activeWindow?.screen)
        case .terminate:
            NSApp.terminate(nil)
        }
    }

    static func quitCommandToolID(for window: NSWindow?) -> String? {
        var candidate = window
        while let current = candidate {
            if let toolID = quitCommandToolID(for: current.identifier?.rawValue) {
                return toolID
            }
            candidate = current.sheetParent
        }
        return nil
    }

    static func quitCommandToolID(for identifier: String?) -> String? {
        if isFreeRulerWindowIdentifier(identifier) { return "ruler" }
        return nativeSceneToolIDs
            .filter { $0 != "main" }
            .first { ToolActionRouter.windowIdentifier(identifier, matches: $0) }
    }

    static func window(_ window: NSWindow, belongsTo toolID: String) -> Bool {
        if toolID == "ruler" {
            return isFreeRulerWindowIdentifier(window.identifier?.rawValue)
        }
        return ToolActionRouter.windowIdentifier(window.identifier?.rawValue, matches: toolID)
    }

    static func endAttachedSheet(for window: NSWindow?) {
        guard let sheet = window?.sheetParent == nil ? window?.attachedSheet : window,
              let parent = sheet.sheetParent else { return }
        parent.endSheet(sheet)
    }

    static func closeToolWindows(
        _ toolID: String,
        activeWindow: NSWindow?,
        windows: [NSWindow]
    ) {
        endAttachedSheet(for: activeWindow)
        windows
            .filter { window($0, belongsTo: toolID) }
            .forEach { $0.performClose(nil) }
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
        guard !AppRuntime.isRunningUnitTests else { return false }
        return handleReopen(hasVisibleWindows: flag, isActive: NSApp.isActive)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        openMainWindowIfLaunchActivated()
        updateFreeRulerForApplicationActivation(true)
        if let message = pendingQuitRefusal {
            pendingQuitRefusal = nil
            showQuitRefusedAlert(message)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        updateFreeRulerForApplicationActivation(false)
    }

    private var terminationTask: Task<Void, Never>?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ownsInstance else { return .terminateNow }
        // The test host shares the bundle ID, so a quit meant for the installed app must not end a test run.
        guard !AppRuntime.isRunningUnitTests else { return .terminateCancel }
        guard terminationTask == nil else { return .terminateLater }
        let systemQuit = Self.isSystemQuit(NSAppleEventManager.shared().currentAppleEvent)
        terminationTask = Task { @MainActor in
            do {
                try await AppInitializer.shared.shutdown(systemQuit: systemQuit)
                prepareFreeRulerForTermination()
                AwakeService.shared.shutdown()
                GlobalShortcutManager.shared.shutdown()
                terminationTask = nil
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                terminationTask = nil
                sender.reply(toApplicationShouldTerminate: false)
                // A modal behind a game or another app is never seen; notify without taking focus instead.
                let decision: QuitDecision = (error as? QuitRefusal)?.decision ?? (sender.isActive ? .ask : .cancel)
                guard decision == .ask else {
                    await reportBackgroundQuitRefusal(error.localizedDescription)
                    return
                }
                showQuitRefusedAlert(error.localizedDescription)
            }
        }
        return .terminateLater
    }

    private var pendingQuitRefusal: String?

    private func reportBackgroundQuitRefusal(_ message: String) async {
        let center = UNUserNotificationCenter.current()
        guard await PermissionCenter.allowNotifications() else {
            pendingQuitRefusal = message
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "MacPowerToys could not quit"
        content.body = message
        try? await center.add(UNNotificationRequest(identifier: "app.quit-refused", content: content, trigger: nil))
    }

    private func showQuitRefusedAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MacPowerToys could not quit"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Keep Open")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { NSApp.terminate(nil) }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow,
           window.sheetParent == nil, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private static func isSystemQuit(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let reason = event?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else { return false }
        return [OSType(kAELogOut), OSType(kAEReallyLogOut), OSType(kAEShowRestartDialog),
                OSType(kAEShowShutdownDialog), OSType(kAERestart), OSType(kAEShutDown)].contains(reason)
    }
}

struct QuitCommandCoordinator {
    enum Action: Equatable {
        case closeToolWindows(String)
        case awaitMainWindowRepeat
        case terminate
    }

    static let repeatInterval: TimeInterval = 2
    private var mainWindowDeadline: TimeInterval?

    mutating func action(
        toolID: String?,
        now: TimeInterval
    ) -> Action {
        if let toolID {
            mainWindowDeadline = nil
            return .closeToolWindows(toolID)
        }
        if let mainWindowDeadline, now <= mainWindowDeadline {
            self.mainWindowDeadline = nil
            return .terminate
        }
        mainWindowDeadline = now + Self.repeatInterval
        return .awaitMainWindowRepeat
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
        // Only an earlier copy wins, so two copies that start together never both quit.
        let current = NSRunningApplication.current
        let currentOrder = (current.launchDate ?? .distantPast, current.processIdentifier)
        if runningApps.contains(where: { $0 != current && ($0.launchDate ?? .distantPast, $0.processIdentifier) < currentOrder }) {
            ownsInstance = false
            return
        }

        let lock = ProcessInstanceLock(name: AppIdentity.bundleIdentifier)
        if lock.acquire() {
            instanceLock = lock
            ownsInstance = true
        } else {
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
