import OnePlusUI
import SwiftUI

struct SystemCareSettingsContent: View {
    @Binding var mode: SystemCareMode

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader("Cleanup", systemImage: "sparkles")
            OnePlusSettingRow(
                "Default mode",
                caption: "Guided mode lets you choose categories. Analysis Only cannot remove items.",
                separator: false
            ) {
                OnePlusSelect(
                    choices: SystemCareMode.allCases.map { ($0, $0.rawValue) },
                    selection: $mode,
                    accessibilityLabel: "Default cleanup mode"
                )
            }
        }
        OnePlusCard {
            OnePlusCardHeader("Safety", systemImage: "lock.shield")
            OnePlusSettingRow("Native cleanup", caption: "Moves reviewed items to macOS Trash.", separator: false) {
                OnePlusStatus("Recoverable", state: .success)
            }
            OnePlusSettingRow("Symbolic links", caption: "Never followed while size is calculated.", separator: false) {
                OnePlusStatus("Protected", state: .success)
            }
            OnePlusSettingRow("Mole privileges", caption: "Requests appear only in a visible Terminal.", separator: false) {
                OnePlusStatus("Visible", state: .success)
            }
        }
    }
}

struct AwakePreferencesView: View {
    @State private var service = AwakeService.shared
    @State private var presetMinutes = 30

    var body: some View {
        OnePlusCard {
            OnePlusCardHeader("Display")
            OnePlusSettingRow("Keep display on", separator: false) {
                Toggle("Keep display on", isOn: Binding(
                    get: { service.configuration.keepDisplayOn }, set: service.setKeepDisplayOn
                )).labelsHidden().toggleStyle(OnePlusSwitchStyle())
            }
        }
        OnePlusCard {
            OnePlusCardHeader("Duration presets", systemImage: "clock")
            ForEach(service.configuration.presets, id: \.self) { seconds in
                OnePlusSettingRow(AwakeService.presetLabel(seconds)) {
                    Button("Remove") {
                        service.setPresets(service.configuration.presets.filter { $0 != seconds })
                    }
                    .buttonStyle(OnePlusButtonStyle(.ghost))
                    .accessibilityLabel("Remove \(AwakeService.presetLabel(seconds)) preset")
                }
            }
            OnePlusSettingRow("New preset", caption: "Save up to eight durations.", separator: false) {
                HStack(spacing: OnePlusMetrics.actionSpacing) {
                    OnePlusStepperField("Preset minutes", value: $presetMinutes, in: 1...10_080, unit: "min")
                    Button("Add") {
                        service.setPresets(service.configuration.presets + [TimeInterval(presetMinutes * 60)])
                    }
                    .buttonStyle(OnePlusButtonStyle())
                    .disabled(service.configuration.presets.count >= 8
                        || service.configuration.presets.contains(TimeInterval(presetMinutes * 60)))
                }
            }
        }
    }
}
