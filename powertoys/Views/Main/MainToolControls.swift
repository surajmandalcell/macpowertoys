import SwiftUI
import OnePlusUI

/// Enablement goes through `SettingsManager`, which starts and stops the tool's services. A tool that is still
/// starting or stopping ignores new changes.
enum MainToolEnablement {
    @MainActor
    static func binding(for toolID: String, settings: SettingsManager) -> Binding<Bool> {
        Binding(get: { settings.isToolEnabled(toolID) }, set: { enabled in
            guard !settings.isToolTransitioning(toolID) else { return }
            settings.setToolEnabled(enabled, for: toolID)
        })
    }
}

struct MainToolEnableSwitch: View {
    let tool: any Tool
    @State private var settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("Enabled").linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                .accessibilityHidden(true)
            Toggle("Enable \(tool.name)", isOn: MainToolEnablement.binding(for: tool.id, settings: settings))
                .toggleStyle(OnePlusLinearSwitchStyle()).labelsHidden()
                .disabled(settings.isToolTransitioning(tool.id))
                .accessibilityIdentifier("tool.\(tool.id).enabled")
        }
    }
}

struct MainOpenToolButton: View {
    let toolID: String?
    var toolName: String? = nil
    var title = "Open"
    var style = OnePlusLinearButtonStyle.Kind.raised
    @State private var settings = SettingsManager.shared

    var body: some View {
        let resolvedToolName = toolName ?? toolID.flatMap { ToolRegistry.tool(for: $0)?.name } ?? "selected tool"
        Button(title) {
            guard let toolID else { return }
            ToolActionRouter.shared.open(toolID: toolID)
        }
        .buttonStyle(OnePlusLinearButtonStyle(style))
        .disabled(toolID == nil || !settings.isToolEnabled(toolID ?? "") || settings.isToolTransitioning(toolID ?? ""))
        .accessibilityIdentifier("tool.\(toolID ?? "none").launch")
        .accessibilityLabel("Open \(resolvedToolName)")
        .help("Open \(resolvedToolName)")
    }
}

/// The tool page "Launch tile": opens the tool, and shows its global shortcut when one is on.
struct MainLaunchTile: View {
    let tool: any Tool
    @State private var settings = SettingsManager.shared
    @State private var shortcuts = GlobalShortcutManager.shared

    private var action: GlobalShortcutAction? {
        switch tool.id {
        case "color-picker": .colorPicker
        case "text-extractor": .textExtractor
        case "portman": .portman
        default: nil
        }
    }

    var body: some View {
        let active = action.flatMap { shortcuts.isEnabled($0) && shortcuts.shortcut(for: $0).isSet ? $0 : nil }
        OnePlusLinearLaunchTile(shortcut: active.map { shortcuts.shortcut(for: $0).display },
                                caption: active.map { $0 == .portman ? "Open \(tool.name)" : $0.title } ?? "Open \(tool.name)") {
            ToolActionRouter.shared.open(toolID: tool.id)
        }
        .disabled(!settings.isToolEnabled(tool.id) || settings.isToolTransitioning(tool.id))
        .accessibilityIdentifier("tool.\(tool.id).launch")
        .help("Open \(tool.name)")
    }
}

struct MainToolContextMenu: View {
    let tool: any Tool
    let select: () -> Void
    @AppStorage("main.favorites") private var storedFavorites = "[]"
    @State private var settings = SettingsManager.shared

    var body: some View {
        let favorites = MainCatalog.favorites(from: storedFavorites)
        Button("Settings") {
            MainToolTab.select(.settings, for: tool.id)
            select()
        }
        MainOpenToolButton(toolID: tool.id, toolName: tool.name)
        Button(settings.isToolEnabled(tool.id) ? "Disable" : "Enable") {
            settings.setToolEnabled(!settings.isToolEnabled(tool.id), for: tool.id)
        }.disabled(settings.isToolTransitioning(tool.id))
        Button(favorites.contains(tool.id) ? "Remove favorite" : "Add favorite") {
            storedFavorites = MainCatalog.storing(
                favorites: MainCatalog.setting(favorite: !favorites.contains(tool.id), for: tool.id, in: favorites))
        }
    }
}
