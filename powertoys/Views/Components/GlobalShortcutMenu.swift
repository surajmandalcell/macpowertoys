import SwiftUI

struct GlobalShortcutMenu: View {
    let action: GlobalShortcutAction
    @State private var shortcuts = GlobalShortcutManager.shared

    var body: some View {
        Menu {
            Toggle("Enable global shortcut", isOn: Binding(
                get: { shortcuts.isEnabled(action) },
                set: { shortcuts.setEnabled($0, for: action) }
            ))
            Divider()
            Picker("Key", selection: Binding(
                get: { shortcuts.key(for: action) },
                set: { shortcuts.setKey($0, for: action) }
            )) {
                ForEach(GlobalShortcutKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "command")
                    .font(.system(size: 10, weight: .medium))
                Text("⌃⌥⌘\(shortcuts.key(for: action).title)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(shortcuts.isEnabled(action) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .help("Global shortcut")
    }
}
