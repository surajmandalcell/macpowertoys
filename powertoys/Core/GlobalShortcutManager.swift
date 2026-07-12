import Carbon.HIToolbox
import Foundation
import Observation

enum GlobalShortcutKey: String, CaseIterable, Identifiable {
    case c, p, k
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var keyCode: UInt32 {
        switch self {
        case .c: UInt32(kVK_ANSI_C)
        case .p: UInt32(kVK_ANSI_P)
        case .k: UInt32(kVK_ANSI_K)
        }
    }
}

@Observable
@MainActor
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private(set) var colorKey: GlobalShortcutKey
    private(set) var isColorShortcutEnabled: Bool

    private init() {
        colorKey = UserDefaults.standard.string(forKey: "shortcut.color-picker.key")
            .flatMap(GlobalShortcutKey.init(rawValue:)) ?? .c
        isColorShortcutEnabled = UserDefaults.standard.object(forKey: "shortcut.color-picker.enabled") as? Bool ?? true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        register(id: 1, keyCode: UInt32(kVK_ANSI_R))
        register(id: 2, keyCode: UInt32(kVK_ANSI_A))
        if isColorShortcutEnabled { register(id: 3, keyCode: colorKey.keyCode) }
        register(id: 4, keyCode: UInt32(kVK_ANSI_T))
    }

    func shutdown() {
        hotKeys.values.forEach { _ = UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    func setColorKey(_ key: GlobalShortcutKey) {
        guard key != colorKey else { return }
        colorKey = key
        UserDefaults.standard.set(key.rawValue, forKey: "shortcut.color-picker.key")
        if isColorShortcutEnabled {
            unregister(id: 3)
            register(id: 3, keyCode: key.keyCode)
        }
    }

    func setColorShortcutEnabled(_ enabled: Bool) {
        guard enabled != isColorShortcutEnabled else { return }
        isColorShortcutEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "shortcut.color-picker.enabled")
        if enabled { register(id: 3, keyCode: colorKey.keyCode) }
        else { unregister(id: 3) }
    }

    private func register(id: UInt32, keyCode: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x50545759), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(controlKey | optionKey | cmdKey),
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

    private func run(id: UInt32) {
        let action: ToolActionID? = switch id {
        case 1: .rulerNewHorizontal
        case 2: .awakeToggle
        case 3: .colorPickerPick
        case 4: .textExtractorCapture
        default: nil
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
        Task { @MainActor in manager.run(id: hotKeyID.id) }
        return noErr
    }
}
