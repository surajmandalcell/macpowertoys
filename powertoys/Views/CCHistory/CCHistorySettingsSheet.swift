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

            ScrollView {
                VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GENERAL").utilitySectionHeader()
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Start AI History at launch")
                                Spacer()
                                Toggle("Start AI History at launch", isOn: $startAtLaunch)
                                    .labelsHidden()
                            }
                            Text("Opens AI History automatically when MacPowerToys launches.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 12))
                        .controlSize(.small)
                        .utilitySectionCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("HISTORY").utilitySectionHeader()
                        VStack(alignment: .leading, spacing: 10) {
                            CCHistorySettings()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 12))
                        .controlSize(.small)
                        .utilitySectionCard()
                    }
                }
                .settingsPageInsets(horizontal: UtilityLayout.horizontalInset, top: 16, bottom: 20)
            }
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
        HStack {
            Text("Auto-refresh")
            Spacer()
            Toggle("Auto-refresh", isOn: $autoRefresh)
                .labelsHidden()
        }
        HStack {
            Text("Deep search by default")
            Spacer()
            Toggle("Deep search by default", isOn: $deepSearchDefault)
                .labelsHidden()
        }

        HStack {
            Text("Cached Sessions")
            Spacer()
            Text("\(cacheSessionCount)").monospacedDigit()
        }
        HStack {
            Text("Cache Size")
            Spacer()
            Text(formatBytes(cacheFileSize)).monospacedDigit()
        }

        HStack {
            Spacer()
            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                Label("Clear Cache", systemImage: "trash")
            }
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
