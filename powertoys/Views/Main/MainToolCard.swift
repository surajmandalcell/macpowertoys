import SwiftUI
import OnePlusUI

struct MainToolCard: View {
    let tool: any Tool
    @Binding var favorite: Bool
    @Binding var focusedToolID: String?
    let bodyFocus: FocusState<String?>.Binding
    let move: (MoveCommandDirection) -> Void
    let typeSelect: (String) -> Void
    let select: () -> Void
    @State private var hovering = false
    @FocusState private var focusedPart: String?

    var body: some View {
        OnePlusCard {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: OnePlusCatalogMetrics.identityGap) {
                        ToolIconView(tool: tool, size: OnePlusCatalogMetrics.iconSize)
                        MainToolIdentity(tool: tool).padding(.trailing, OnePlusMetrics.compactControlHeight)
                    }
                    .padding(.bottom, OnePlusMetrics.actionSpacing)
                    Text(tool.summary).font(OnePlusCatalogMetrics.summaryFont).monospacedDigit()
                        .foregroundStyle(OnePlusColor.secondary).lineSpacing(OnePlusCatalogMetrics.summaryLineSpacing)
                        .lineLimit(2, reservesSpace: true).help(tool.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, OnePlusCatalogMetrics.gap)
                    Color.clear.frame(height: OnePlusCatalogMetrics.openHeight)
                }
                .padding(OnePlusCatalogMetrics.cardInset)
                .contentShape(Rectangle())
            }
            .buttonStyle(OnePlusInteractionStyle(radius: OnePlusMetrics.panelRadius))
            .focused(bodyFocus, equals: tool.id)
            .onKeyPress(.return) { select(); return .handled }
            .onMoveCommand(perform: move)
            .onKeyPress(characters: .alphanumerics) { press in
                guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
                typeSelect(press.characters); return .handled
            }
            .accessibilityLabel("\(tool.name) settings")
            .accessibilityIdentifier("tool.\(tool.id).card")
        }
        .overlay(alignment: .topTrailing) {
            MainFavoriteButton(toolName: tool.name, isFavorite: $favorite)
                .focused($focusedPart, equals: "favorite")
                .opacity(hovering || favorite || focusedPart != nil || bodyFocus.wrappedValue == tool.id ? 1 : 0)
                .padding(OnePlusCatalogMetrics.cardInset)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: OnePlusCatalogMetrics.smallGap) {
                MainToolEnableSwitch(tool: tool, catalog: true)
                    .focused($focusedPart, equals: "enable")
                Spacer(minLength: OnePlusCatalogMetrics.smallGap)
                MainOpenToolButton(toolID: tool.id, toolName: tool.name, catalog: true)
                    .focused($focusedPart, equals: "open")
            }.padding(OnePlusCatalogMetrics.cardInset)
        }
        .onHover { hovering = $0 }
        .onChange(of: focusedPart) { _, value in if value != nil { focusedToolID = tool.id } }
        .contextMenu { MainToolContextMenu(tool: tool, select: select) }
        .accessibilityElement(children: .contain)
    }
}

struct MainToolListRow: View {
    let tool: any Tool
    @Binding var favorite: Bool
    @Binding var focusedToolID: String?
    let bodyFocus: FocusState<String?>.Binding
    let move: (MoveCommandDirection) -> Void
    let typeSelect: (String) -> Void
    let select: () -> Void
    @FocusState private var focusedPart: String?

    var body: some View {
        HStack(spacing: OnePlusCatalogMetrics.gap) {
            Button(action: select) {
                HStack(spacing: OnePlusCatalogMetrics.identityGap) {
                    ToolIconView(tool: tool, size: OnePlusCatalogMetrics.listIconSize)
                    MainToolIdentity(tool: tool).frame(width: OnePlusCatalogMetrics.listNameWidth, alignment: .leading)
                    Text(tool.summary).font(OnePlusCatalogMetrics.summaryFont).monospacedDigit()
                        .foregroundStyle(OnePlusColor.secondary).lineSpacing(OnePlusCatalogMetrics.summaryLineSpacing)
                        .lineLimit(2).help(tool.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: OnePlusCatalogMetrics.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(OnePlusInteractionStyle()).focused(bodyFocus, equals: tool.id)
            .onKeyPress(.return) { select(); return .handled }
            .onMoveCommand(perform: move)
            .onKeyPress(characters: .alphanumerics) { press in
                guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
                typeSelect(press.characters); return .handled
            }
            .accessibilityLabel("\(tool.name) settings")
            MainFavoriteButton(toolName: tool.name, isFavorite: $favorite)
                .focused($focusedPart, equals: "favorite")
            MainToolEnableSwitch(tool: tool, catalog: true)
                .focused($focusedPart, equals: "enable")
            MainOpenToolButton(toolID: tool.id, toolName: tool.name, catalog: true)
                .focused($focusedPart, equals: "open")
        }
        .padding(.horizontal, OnePlusCatalogMetrics.cardInset)
        .frame(height: OnePlusCatalogMetrics.rowHeight)
        .onePlusRowHover()
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
        .onChange(of: focusedPart) { _, value in if value != nil { focusedToolID = tool.id } }
        .contextMenu { MainToolContextMenu(tool: tool, select: select) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tool.\(tool.id).row")
    }
}

struct MainToolIdentity: View {
    let tool: any Tool
    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusCatalogMetrics.titleGap) {
            Text(tool.name).onePlusText(.cardTitle).lineLimit(1).help(tool.name)
            Text(tool.category.rawValue).font(OnePlusCatalogMetrics.categoryFont)
                .foregroundStyle(OnePlusColor.muted).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
