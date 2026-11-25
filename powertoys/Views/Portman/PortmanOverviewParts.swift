import AppKit
import OnePlusUI
import SwiftUI

/// The Portman Servers page parts (DESIGN.md "Portman"): the hero ring and the two-line rows.
enum PortmanOverviewMetrics {
    static let rowHeight: CGFloat = 40
    static let ringSize: CGFloat = 132
    static let ringWidth: CGFloat = 9
    static let chipColumn: CGFloat = 50
    static let memoryColumn: CGFloat = 52
    static let ringToStats: CGFloat = 20
    static let statDividerHeight: CGFloat = 30
}

/// The first Servers open after launch counts the ring and numbers up; later opens show values as is.
enum PortmanEntrance {
    @MainActor static var pending = true
}

func portmanPortColor(_ port: UInt16) -> Color {
    let series = OnePlusColor.portmanSeries
    return series[(Int(port) * 7 / 11) % series.count]
}

/// Each listening process's memory share as a colored arc on one track. The arcs grow with the first-open reveal.
struct PortmanShareRing: View {
    let segments: [PortmanUsagePresentation]
    @Environment(\.onePlusLinearReveal) private var reveal

    var body: some View {
        let size = PortmanOverviewMetrics.ringSize, width = PortmanOverviewMetrics.ringWidth
        let total = max(1, segments.reduce(Int64(0)) { $0 + $1.memoryBytes })
        let gap = (width + 4) / (Double.pi * size)
        var start = 0.0
        let arcs = segments.map { segment in
            let span = Double(segment.memoryBytes) / Double(total)
            defer { start += span }
            return (segment, start, span)
        }
        ZStack {
            Circle().stroke(OnePlusLinearColor.fillTrack, lineWidth: width)
            ForEach(arcs, id: \.0.id) { segment, start, span in
                if span > gap {
                    Circle()
                        .trim(from: (start + gap / 2) * reveal, to: (start + span - gap / 2) * reveal)
                        .stroke(portmanPortColor(segment.port.port), style: StrokeStyle(lineWidth: width, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .help("Port \(String(segment.port.port)): \(portmanMemoryString(segment.memoryBytes))")
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The hero: the ring with the total memory in its center, then servers, CPU, and the longest uptime.
/// Its numbers are sums of the rows, so they follow each scan at once (`.process`), never lagging the rows.
struct PortmanHeroRing: View {
    let presentation: PortmanOverviewPresentation
    let caption: String

    var body: some View {
        VStack(spacing: PortmanOverviewMetrics.ringToStats) {
            ZStack {
                PortmanShareRing(segments: presentation.segments)
                VStack(spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        OnePlusLinearNumberText(String(format: "%.1f", Double(presentation.memoryBytes) / 1_048_576), pace: .process)
                            .font(.system(size: 26, weight: .light)).monospacedDigit().foregroundStyle(OnePlusLinearColor.ink)
                        Text("MB").linearText(13, color: OnePlusLinearColor.secondary)
                    }
                    Text(caption).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
                }
            }
            .help("Memory used only by processes listening on scanned ports")
            HStack(spacing: 0) {
                stat(String(presentation.uniquePortCount), "Servers", color: OnePlusLinearColor.ink)
                statDivider
                stat(String(format: "%.1f%%", presentation.cpuPercent), "CPU", color: OnePlusLinearColor.cpuText)
                statDivider
                stat(longestUptime, "Longest up", color: OnePlusLinearColor.ink)
            }
            .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(OnePlusLinearColor.fillGroup, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("portman.memoryBreakdown")
    }

    private var longestUptime: String {
        presentation.rows.map(\.port).filter { $0.started > 0 }.min { $0.started < $1.started }?.uptime ?? "–"
    }

    /// Three equal columns: a value in its data color or ink over a muted caption.
    private func stat(_ value: String, _ label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            OnePlusLinearNumberText(value, pace: .process).font(.system(size: 15, weight: .medium)).monospacedDigit()
                .foregroundStyle(color)
            Text(label).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
        }
        .frame(maxWidth: .infinity)
    }

    /// A faint divider that fades out at both ends, like the soft-key dividers.
    private var statDivider: some View {
        LinearGradient(colors: [.clear, OnePlusLinearColor.line, .clear], startPoint: .top, endPoint: .bottom)
            .frame(width: 1, height: PortmanOverviewMetrics.statDividerHeight)
    }
}

/// The port in its data color in a sunken badge well, on every Portman list.
struct PortmanPortChip: View {
    let port: UInt16
    var body: some View { OnePlusLinearBadge(":\(String(port))", color: portmanPortColor(port)) }
}

/// A 40 pt server row: port chip, app icon, name over branch and uptime, then a sparkline and memory. On hover the
/// sparkline gives way to Open and Stop. Hover is a fill step only; nothing moves.
struct PortmanServerRow: View {
    let row: PortmanOverviewRow
    let icon: NSImage?
    let cleanupMode: Bool
    @Binding var selected: Bool
    let open: () -> Void
    let openLocal: () -> Void
    let stop: () -> Void
    @State private var hover = false

    var body: some View {
        let port = row.port
        let showsActions = hover && !cleanupMode
        HStack(spacing: OnePlusLinearMetrics.rowGap) {
            if cleanupMode {
                Toggle(isOn: $selected) { EmptyView() }
                    .labelsHidden().toggleStyle(OnePlusCheckboxStyle()).disabled(!row.canStop)
                    .accessibilityLabel("Select process \(String(port.pid)) for cleanup")
            }
            PortmanPortChip(port: port.port).frame(width: PortmanOverviewMetrics.chipColumn, alignment: .leading)
            serverIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).linearText(OnePlusLinearMetrics.control).lineLimit(1)
                caption
            }
            Spacer(minLength: 0)
            if showsActions {
                OnePlusLinearIconButton(systemImage: "arrow.up.right.square", help: "Open localhost:\(String(port.port))",
                                        size: 22, action: openLocal)
                    .accessibilityIdentifier("portman.link.\(String(port.port))")
                if row.canStop {
                    OnePlusLinearIconButton(systemImage: "stop.circle", help: "Stop process tree for port \(String(port.port))",
                                            size: 22, action: stop)
                        .accessibilityIdentifier("portman.stop.\(String(port.port))")
                }
            } else {
                OnePlusSparkline(values: row.sparklineValues, range: row.sparklineRange, color: portmanPortColor(port.port))
                    .frame(width: 32, height: 14)
                    .accessibilityHidden(true)
            }
            Text(row.memoryText).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                .lineLimit(1).fixedSize()
                .frame(width: PortmanOverviewMetrics.memoryColumn, alignment: .trailing)
        }
        .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
        .frame(height: PortmanOverviewMetrics.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            if !cleanupMode { open() } else if row.canStop { selected.toggle() }
        }
        .linearRowHover($hover, sample: .rest, enabled: true, panelStyle: .fillSteps, selected: cleanupMode && selected)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(cleanupMode ? "Select port \(String(port.port)) for cleanup" : "Show port \(String(port.port)) details")
        .accessibilityValue("Memory \(row.memoryText), running for \(port.uptime)")
        .accessibilityAction { open() }
        .accessibilityActions {
            if row.canStop && !cleanupMode { Button("Stop process tree", action: stop) }
        }
        .accessibilityIdentifier("portman.local.row.\(String(port.port))")
        .help("\(row.title)\(row.subtitle.isEmpty ? "" : " · \(row.subtitle)") · up \(port.uptime)")
    }

    private var serverIcon: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().scaledToFit() }
            else {
                Image(systemName: PortmanRowIcon.fallbackSymbol).font(.system(size: 8)).foregroundStyle(OnePlusLinearColor.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(OnePlusLinearColor.iconOutline, lineWidth: 1) }
            }
        }
        .frame(width: OnePlusLinearMetrics.processIcon, height: OnePlusLinearMetrics.processIcon)
        .accessibilityHidden(true)
    }

    private var caption: some View {
        HStack(spacing: 4) {
            if !row.subtitle.isEmpty {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                Text(row.subtitle)
                Text("·")
            }
            Text("up \(row.port.uptime)")
        }
        .linearText(11, color: OnePlusLinearColor.panelMuted).lineLimit(1)
    }
}

/// Live instrument row motion: an added row opens over 250 ms and fades in after 70 ms; a removed row fades out over
/// 150 ms and closes over 250 ms after 50 ms. Drive it with `PortmanRowPresence.animation`.
struct PortmanRowPresence: ViewModifier, Animatable {
    static let duration = 0.3
    static var animation: Animation? { OnePlusMotion.reducesMotion ? nil : .linear(duration: duration) }
    static var transition: AnyTransition {
        .asymmetric(insertion: .modifier(active: Self(progress: 0, removal: false), identity: Self(progress: 1, removal: false)),
                    removal: .modifier(active: Self(progress: 0, removal: true), identity: Self(progress: 1, removal: true)))
    }

    var progress: Double
    let removal: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let elapsed = (removal ? 1 - progress : progress) * Self.duration
        let height = removal ? 1 - Self.easeOut(Self.ramp(elapsed, 0.05, 0.25)) : Self.easeOut(Self.ramp(elapsed, 0, 0.25))
        let opacity = removal ? 1 - Self.ramp(elapsed, 0, 0.15) : Self.ramp(elapsed, 0.07, 0.2)
        content
            .opacity(opacity)
            .frame(height: PortmanOverviewMetrics.rowHeight * height, alignment: .top)
            .clipped()
    }

    private static func ramp(_ t: Double, _ start: Double, _ length: Double) -> Double { min(1, max(0, (t - start) / length)) }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}

/// The server detail parts (DESIGN.md "Portman"): Home's floating groups, label-value rows, and process rows.
enum PortmanDetailMetrics {
    static let label: CGFloat = 72
    static let rowPadding: CGFloat = 7
    static let processBarGap: CGFloat = 6
}

/// A label-value row in a detail group: muted label, selectable value on the right, an optional 22 pt accessory.
struct PortmanDetailRow<Accessory: View>: View {
    private let label: String
    private let value: String
    private let accessory: Accessory
    @State private var hover = false
    @Environment(\.onePlusControlState) private var sample
    @Environment(\.onePlusLinearPanelStyle) private var panelStyle
    init(_ label: String, _ value: String, @ViewBuilder accessory: () -> Accessory) {
        self.label = label; self.value = value; self.accessory = accessory()
    }
    var body: some View {
        HStack(spacing: OnePlusLinearMetrics.rowGap) {
            Text(label).linearText(color: OnePlusLinearColor.panelMuted).lineLimit(1)
                .frame(width: PortmanDetailMetrics.label, alignment: .leading)
            Text(value).linearText(OnePlusLinearMetrics.control).textSelection(.enabled)
                .lineLimit(2).truncationMode(.middle).multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing).help(value)
            if Accessory.self != EmptyView.self { accessory.frame(width: OnePlusLinearMetrics.panelAccessory) }
        }
        .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
        .padding(.vertical, PortmanDetailMetrics.rowPadding)
        .frame(minHeight: OnePlusLinearMetrics.controlRow)
        .linearRowHover($hover, sample: sample, enabled: true, panelStyle: panelStyle)
        .accessibilityElement(children: .contain)
    }
}

