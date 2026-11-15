import AppKit
import OnePlusUI
import ServiceManagement
import SwiftUI

struct FanControlView: View {
    nonisolated private static let presetChoices = FanPreset.allCases.map { (Optional($0), $0.rawValue) }
    let owner: String

    @State private var service = FanControlService.shared
    @State private var showsSetup = false
    @Environment(\.onePlusIsVisible) private var isVisible

    private var display: FanControlPresentation { service.display }
    private var detail: String { display.detail }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            compactContent
        }
        .padding(.horizontal, 1)
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

    private var compactContent: some View {
        OnePlusMenuControlRow("Fan", systemImage: "fanblades", status: compactStatus) {
            HStack(spacing: 2) {
                if display.hasError || (display.hasCompletedRead && !display.canControl) {
                    setupButton
                }
                presetButtons
            }
        }
        .accessibilityHint(detail)
    }

    private var compactStatus: String {
        display.status
    }

    private var setupButton: some View {
        Button { showsSetup = true } label: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(OnePlusColor.warn)
        }
        .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
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
            Text("Enable the helper, then allow MacPowerToys under Background App Activity in Login Items.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if display.canRestoreAutomatic && !display.canControl {
                Button("Restore Auto") { service.select(.auto) }
                    .onePlusControl()
                    .disabled(display.isChanging)
                    .help("Return fan control to macOS")
            }
            HStack(spacing: 8) {
                if display.needsApproval {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .onePlusControl(.primary)
                } else if !display.canControl {
                    Button(display.needsHelperUpdate ? "Update Fan Helper" : "Enable Fan Control") {
                        Task { await service.enableControl() }
                    }
                    .onePlusControl(.primary)
                }
                Button("Check Again") { Task { await service.refresh() } }
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

    private var presetBinding: Binding<FanPreset?> {
        Binding(
            get: { activePreset },
            set: { if let preset = $0 { service.select(preset) } }
        )
    }

    private var presetButtons: some View {
        OnePlusSegmented(
            choices: Self.presetChoices,
            selection: presetBinding,
            accessibilityLabel: "Fan preset",
            isChoiceEnabled: { display.canSelect($0) }
        )
        .onePlusDensity(.compact)
        .disabled(display.isChanging)
        .help("Auto follows macOS. Cool boosts cooling for 10 minutes. Max runs fans at their hardware maximum.")
    }
}
