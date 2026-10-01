import AppKit
import OnePlusUI
import ServiceManagement
import SwiftUI

struct FanControlView: View {
    nonisolated private static let presetChoices = FanPreset.allCases.map { (Optional($0), $0.rawValue) }
    let owner: String
    var compact = false

    @State private var service = FanControlService.shared
    @State private var showsSetup = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.onePlusIsVisible) private var isVisible

    private var display: FanControlPresentation { service.display }
    private var detail: String { display.detail }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            if compact { compactContent } else { expandedContent }
        }
        .padding(.horizontal, compact ? 1 : 0)
        .padding(.vertical, 0)
        .background(compact ? Color.clear : TaskManagerTheme.card,
                    in: RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: TaskManagerTheme.panelRadius)
                .strokeBorder(compact ? Color.clear : TaskManagerTheme.line,
                              lineWidth: contrast == .increased ? 1.5 : 1)
        }
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
                    .taskManagerControl()
                    .disabled(display.isChanging)
                    .help("Return fan control to macOS")
            }
            HStack(spacing: 8) {
                if display.needsApproval {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .taskManagerControl(.primary)
                } else if !display.canControl {
                    Button(display.needsHelperUpdate ? "Update Fan Helper" : "Enable Fan Control") {
                        Task { await service.enableControl() }
                    }
                    .taskManagerControl(.primary)
                }
                Button("Check Again") { Task { await service.refresh() } }
                    .taskManagerControl()
            }
            .frame(minHeight: 34)
        }
        .frame(width: 292, alignment: .leading)
        .padding(OnePlusMetrics.spacing[6])
        .foregroundStyle(TaskManagerTheme.ink)
        .background(TaskManagerTheme.card)
        .onePlusFocusPolicy()
        .onePlusAppAppearance()
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            OnePlusCardHeader("Fan", systemImage: "fanblades") {
                Text(display.status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(TaskManagerTheme.secondary)
            }
            OnePlusSettingRow(
                "Fan control",
                controlWidth: 160
            ) {
                HStack(spacing: OnePlusMetrics.spacing[0]) {
                    if display.hasError || (display.hasCompletedRead && !display.canControl) { setupButton }
                    Toggle("Fan control", isOn: fanControlBinding)
                        .labelsHidden()
                        .toggleStyle(OnePlusSwitchStyle())
                        .disabled(display.isChanging)
                        .accessibilityIdentifier("fan-control.enabled")
                }
                .help(detail)
                .accessibilityHint(detail)
            }
            OnePlusSettingRow(
                "Preset",
                controlWidth: 160,
                separator: false
            ) {
                presetButtons
            }
        }
    }

    private var fanControlBinding: Binding<Bool> {
        Binding(
            get: { display.selectedPreset != nil && display.selectedPreset != .auto },
            set: { enabled in
                if enabled {
                    if display.canControl { service.select(.cool) }
                    else { showsSetup = true }
                } else if display.canControl || display.canRestoreAutomatic {
                    service.select(.auto)
                }
            }
        )
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
