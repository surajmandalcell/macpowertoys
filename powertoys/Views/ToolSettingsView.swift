//
//  ToolSettingsView.swift
//  powertoys
//

import SwiftUI

struct ToolSettingsView: View {
    let toolId: String
    let openWindow: OpenWindowAction

    @State private var isEnabled = true

    private var tool: (any Tool)? {
        ToolRegistry.allTools.first { $0.id == toolId }
    }

    var body: some View {
        Form {
            if let tool = tool {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 24))
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name).font(.headline)
                            Text(tool.category.rawValue).font(.caption).foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Open") {
                            openWindow(id: toolId)
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                        .disabled(!isEnabled)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                } header: {
                    Text("Status")
                }

                if toolId == "cc-history" {
                    Section {
                        CCHistorySettings()
                    } header: {
                        Text("Options")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.top, -20)
    }
}

struct CCHistorySettings: View {
    @AppStorage("cchistory.autoRefresh") private var autoRefresh = true

    var body: some View {
        Toggle("Auto-refresh", isOn: $autoRefresh)
    }
}

#Preview {
    struct Wrapper: View {
        @Environment(\.openWindow) var openWindow
        var body: some View {
            ToolSettingsView(toolId: "cc-history", openWindow: openWindow)
                .frame(width: 500, height: 400)
        }
    }
    return Wrapper()
}
