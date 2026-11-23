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
    /// Host card parts (owner picks 2026-11-21, DESIGN.md "Portman").
    static let badgeColumn: CGFloat = 50
    static let memoryColumn: CGFloat = 52
    static let chevron: CGFloat = 12
    static let sparkline = CGSize(width: 32, height: 14)
    static let tileGap: CGFloat = 6
    static let statsTop: CGFloat = 2
    static let statsBottom: CGFloat = 6
    /// Drag to reorder (DESIGN.md "Portman"): starts after 4 pt, the others slide in 200 ms, a 2 pt accent drop line.
    static let dragStart: CGFloat = 4
    static let reorderSlide: TimeInterval = 0.2
    static let dropLine: CGFloat = 2
    static let liftShadowRadius: CGFloat = 8
    static let liftShadowY: CGFloat = 2
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
                        choices: aliases.map { ($0, $0) },
                        // A picker that fills the field: it always reads "Hosts", so the chosen name shows once, uncut.
                        selection: Binding(get: { "" }, set: { host = $0 }),
                        accessibilityLabel: "Choose an SSH host",
                        width: PortmanForwardMetrics.hostSelect,
                        placeholder: "Hosts"
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

/// What a host card asks the panel to do.
struct PortmanHostCardActions {
    var toggleStats: () -> Void = {}
    /// Nil re-forwards every down forward of the host (Reconnect all).
    var retry: (PortmanForwardChild?) -> Void = { _ in }
    var open: (UInt16) -> Void = { _ in }
    var stop: (PortmanForwardChild) -> Void = { _ in }
    var remove: (PortmanForwardChild) -> Void = { _ in }
    /// Moves a saved forward to a new index inside this card.
    var move: (PortmanForwardChild, Int) -> Void = { _, _ in }
}

/// One card per host (DESIGN.md "Portman", Forward): the host row, its chart tiles when open, then its forwards
/// indented under a guide line from the host icon.
struct PortmanHostCard: View {
    let group: PortmanHostGroup
    let model: PortmanHostCardModel
    let expanded: Bool
    let actions: PortmanHostCardActions

    var body: some View {
        OnePlusLinearList(style: .panel) {
            PortmanHostCardRow(group: group, model: model, expanded: expanded, actions: actions)
                .overlay(alignment: .bottomLeading) { if !group.children.isEmpty || showsStats { guide(from: .icon) } }
            if showsStats {
                PortmanHostStats(tiles: model.tiles)
                    .overlay(alignment: .leading) { guide(from: .top) }
            }
            PortmanReorderStack(items: group.children, movable: group.saved ? group.host.forwards.count : 0,
                                lineInsets: EdgeInsets(top: 0, leading: OnePlusLinearMetrics.treeChildInset,
                                                       bottom: 0, trailing: OnePlusLinearMetrics.panelRowInset),
                                name: { "localhost:\(String($0.spec.localPort))" }, move: actions.move) { child, _ in
                PortmanForwardChildRow(destination: group.host.destination, child: child, actions: actions)
            } slot: { index in
                guide(from: .top, last: index == group.children.count - 1, tick: true)
            }
        }
    }

    private var showsStats: Bool { expanded && !model.tiles.isEmpty }

    private enum GuideStart { case icon, top }

