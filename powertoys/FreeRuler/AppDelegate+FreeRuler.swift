import AppKit
import Carbon.HIToolbox

private enum HotkeyBezelLocalizationKey: String {
    case rulerFloated = "HotkeyBezel.RulerFloated"
    case rulerUnfloated = "HotkeyBezel.RulerUnfloated"
    case rulersGrouped = "HotkeyBezel.RulersGrouped"
    case rulersUngrouped = "HotkeyBezel.RulersUngrouped"
    case shadowEnabled = "HotkeyBezel.ShadowEnabled"
    case shadowDisabled = "HotkeyBezel.ShadowDisabled"
    case flipHorizontal = "HotkeyBezel.FlipHorizontal"
    case flipVertical = "HotkeyBezel.FlipVertical"
    case unitsFormat = "HotkeyBezel.UnitsFormat"
    case pixelsUnit = "Unit.Pixels.Abbreviation"
    case millimetersUnit = "Unit.Millimeters.Abbreviation"
    case inchesUnit = "Unit.Inches.Abbreviation"

    var localizedString: String {
        NSLocalizedString(rawValue, comment: comment)
    }

    private var comment: String {
        switch self {
        case .rulerFloated:
            return "Hotkey status bezel text indicating the ruler now floats above other windows"
        case .rulerUnfloated:
            return "Hotkey status bezel text indicating the ruler no longer floats above other windows"
        case .rulersGrouped:
            return "Hotkey status bezel text indicating rulers are grouped"
        case .rulersUngrouped:
            return "Hotkey status bezel text indicating rulers are ungrouped"
        case .shadowEnabled:
            return "Hotkey status bezel text indicating ruler shadow is enabled"
        case .shadowDisabled:
            return "Hotkey status bezel text indicating ruler shadow is disabled"
        case .flipHorizontal:
            return "Hotkey status bezel text indicating the horizontal ruler was flipped"
        case .flipVertical:
            return "Hotkey status bezel text indicating the vertical ruler was flipped"
        case .unitsFormat:
            return "Hotkey status bezel format for the selected measurement unit"
        case .pixelsUnit:
            return "Pixels unit abbreviation"
        case .millimetersUnit:
            return "Millimeters unit abbreviation"
        case .inchesUnit:
            return "Inches unit abbreviation"
        }
    }
}

final class UITestSupport {
    static var isEnabled: Bool { AppRuntime.isUITesting }
    static let current: UITestSupport? = nil

    func writeCursorState(_ value: String) {}
}

extension AppDelegate {
    static func isFreeRulerWindowIdentifier(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return [
            "ruler-window",
            "ruler-settings-window",
            "preferences-window",
            "ruler-color-panel",
        ].contains(identifier)
    }

    func installFreeRulerRouting() {
        guard !freeRulerRoutingDidInstall else { return }
        freeRulerRoutingDidInstall = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFreeRulerToolAction(_:)),
            name: .toolActionRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFreeRulerSettingsCommand(_:)),
            name: .commandOpenSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(freeRulerWindowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        freeRulerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleFreeRulerWindowKeyDown(event) ?? event
        }
    }

    func handleFreeRulerWindowKeyDown(
        _ event: NSEvent,
        keyWindow: NSWindow? = NSApp.keyWindow
    ) -> NSEvent? {
        guard Self.isFreeRulerWindowIdentifier(keyWindow?.identifier?.rawValue) else {
            return event
        }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        switch (Int(event.keyCode), modifiers) {
        case (kVK_ANSI_Comma, .command):
            openRulerSettings(self)
        case (kVK_ANSI_Comma, [.option, .command]):
            openPreferences(self)
        case (kVK_ANSI_W, .command):
            closeKeyWindow(self, keyWindow: keyWindow)
        default:
            return event
        }
        return nil
    }

    @objc private func handleFreeRulerToolAction(_ notification: Notification) {
        guard let action = notification.object as? ToolActionID else { return }

        switch action {
        case .rulerOpen:
            openFreeRuler()
        case .rulerSettings:
            openFreeRuler()
            openRulerSettings(self)
        default:
            break
        }
    }

    @objc private func handleFreeRulerSettingsCommand(_ notification: Notification) {
        guard Self.isFreeRulerWindowIdentifier(NSApp.keyWindow?.identifier?.rawValue) else { return }
        openRulerSettings(self)
    }

    @objc private func freeRulerWindowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateFreeRulerMenuContext(for: NSApp.keyWindow)
        }
    }

    func updateFreeRulerMenuContext(for window: NSWindow?) {
        let isRulerContext = Self.isFreeRulerWindowIdentifier(window?.identifier?.rawValue)
        FreeRulerCommandContext.shared.update(isActive: isRulerContext)
    }
}

