import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderField: View {
    let action: GlobalShortcutAction
    @State private var shortcuts = GlobalShortcutManager.shared
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Type shortcut…" : shortcuts.shortcut(for: action).display)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isRecording ? .secondary : .primary)
                .padding(.horizontal, 10)
                .frame(minWidth: 96)
                .frame(height: 28)
                .background(isRecording ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(isRecording ? "Press the new keys, or Escape to cancel" : "Click, then press the new shortcut")
        .accessibilityLabel("Record keyboard shortcut")
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return true
        }
        let modifiers = carbonModifiers(from: event.modifierFlags)
        let required = UInt32(cmdKey | controlKey | optionKey)
        guard modifiers & required != 0, let label = Self.keyLabel(for: event) else { return true }
        shortcuts.setShortcut(
            GlobalShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers, keyLabel: label),
            for: action
        )
        stopRecording()
        return true
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private static let namedKeys: [Int: String] = [
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
