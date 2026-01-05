//
//  SettingsView.swift
//  powertoys
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

struct SettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.automatic.rawValue
    @AppStorage("logs.fontSize") private var logsFontSize: Int = 11
    @State private var cacheSessionCount: Int = 0
    @State private var cacheFileSize: Int64 = 0
    @State private var showingClearConfirm = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                .onChange(of: selectedTheme) { _, newValue in
                    applyTheme(AppTheme(rawValue: newValue) ?? .automatic)
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("Font Size", selection: $logsFontSize) {
                    Text("Small (10pt)").tag(10)
                    Text("Medium (11pt)").tag(11)
                    Text("Default (12pt)").tag(12)
                    Text("Large (14pt)").tag(14)
                }
            } header: {
                Text("Logs")
            }

            Section {
                LabeledContent("Cached Sessions", value: "\(cacheSessionCount)")
                LabeledContent("Cache Size", value: formatBytes(cacheFileSize))

                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("Clear CC History Cache", systemImage: "trash")
                }
                .confirmationDialog("Clear Cache?", isPresented: $showingClearConfirm) {
                    Button("Clear Cache", role: .destructive) {
                        Task {
                            await SessionMetadataCache.shared.clearAndDeleteFile()
                            await updateCacheStats()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will force CC History to re-read all conversation files on next load.")
                }
            } header: {
                Text("CC History")
            } footer: {
                Text("Clear the cache if conversations aren't showing correctly.")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.adjustable.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PowerToys")
                            .font(.headline)
                        Text("Version 1.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent("Developer", value: "Suraj Mandal")

                LabeledContent("Contact") {
                    Link("surajmandalcell@gmail.com", destination: URL(string: "mailto:surajmandalcell@gmail.com")!)
                        .font(.callout)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.top, -20)
        .onAppear {
            applyTheme(AppTheme(rawValue: selectedTheme) ?? .automatic)
            Task { await updateCacheStats() }
        }
    }

    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .automatic: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func updateCacheStats() async {
        cacheSessionCount = await SessionMetadataCache.shared.cacheSize()
        cacheFileSize = await SessionMetadataCache.shared.cacheFileSize()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

#Preview {
    SettingsView()
        .frame(width: 500, height: 400)
}
