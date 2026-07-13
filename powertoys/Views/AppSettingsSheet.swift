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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.automatic.rawValue

    private static let sheetSize = CGSize(width: 460, height: 400)
    private static let iconSize: CGFloat = 44
    private static let iconCornerRadius: CGFloat = 8

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Form {
                Section {
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
                } header: {
                    sectionHeader("Appearance")
                }

                Section {
                    aboutRow

                    LabeledContent("Developer", value: "Suraj Mandal")
                        .font(.system(size: 13))

                    LabeledContent("Contact") {
                        Link("surajmandalcell@gmail.com", destination: URL(string: "mailto:surajmandalcell@gmail.com")!)
                    }
                    .font(.system(size: 13))
                } header: {
                    sectionHeader("About")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
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
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSImage(named: "AppIcon") {
            Image(nsImage: icon)
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
        } else {
            RoundedRectangle(cornerRadius: Self.iconCornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: Self.iconSize, height: Self.iconSize)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .automatic: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

#Preview {
    AppSettingsSheet()
}
