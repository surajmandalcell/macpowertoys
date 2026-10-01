import AppKit
import Carbon.HIToolbox
import SwiftUI
import OnePlusUI

struct ShortcutRecorderField: View {
    let action: GlobalShortcutAction
    var width: CGFloat = OnePlusMetrics.controlColumn
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var recordingWindowNumber: Int?

    private var registrationError: String? {
        if case .failed(let message) = shortcuts.registrationStatus[action] { return message }
        return nil
    }

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Group {
                if isRecording { Text("Type shortcut…") }
                else if registrationError != nil {
                    Label("Change Shortcut", systemImage: "exclamationmark.triangle")
                } else { Text(shortcuts.shortcut(for: action).display) }
            }
                .onePlusText(.control)
                .foregroundStyle(OnePlusColor.controlInk)
                .lineLimit(1)
                .frame(width: max(0, width - 2 * OnePlusMetrics.controlHorizontalPadding))
        }
        .buttonStyle(OnePlusButtonStyle())
        .onePlusNeutralControls()
        .environment(\.onePlusControlState, isRecording ? .focus : .rest)
        .help(registrationError ?? (isRecording ? "Press the new keys, or Escape to cancel" : "Click, then press the new shortcut"))
        .accessibilityLabel("\(registrationError == nil ? "Record" : "Change") \(action.title) shortcut")
        .accessibilityValue(shortcuts.shortcut(for: action).display)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.windowNumber == recordingWindowNumber { stopRecording() }
        }
        .onChange(of: shortcuts.isEnabled(action)) { _, enabled in
            if !enabled { stopRecording() }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard let window = NSApp.keyWindow else { return }
        recordingWindowNumber = window.windowNumber
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingWindowNumber = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording, Self.accepts(event, windowNumber: recordingWindowNumber) else { return false }
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return true
        }
        guard let shortcut = Self.shortcut(from: event) else { return true }
        shortcuts.setShortcut(shortcut, for: action)
        stopRecording()
        return true
    }

    static func accepts(_ event: NSEvent, windowNumber: Int?) -> Bool {
        guard let windowNumber else { return false }
        return event.windowNumber == windowNumber
    }

    static func shortcut(from event: NSEvent) -> GlobalShortcut? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        let required = UInt32(cmdKey | controlKey | optionKey)
        guard modifiers & required != 0, let label = keyLabel(for: event) else { return nil }
        return GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers,
            keyLabel: label
        )
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private static let namedKeys: [Int: String] = [
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    private static func keyLabel(for event: NSEvent) -> String? {
        if let named = namedKeys[Int(event.keyCode)] { return named }
        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value < 0xE000 else { return nil }
        return characters
    }
}

struct ShortcutPermissionNotice: View {
    let action: GlobalShortcutAction
    @State private var shortcuts = GlobalShortcutManager.shared

    var body: some View {
        if shortcuts.needsAccessibilityPermission(for: action) {
            HStack(spacing: OnePlusMetrics.actionSpacing) {
                Text("Accessibility access needed")
                    .onePlusText(.caption, color: OnePlusColor.warn)
                Spacer(minLength: OnePlusMetrics.actionSpacing)
                Button("Allow Access…") { shortcuts.requestAccessibilityPermission() }
                    .buttonStyle(OnePlusButtonStyle(.ghost))
            }
            .help("macOS reserves screenshot shortcuts. Accessibility access lets MacPowerToys use them.")
        } else if case .failed(let message) = shortcuts.registrationStatus[action] {
            Text(message).onePlusText(.caption, color: OnePlusColor.warn)
        }
    }
}
