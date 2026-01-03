//
//  ToolSettingsView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

struct ToolSettingsView: View {
    let toolId: String
    let openWindow: OpenWindowAction

    @State private var isEnabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with icon and name
                HStack(spacing: 16) {
                    if let tool = ToolRegistry.allTools.first(where: { $0.id == toolId }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                            .frame(width: 72, height: 72)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(tool.name)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(tool.category.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }

                Divider()

                // Enable/Disable Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.headline)

                    Toggle(isOn: $isEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Tool")
                                .font(.body)
                            Text("Allow this tool to be used")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Divider()

                // Tool-specific settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configuration")
                        .font(.headline)

                    if toolId == "cc-history" {
                        CCHistorySettings()
                    } else {
                        Text("No configuration options available")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Open Tool Button
                VStack(alignment: .leading, spacing: 12) {
                    Text("Launch")
                        .font(.headline)

                    Button {
                        openWindow(id: toolId)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.forward.square")
                            Text("Open Tool")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isEnabled)

                    Text("Opens the tool in a separate window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("Tool Settings")
        .frame(maxWidth: 600)
    }
}

// MARK: - CC History Settings

struct CCHistorySettings: View {
    @AppStorage("cchistory.autoRefresh") private var autoRefresh = true
    @AppStorage("cchistory.refreshInterval") private var refreshInterval = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Auto-refresh conversations", isOn: $autoRefresh)
                .help("Automatically refresh when new conversations are detected")

            if autoRefresh {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Refresh Interval: \(Int(refreshInterval)) seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(value: $refreshInterval, in: 1...30, step: 1)
                        .frame(maxWidth: 300)
                }
                .padding(.leading, 20)
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Environment(\.openWindow) var openWindow

        var body: some View {
            ToolSettingsView(toolId: "cc-history", openWindow: openWindow)
                .frame(width: 600, height: 500)
        }
    }

    return PreviewWrapper()
}
