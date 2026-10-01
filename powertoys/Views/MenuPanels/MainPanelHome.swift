import OnePlusUI
import SwiftUI

struct TrayHomeView: View {
    let toolIDs: [String]

    var body: some View {
        VStack(spacing: OnePlusMenuMetrics.tileGap) {
            HStack(spacing: OnePlusMenuMetrics.tileGap) {
                TrayHomeActionButton(
                    title: "Pick Color", symbol: ToolGlyph.colorPicker.symbol,
                    enabled: toolIDs.contains("color-picker")
                ) {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: .colorPickerPick))
                }
                TrayHomeActionButton(
                    title: "Extract Text", symbol: ToolGlyph.textExtractor.symbol,
                    enabled: toolIDs.contains("text-extractor")
                ) {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: .textExtractorCapture))
                }
                TrayHomeActionButton(
                    title: "Ruler", symbol: ToolGlyph.ruler.symbol, iconRotation: ToolGlyph.ruler.rotation,
                    enabled: toolIDs.contains("ruler")
                ) {
                    ToolActionRouter.shared.execute(ToolActionRequest(action: .rulerOpen))
                }
            }
            if toolIDs.contains("awake") {
                AwakeTrayRow()
            }
            if SettingsManager.shared.isToolEnabled("system-monitor") {
                FanControlView(owner: "main-tray-home", compact: true)
            }
        }
    }
}

private struct TrayHomeActionButton: View {
    let title: String
    let symbol: String
    var iconRotation = 0.0
    var enabled = true
    let action: () -> Void

    var body: some View {
        OnePlusMenuTile(span: 1, height: 32, textured: false, action: action) {
            Label {
                Text(title).lineLimit(1)
            } icon: {
                Image(systemName: symbol)
                    .rotationEffect(.degrees(iconRotation))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

struct AwakeTrayRow: View {
    @State private var service = AwakeService.shared

    private var quickMode: Binding<AwakeQuickMode?> {
        Binding(
            get: {
                let mode = AwakeQuickMode(configuration: service.configuration)
                return mode == .custom ? nil : mode
            },
            set: { mode in
                guard let mode else { return }
                switch mode {
                case .off: service.setMode(.passive)
                case .thirtyMinutes: service.setMode(.timed, duration: 30 * 60)
                case .oneHour: service.setMode(.timed, duration: 60 * 60)
                case .indefinite: service.setMode(.indefinite)
                case .custom: break
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            OnePlusMenuControlRow("Awake", systemImage: ToolGlyph.awake.symbol, status: status) {
                OnePlusSegmented(
                    choices: [
                        (AwakeQuickMode?.some(.off), "Off"),
                        (AwakeQuickMode?.some(.thirtyMinutes), "30m"),
                        (AwakeQuickMode?.some(.oneHour), "1h"),
                        (AwakeQuickMode?.some(.indefinite), "∞"),
                    ],
                    selection: quickMode
                )
                .accessibilityLabel("Awake duration")
            }
            OnePlusMenuControlRow("Keep display on", systemImage: "display") {
                Toggle("Keep display on", isOn: Binding(
                    get: { service.configuration.keepDisplayOn },
                    set: service.setKeepDisplayOn
                ))
                .labelsHidden()
                .toggleStyle(OnePlusSwitchStyle())
                .accessibilityIdentifier("awake.keep-display-on")
            }
            if let assertionError = service.assertionError {
                Text(assertionError)
                    .onePlusText(.caption)
                    .foregroundStyle(OnePlusColor.danger)
                    .lineLimit(2)
            }
        }
    }

    private var status: String {
        guard service.configuration.mode != .passive else { return "Off" }
        guard let remaining = service.remaining else { return "On" }
        let seconds = max(Int(remaining), 0)
        return String(format: "%d:%02d:%02d left", seconds / 3_600, seconds / 60 % 60, seconds % 60)
    }
}
