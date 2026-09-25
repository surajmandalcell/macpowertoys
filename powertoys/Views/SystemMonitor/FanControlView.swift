import SwiftUI

struct FanControlView: View {
    let owner: String
    var compact = false

    @State private var service = FanControlService.shared
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
        guard snapshot.canControl else {
            if service.canRestoreAutomatic { return "Fan helper unavailable · try Auto" }
            if FanCommand.smctlPath != nil {
                return snapshot.fans.contains { $0.mode?.hasPrefix("unknown") == true }
                    ? "Fan control unavailable on this Mac"
                    : "Fan helper unavailable · finish setup"
            }
            return snapshot.hasExternalManualControl
                ? "Manual fan speed set elsewhere · read only"
                : "Read only · install smctl and approve its helper"
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
        .padding(compact ? 10 : 14)
        .background(Color.orange.opacity(compact ? 0.045 : 0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.18 : 0.07))
        }
        .onAppear { service.start(owner: owner) }
        .onDisappear { service.stop(owner: owner) }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                fanIdentity
                Spacer(minLength: 4)
                presetButtons
            }
            if service.errorMessage != nil {
                Text(detail).foregroundStyle(.red)
                    .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
            }
        }
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
                    Link("Set up fan control", destination: URL(string: "https://github.com/leaperone/smctl/releases/latest")!)
                        .font(.system(size: 11))
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
                .foregroundStyle(.orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fan, \(rpm), \(utilization) of maximum speed")
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
}