    /// The tree line: under the host icon it runs from the icon's bottom; in a forward row it ends at the row's
    /// center on the last row, with a tick to the badge.
    private func guide(from start: GuideStart, last: Bool = false, tick: Bool = false) -> some View {
        let x = OnePlusLinearMetrics.panelRowInset + OnePlusLinearMetrics.hostIcon / 2 - 0.5
        return GeometryReader { proxy in
            let height = proxy.size.height
            let top = start == .icon ? (height + OnePlusLinearMetrics.hostIcon) / 2 + 1 : 0
            let bottom = last ? height / 2 + 0.5 : height
            ZStack(alignment: .topLeading) {
                OnePlusLinearColor.lineStrong.frame(width: 1, height: max(0, bottom - top)).offset(x: x, y: top)
                if tick {
                    OnePlusLinearColor.lineStrong.frame(width: OnePlusLinearMetrics.guideTick, height: 1)
                        .offset(x: x, y: height / 2 - 0.5)
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The 40 pt host row: icon with status dot, name over caption, CPU line and memory (or the failure), a
/// Reconnect all key when a forward is down, and the stats chevron.
private struct PortmanHostCardRow: View {
    let group: PortmanHostGroup
    let model: PortmanHostCardModel
    let expanded: Bool
    let actions: PortmanHostCardActions
    @State private var hover = false

    var body: some View {
        HStack(spacing: OnePlusLinearMetrics.rowGap) {
            Button(action: actions.toggleStats) { summary }
                .buttonStyle(.plain).focusEffectDisabled().disabled(model.tiles.isEmpty)
                .accessibilityLabel("\(group.host.destination), \(model.caption)")
                .accessibilityHint(model.tiles.isEmpty ? "" : expanded ? "Hides the charts" : "Shows the charts")
            if group.children.contains(where: { PortmanForwardHealth($0.tunnel).isDown }) {
                OnePlusLinearIconButton(systemImage: "arrow.clockwise", help: "Reconnect all forwards",
                                        size: OnePlusLinearMetrics.panelAccessory) { actions.retry(nil) }
            }
        }
        .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
        .frame(height: OnePlusLinearMetrics.panelTwoLineRow)
        .linearRowHover($hover, sample: .rest, enabled: !model.tiles.isEmpty, panelStyle: .fillSteps)
        .help(help)
    }

    private var summary: some View {
        HStack(spacing: OnePlusLinearMetrics.rowGap) {
            OnePlusLinearHostIcon(online: model.online)
            VStack(alignment: .leading, spacing: 0) {
                Text(group.host.destination).linearText(OnePlusLinearMetrics.control, weight: .semibold)
                    .lineLimit(1).truncationMode(.middle)
                Text(model.caption).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            if !model.tiles.isEmpty {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(OnePlusLinearColor.tertiary)
                    .frame(width: PortmanForwardMetrics.chevron)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var trailing: some View {
        switch model.health {
        case .online, .stale:
            if !model.sparkline.isEmpty {
                OnePlusSparkline(values: model.sparkline, color: OnePlusLinearColor.cpu)
                    .frame(width: PortmanForwardMetrics.sparkline.width, height: PortmanForwardMetrics.sparkline.height)
            }
            Text(model.memory ?? "").linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                .monospacedDigit().lineLimit(1)
                .frame(width: PortmanForwardMetrics.memoryColumn, alignment: .trailing)
        case .offline(let label):
            Text(label).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.panelMuted).lineLimit(1).fixedSize()
        case .waiting, .unmonitored:
            EmptyView()
        }
    }

    private var help: String { "\(group.host.destination) · \(group.host.mode.title) · \(model.caption)" }
}

/// The open host's chart tiles: CPU, memory, disk, network, two by two.
private struct PortmanHostStats: View {
    let tiles: [PortmanHostCardModel.Tile]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: PortmanForwardMetrics.tileGap), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: PortmanForwardMetrics.tileGap) {
            ForEach(tiles, id: \.kind) { tile in
                let look = Self.look(tile.kind)
                OnePlusLinearInsetTile(look.title, systemImage: look.symbol, meta: tile.meta, value: tile.value, unit: tile.unit,
                                       color: look.text, chart: OnePlusLinearChart(
                                           [OnePlusLinearSeries(tile.series, color: look.color, filled: true)]
                                               + (tile.secondary.isEmpty ? [] : [OnePlusLinearSeries(tile.secondary, color: OnePlusLinearColor.networkUp, filled: false)]),
                                           range: tile.range, height: OnePlusLinearMetrics.insetTileChart))
            }
        }
        .padding(.leading, OnePlusLinearMetrics.treeChildInset)
        .padding(.trailing, OnePlusLinearMetrics.panelRowInset)
        .padding(.top, PortmanForwardMetrics.statsTop).padding(.bottom, PortmanForwardMetrics.statsBottom)
    }

    private static func look(_ kind: PortmanHostCardModel.Kind) -> (title: String, symbol: String, color: Color, text: Color) {
        switch kind {
        case .cpu: ("CPU", "cpu", OnePlusLinearColor.cpu, OnePlusLinearColor.cpuText)
        case .memory: ("Memory", "memorychip", OnePlusLinearColor.memory, OnePlusLinearColor.memory)
        case .disk: ("Disk", "internaldrive", OnePlusLinearColor.disk, OnePlusLinearColor.disk)
        case .network: ("Network", "network", OnePlusLinearColor.networkDown, OnePlusLinearColor.networkDown)
        }
    }
}

/// A 32 pt forward row under its host: the port badge, the local address, its state in plain words, and one
/// icon: open it, or re-forward it when it is down.
private struct PortmanForwardChildRow: View {
    let destination: String
    let child: PortmanForwardChild
    let actions: PortmanHostCardActions

    var body: some View {
        let health = PortmanForwardHealth(child.tunnel)
        let spec = child.spec
        HStack(spacing: OnePlusLinearMetrics.rowGap) {
            PortmanPortChip(port: spec.localPort)
                .frame(width: PortmanForwardMetrics.badgeColumn, alignment: .leading)
            HStack(spacing: 6) {
                Text("localhost:\(String(spec.localPort))").linearText(OnePlusLinearMetrics.control)
                if spec.remotePort != spec.localPort {
                    Text("→ :\(String(spec.remotePort))").linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.panelMuted)
                        .monospacedDigit()
                }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(health.label)
                .linearText(OnePlusLinearMetrics.control, color: health.isFailed ? OnePlusLinearColor.destructiveText : OnePlusLinearColor.secondary)
                .lineLimit(1).fixedSize()
            switch health {
            case .forwarding:
                OnePlusLinearIconButton(systemImage: "link", help: "Open localhost:\(String(spec.localPort))",
                                        size: OnePlusLinearMetrics.panelAccessory) { actions.open(spec.localPort) }
            case .connecting:
                OnePlusLinearIconButton(systemImage: "link", help: "Open localhost:\(String(spec.localPort))",
                                        size: OnePlusLinearMetrics.panelAccessory, busy: "Connecting") {}
            case .stopped, .failed:
                OnePlusLinearIconButton(systemImage: "arrow.clockwise", help: "Forward again",
                                        size: OnePlusLinearMetrics.panelAccessory) { actions.retry(child) }
            }
        }
        .padding(.leading, OnePlusLinearMetrics.treeChildInset)
        .padding(.trailing, OnePlusLinearMetrics.panelRowInset)
        .frame(height: OnePlusLinearMetrics.treeChildRow)
        .help("localhost:\(String(spec.localPort)) → \(destination):\(String(spec.remotePort)) · \(child.tunnel.flatMap(\.failureMessage) ?? health.label)")
        .contextMenu {
            if child.tunnel != nil { Button("Stop forwarding") { actions.stop(child) } }
            Button("Remove forward") { actions.remove(child) }
        }
    }
}

private extension PortmanForwardHealth {
    var isFailed: Bool { if case .failed = self { true } else { false } }
}

private extension PortmanTunnel {
    var failureMessage: String? { if case .failed(let message) = state { message } else { nil } }
}
