import SwiftUI
import OnePlusUI

/// One Settings-style overview row: icon, name and summary, then favorite, enable, and a chevron.
struct MainToolRow: View {
    let tool: any Tool
    @Binding var favorite: Bool
    @Binding var focusedToolID: String?
    let bodyFocus: FocusState<String?>.Binding
    var separator = true
    let move: (MoveCommandDirection) -> Void
    let typeSelect: (String) -> Void
    let select: () -> Void
    @State private var hovering = false
    @FocusState private var focusedPart: String?

    var body: some View {
        HStack(spacing: OnePlusCatalogMetrics.gap) {
            Button(action: select) {
                HStack(spacing: OnePlusCatalogMetrics.gap) {
                    ToolIconView(tool: tool, size: MainPaneMetrics.rowIcon)
                    VStack(alignment: .leading, spacing: OnePlusCatalogMetrics.titleGap) {
                        Text(tool.name).onePlusText(.row).lineLimit(1)
                        Text(tool.summary).onePlusText(.caption).lineLimit(1).help(tool.description)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: OnePlusCatalogMetrics.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focused(bodyFocus, equals: tool.id)
            .onKeyPress(.return) { select(); return .handled }
            .onMoveCommand(perform: move)
            .onKeyPress(characters: .alphanumerics) { press in
                guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
                typeSelect(press.characters); return .handled
            }
            .accessibilityLabel("\(tool.name) settings")
            .accessibilityIdentifier("tool.\(tool.id).card")
            MainFavoriteButton(toolName: tool.name, isFavorite: $favorite)
                .focused($focusedPart, equals: "favorite")
                .opacity(hovering || favorite || focusedPart != nil || bodyFocus.wrappedValue == tool.id ? 1 : 0)
            MainToolEnableSwitch(tool: tool, catalog: true)
                .focused($focusedPart, equals: "enable")
            Image(systemName: "chevron.right").onePlusText(.caption).accessibilityHidden(true)
        }
        .padding(.horizontal, OnePlusCatalogMetrics.cardInset)
        .frame(height: OnePlusCatalogMetrics.rowHeight)
        .onePlusRowHover(selected: bodyFocus.wrappedValue == tool.id && OnePlusFocusPolicy.shared.showsFocus)
        .overlay(alignment: .bottom) {
            if separator { OnePlusColor.lineSoft.frame(height: 1).padding(.horizontal, OnePlusCatalogMetrics.cardInset) }
        }
        .onHover { hovering = $0 }
        .onChange(of: focusedPart) { _, value in if value != nil { focusedToolID = tool.id } }
        .contextMenu { MainToolContextMenu(tool: tool, select: select) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tool.\(tool.id).row")
    }
}