extension AppDelegate {
    func openFreeRuler() {
        if !freeRulerDidInitialize {
            if AppRuntime.isUITesting {
                resetFreeRulerPreferences()
            }
            configureOpaqueColorPicking()
            subscribeToPrefs()
            updateDisplay()
            rulerManager.setApplicationActive(NSApp.isActive)
            restoreSavedRulers()
            freeRulerDidInitialize = true
        }

        showRulers()
        NSApp.activate(ignoringOtherApps: true)
        updateFreeRulerMenuContext(for: NSApp.keyWindow)
    }

    func updateFreeRulerForApplicationActivation(_ isActive: Bool) {
        guard freeRulerDidInitialize else { return }

        rulerManager.setApplicationActive(isActive)
        for controller in rulerManager.controllers {
            if isActive {
                controller.foreground()
            } else {
                controller.background()
            }
        }

        if isActive {
            mouseTickTimerPolicy.applicationDidBecomeActive()
            rulerCursorController.applicationDidBecomeActive()
        } else {
            mouseTickTimerPolicy.applicationDidResignActive()
            rulerCursorController.applicationDidResignActive()
        }
        updateMouseTickTimer()
    }

    func prepareFreeRulerForTermination() {
        guard freeRulerDidInitialize else { return }

        closeRulerColorPanel()
        saveRulerSetState()
        prefs.save()
    }

    private func resetFreeRulerPreferences() {
        let defaults = Prefs.userDefaults
        [
            "groupRulers",
            "floatRulers",
            "rulerShadow",
            "foregroundOpacity",
            "backgroundOpacity",
            "rulerColor",
            "unit",
            "zeroCorner",
            Prefs.rulerSetStateKey,
            "NSWindow Frame horizontal-ruler",
            "NSWindow Frame vertical-ruler",
            "NSWindow Frame preferencesWindow",
        ].forEach(defaults.removeObject(forKey:))

        prefs.groupRulers = Prefs.defaultGroupRulers
        prefs.floatRulers = true
        prefs.rulerShadow = false
        prefs.foregroundOpacity = 90
        prefs.backgroundOpacity = 50
        prefs.rulerColor = Prefs.defaultRulerFillColor
        prefs.unit = .pixels
        prefs.zeroCorner = Prefs.defaultZeroCorner
    }

    func subscribeToPrefs() {
        freeRulerObservers = [
            prefs.observe(\Prefs.unit, options: .new) { prefs, changed in
                self.updateUnitMenu()
                self.redrawDefaultBackedRulers()
            },
            prefs.observe(\Prefs.floatRulers, options: .new) { prefs, changed in
                self.updateFloatRulersMenuItem()
            },
            prefs.observe(\Prefs.groupRulers, options: .new) { prefs, changed in
                self.updateGroupRulersMenuItem()
            },
            prefs.observe(\Prefs.rulerShadow, options: .new) { prefs, changed in
                self.updateRulerShadowMenuItem()
            },
            prefs.observe(\Prefs.rulerColor, options: .new) { prefs, changed in
                self.redrawDefaultBackedRulers()
            },
            prefs.observe(\Prefs.zeroCorner, options: .new) { prefs, changed in
                self.redrawDefaultBackedRulers()
            },
        ]
    }

    func updateDisplay() {
        let activeController = rulerManager.activeController
        let settings = activeRulerSettings
        FreeRulerCommandContext.shared.update(.init(
            hasRuler: activeController != nil,
            horizontalVisible: activeController?.state.isWingVisible(.horizontal) ?? false,
            verticalVisible: activeController?.state.isWingVisible(.vertical) ?? false,
            unit: settings.unit,
            floatRulers: settings.floatRulers,
            rulerShadow: settings.rulerShadow,
            groupRulers: prefs.groupRulers
        ))
    }

    func updateUnitMenu() {
        updateDisplay()
    }

    func redrawRulers() {
        for controller in rulerManager.controllers {
            controller.redrawForPreferenceChange()
        }
    }

    func redrawDefaultBackedRulers() {
        redrawRulers()
    }

    func updateFloatRulersMenuItem() {
        updateDisplay()
    }

    func updateGroupRulersMenuItem() {
        updateDisplay()
    }

    func updateRulerShadowMenuItem() {
        updateDisplay()
    }

    private var activeRulerSettings: RulerSettings {
        return rulerManager.activeController?.state.settings ?? RulerSettings(defaults: prefs)
    }

