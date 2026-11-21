import AppKit
import OnePlusUI
import SwiftUI

struct FanControlView: View {
    let owner: String

    @State private var service = FanControlService.shared
    @State private var showsSetup = false
    @Environment(\.onePlusIsVisible) private var isVisible

    private var display: FanControlPresentation { service.display }
    private var detail: String { display.detail }

    var body: some View {
        MainPanelFanRow(status: display.rpm, cpuCelsius: display.cpuCelsius, inputName: display.inputName, selection: presetBinding,
                                isChoiceEnabled: { !display.isChanging && display.canSelect($0) }) {
            if display.hasError || (display.hasCompletedRead && !display.canControl) {
                setupButton
            }
        }
        .accessibilityHint(detail)
        .onChange(of: isVisible, initial: true) {
            if isVisible { service.start(owner: owner) }
            else {
                service.stop(owner: owner)
                showsSetup = false
            }
        }
        .onDisappear { service.stop(owner: owner) }
        .onChange(of: display.canControl) { _, canControl in
            if canControl { showsSetup = false }
        }
        .popover(isPresented: $showsSetup, arrowEdge: .bottom) { setupPopover.onePlusFocusPolicy() }
    }

    private static let glyphOpticalOffset: CGFloat = 0.5

    private var setupButton: some View {
        Button { showsSetup = true } label: {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: OnePlusLinearMetrics.caption))
                .foregroundStyle(OnePlusColor.warn)
                // The symbol box sits 0.5 pt above the row's cap center; this centers its ink on the "Fan" caps.
                .offset(y: Self.glyphOpticalOffset)
                .frame(width: OnePlusLinearMetrics.segment.height + 4, height: OnePlusLinearMetrics.segment.height + 4)
        }
        .buttonStyle(OnePlusLinearButtonStyle())
        .accessibilityLabel(!display.hasError ? "Set up fan control" : "Fan control issue")
        .accessibilityHint(detail)
        .accessibilityIdentifier("fan-control.setup")
        .help(detail)
    }

    private var setupPopover: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[5]) {
            Label(!display.hasError ? "Enable fan control" : "Fan control issue", systemImage: "fanblades")
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if display.canRestoreAutomatic && !display.canControl {
                    Button("Restore Auto") { service.select(.auto) }
                        .onePlusControl()
                        .disabled(display.isChanging)
                        .help("Return fan control to macOS")
                }
                Button("Retry") {
                    showsSetup = false
                    service.retry()
                }
                .onePlusControl(.primary)
                .disabled(display.isChanging)
            }
            .frame(minHeight: 34)
        }
        .frame(width: 292, alignment: .leading)
        .padding(OnePlusMetrics.spacing[6])
        .foregroundStyle(OnePlusTheme.ink)
        .background(OnePlusTheme.card)
        .onePlusFocusPolicy()
        .onePlusAppAppearance()
    }

    private var activePreset: FanPreset? {
        display.activePreset
    }

    nonisolated static func reportedPreset(_ snapshot: FanSnapshot?, selectedPreset: FanPreset?) -> FanPreset? {
        FanControlPresentation.reportedPreset(snapshot, selectedPreset: selectedPreset)
    }

    /// Only a user choice writes: reading the binding never selects, and a choice the helper cannot apply does nothing.
    private var presetBinding: Binding<FanPreset?> {
        Binding(
            get: { activePreset },
            set: { if let preset = $0, display.canSelect(preset) { service.select(preset) } }
        )
    }

}

/// The Fan row: RPM, the CPU thermometer, and the Auto, Cool, Max control. Cool reads "Custom" while the Fan page
/// follows the user's own edited curve. Only a click on a choice changes `selection`.
struct MainPanelFanRow<Setup: View>: View {
    let status: String
    var cpuCelsius: Int?
    var inputName = FanInput.cpuName
    @Binding var selection: FanPreset?
    let isChoiceEnabled: (FanPreset) -> Bool
    @ViewBuilder let setup: Setup
    @AppStorage(FanCurve.storageKey) private var curveData: Data?
    @AppStorage(FanCurvePreset.storageKey) private var presetName: String?
    @AppStorage(FanHold.storageKey) private var holdCelsius: Double?
    /// The clicked choice, shown at once while the helper applies it; cleared when the service reports back.
    @State private var requested: FanPreset?

    private var shownSelection: Binding<FanPreset?> {
        Binding(get: { requested ?? selection }, set: { requested = $0; selection = $0 })
    }

    private var isCustom: Bool { curveData != nil && presetName == nil && holdCelsius == nil }

    private var choices: [(FanPreset?, String)] {
        FanPreset.allCases.map { (Optional($0), $0 == .cool && isCustom ? "Custom" : $0.rawValue) }
    }

    var body: some View {
        // No fixed title width: "Fan" is short, and the room keeps the RPM whole beside the fitted segments.
        OnePlusLinearControlRow("Fan", systemImage: "fanblades", status: status, titleWidth: nil) {
            HStack(spacing: 4) {
                setup
                if let cpuCelsius { CPUThermometer(celsius: cpuCelsius, name: inputName) }
                OnePlusLinearSegmented(choices: choices, selection: shownSelection, accessibilityLabel: "Fan preset",
                                       sizing: .snug, isChoiceEnabled: { $0.map(isChoiceEnabled) ?? false || $0 == requested })
                    .onChange(of: selection) { requested = nil }
                    .task(id: requested) {
                        // A command that fails never reports back, so the pill returns to the real state.
                        guard requested != nil else { return }
                        try? await Task.sleep(for: .seconds(3))
                        requested = nil
                    }
                    .help(isCustom
                          ? "Auto follows macOS. Custom follows your curve on the Fan page. Max runs fans at their hardware maximum."
                          : "Auto follows macOS. Cool follows the pick on the Fan page, full speed at an 80 °C CPU average. Max runs fans at their hardware maximum.")
            }
        }
    }
}

/// A thermometer tinted by `CPUHeat`: gray while the CPU is at normal temperatures, then yellow, orange, and red.
struct CPUThermometer: View {
    let celsius: Int
    var name = FanInput.cpuName

    var body: some View {
        Image(systemName: "thermometer.medium")
            .font(.system(size: OnePlusLinearMetrics.caption + 1, weight: .medium))
            .foregroundStyle(Self.color(CPUHeat(celsius: Double(celsius))))
            .frame(width: OnePlusLinearMetrics.segment.height - 4, height: OnePlusLinearMetrics.segment.height)
            .help(CPUHeat.help(celsius, name: name))
            .accessibilityLabel(CPUHeat.help(celsius, name: name))
    }

    static func color(_ heat: CPUHeat) -> Color {
        switch heat {
        case .normal: OnePlusLinearColor.panelMuted
        case .warm: OnePlusLinearColor.temperatureWarm
        case .hot: OnePlusLinearColor.temperatureHot
        case .veryHot: OnePlusLinearColor.temperatureVeryHot
        case .nearLimit: OnePlusLinearColor.temperatureCritical
        }
    }
}
