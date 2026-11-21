import OnePlusUI
import SwiftUI

/// The Portman Forward tab parts (DESIGN.md "Portman"): every control is a 28 pt raised-keys control, every
/// right-hand key and local-port field shares one column, and each block is one Fill steps group.
enum PortmanForwardMetrics {
    /// Raised keys pad their label 12 pt on each side, so a 64 pt label makes the 88 pt column.
    static let keyLabel: CGFloat = 64
    static let column: CGFloat = keyLabel + 24
    static let hostSelect: CGFloat = 76
    static let rowHeight: CGFloat = 40
}

extension View {
    /// The Forward tab controls: the panel's soft-key family (sunken wells, raised keys), all 28 pt, radius 7.
    func portmanForwardLook() -> some View {
        environment(\.onePlusLinearControlLook, .raisedKeys).onePlusLinearMotion(.quiet)
    }
}

/// A raised key in the shared right-hand column.
struct PortmanForwardKey: View {
    private let title: String
    private let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) { Text(title).lineLimit(1).frame(width: PortmanForwardMetrics.keyLabel) }
            .buttonStyle(OnePlusLinearButtonStyle(.soft))
    }
}

/// A 40 pt row inside a Forward group, on the panel row inset.
struct PortmanForwardRow<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        HStack(spacing: OnePlusLinearMetrics.rowGap) { content }
            .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
            .frame(minHeight: PortmanForwardMetrics.rowHeight)
    }
}

/// The status line at the top of a Forward group, such as "oc1 · 28 ports".
struct PortmanForwardStatus: View {
    private let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).linearText(OnePlusLinearMetrics.control, weight: .medium, color: OnePlusLinearColor.secondary)
            .lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The input group: the SSH host with its saved hosts and Scan, then a manual remote port and Add port.
/// While a scan runs, Scan becomes Cancel in the same column; the spinner lives on the top-bar gear.
struct PortmanForwardInputs: View {
    @Binding var host: String
    @Binding var manualPort: String
    @Binding var mode: PortmanHostMode
    let aliases: [String]
    let scanning: Bool
    let scan: () -> Void
    let cancel: () -> Void
    let addPort: () -> Void
    let addHost: () -> Void

    var body: some View {
        OnePlusLinearList(style: .panel) {
            PortmanForwardRow {
                OnePlusLinearTextField("alias or user@IP", text: $host, onSubmit: scan)
                    .accessibilityLabel("SSH alias or username at IP address")
                    .help(host.isEmpty ? "SSH alias or username at IP address" : host)
                if !aliases.isEmpty {
                    OnePlusLinearSelect(
                        choices: [("", "Hosts")] + aliases.map { ($0, $0) },
                        selection: Binding(get: { aliases.contains(host) ? host : "" }, set: { if !$0.isEmpty { host = $0 } }),
                        accessibilityLabel: "Choose an SSH host",
                        width: PortmanForwardMetrics.hostSelect
                    )
                }
                if scanning {
                    PortmanForwardKey("Cancel", action: cancel)
                } else {
                    PortmanForwardKey("Scan", action: scan).disabled(host.isEmpty)
                }
            }
            PortmanForwardRow {
                OnePlusLinearTextField("Remote port", text: $manualPort, onSubmit: addPort)
                    .accessibilityLabel("Remote port to add")
                PortmanForwardKey("Add port", action: addPort).disabled(host.isEmpty)
            }
            PortmanForwardRow {
                OnePlusLinearSelect(
                    choices: PortmanHostMode.allCases.map { ($0, $0.title) },
                    selection: $mode,
                    accessibilityLabel: "What to do with this host"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                PortmanForwardKey("Add host", action: addHost).disabled(host.isEmpty)
            }
        }
    }
}

/// The parent row of a host in Forward: its name, mode, and monitor status or latest readings.
struct PortmanHostRow: View {
    let group: PortmanHostGroup
    let state: PortmanServerState?
    let now: Date

    var body: some View {
        PortmanForwardRow {
            VStack(alignment: .leading, spacing: 0) {
                Text(group.host.destination).linearText(OnePlusLinearMetrics.control, weight: .medium)
                    .lineLimit(1).truncationMode(.middle)
                Text(detail).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(status).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                .lineLimit(1).fixedSize()
        }
        .help(help)
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        guard group.host.monitors, let state else { return group.saved ? group.host.mode.title : "Not saved" }
        return state.statusText(now: now)
    }

    private var detail: String {
        if group.host.monitors, let summary = state?.latest?.summary, !summary.isEmpty { return summary }
        let count = group.children.count
        return count == 1 ? "1 forward" : "\(count) forwards"
    }

    private var help: String {
        if case .failed(let failure) = state?.status { return "\(group.host.destination) · \(failure.detail)" }
        return "\(group.host.destination) · \(group.host.mode.title)"
    }
}
