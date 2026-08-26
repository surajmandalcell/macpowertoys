//
//  CCHistorySettingsSheet.swift
//  powertoys
//

import SwiftUI

struct CCHistorySettingsPage: View {
    let onDone: () -> Void
    let showsHeader: Bool
    @AppStorage("tool.cc-history.startAtLaunch") private var startAtLaunch = false

    init(onDone: @escaping () -> Void = {}, showsHeader: Bool = true) {
        self.onDone = onDone
        self.showsHeader = showsHeader
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    Text("Settings")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    UtilityModalCloseButton(action: onDone)
                }
                .padding(.horizontal, 20)
                .padding(.top, UtilityLayout.workspaceContentTopInset)
                .padding(.bottom, 12)

                QuietDivider()
            }

            Form {
                Section {
                    Toggle("Start AI History at launch", isOn: $startAtLaunch)
                } header: {
                    Text("General")
                } footer: {
                    Text("Opens AI History automatically when MacPowerToys launches.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Section("History") {
                    CCHistorySettings()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .thinScrollIndicators()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CCHistorySettings: View {
    @AppStorage("cchistory.autoRefresh") private var autoRefresh = true
    @AppStorage("cchistory.deepSearchDefault") private var deepSearchDefault = false
    @State private var cacheSessionCount: Int = 0
    @State private var cacheFileSize: Int64 = 0
    @State private var showingClearConfirm = false

    var body: some View {
        Toggle("Auto-refresh", isOn: $autoRefresh)
        Toggle("Deep search by default", isOn: $deepSearchDefault)

        LabeledContent("Cached Sessions", value: "\(cacheSessionCount)")
        LabeledContent("Cache Size", value: formatBytes(cacheFileSize))

        Button(role: .destructive) {
            showingClearConfirm = true
        } label: {
            Label("Clear Cache", systemImage: "trash")
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
            Text("This will force AI History to re-read all conversation files on next load.")
        }
        .onAppear {
            Task { await updateCacheStats() }
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
    CCHistorySettingsPage(onDone: {})
        .frame(width: 700, height: 500)
}
