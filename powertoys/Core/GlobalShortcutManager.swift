import ApplicationServices
import Carbon.HIToolbox
import Foundation
import Observation

enum GlobalShortcutKey: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var keyCode: UInt32 {
        switch self {
        case .a: UInt32(kVK_ANSI_A)
        case .b: UInt32(kVK_ANSI_B)
        case .c: UInt32(kVK_ANSI_C)
        case .d: UInt32(kVK_ANSI_D)
        case .e: UInt32(kVK_ANSI_E)
        case .f: UInt32(kVK_ANSI_F)
        case .g: UInt32(kVK_ANSI_G)
        case .h: UInt32(kVK_ANSI_H)
        case .i: UInt32(kVK_ANSI_I)
        case .j: UInt32(kVK_ANSI_J)
        case .k: UInt32(kVK_ANSI_K)
        case .l: UInt32(kVK_ANSI_L)
        case .m: UInt32(kVK_ANSI_M)
        case .n: UInt32(kVK_ANSI_N)
        case .o: UInt32(kVK_ANSI_O)
        case .p: UInt32(kVK_ANSI_P)
        case .q: UInt32(kVK_ANSI_Q)
        case .r: UInt32(kVK_ANSI_R)
        case .s: UInt32(kVK_ANSI_S)
        case .t: UInt32(kVK_ANSI_T)
        case .u: UInt32(kVK_ANSI_U)
        case .v: UInt32(kVK_ANSI_V)
        case .w: UInt32(kVK_ANSI_W)
        case .x: UInt32(kVK_ANSI_X)
        case .y: UInt32(kVK_ANSI_Y)
        case .z: UInt32(kVK_ANSI_Z)
        }
    }
}

struct GlobalShortcut: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    var display: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyLabel
    }

    var overridesSystemScreenshotShortcut: Bool {
        let screenshotKeys = [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].map(UInt32.init)
        return screenshotKeys.contains(keyCode)
            && carbonModifiers == UInt32(shiftKey | cmdKey)
    }

    func matches(keyCode: UInt32, flags: CGEventFlags) -> Bool {
        var modifiers: UInt32 = 0
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        return self.keyCode == keyCode && carbonModifiers == modifiers
    }
}

enum GlobalShortcutAction: UInt32, CaseIterable, Identifiable {
    case colorPicker = 3
    case textExtractor = 4

    var id: UInt32 { rawValue }
    var defaultsName: String {
        switch self {
        case .colorPicker: "color-picker"
        case .textExtractor: "text-extractor"
        }
    }
    var defaultShortcut: GlobalShortcut {
        switch self {
        case .colorPicker:
            GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_3),
                carbonModifiers: UInt32(shiftKey | cmdKey),
                keyLabel: "3"
            )
        case .textExtractor:
            GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_2),
                carbonModifiers: UInt32(shiftKey | cmdKey),
                keyLabel: "2"
            )
        }
    }
    var toolAction: ToolActionID {
        switch self {
        case .colorPicker: .colorPickerPick
        case .textExtractor: .textExtractorCapture
        }
    }
}

