//
//  AppSettingsSheet.swift
//  powertoys
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

struct AppSettingsSheet: View {
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case marketplace = "Marketplace"
        case about = "About"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general

    private static let sheetSize = CGSize(width: 680, height: 560)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabStrip
            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab()
                case .marketplace:
                    MarketplaceSettingsView()
                case .about:
                    AboutSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.sheetSize.width, height: Self.sheetSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("App Settings")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabPill(
                    title: tab.rawValue,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

private struct SettingsTabPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(isSelected || isHovering ? 0.06 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.automatic.rawValue
    @State private var showSyncConflictDialog = false

    private var syncManager: SettingsSyncManager { SettingsSyncManager.shared }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                appearanceSection
                syncSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 12)
        }
        .confirmationDialog(
            "iCloud already contains MacPowerToys settings",
            isPresented: $showSyncConflictDialog,
            titleVisibility: .visible
        ) {
            Button("Use iCloud Settings") { syncManager.resolveConflict(useCloud: true) }
            Button("Replace iCloud with This Mac", role: .destructive) {
                syncManager.resolveConflict(useCloud: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether this Mac should adopt the settings already in iCloud, or overwrite iCloud with the settings on this Mac.")
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPEARANCE")
                .utilitySectionHeader()

            Picker("Theme", selection: $selectedTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: selectedTheme) { _, newValue in
                applyTheme(AppTheme(rawValue: newValue) ?? .automatic)
            }
            .utilitySectionCard()
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICLOUD")
                .utilitySectionHeader()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Sync settings via iCloud", isOn: syncBinding)
                    .font(.system(size: 13))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Text(syncManager.lastSyncDescription
                     ?? "Syncs appearance, safe tool preferences, and marketplace sources. Never syncs credentials, histories, file paths, or installed apps.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .utilitySectionCard()
        }
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { syncManager.isEnabled },
            set: { enabled in
                if enabled {
                    if syncManager.enable() == .conflict {
                        showSyncConflictDialog = true
                    }
                } else {
                    syncManager.disable()
                }
            }
        )
    }

    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .automatic: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    private static let iconSize: CGFloat = 44

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ABOUT")
                        .utilitySectionHeader()

                    VStack(alignment: .leading, spacing: 14) {
                        aboutRow

                        LabeledContent("Developer", value: "Suraj Mandal")
                            .font(.system(size: 13))

                        LabeledContent("Contact") {
                            Link("surajmandalcell@gmail.com", destination: URL(string: "mailto:surajmandalcell@gmail.com")!)
                        }
                        .font(.system(size: 13))
                    }
                    .utilitySectionCard()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("OPEN SOURCE")
                        .utilitySectionHeader()

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Cloud Sync engine") {
                            Link("Powered by rclone", destination: URL(string: "https://rclone.org/")!)
                        }
                        .font(.system(size: 13))

                        Text("rclone is independent free and open-source software by Nick Craig-Wood and contributors.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Link("rclone MIT licence", destination: URL(string: "https://rclone.org/licence/")!)
                            .font(.system(size: 11))
                    }
                    .utilitySectionCard()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 12)
        }
    }

    private var aboutRow: some View {
        HStack(spacing: 12) {
            appIcon

            VStack(alignment: .leading, spacing: 2) {
                Text("MacPowerToys")
                    .font(.system(size: 13, weight: .semibold))
                Text("Version \(appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSImage(named: "AppIcon") {
            Image(nsImage: icon)
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .frame(width: Self.iconSize, height: Self.iconSize)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }
        }
    }
}

#Preview {
    AppSettingsSheet()
}