    @discardableResult
    private func updateActiveRulerSettings(_ update: (inout RulerSettings) -> Void) -> Bool {
        guard let controller = rulerManager.activeController else { return false }

        controller.updateSettings(update)
        updateDisplay()
        return true
    }

    func createRulersIfNeeded() {
        guard !rulerManager.hasRulers else { return }

        rulerManager.createRuler()
    }

    func showRulers() {
        createRulersIfNeeded()
        rulerManager.showAll()
        updateMouseTickTimer()
    }

    func restoreSavedRulers() {
        if let restoredState = prefs.loadRulerSetState() {
            rulerManager.restore(
                restoredState.rulers,
                activeRulerID: restoredState.activeRulerID
            )
            return
        }

        if let migratedState = migratedLegacyRulerState() {
            rulerManager.restore([migratedState], activeRulerID: migratedState.id)
        }
    }

    func saveRulerSetState() {
        prefs.saveRulerSetState(
            rulers: rulerManager.states,
            activeRulerID: rulerManager.activeRulerID
        )
    }

    private func migratedLegacyRulerState() -> RulerInstanceState? {
        let defaults = Prefs.userDefaults
        let horizontalAutosaveName = "horizontal-ruler"
        let verticalAutosaveName = "vertical-ruler"
        let hasLegacyAutosave = defaults.object(forKey: "NSWindow Frame \(horizontalAutosaveName)") != nil
            || defaults.object(forKey: "NSWindow Frame \(verticalAutosaveName)") != nil
        guard hasLegacyAutosave else { return nil }

        let settings = RulerSettings(defaults: prefs)
        let horizontalFrame = legacyAutosavedFrame(
            name: horizontalAutosaveName,
            fallback: getDefaultContentRect(orientation: .horizontal, zeroCorner: settings.zeroCorner)
        )
        let verticalFrame = legacyAutosavedFrame(
            name: verticalAutosaveName,
            fallback: getDefaultContentRect(orientation: .vertical, zeroCorner: settings.zeroCorner)
        )

        return RulerInstanceState(
            settings: settings,
            layout: RulerLayoutState(
                horizontalFrame: horizontalFrame,
                verticalFrame: verticalFrame,
                zeroCorner: settings.zeroCorner
            )
        )
    }

