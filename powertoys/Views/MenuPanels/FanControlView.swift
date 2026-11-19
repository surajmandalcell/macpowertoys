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
        MainPanelFanRow(status: display.rpm, selection: presetBinding,
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
        .popover(isPresented: $showsSetup, arrowEdge: .bottom) { setupPopover }
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
            if display.canInstallHelper {
                Text("Fan control uses a small helper. macOS asks for your password once to install it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if display.canRestoreAutomatic && !display.canControl {
                Button("Restore Auto") { service.select(.auto) }
                    .onePlusControl()
                    .disabled(display.isChanging)
                    .help("Return fan control to macOS")
            }
            HStack(spacing: 8) {
                if display.canInstallHelper {
                    Button("Install Helper") {
                        Task { await service.enableControl() }
                    }
                    .onePlusControl(.primary)
                    .disabled(display.isChanging)
                }
                Button("Check Again") {
                    Task {
                        await PermissionCenter.shared.refresh()
                        await service.refresh()
                    }
                }
                    .onePlusControl()
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

/// The Fan row: RPM and the Auto, Cool, Max control. Only a click on a choice changes `selection`.
struct MainPanelFanRow<Setup: View>: View {
    private static var choices: [(FanPreset?, String)] { FanPreset.allCases.map { (Optional($0), $0.rawValue) } }
    let status: String
    @Binding var selection: FanPreset?
    let isChoiceEnabled: (FanPreset) -> Bool
    @ViewBuilder let setup: Setup

    var body: some View {
        OnePlusLinearControlRow("Fan", systemImage: "fanblades", status: status) {
            HStack(spacing: 4) {
                setup
                OnePlusLinearSegmented(choices: Self.choices, selection: $selection, accessibilityLabel: "Fan preset",
                                       isChoiceEnabled: { $0.map(isChoiceEnabled) ?? false })
                    .help("Auto follows macOS. Cool boosts cooling for 10 minutes. Max runs fans at their hardware maximum.")
            }
        }
    }
}
