import SwiftUI
import OnePlusUI

/// One overview row: the package tool row plus the app's routing, keyboard, and context menu.
struct MainToolRow: View {
    let tool: any Tool
    @Binding var favorite: Bool
    let focus: FocusState<String?>.Binding
    let move: (MoveCommandDirection) -> Void
    let typeSelect: (String) -> Void
    let open: () -> Void
    @State private var settings = SettingsManager.shared

    var body: some View {
        OnePlusLinearToolRow(tool.name, summary: tool.summary, icon: MainToolIcon.image(for: tool),
                             isEnabled: MainToolEnablement.binding(for: tool.id, settings: settings),
                             isFavorite: $favorite, open: open)
            .focused(focus, equals: tool.id)
            .onKeyPress(.return) { open(); return .handled }
            .onMoveCommand(perform: move)
            .onKeyPress(characters: .alphanumerics) { press in
                guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
                typeSelect(press.characters); return .handled
            }
            .help(tool.description)
            .contextMenu { MainToolContextMenu(tool: tool, select: open) }
            .accessibilityValue(settings.isToolEnabled(tool.id) ? "Enabled" : "Disabled")
            .accessibilityIdentifier("tool.\(tool.id).card")
    }
}
