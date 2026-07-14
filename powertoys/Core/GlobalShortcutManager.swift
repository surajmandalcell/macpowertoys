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
    var defaultKey: GlobalShortcutKey {
        switch self {
        case .colorPicker: .c
        case .textExtractor: .t
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
    private var keys: [GlobalShortcutAction: GlobalShortcutKey]
    private var enabledActions: Set<GlobalShortcutAction>

    private init() {
        keys = Dictionary(uniqueKeysWithValues: GlobalShortcutAction.allCases.map { action in
            let key = UserDefaults.standard.string(forKey: "shortcut.\(action.defaultsName).key")
                .flatMap(GlobalShortcutKey.init(rawValue:)) ?? action.defaultKey
            return (action, key)
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
        register(id: 1, keyCode: UInt32(kVK_ANSI_R))
        register(id: 2, keyCode: UInt32(kVK_ANSI_A))
        for action in enabledActions { register(action) }
    }

    func key(for action: GlobalShortcutAction) -> GlobalShortcutKey {
        keys[action] ?? action.defaultKey
    }

    func isEnabled(_ action: GlobalShortcutAction) -> Bool {
        enabledActions.contains(action)
    }

    func setKey(_ key: GlobalShortcutKey, for action: GlobalShortcutAction) {
        guard key != self.key(for: action) else { return }
        keys[action] = key
        UserDefaults.standard.set(key.rawValue, forKey: "shortcut.\(action.defaultsName).key")
        if isEnabled(action) {
            unregister(id: action.rawValue)
            register(action)
        }
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
    }

    func shutdown() {
        hotKeys.values.forEach { _ = UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private func register(_ action: GlobalShortcutAction) {
        register(id: action.rawValue, keyCode: key(for: action).keyCode)
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
}