    private func legacyAutosavedFrame(name: String, fallback: NSRect) -> NSRect {
        let window = NSWindow(
            contentRect: fallback,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        _ = window.setFrameUsingName(NSWindow.FrameAutosaveName(name))
        let frame = window.frame
        window.close()
        return frame
    }

    func toggleRuler(orientation: Orientation) {
        createRulersIfNeeded()

        let controller = rulerManager.activeController ?? rulerManager.createRuler()
        controller.toggleWing(orientation)
        updateDisplay()
        updateMouseTickTimer()
    }

    private var hasVisibleRuler: Bool {
        return rulerManager.hasVisibleRulers
    }

    @IBAction func setUnitPixels(_ sender: Any) {
        setUnit(.pixels)
    }
    @IBAction func setUnitMillimetres(_ sender: Any) {
        setUnit(.millimeters)
    }
    @IBAction func setUnitInches(_ sender: Any) {
        setUnit(.inches)
    }
    @IBAction func cycleUnits(_ sender: Any) {
        let nextUnit: Unit
        switch activeRulerSettings.unit {
        case .pixels:
            nextUnit = .millimeters
        case .millimeters:
            nextUnit = .inches
        case .inches:
            nextUnit = .pixels
        }

        setUnit(nextUnit)
        showHotkeyBezel(format: .unitsFormat, unitLabel(nextUnit), on: bezelScreen(for: sender))
    }

    @IBAction func toggleFloatRulers(_ sender: Any) {
        if let controller = rulerManager.activeController {
            let shouldFloat = !controller.state.settings.floatRulers
            controller.updateSettings { settings in
                settings.floatRulers = shouldFloat
            }
            updateFloatRulersMenuItem()
            showHotkeyBezel(
                shouldFloat ? .rulerFloated : .rulerUnfloated,
                on: bezelScreen(for: sender)
            )
            return
        }

        prefs.floatRulers = !prefs.floatRulers
        showHotkeyBezel(
            prefs.floatRulers ? .rulerFloated : .rulerUnfloated,
            on: bezelScreen(for: sender)
        )
    }

    @IBAction func toggleGroupRulers(_ sender: Any) {
        prefs.groupRulers = !prefs.groupRulers
        showGroupRulersHotkeyBezel(on: bezelScreen(for: sender))
    }
    @IBAction func toggleRulerShadow(_ sender: Any) {
        if let controller = rulerManager.activeController {
            let shouldShowShadow = !controller.state.settings.rulerShadow
            controller.updateSettings { settings in
                settings.rulerShadow = shouldShowShadow
            }
            updateRulerShadowMenuItem()
            showHotkeyBezel(
                shouldShowShadow ? .shadowEnabled : .shadowDisabled,
                on: bezelScreen(for: sender)
            )
            return
        }

        prefs.rulerShadow = !prefs.rulerShadow
        showHotkeyBezel(
            prefs.rulerShadow ? .shadowEnabled : .shadowDisabled,
            on: bezelScreen(for: sender)
        )
    }

    @IBAction func openPreferences(_ sender: Any) {
        if preferencesController == nil {
            preferencesController = PreferencesController()
        }

        if preferencesController != nil {
            preferencesController?.showWindow(self)
        }
    }

    @IBAction func openRulerSettings(_ sender: Any) {
        guard let controller = rulerManager.activeController else { return }

        if rulerSettingsController == nil {
            rulerSettingsController = RulerSettingsController(rulerController: controller)
        }

        rulerSettingsController?.show(attachedTo: controller, sender: sender)
    }

    @IBAction func newRuler(_ sender: Any) {
        let controller = rulerManager.createRuler()
        controller.show()
        updateMouseTickTimer()
    }

    @IBAction func cycleRulers(_ sender: Any) {
        guard rulerManager.cycleActiveRuler() != nil else { return }

        updateDisplay()
    }

    @IBAction func closeKeyWindow(_ sender: Any) {
        closeKeyWindow(sender, keyWindow: NSApp.keyWindow)
    }

    private func closeKeyWindow(_ sender: Any, keyWindow: NSWindow?) {
        if let controller = rulerManager.controller(containing: keyWindow) {
            rulerManager.close(controller)
            updateMouseTickTimer()
            return
        }

        if FreeRulerCommandContext.shared.isActive,
           rulerManager.hasRulers,
           keyWindow == nil,
           rulerManager.closeActiveRuler() {
            updateMouseTickTimer()
            return
        }

        keyWindow?.performClose(sender)
    }

    @IBAction func alignRulersAtMouseLocation(_ sender: Any) {
        var mouseLoc = NSEvent.mouseLocation
        mouseLoc.x = mouseLoc.x.rounded()
        mouseLoc.y = mouseLoc.y.rounded()

        createRulersIfNeeded()

        if let controller = rulerManager.activeController {
            controller.align(at: mouseLoc)
        }
    }

    @IBAction func resetRulerPositions(_ sender: Any) {
        createRulersIfNeeded()

        if let controller = rulerManager.activeController {
            controller.resetPosition()
            updateDisplay()
            updateMouseTickTimer()
        }
    }

    @IBAction func toggleHorizontalRuler(_ sender: Any) {
        toggleRuler(orientation: .horizontal)
    }

    @IBAction func toggleVerticalRuler(_ sender: Any) {
        toggleRuler(orientation: .vertical)
    }

    @IBAction func flipHorizontalRuler(_ sender: Any) {
        flipRulers(along: .horizontal)
        showHorizontalOriginHotkeyBezel(on: bezelScreen(for: sender))
    }

    @IBAction func flipVerticalRuler(_ sender: Any) {
        flipRulers(along: .vertical)
        showVerticalOriginHotkeyBezel(on: bezelScreen(for: sender))
    }

    func flipRulers(along orientation: Orientation) {
        createRulersIfNeeded()

        if let controller = rulerManager.activeController {
            let flippedCorner = controller.state.settings.zeroCorner.flipped(along: orientation)
            controller.prepareForZeroCornerChange(to: flippedCorner)
            controller.redrawForPreferenceChange()
            updateDisplay()
        }
    }

    private func setUnit(_ unit: Unit) {
        if updateActiveRulerSettings({ settings in
            settings.unit = unit
        }) {
            return
        }

        prefs.unit = unit
    }

    func performRulerHotkey(
        keyCode: Int,
        modifierFlags: NSEvent.ModifierFlags,
        sender: Any
    ) -> Bool {
        if let controller = sender as? RulerController {
            rulerManager.markActive(controller)
        }

        let keyboardModifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)

        if keyboardModifiers == .shift {
            switch keyCode {
            case kVK_ANSI_H:
                flipHorizontalRuler(sender)
            case kVK_ANSI_V:
                flipVerticalRuler(sender)
            default:
                return false
            }

            return true
        }

        if keyboardModifiers == .command {
            switch keyCode {
            case kVK_ANSI_N:
                newRuler(sender)
            case kVK_ANSI_Grave:
                cycleRulers(sender)
            default:
                return false
            }

            return true
        }

        guard keyboardModifiers.isEmpty else { return false }

        switch keyCode {
        case kVK_ANSI_H:
            toggleHorizontalRuler(sender)
        case kVK_ANSI_V:
            toggleVerticalRuler(sender)
        case kVK_ANSI_U:
            cycleUnits(sender)
        case kVK_ANSI_F:
            toggleFloatRulers(sender)
        case kVK_ANSI_G:
            toggleGroupRulers(sender)
        case kVK_ANSI_S:
            toggleRulerShadow(sender)
        case kVK_ANSI_O:
            alignRulersAtMouseLocation(sender)
        default:
            return false
        }

        return true
    }