@Observable
@MainActor
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var reservedShortcutTap: CFMachPort?
    private var reservedShortcutTapSource: CFRunLoopSource?
    private var shortcuts: [GlobalShortcutAction: GlobalShortcut]
    private var enabledActions: Set<GlobalShortcutAction>

    private init() {
        shortcuts = Dictionary(uniqueKeysWithValues: GlobalShortcutAction.allCases.map { action in
            (action, Self.storedShortcut(for: action))
        })
        enabledActions = Set(GlobalShortcutAction.allCases.filter { action in
            UserDefaults.standard.object(forKey: "shortcut.\(action.defaultsName).enabled") as? Bool ?? true
        })

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        let legacyModifiers = UInt32(controlKey | optionKey | cmdKey)
        register(id: 1, keyCode: UInt32(kVK_ANSI_R), modifiers: legacyModifiers)
        register(id: 2, keyCode: UInt32(kVK_ANSI_A), modifiers: legacyModifiers)
        for action in enabledActions { register(action) }
        refreshReservedShortcutTap()
    }

    private static func storedShortcut(for action: GlobalShortcutAction) -> GlobalShortcut {
        let defaults = UserDefaults.standard
        let prefix = "shortcut.\(action.defaultsName)"
        if let keyCode = defaults.object(forKey: "\(prefix).keyCode") as? Int,
           let modifiers = defaults.object(forKey: "\(prefix).modifiers") as? Int,
           let label = defaults.string(forKey: "\(prefix).keyLabel") {
            return GlobalShortcut(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers), keyLabel: label)
        }
        if let legacy = defaults.string(forKey: "\(prefix).key")
            .flatMap(GlobalShortcutKey.init(rawValue:)) {
            return GlobalShortcut(
                keyCode: legacy.keyCode,
                carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
                keyLabel: legacy.title
            )
        }
        return action.defaultShortcut
    }

    func shortcut(for action: GlobalShortcutAction) -> GlobalShortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func isEnabled(_ action: GlobalShortcutAction) -> Bool {
        enabledActions.contains(action)
    }

    func setShortcut(_ shortcut: GlobalShortcut, for action: GlobalShortcutAction) {
        guard shortcut != self.shortcut(for: action) else { return }
        shortcuts[action] = shortcut
        let prefix = "shortcut.\(action.defaultsName)"
        UserDefaults.standard.set(Int(shortcut.keyCode), forKey: "\(prefix).keyCode")
        UserDefaults.standard.set(Int(shortcut.carbonModifiers), forKey: "\(prefix).modifiers")
        UserDefaults.standard.set(shortcut.keyLabel, forKey: "\(prefix).keyLabel")
        if isEnabled(action) {
            unregister(id: action.rawValue)
            register(action)
        }
        refreshReservedShortcutTap()
    }

    func setEnabled(_ enabled: Bool, for action: GlobalShortcutAction) {
        guard enabled != isEnabled(action) else { return }
        if enabled {
            enabledActions.insert(action)
            register(action)
        } else {
            enabledActions.remove(action)
            unregister(id: action.rawValue)
        }
        UserDefaults.standard.set(enabled, forKey: "shortcut.\(action.defaultsName).enabled")
        refreshReservedShortcutTap()
    }

    func needsAccessibilityPermission(for action: GlobalShortcutAction) -> Bool {
        isEnabled(action)
            && shortcut(for: action).overridesSystemScreenshotShortcut
            && reservedShortcutTap == nil
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshReservedShortcutTap()
        }
    }

    func shutdown() {
        hotKeys.values.forEach { _ = UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        stopReservedShortcutTap()
    }

    private func register(_ action: GlobalShortcutAction) {
        let shortcut = shortcut(for: action)
        register(id: action.rawValue, keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers)
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x50545759), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference { hotKeys[id] = reference }
    }

    private func unregister(id: UInt32) {
        guard let reference = hotKeys.removeValue(forKey: id) else { return }
        _ = UnregisterEventHotKey(reference)
    }

    private func refreshReservedShortcutTap() {
        stopReservedShortcutTap()
        let needsTap = enabledActions.contains {
            shortcut(for: $0).overridesSystemScreenshotShortcut
        }
        guard needsTap else { return }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.handleReservedShortcutEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        reservedShortcutTap = tap
        reservedShortcutTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopReservedShortcutTap() {
        if let source = reservedShortcutTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = reservedShortcutTap { CFMachPortInvalidate(tap) }
        reservedShortcutTapSource = nil
        reservedShortcutTap = nil
    }

    private func reservedAction(keyCode: UInt32, flags: CGEventFlags) -> GlobalShortcutAction? {
        enabledActions.first {
            let shortcut = shortcut(for: $0)
            return shortcut.overridesSystemScreenshotShortcut
                && shortcut.matches(keyCode: keyCode, flags: flags)
        }
    }

    private func run(id: UInt32) {
        let action: ToolActionID? = switch id {
        case 1: .rulerNewHorizontal
        case 2: .awakeToggle
        default: GlobalShortcutAction(rawValue: id)?.toolAction
        }
        if let action { ToolActionRouter.shared.execute(ToolActionRequest(action: action)) }
    }

    nonisolated private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        let id = hotKeyID.id
        Task { @MainActor in manager.run(id: id) }
        return noErr
    }

    nonisolated private static let handleReservedShortcutEvent: CGEventTapCallBack = {
        _, type, event, userData in
        guard type == .keyDown, let userData else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let action = MainActor.assumeIsolated {
            manager.reservedAction(keyCode: keyCode, flags: event.flags)
        }
        guard let action else { return Unmanaged.passUnretained(event) }
        Task { @MainActor in manager.run(id: action.rawValue) }
        return nil
    }
}
