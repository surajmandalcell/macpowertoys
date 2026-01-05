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
        .onAppear { applyTheme(AppTheme(rawValue: selectedTheme) ?? .automatic) }
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
    SettingsView()
        .frame(width: 500, height: 400)
}