    private func showHotkeyBezel(_ key: HotkeyBezelLocalizationKey, on screen: NSScreen?) {
        hotkeyBezel.show(key.localizedString, on: screen)
    }

    private func showHotkeyBezel(format key: HotkeyBezelLocalizationKey, _ value: String, on screen: NSScreen?) {
        hotkeyBezel.show(String(format: key.localizedString, value), on: screen)
    }

    private func showGroupRulersHotkeyBezel(on screen: NSScreen?) {
        showHotkeyBezel(prefs.groupRulers ? .rulersGrouped : .rulersUngrouped, on: screen)
    }

    private func showHorizontalOriginHotkeyBezel(on screen: NSScreen?) {
        showHotkeyBezel(.flipHorizontal, on: screen)
    }

    private func showVerticalOriginHotkeyBezel(on screen: NSScreen?) {
        showHotkeyBezel(.flipVertical, on: screen)
    }

    private func bezelScreen(for sender: Any) -> NSScreen? {
        if let rulerController = sender as? RulerController {
            return rulerController.rulerWindow.screen
        }

        if let activeController = rulerManager.activeController {
            return activeController.rulerWindow.screen
        }

        return nil
    }

    private func unitLabel(_ unit: Unit) -> String {
        switch unit {
        case .pixels:
            return HotkeyBezelLocalizationKey.pixelsUnit.localizedString
        case .millimeters:
            return HotkeyBezelLocalizationKey.millimetersUnit.localizedString
        case .inches:
            return HotkeyBezelLocalizationKey.inchesUnit.localizedString
        }
    }

}

// MARK: - Timer
extension AppDelegate {

    func suspendMouseTickUpdates(owner: AnyObject) {
        mouseTickTimerPolicy.suspend(owner: owner)
        updateMouseTickTimer()
    }

    func resumeMouseTickUpdates(owner: AnyObject) {
        mouseTickTimerPolicy.resume(owner: owner)
        updateMouseTickTimer()
    }

    func suppressMouseTickDrawing(owner: AnyObject) {
        guard !mouseTickDrawingSuppressedOwners.contains(owner) else { return }

        mouseTickDrawingSuppressedOwners.add(owner)
        updateMouseTickDrawingVisibility()
    }

    func unsuppressMouseTickDrawing(owner: AnyObject) {
        guard mouseTickDrawingSuppressedOwners.contains(owner) else { return }

        mouseTickDrawingSuppressedOwners.remove(owner)
        updateMouseTickDrawingVisibility()
    }

    private func updateMouseTickDrawingVisibility() {
        setMouseTickDrawingEnabled(!hasMouseTickDrawingSuppressedOwners)
    }

    private var hasMouseTickDrawingSuppressedOwners: Bool {
        guard mouseTickDrawingSuppressedOwners.count > 0 else { return false }
        return mouseTickDrawingSuppressedOwners.anyObject != nil
    }

    private func setMouseTickDrawingEnabled(_ isEnabled: Bool) {
        for controller in rulerManager.controllers {
            controller.setMouseTickDrawingEnabled(isEnabled)
        }
    }

    private func updateMouseTickTimer() {
        mouseTickTimerPolicy.updateVisibleRulers(hasVisibleRuler)

        guard let timeInterval = mouseTickTimerPolicy.desiredInterval else {
            stopTimer()
            return
        }

        startTimer(timeInterval: timeInterval)
    }

    private func startTimer(timeInterval: TimeInterval) {
        guard timer == nil || timerInterval != timeInterval else { return }

        timer?.invalidate()
        timerInterval = timeInterval

        timer = Timer.scheduledTimer(
            timeInterval: timeInterval,
            target: self,
            selector: #selector(self.onInterval),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerInterval = nil
    }

    @objc func onInterval() {
        self.updateMouseLocation()
    }

    private func updateMouseLocation() {
        let mouseLoc = NSEvent.mouseLocation

        for controller in rulerManager.controllers where controller.isVisible {
            controller.drawMouseTick(at: mouseLoc)
        }
    }

}
