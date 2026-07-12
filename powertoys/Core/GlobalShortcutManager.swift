import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef?] = []

    private init() {
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
        register(id: 3, keyCode: UInt32(kVK_ANSI_C))
        register(id: 4, keyCode: UInt32(kVK_ANSI_T))
    }

    func shutdown() {
        hotKeys.compactMap { $0 }.forEach { _ = UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
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
        if status == noErr { hotKeys.append(reference) }
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
