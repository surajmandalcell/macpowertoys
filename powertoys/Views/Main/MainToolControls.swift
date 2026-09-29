import SwiftUI
import OnePlusUI

struct MainFavoriteButton: View {
    let toolName: String
    @Binding var isFavorite: Bool
    private var title: String { "\(isFavorite ? "Remove" : "Add") \(toolName) \(isFavorite ? "from" : "to") favorites" }

    var body: some View {
        Button { isFavorite.toggle() } label: { Image(systemName: isFavorite ? "star.fill" : "star") }
            .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
            .help(title).accessibilityLabel(title)
            .accessibilityValue(isFavorite ? "Favorite" : "Not a favorite")
    }
}

struct MainToolEnableSwitch: View {
    let tool: any Tool
    var showsCaption = false
    @State private var settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: OnePlusCatalogMetrics.smallGap) {
            Toggle("Enable \(tool.name)", isOn: Binding(
                get: { settings.isToolEnabled(tool.id) },
                set: { settings.setToolEnabled($0, for: tool.id) }
            ))
            .labelsHidden().toggleStyle(OnePlusSwitchStyle())
            .disabled(settings.isToolTransitioning(tool.id))
            .accessibilityLabel("Enable \(tool.name)")
            .accessibilityIdentifier("tool.\(tool.id).\(showsCaption ? "quick-toggle" : "enabled")")
            if showsCaption {
                Text(settings.isToolEnabled(tool.id) ? "Enabled" : "Disabled").onePlusText(.caption)
            }
        }.fixedSize()
    }
}

struct MainOpenToolButton: View {
    let toolID: String?
    var title = "Open"
    var showsArrow = false
    @State private var settings = SettingsManager.shared

    var body: some View {
        Button {
            guard let toolID else { return }
            ToolActionRouter.shared.open(toolID: toolID)
        } label: {
            HStack(spacing: OnePlusCatalogMetrics.smallGap) {
                Text(title)
                if showsArrow { Image(systemName: "arrow.right").accessibilityHidden(true) }
            }
        }
        .buttonStyle(OnePlusButtonStyle.catalogOpen)
        .disabled(toolID == nil || !settings.isToolEnabled(toolID ?? "") || settings.isToolTransitioning(toolID ?? ""))
        .accessibilityIdentifier("tool.\(toolID ?? "none").\(showsArrow ? "open" : "launch")")
        .accessibilityLabel("Open \(toolID.flatMap { ToolRegistry.tool(for: $0)?.name } ?? "selected tool")")
        .help("Open \(toolID.flatMap { ToolRegistry.tool(for: $0)?.name } ?? "selected tool")")
    }
}

struct MainToolContextMenu: View {
    let tool: any Tool
    let select: () -> Void
    @AppStorage("main.favorites") private var storedFavorites = "[]"
    @State private var settings = SettingsManager.shared

    var body: some View {
        Button("Settings", action: select)
        MainOpenToolButton(toolID: tool.id)
        Button(settings.isToolEnabled(tool.id) ? "Disable" : "Enable") {
            settings.setToolEnabled(!settings.isToolEnabled(tool.id), for: tool.id)
        }.disabled(settings.isToolTransitioning(tool.id))
        Button(MainCatalog.favorites(from: storedFavorites).contains(tool.id) ? "Remove favorite" : "Add favorite") {
            var favorites = MainCatalog.favorites(from: storedFavorites)
            if !favorites.insert(tool.id).inserted { favorites.remove(tool.id) }
            storedFavorites = MainCatalog.storing(favorites: favorites)
        }
    }
}
