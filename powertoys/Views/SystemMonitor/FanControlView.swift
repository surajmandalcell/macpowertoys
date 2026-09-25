import AppKit
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
        .padding(.leading, compact ? TrayPopoverLayout.horizontalInset + 4 : 14)
        .padding(.trailing, compact ? TrayPopoverLayout.horizontalInset : 14)
        .padding(.vertical, compact ? 8 : 14)
        .background(compact ? Color.clear : Color.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(compact ? Color.clear : Color.primary.opacity(contrast == .increased ? 0.18 : 0.07))
        }
        .onAppear { service.start(owner: owner) }
        .onDisappear { service.stop(owner: owner) }
        .onChange(of: service.canControl) { _, canControl in
            if canControl { showsSetup = false }
        }
        .popover(isPresented: $showsSetup, arrowEdge: .bottom) { setupPopover }
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            fanIdentity
            Spacer(minLength: 4)
            if service.errorMessage != nil || (service.hasCompletedRead && !service.canControl) {
                Button { showsSetup = true } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colorScheme == .light ? Color(red: 0.64, green: 0.32, blue: 0) : Color.orange)
                        .frame(width: 28, height: 28)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 7))
                .accessibilityLabel(service.errorMessage == nil ? "Set up fan control" : "Fan control issue")
                .accessibilityHint(detail)
                .accessibilityIdentifier("fan-control.setup")
                .help(detail)
            }
            compactPresets
        }
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
                        .buttonStyle(.borderedProminent)
                } else if !service.canControl {
                    Button(service.needsHelperUpdate ? "Update Fan Helper" : "Enable Fan Control") {
                        Task { await service.enableControl() }
                    }
                        .buttonStyle(.borderedProminent)
                }
                Button("Check Again") { Task { await service.refresh() } }
                    .buttonStyle(.bordered)
            }
            .controlSize(.regular)
            .frame(minHeight: 34)
        }
        .frame(width: 292, alignment: .leading)
        .padding(15)
    }

    private var expandedContent: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Label("Fan", systemImage: "fanblades")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rpm)
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .utilityAnimation(value: rpm)
                    Text(utilization + " of max")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .utilityAnimation(value: utilization)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(service.errorMessage == nil ? Color.secondary : Color.red)
            }
            Spacer(minLength: 8)
            if let load = service.snapshot?.utilization { speedMeter(load) }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 10) {
                presetButtons
                if !service.canControl && (service.isAvailable || service.snapshot == nil)
                    && !(service.snapshot?.fans.contains { $0.mode?.hasPrefix("unknown") == true } ?? false) {
                    Button("Enable fan control") { showsSetup = true }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
        }
    }

    private func speedMeter(_ load: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.orange.opacity(0.72))
                    .frame(width: proxy.size.width * CGFloat(load) / 100)
                    .utilityAnimation(value: load)
            }
        }
        .frame(width: 170, height: 4)
        .padding(.top, 32)
        .accessibilityHidden(true)
    }

    private var fanIdentity: some View {
        HStack(spacing: 7) {
            Image(systemName: "fanblades")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.84))
                .frame(width: 16)
            Text("Fan")
                .font(.system(size: 12, weight: .medium))
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
                    .padding(.horizontal, 8)
                    .frame(minHeight: 26)
                    .background(
                        service.selectedPreset == preset ? Color.orange.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .buttonStyle(UtilityInteractionButtonStyle(cornerRadius: 6))
                    .disabled(service.isChanging || !(service.canControl ||
                              (preset == .auto && service.canRestoreAutomatic)))
                    .accessibilityLabel("Fan \(preset.rawValue)")
                    .accessibilityAddTraits(service.selectedPreset == preset ? .isSelected : [])
                    .help(preset == .cool ? "Maximum cooling for 10 minutes, then Auto" :
                          preset == .max ? "Run fans at their hardware maximum" : "Return fan control to macOS")
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .utilityAnimation(value: service.selectedPreset)
    }

    @ViewBuilder
    private var compactPresets: some View {
        if service.canRestoreAutomatic && !service.canControl {
            Button("Auto") { service.select(.auto) }
                .controlSize(.small)
                .disabled(service.isChanging)
                .help("Return fan control to macOS")
        } else {
            Picker("Fan speed", selection: Binding<FanPreset?>(
                get: { service.selectedPreset },
                set: { if let preset = $0 { service.select(preset) } }
            )) {
                ForEach(FanPreset.allCases) { preset in
                    Text(preset.rawValue).tag(Optional(preset))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 158)
            .disabled(service.isChanging || !service.canControl)
        }
    }
}
