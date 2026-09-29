import AppKit
import OnePlusUI
import ServiceManagement
import SwiftUI

struct FanControlView: View {
    let owner: String
    var compact = false

    @State private var service = FanControlService.shared
    @State private var showsSetup = false
    @Environment(\.colorScheme) private var colorScheme
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
        OnePlusMenuControlRow("Fan", systemImage: "fanblades", status: "\(rpm) · \(utilization)") {
            HStack(spacing: 2) {
                if service.errorMessage != nil || (service.hasCompletedRead && !service.canControl) {
                    Button { showsSetup = true } label: {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(colorScheme == .light ? OnePlusColor.warn : OnePlusColor.accent)
                    }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
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
                caption: service.selectedPreset?.rawValue ?? "No MacPowerToys preset",
                controlWidth: 160,
                separator: false
            ) {
                presetButtons
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

    private var fanIdentity: some View {
        HStack(spacing: 7) {
            Image(systemName: "fanblades")
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .foregroundStyle(TaskManagerTheme.secondary)
                .frame(width: compact ? 13 : 16)
            Text("Fan")
                .font(.system(size: compact ? 10 : 12, weight: .medium))
            Text("\(rpm) · \(utilization)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .utilityAnimation(value: rpm + utilization)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fan, \(rpm), \(utilization) of maximum speed")
        .accessibilityHint(detail)
        .help(detail)
    }

    private var presetButtons: some View {
        HStack(spacing: 3) {
            ForEach(FanPreset.allCases) { preset in
                Button(preset.rawValue) { service.select(preset) }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(service.selectedPreset == preset ? Color.primary : Color.secondary)
                    .padding(.horizontal, compact ? 5 : 8)
                    .frame(maxWidth: compact ? .infinity : nil, minHeight: compact ? 20 : 26)
                    .background(
                        service.selectedPreset == preset ? Color.white.opacity(0.11) : .clear,
                        in: RoundedRectangle(cornerRadius: compact ? 3 : 6)
                    )
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .disabled(service.isChanging || !(service.canControl ||
                              (preset == .auto && service.canRestoreAutomatic)))
                    .accessibilityLabel("Fan \(preset.rawValue)")
                    .accessibilityAddTraits(service.selectedPreset == preset ? .isSelected : [])
                    .help(preset == .cool ? "Maximum cooling for 10 minutes, then Auto" :
                          preset == .max ? "Run fans at their hardware maximum" : "Return fan control to macOS")
            }
        }
        .frame(width: compact ? 118 : 160)
        .padding(2)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: compact ? 5 : 6))
        .overlay { RoundedRectangle(cornerRadius: compact ? 5 : 6)
            .strokeBorder(compact ? TaskManagerTheme.lineSoft : Color.clear) }
        .utilityAnimation(value: service.selectedPreset)
    }
}
