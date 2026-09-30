import AppKit
import OnePlusUI
import ServiceManagement
import SwiftUI

struct FanControlView: View {
    let owner: String
    var compact = false

    @State private var service = FanControlService.shared
    @State private var showsSetup = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var rpm: String {
        service.snapshot?.averageRPM.map { $0.formatted() + " RPM" } ?? "— RPM"
    }

    private var utilization: String {
        service.snapshot?.utilization.map { "\($0)%" } ?? "—%"
    }

    private var detail: String {
        if let error = service.errorMessage { return error }
        guard let snapshot = service.snapshot else { return "Fan data unavailable" }
        guard !snapshot.fans.isEmpty else { return "No fans detected" }
        if service.selectedPreset == nil, snapshot.hasExternalManualControl {
            return service.canRestoreAutomatic
                ? "Manual fan speed set elsewhere · Auto restores macOS"
                : "Manual fan speed set elsewhere · read only"
        }
        if activePreset == .auto { return "Auto follows macOS" }
        guard service.canControl else {
            if service.canRestoreAutomatic {
                return snapshot.hasExternalManualControl
                    ? "Manual control active · Auto restores macOS"
                    : "Fan helper unavailable · try Auto"
            }
            if service.needsApproval { return "Allow MacPowerToys in Login Items" }
            if service.needsHelperUpdate { return "Update the built-in fan helper" }
            if snapshot.fans.contains(where: { $0.mode?.hasPrefix("unknown") == true }) {
                return "Fan control unavailable on this Mac"
            }
            return snapshot.hasExternalManualControl
                ? "Manual fan speed set elsewhere · read only"
                : "Read only · enable built-in fan control"
        }
        switch service.selectedPreset {
        case .auto: return "Controlled by macOS"
        case .cool: return "Cooling boost · Auto in 10 minutes"
        case .max: return "Maximum cooling"
        case nil: return "Manual control active"
        }
    }

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
        .onAppear { service.start(owner: owner) }
        .onDisappear { service.stop(owner: owner) }
        .onChange(of: service.canControl) { _, canControl in
            if canControl { showsSetup = false }
        }
        .popover(isPresented: $showsSetup, arrowEdge: .bottom) { setupPopover }
    }

    private var compactContent: some View {
        OnePlusMenuControlRow("Fan", systemImage: "fanblades", status: compactStatus) {
            HStack(spacing: 2) {
                if service.errorMessage != nil || (service.hasCompletedRead && !service.canControl) {
                    Button("Set up") { showsSetup = true }
                    .buttonStyle(OnePlusButtonStyle(.ghost, size: .small))
                    .accessibilityLabel(service.errorMessage == nil ? "Set up fan control" : "Fan control issue")
                    .accessibilityHint(detail)
                    .accessibilityIdentifier("fan-control.setup")
                    .help(detail)
                }
                presetButtons
            }
        }
        .accessibilityHint(detail)
    }

    private var compactStatus: String {
        if service.errorMessage != nil { return "Fan issue" }
        if service.hasCompletedRead && !service.canControl {
            if service.needsApproval { return "Approval needed" }
            if service.needsHelperUpdate { return "Update needed" }
            return "Helper needed"
        }
        return "\(rpm) · \(utilization)"
    }

    private var setupPopover: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(service.errorMessage == nil ? "Enable fan control" : "Fan control issue", systemImage: "fanblades")
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("MacPowerToys includes fan control. macOS may ask you to allow its background item once; there is no package or Terminal command to install.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if service.needsApproval {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .taskManagerControl(.primary)
                } else if !service.canControl {
                    Button(service.needsHelperUpdate ? "Update Fan Helper" : "Enable Fan Control") {
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
        .padding(15)
        .foregroundStyle(TaskManagerTheme.ink)
        .background(TaskManagerTheme.card)
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            OnePlusCardHeader("Fan", systemImage: "fanblades") {
                Text("\(rpm) · \(utilization)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(TaskManagerTheme.secondary)
            }
            OnePlusSettingRow(
                "Fan control",
                caption: detail,
                controlWidth: 160
            ) {
                Toggle("Fan control", isOn: fanControlBinding)
                    .labelsHidden()
                    .toggleStyle(OnePlusSwitchStyle())
                    .disabled(service.isChanging)
                    .accessibilityIdentifier("fan-control.enabled")
            }
            OnePlusSettingRow(
                "Preset",
                caption: manualControlEnabled ? service.selectedPreset?.rawValue : "Turn on fan control to choose a preset",
                controlWidth: 160,
                separator: false
            ) {
                presetButtons
                    .disabled(!manualControlEnabled)
            }
        }
    }

    private var fanControlBinding: Binding<Bool> {
        Binding(
            get: { service.selectedPreset != nil && service.selectedPreset != .auto },
            set: { enabled in
                if enabled {
                    if service.canControl { service.select(.cool) }
                    else { showsSetup = true }
                } else if service.canControl || service.canRestoreAutomatic {
                    service.select(.auto)
                }
            }
        )
    }

    private var manualControlEnabled: Bool {
        service.selectedPreset != nil && service.selectedPreset != .auto
    }

    private var activePreset: FanPreset? {
        Self.reportedPreset(service.snapshot, selectedPreset: service.selectedPreset)
    }

    nonisolated static func reportedPreset(_ snapshot: FanSnapshot?, selectedPreset: FanPreset?) -> FanPreset? {
        if let selectedPreset { return selectedPreset }
        guard let snapshot, !snapshot.fans.isEmpty else { return nil }
        if let detected = snapshot.detectedPreset { return detected }
        return snapshot.fans.allSatisfy { ["auto", "system"].contains($0.mode?.lowercased() ?? "") } ? .auto : nil
    }

    private var presetBinding: Binding<FanPreset?> {
        Binding(
            get: { activePreset },
            set: { if let preset = $0 { service.select(preset) } }
        )
    }

    @ViewBuilder
    private var presetButtons: some View {
        if compact && !service.canControl && service.canRestoreAutomatic {
            Button("Auto") { service.select(.auto) }
                .buttonStyle(OnePlusButtonStyle(.neutral, size: .small))
                .disabled(service.isChanging)
                .accessibilityLabel("Fan Auto")
                .help("Return fan control to macOS")
        } else {
            OnePlusSegmented(
                choices: FanPreset.allCases.map { (Optional($0), $0.rawValue) },
                selection: presetBinding,
                accessibilityLabel: "Fan preset"
            )
            .onePlusDensity(.compact)
            .disabled(service.isChanging || !service.canControl)
            .help("Auto follows macOS. Cool boosts cooling for 10 minutes. Max runs fans at their hardware maximum.")
            .accessibilityRepresentation {
                Picker("Fan preset", selection: presetBinding) {
                    ForEach(FanPreset.allCases) { preset in
                        Text("Fan \(preset.rawValue)").tag(Optional(preset))
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}
