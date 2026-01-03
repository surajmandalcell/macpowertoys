//
//  SettingsView.swift
//  powertoys
//
//  Created by Suraj Mandal on 2026-01-02.
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .automatic: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

struct SettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.automatic.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Customize your PowerToys experience")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Appearance Section
                VStack(alignment: .leading, spacing: 16) {
                    Label("Appearance", systemImage: "paintbrush")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Theme", selection: $selectedTheme) {
                            ForEach(AppTheme.allCases) { theme in
                                Label(theme.rawValue, systemImage: theme.icon)
                                    .tag(theme.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                        .onChange(of: selectedTheme) { _, newValue in
                            applyTheme(AppTheme(rawValue: newValue) ?? .automatic)
                        }

                        Text("Choose how PowerToys appears on your Mac")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                // Credits Section - Compact horizontal layout
                VStack(alignment: .leading, spacing: 12) {
                    Label("About", systemImage: "info.circle")
                        .font(.headline)

                    HStack(spacing: 16) {
                        Image(systemName: "wrench.adjustable.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("PowerToys")
                                    .font(.headline)
                                Text("v1.0")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 4) {
                                Text("by")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text("Suraj Mandal")
                                    .font(.caption)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Link("surajmandalcell@gmail.com", destination: URL(string: "mailto:surajmandalcell@gmail.com")!)
                                    .font(.caption)
                            }
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: 600)
        .onAppear {
            applyTheme(AppTheme(rawValue: selectedTheme) ?? .automatic)
        }
    }

    private func applyTheme(_ theme: AppTheme) {
        switch theme {
        case .automatic:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 600, height: 500)
}