extension PortmanDetailRow where Accessory == EmptyView {
    init(_ label: String, _ value: String) { self.init(label, value) { EmptyView() } }
}

/// A 40 pt process row: command, PID, and memory over its share of the server's memory.
struct PortmanProcessRow: View {
    let command: String
    let pid: Int32
    let memory: String
    let fraction: Double
    let color: Color
    @State private var hover = false
    @Environment(\.onePlusControlState) private var sample
    @Environment(\.onePlusLinearPanelStyle) private var panelStyle
    var body: some View {
        VStack(spacing: PortmanDetailMetrics.processBarGap) {
            HStack(spacing: OnePlusLinearMetrics.rowGap) {
                Text(command).linearText(OnePlusLinearMetrics.control).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(pid)).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.panelMuted)
                Text(memory).linearText(OnePlusLinearMetrics.control, color: OnePlusLinearColor.secondary)
                    .frame(width: OnePlusLinearMetrics.memoryColumn, alignment: .trailing)
            }
            OnePlusLinearUsageBar(fraction, color: color)
        }
        .padding(.horizontal, OnePlusLinearMetrics.panelRowInset)
        .frame(height: OnePlusLinearMetrics.panelTwoLineRow)
        .linearRowHover($hover, sample: sample, enabled: true, panelStyle: panelStyle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(command), process \(pid), \(memory)")
    }
}
