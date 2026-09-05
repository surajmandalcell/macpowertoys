import SwiftUI

enum InputControlState {
    case disabled
    case permissionNeeded
    case passthrough
    case active

    static func state(
        settings: InputDevicesSettings,
        permissionGranted: Bool,
        kind: InputDeviceDescriptor.Kind
    ) -> InputControlState {
        guard settings.scrollControlEnabled else { return .disabled }
        guard permissionGranted else { return .permissionNeeded }
        let profile = kind == .mouse ? settings.mouse : settings.trackpad
        return profile.enabled ? .active : .passthrough
    }

    var title: String {
        switch self {
        case .disabled: "Not controlled"
        case .permissionNeeded: "Permission needed"
        case .passthrough: "Passthrough"
        case .active: "Controlled"
        }
    }

    var icon: String {
        switch self {
        case .disabled: "circle.dashed"
        case .permissionNeeded: "exclamationmark.triangle.fill"
        case .passthrough: "arrow.right"
        case .active: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .disabled, .passthrough: .secondary
        case .permissionNeeded: .orange
        case .active: .green
        }
    }
}

struct InputStateBadge: View {
    let state: InputControlState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.icon).font(.system(size: 10))
            Text(state.title).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(state.tint.opacity(0.12)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

private struct InputCardSurface<Content: View>: View {
    @State private var isHovering = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(UtilityLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(isHovering ? 0.06 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
        .utilityAnimation(value: isHovering)
    }
}

private struct InputCardHeader: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .frame(height: 30)
    }
}

struct InputDeviceCard: View {
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 82

    let device: InputDeviceDescriptor
    let profile: InputScrollProfile
    let state: InputControlState

    var body: some View {
        InputCardSurface {
            HStack(alignment: .top, spacing: 10) {
                InputCardHeader(
                    icon: device.kind.icon,
                    title: device.name,
                    detail: device.isBuiltIn ? "\(device.kind.rawValue) · Built in" : device.kind.rawValue
                )
                InputStateBadge(state: state)
            }
            QuietDivider()
            ForEach(rows, id: \.label) { row in
                detailRow(row)
            }
        }
    }

    private struct Row {
        let label: String
        let value: String?
        var monospaced = false
    }

    private var rows: [Row] {
        [
            Row(label: "Connection", value: device.transport),
            Row(label: "Maker", value: device.manufacturer.flatMap { $0.isEmpty ? nil : $0 }),
            Row(label: "Tracking", value: device.systemTrackingSpeed?.formatted(.number.precision(.fractionLength(2)))),
            Row(label: "Scroll speed", value: profile.speed.formatted(.number.precision(.fractionLength(2))) + "×"),
            Row(label: "Resolution", value: device.pointerResolutionDPI.map {
                $0.formatted(.number.precision(.fractionLength(0))) + " dpi"
            }),
            Row(label: "Polling", value: device.pollingRateHz.map {
                $0.formatted(.number.precision(.fractionLength(0))) + " Hz"
            }),
            Row(label: "Buttons", value: device.buttonCount.flatMap { $0 > 0 ? $0.formatted() : nil }),
            Row(
                label: "Device ID",
                value: String(format: "%04X:%04X", device.vendorID, device.productID),
                monospaced: true
            ),
            Row(
                label: "Location",
                value: device.locationID > 0 ? String(format: "0x%08X", device.locationID) : nil,
                monospaced: true
            ),
            Row(
                label: "Firmware",
                value: device.versionNumber.map { String(format: "0x%04X", $0) },
                monospaced: true
            ),
            Row(label: "Input report", value: device.maxInputReportSize.flatMap { $0 > 0 ? "\($0) bytes" : nil }),
            Row(
                label: "Serial",
                value: device.serialNumber.flatMap { $0.isEmpty ? nil : $0 },
                monospaced: true
            )
        ]
    }

    private func detailRow(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            Text(row.value ?? "—")
                .font(row.monospaced && row.value != nil
                    ? .system(size: 11, design: .monospaced)
                    : .system(size: 11))
                .foregroundStyle(row.value == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label): \(row.value ?? "Not reported")")
    }
}

struct InputSettingRow<Control: View>: View {
    let label: String
    var help: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 12)
            control
                .labelsHidden()
                .accessibilityLabel(label)
        }
        .frame(minHeight: 22)
        .help(help ?? label)
    }
}

struct InputScrollProfileCard: View {
    let title: String
    let icon: String
    let deviceCount: Int
    @Binding var profile: InputScrollProfile

    var body: some View {
        InputCardSurface {
            HStack(alignment: .top, spacing: 10) {
                InputCardHeader(icon: icon, title: title, detail: deviceDetail)
                Toggle("Use this profile", isOn: $profile.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Use the \(title) profile")
                    .help("Apply this profile to \(title.lowercased()) scroll events.")
            }
            QuietDivider()
            settingRows
        }
        .controlSize(.small)
        .utilityAnimation(value: profile)
    }

    @ViewBuilder
    private var settingRows: some View {
        Group {
            InputSettingRow(
                label: "Scroll speed",
                help: "Multiply every scroll delta from this device kind."
            ) {
                HStack(spacing: 8) {
                    Slider(value: $profile.speed, in: 0.35...3, step: 0.05)
                    Text(profile.speed.formatted(.number.precision(.fractionLength(2))) + "×")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 42, alignment: .trailing)
                }
            }
            InputSettingRow(
                label: "Reverse vertical",
                help: "Invert up and down scrolling for this device kind."
            ) {
                Toggle("Reverse vertical", isOn: $profile.reverseVertical)
            }
            InputSettingRow(
                label: "Horizontal scrolling",
                help: "Pass horizontal scroll through. Turn it off to block sideways movement."
            ) {
                Toggle("Horizontal scrolling", isOn: $profile.horizontalEnabled)
            }
            InputSettingRow(
                label: "Reverse horizontal",
                help: "Invert left and right scrolling. Needs horizontal scrolling."
            ) {
                Toggle("Reverse horizontal", isOn: $profile.reverseHorizontal)
            }
            .disabled(!profile.horizontalEnabled)
            InputSettingRow(
                label: "Smooth wheel steps",
                help: "Split a coarse wheel notch into small steps. Continuous scrolling is unchanged."
            ) {
                Toggle("Smooth wheel steps", isOn: $profile.smooth)
            }
        }
        .disabled(!profile.enabled)
    }

    private var deviceDetail: String {
        switch deviceCount {
        case 0: "No device connected"
        case 1: "1 device connected"
        default: "\(deviceCount) devices connected"
        }
    }
}
