import OnePlusUI
import SwiftUI

/// The Fan page: the picked fan curve as one large chart. Drag a point to move it,
/// double-click a point to type exact values, double-click empty space to add a point.
struct FanPageView: View {
    static let pageID = "fan"
    static let title = "Fan"
    private static let owner = "fan-page"

    @State private var service = FanControlService.shared
    @AppStorage(FanCurve.storageKey) private var curveData: Data?
    @AppStorage(FanCurvePreset.storageKey) private var presetName: String?
    @AppStorage(FanHold.storageKey) private var holdCelsius: Double?

    private var preset: FanCurvePreset { FanCurvePreset(rawValue: presetName ?? "") ?? .custom }
    private var custom: FanCurve { curveData.flatMap { try? JSONDecoder().decode(FanCurve.self, from: $0) } ?? .standard }
    private var curve: FanCurve { preset.curve ?? custom }
    /// The target the chart shows: the user's Hold, else Balanced's or Cool's fixed target.
    private var hold: Double? {
        (holdCelsius ?? preset.holdTarget).map { min(max($0, FanHold.range.lowerBound), FanHold.range.upperBound) }
    }
    /// The chart title: the picked card's name, such as "Hold 56 °C" or "Cool".
    private var pickName: String {
        if let hold, holdCelsius != nil { return "Hold \(Int(hold)) °C" }
        return preset.name
    }
    private var holdRange: String { "\(Int(FanHold.range.lowerBound))-\(Int(FanHold.range.upperBound)) °C" }
    private var nowCelsius: Double? { service.display.cpuCelsius.map(Double.init) }
    private var nowChip: String? { service.display.cpuCelsius.map { "\(service.display.inputName) \($0) °C · \(service.display.rpm)" } }

    var body: some View {
        OnePlusLinearEditorialBody {
            OnePlusLinearToolHeader(Self.title, detail: "Set how fast the fans spin as the CPU heats up.") { size in
                FanPageIcon(size: size)
            } actions: { EmptyView() }
            OnePlusLinearAppletSection(pickName) {
                VStack(spacing: 0) {
                    if let hold {
                        FanCurveEditor(curve: FanHold.displayCurve(target: hold), nowCelsius: nowCelsius, nowChip: nowChip,
                                       hold: hold, setHold: { FanHold.save($0) }) { _ in }.padding(.top, 12)
                        FanHintRow(text: holdCelsius == nil
                                   ? "\(preset.name) keeps the CPU near \(Int(hold)) °C · drag the line or type \(holdRange) to hold another"
                                   : "Holds \(Int(hold)) °C, give or take \(Int(FanHold.band)) °C · drag the line or type \(holdRange)") {
                            OnePlusStepperField("Hold at", value: Binding(get: { Int(hold) }, set: { FanHold.save(Double($0)) }),
                                                in: Int(FanHold.range.lowerBound)...Int(FanHold.range.upperBound), unit: "°C")
                                .fixedSize()
                        }
                    } else {
                        FanCurveEditor(curve: curve, nowCelsius: nowCelsius, nowChip: nowChip) { $0.save() }.padding(.top, 12)
                        FanHintRow(text: "Drag points · double-click to edit · right-click to add or remove") {
                            Button("Reset Curve") { FanCurve.standard.save() }
                                .buttonStyle(OnePlusLinearButtonStyle(.inlineDestructive)).focusEffectDisabled()
                                .disabled(preset != .custom || curveData == nil)
                                .help("Go back to the standard curve")
                        }
                    }
                }
                OnePlusLinearAppletRow("Now", value: nowText, systemImage: "thermometer.medium")
            }
            FanPresetCards(preset: preset, hold: holdCelsius == nil ? nil : hold, custom: custom)
        } footer: { EmptyView() }
        .transformEnvironment(\.onePlusLinearControlLook) { if $0 == nil { $0 = .quietRaised } }
        .onAppear { service.start(owner: Self.owner) }
        .onDisappear { service.stop(owner: Self.owner) }
        .accessibilityIdentifier("fan.page")
    }

    private var nowText: String {
        let display = service.display
        return [display.cpuCelsius.map { CPUHeat.help($0, name: display.inputName) }, display.rpm].compactMap(\.self).joined(separator: " · ")
    }
}

/// The caption line under the chart: a `tertiary` hint on the left, one control on the right.
private struct FanHintRow<Trailing: View>: View {
    let text: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(text).linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.tertiary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, OnePlusLinearMetrics.appletRowPadding)
        .frame(minHeight: 20)
        .padding(.bottom, 10)
    }
}

/// The five picks under the chart, each with a small picture
/// of what it does. A curve card picks its curve and turns Hold off; Hold sets its target.
private struct FanPresetCards: View {
    let preset: FanCurvePreset
    let hold: Double?
    let custom: FanCurve
    private static let gap: CGFloat = 8

    var body: some View {
        HStack(spacing: Self.gap) {
            card(FanCurvePreset.quiet.name, selected: hold == nil && preset == .quiet,
                 shape: .curve(FanCurvePreset.quiet.curve ?? custom)) { FanCurvePreset.quiet.pick() }
            ForEach([FanCurvePreset.balanced, .cool], id: \.self) { pick in
                card(pick.name, selected: hold == nil && preset == pick, shape: .hold(pick.holdTarget ?? FanHold.defaultTarget),
                     help: "Keeps the CPU near \(Int(pick.holdTarget ?? 0)) °C") { pick.pick() }
            }
            let target = hold ?? FanHold.savedTarget() ?? FanHold.defaultTarget
            card("Hold \(Int(target)) °C", selected: hold != nil, shape: .hold(target)) { FanHold.save(target) }
            card(FanCurvePreset.custom.name, selected: hold == nil && preset == .custom, shape: .curve(custom)) {
                FanCurvePreset.custom.pick()
            }
        }
    }

    private func card(_ name: String, selected: Bool, shape: FanMiniChart.Shape, help: String = "",
                      pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 6) {
                FanMiniChart(shape: shape, tint: selected ? OnePlusLinearColor.accent : OnePlusLinearColor.secondary)
                    .frame(height: 30)
                Text(name)
                    .linearText(OnePlusLinearMetrics.caption, weight: .medium,
                                color: selected ? OnePlusLinearColor.ink : OnePlusLinearColor.secondary)
                    .lineLimit(1).fixedSize()
            }
            .padding(Self.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(OnePlusLinearButtonStyle(.plain, radius: OnePlusLinearMetrics.appletGroupRadius))
        .background(RoundedRectangle(cornerRadius: OnePlusLinearMetrics.appletGroupRadius).fill(OnePlusLinearColor.fillGroup))
        .overlay(RoundedRectangle(cornerRadius: OnePlusLinearMetrics.appletGroupRadius)
            .strokeBorder(selected ? OnePlusLinearColor.accent : OnePlusLinearColor.line, lineWidth: selected ? 1.5 : 1))
        .focusEffectDisabled()
        .help(help)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A card's picture on the full 30-90 °C scale: the curve with a soft fill; Hold also shades its ±2 °C band.
private struct FanMiniChart: View {
    enum Shape { case curve(FanCurve), hold(Double) }
    let shape: Shape
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let plot = FanPlot(rect: CGRect(origin: .zero, size: geo.size).insetBy(dx: 2, dy: 2))
            let points: [CGPoint] = switch shape {
            case .curve(let curve): plot.samples(curve)
            case .hold(let target): plot.samples(FanHold.displayCurve(target: target))
            }
            ZStack(alignment: .topLeading) {
                if case .hold(let target) = shape {
                    Rectangle().fill(tint.opacity(0.12))
                        .frame(width: plot.x(target + FanHold.band) - plot.x(target - FanHold.band), height: plot.rect.height)
                        .position(x: plot.x(target), y: plot.rect.midY)
                }
                plot.area(points).fill(tint.opacity(0.12))
                Path { $0.addLines(points) }.stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Temperature across (30-90 °C average) and speed up (0-1) inside one rectangle.
private struct FanPlot {
    let rect: CGRect
    static let domain = FanCurve.temperatureRange

    func x(_ celsius: Double) -> CGFloat {
        rect.minX + rect.width * (celsius - Self.domain.lowerBound) / (Self.domain.upperBound - Self.domain.lowerBound)
    }

    func y(_ speed: Double) -> CGFloat { rect.maxY - rect.height * speed }
    func point(_ celsius: Double, _ speed: Double) -> CGPoint { CGPoint(x: x(celsius), y: y(speed)) }

    func samples(_ curve: FanCurve) -> [CGPoint] {
        stride(from: Self.domain.lowerBound, through: Self.domain.upperBound, by: 0.25).map { point($0, curve.speed(at: $0)) }
    }

    /// `addLines` would start a new subpath, so the fill adds each sample to the bottom-left start instead.
    func area(_ points: [CGPoint]) -> Path {
        Path { path in
            path.move(to: CGPoint(x: points.first?.x ?? rect.minX, y: rect.maxY))
            points.forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: points.last?.x ?? rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// The "Heat line" colors: cool blue through the `CPUHeat` steps to very hot red. The stops
/// sit where those steps fall on the 30-90 °C average scale.
enum FanHeat {
    static func color(_ celsius: Double) -> Color {
        switch CPUHeat(celsius: celsius) {
        case .normal: OnePlusLinearColor.temperatureCool
        case .warm: OnePlusLinearColor.temperatureWarm
        case .hot: OnePlusLinearColor.temperatureHot
        case .veryHot: OnePlusLinearColor.temperatureVeryHot
        case .nearLimit: OnePlusLinearColor.temperatureCritical
        }
    }

    static let gradient = LinearGradient(stops: [
        .init(color: OnePlusLinearColor.temperatureCool, location: 0.1), .init(color: OnePlusLinearColor.temperatureWarm, location: 0.36),
        .init(color: OnePlusLinearColor.temperatureHot, location: 0.54), .init(color: OnePlusLinearColor.temperatureVeryHot, location: 0.7),
    ], startPoint: .leading, endPoint: .trailing)
}

/// Where a chart chip goes so it never covers another label or point: above its dot, else below, left, right, or a
/// far-side diagonal, kept inside the chart. With no clear spot it takes the one with the least overlap.
enum FanChipPlacement {
    static let gap: CGFloat = 4

    static func center(size: CGSize, dot: CGPoint, dotRadius: CGFloat, avoiding obstacles: [CGRect], in bounds: CGRect) -> CGPoint {
        let up = dot.y - dotRadius - gap - size.height / 2, down = dot.y + dotRadius + gap + size.height / 2
        let side = dotRadius + gap + size.width / 2
        let candidates = [CGPoint(x: dot.x, y: up), CGPoint(x: dot.x, y: down),
                          CGPoint(x: dot.x - side, y: dot.y), CGPoint(x: dot.x + side, y: dot.y),
                          CGPoint(x: dot.x - size.width / 2, y: down), CGPoint(x: dot.x - size.width / 2, y: up),
                          CGPoint(x: dot.x + size.width / 2, y: down), CGPoint(x: dot.x + size.width / 2, y: up)]
        let blocked = obstacles + [CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)]
        let placed = candidates.map { clamp(rect(size, at: $0), into: bounds) }
        let overlaps = placed.map { chip in blocked.reduce(0) { total, rect in
            let cut = chip.intersection(rect.insetBy(dx: -gap / 2, dy: -gap / 2))
            return total + (cut.isNull ? 0 : cut.width * cut.height)
        } }
        let best = overlaps.firstIndex(of: 0) ?? overlaps.indices.min { overlaps[$0] < overlaps[$1] }!
        return CGPoint(x: placed[best].midX, y: placed[best].midY)
    }

    static func rect(_ size: CGSize, at center: CGPoint) -> CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    private static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        rect.offsetBy(dx: min(max(rect.minX, bounds.minX), bounds.maxX - rect.width) - rect.minX,
                      dy: min(max(rect.minY, bounds.minY), bounds.maxY - rect.height) - rect.minY)
    }
}

/// A small reading next to a chart point, such as "64 °C · 3,039 RPM".
private struct FanChip: View {
    let text: String

    var body: some View {
        Text(text)
            .linearText(OnePlusLinearMetrics.caption, weight: .medium)
            .monospacedDigit()
            .padding(.horizontal, 7).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: OnePlusLinearMetrics.radius).fill(OnePlusLinearColor.button)
                .shadow(color: OnePlusLinearColor.quietKnobShadow, radius: 3, y: 1))
            .overlay(RoundedRectangle(cornerRadius: OnePlusLinearMetrics.radius).strokeBorder(OnePlusLinearColor.buttonRing, lineWidth: 1))
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// Hold's marks under its curve: the ±2 °C band, the target as a dashed `ink` line, and its label left of the band.
private struct FanHoldBand: View {
    let plot: FanPlot
    let target: Double
    private static let labelWidth: CGFloat = 84

    /// Where the label sits, so the now chip can avoid it.
    static func labelRect(_ plot: FanPlot, target: Double) -> CGRect {
        CGRect(x: plot.x(target - FanHold.band) - 8 - labelWidth, y: plot.rect.minY + 2, width: labelWidth, height: 16)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(OnePlusLinearColor.ink.opacity(0.07))
                .frame(width: plot.x(target + FanHold.band) - plot.x(target - FanHold.band), height: plot.rect.height)
                .position(x: plot.x(target), y: plot.rect.midY)
            Path { $0.move(to: plot.point(target, 0)); $0.addLine(to: plot.point(target, 1)) }
                .stroke(OnePlusLinearColor.ink.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            Text("Target \(Int(target)) °C").linearText(OnePlusLinearMetrics.caption, weight: .semibold)
                .fixedSize().frame(width: 0, alignment: .trailing)
                .position(x: plot.x(target - FanHold.band) - 8, y: plot.rect.minY + 10)
        }
        .allowsHitTesting(false)
    }
}

/// The page icon: Midnight in Light, Porcelain in Dark, like Portman.
struct FanPageIcon: View {
    let size: CGFloat

    var body: some View {
        Image("FanLogo")
            .resizable().scaledToFit()
            .toolIconTile(size: size)
            .accessibilityHidden(true)
    }
}

/// Temperature across (30-90 °C average), speed up (0% at each fan's minimum, 100% at its maximum). With `hold` set it
/// shows Hold's picture read-only: the curve with its band and target, no points to drag.
struct FanCurveEditor: View {
    let curve: FanCurve
    let nowCelsius: Double?
    let nowChip: String?
    var hold: Double?
    /// Saves a Hold target picked by a click or drag on the chart.
    var setHold: ((Double) -> Void)?
    let save: (FanCurve) -> Void

    @State private var draft: FanCurve?
    @State private var holdDraft: Double?
    @State private var dragging: Int?
    @State private var hovered: Int?
    @State private var editing: Int?
    @State private var selected: Int?
    @State private var pointer: CGPoint?
    @State private var keyMonitor: Any?
    @State private var captionWidth = FanLockedEnd.estimatedCaptionWidth
    @State private var nowChipSize = CGSize(width: 130, height: 20)
    @State private var dragChipSize = CGSize(width: 90, height: 20)
    static let chipMargin: CGFloat = 8

    private static let domain = FanCurve.temperatureRange

    /// What a chip must not cover: the user's points, the locked end with its caption, and the axis labels.
    static func obstacles(plot: CGRect, knobs: [CGPoint], captionWidth: CGFloat) -> [CGRect] {
        let lock = CGPoint(x: plot.minX + plot.width * (FanCurve.lockedEnd.celsius - domain.lowerBound)
                               / (domain.upperBound - domain.lowerBound),
                           y: plot.maxY - plot.height * FanCurve.lockedEnd.speed)
        let knobRects = knobs.map { CGRect(x: $0.x - knob / 2, y: $0.y - knob / 2, width: knob, height: knob) }
        let lockSize = FanLockedEnd.size
        let percentLabels = [0.0, 0.5, 1.0].map { speed in
            CGRect(x: plot.minX + OnePlusLinearMetrics.appletRowPadding, y: plot.maxY - plot.height * speed - 15, width: 30, height: 14)
        }
        return knobRects + percentLabels + [
            CGRect(x: lock.x - lockSize / 2, y: lock.y - lockSize / 2, width: lockSize, height: lockSize),
            CGRect(x: lock.x - lockSize - captionWidth, y: plot.minY - 18, width: captionWidth, height: 14),
            CGRect(x: plot.minX, y: plot.maxY + 5, width: plot.width, height: 14),
        ]
    }
    /// The plot runs to the card's left and right edges; its labels sit inside, `appletRowPadding` from each edge.
    static let inset = EdgeInsets(top: 22, leading: 0, bottom: 22, trailing: 0)
    static let height: CGFloat = 240
    private static let hitTarget: CGFloat = 24
    private static let knob: CGFloat = 12

    private var shown: FanCurve { draft ?? curve }

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: Self.inset.leading, y: Self.inset.top,
                              width: geo.size.width - Self.inset.leading - Self.inset.trailing,
                              height: geo.size.height - Self.inset.top - Self.inset.bottom)
            ZStack(alignment: .topLeading) {
                FanCurveGrid(plot: FanPlot(rect: plot))
                if let hold {
                    FanHoldBand(plot: FanPlot(rect: plot), target: holdDraft ?? hold)
                    // The whole chart moves the target: press or drag anywhere, release to save.
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                            .onChanged { holdDraft = holdTarget(at: $0.location, plot: plot) }
                            .onEnded { _ in
                                if let holdDraft { setHold?(holdDraft) }
                                holdDraft = nil
                            })
                        .help("Drag to set the temperature to hold, \(Int(FanHold.range.lowerBound))-\(Int(FanHold.range.upperBound)) °C")
                } else {
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover(coordinateSpace: .named(Self.space)) {
                            if case .active(let location) = $0 { pointer = location } else { pointer = nil }
                        }
                        .onTapGesture(count: 2) { addPoint(at: $0, plot: plot) }
                        .contextMenu {
                            Button("Add point here") { if let pointer { addPoint(at: pointer, plot: plot) } }
                                .disabled(pointer.map { !canAdd(at: $0, plot: plot) } ?? true)
                        }
                }
                FanCurveLine(plot: FanPlot(rect: plot), curve: holdDraft.map { FanHold.displayCurve(target: $0) } ?? shown)
                if let hold {
                    let target = holdDraft ?? hold, at = position(.init(celsius: target, speed: 0.5), plot)
                    holdKnob(at: at)
                    if holdDraft != nil {
                        FanChip(text: "Hold \(Int(target)) °C")
                            .onGeometryChange(for: CGSize.self, of: { $0.size }) { dragChipSize = $0 }
                            .position(FanChipPlacement.center(size: dragChipSize, dot: at, dotRadius: Self.knob / 2,
                                                              avoiding: Self.obstacles(plot: plot, knobs: [], captionWidth: 0),
                                                              in: CGRect(origin: .zero, size: geo.size).insetBy(dx: Self.chipMargin, dy: 0)))
                    }
                } else {
                    ForEach(shown.points.indices, id: \.self) { index in knob(index, plot: plot) }
                }
                // Hold reaches full speed at target + 4 °C, so the "Full speed from 80 °C" caption would mislead there.
                FanLockedEnd(point: position(FanCurve.lockedEnd, plot), plot: plot, showsCaption: hold == nil) { captionWidth = $0 }
                let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: Self.chipMargin, dy: 0)
                if let now = nowPoint(plot), let nowCelsius {
                    FanCurveNow(point: now, color: FanHeat.color(nowCelsius))
                    if let nowChip, dragging == nil, holdDraft == nil {
                        let obstacles = hold.map { [FanHoldBand.labelRect(FanPlot(rect: plot), target: $0)] + Self.obstacles(
                            plot: plot, knobs: [], captionWidth: 0) }
                            ?? Self.obstacles(plot: plot, knobs: shown.points.map { position($0, plot) }, captionWidth: captionWidth)
                        FanChip(text: nowChip).onGeometryChange(for: CGSize.self, of: { $0.size }) { nowChipSize = $0 }
                            .position(FanChipPlacement.center(size: nowChipSize, dot: now, dotRadius: FanCurveNow.size / 2,
                                                              avoiding: obstacles, in: bounds))
                    }
                }
                if let dragging, shown.points.indices.contains(dragging) {
                    let point = shown.points[dragging], at = position(shown.points[dragging], plot)
                    let others = shown.points.indices.filter { $0 != dragging }.map { position(shown.points[$0], plot) }
                    FanChip(text: "\(Int(point.celsius)) °C · \(Int((point.speed * 100).rounded()))%")
                        .onGeometryChange(for: CGSize.self, of: { $0.size }) { dragChipSize = $0 }
                        .position(FanChipPlacement.center(size: dragChipSize, dot: at, dotRadius: Self.knob / 2,
                                                          avoiding: Self.obstacles(plot: plot, knobs: others, captionWidth: captionWidth),
                                                          in: bounds))
                }
            }
            .coordinateSpace(name: Self.space)
            .popover(isPresented: editingBinding, attachmentAnchor: .rect(.rect(anchor(plot))), arrowEdge: .top) {
                if let editing, curve.points.indices.contains(editing) {
                    FanPointEditor(curve: curve, index: editing, save: save) { self.editing = nil }.onePlusOpaquePopover()
                }
            }
        }
        .frame(height: Self.height)
        // The 3 pt line runs edge to edge; clip its round caps at the card's sides, never the chips above.
        .mask(Rectangle().padding(.vertical, -40))
        .task {
            // Screenshot checks open a point's popover without a click: `MPTDiagnosticFanEditPoint` is the 1-based point.
            try? await Task.sleep(for: .milliseconds(600))
            let point = UserDefaults.standard.integer(forKey: "MPTDiagnosticFanEditPoint")
            if hold == nil, curve.points.indices.contains(point - 1) { editing = point - 1 }
        }
        .onAppear { keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: deleteKey) }
        .onDisappear {
            keyMonitor.map(NSEvent.removeMonitor)
            keyMonitor = nil
            selected = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hold.map { "Hold \(Int($0)) °C, give or take \(Int(FanHold.band)) °C" } ?? "Fan curve")
    }

    private var editingBinding: Binding<Bool> {
        Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
    }

    private func anchor(_ plot: CGRect) -> CGRect {
        guard let editing, curve.points.indices.contains(editing) else { return .zero }
        let p = position(curve.points[editing], plot)
        return CGRect(x: p.x - Self.knob / 2, y: p.y - Self.knob / 2, width: Self.knob, height: Self.knob)
    }

    private func position(_ point: FanCurve.Point, _ plot: CGRect) -> CGPoint {
        let span = Self.domain.upperBound - Self.domain.lowerBound
        return CGPoint(x: plot.minX + plot.width * (point.celsius - Self.domain.lowerBound) / span,
                       y: plot.maxY - plot.height * point.speed)
    }

    private func value(at location: CGPoint, _ plot: CGRect) -> FanCurve.Point {
        let span = Self.domain.upperBound - Self.domain.lowerBound
        let celsius = Self.domain.lowerBound + span * Double((location.x - plot.minX) / plot.width)
        return .init(celsius: celsius.rounded(), speed: (Double((plot.maxY - location.y) / plot.height) * 100).rounded() / 100)
    }

    private func nowPoint(_ plot: CGRect) -> CGPoint? {
        nowCelsius.map { now in
            position(.init(celsius: min(max(now, Self.domain.lowerBound), Self.domain.upperBound), speed: shown.speed(at: now)), plot)
        }
    }

    private func knob(_ index: Int, plot: CGRect) -> some View {
        let point = shown.points[index]
        let active = dragging == index || hovered == index || editing == index || selected == index
        return Circle().fill(OnePlusLinearColor.window)
            .overlay(Circle().strokeBorder(FanHeat.color(point.celsius), lineWidth: 2.5))
            .frame(width: active ? Self.knob + 2 : Self.knob, height: active ? Self.knob + 2 : Self.knob)
            .frame(width: Self.hitTarget, height: Self.hitTarget)
            .contentShape(Circle())
            .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                .onChanged { move(index, to: $0.location, plot: plot) }
                .onEnded { _ in
                    if let draft { save(draft) }
                    draft = nil
                    dragging = nil
                    selected = index
                })
            .simultaneousGesture(TapGesture(count: 1).onEnded { selected = index })
            .simultaneousGesture(TapGesture(count: 2).onEnded { editing = index })
            .contextMenu {
                Button("Edit…") { editing = index }
                Button("Remove point", role: .destructive) { remove(index) }.disabled(curve.points.count <= 1)
            }
            .position(position(point, plot))
            .help("\(Int(point.celsius)) °C · \(Int((point.speed * 100).rounded()))%. Drag to move, double-click to type values, right-click to remove.")
            .accessibilityElement()
            .accessibilityLabel("Point \(index + 1): \(Int(point.celsius)) °C, \(Int((point.speed * 100).rounded()))%")
            .accessibilityAction(named: "Edit") { editing = index }
    }

    private static let space = "fan-curve"

    /// Hold's handle at the target, 50%: the same white knob as a curve point, drawn only; the chart takes the drag.
    private func holdKnob(at point: CGPoint) -> some View {
        Circle().fill(OnePlusLinearColor.window)
            .overlay(Circle().strokeBorder(FanHeat.color(holdDraft ?? hold ?? 0), lineWidth: 2.5))
            .frame(width: holdDraft == nil ? Self.knob : Self.knob + 2, height: holdDraft == nil ? Self.knob : Self.knob + 2)
            .position(point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The whole degree under the pointer, kept inside `FanHold.range`.
    private func holdTarget(at location: CGPoint, plot: CGRect) -> Double {
        min(max(value(at: location, plot).celsius, FanHold.range.lowerBound), FanHold.range.upperBound)
    }

    /// A dragged point stays between its neighbors: at least 1 °C apart, below the locked end, and never faster than
    /// the next point or slower than the one before, so the curve keeps rising.
    private func move(_ index: Int, to location: CGPoint, plot: CGRect) {
        var points = curve.points
        guard points.indices.contains(index) else { return }
        let target = value(at: location, plot)
        let low = index > 0 ? points[index - 1] : nil
        let high = index < points.count - 1 ? points[index + 1] : FanCurve.lockedEnd
        let celsius = min(max(target.celsius, (low?.celsius ?? Self.domain.lowerBound - 1) + 1), high.celsius - 1)
        let speed = min(max(target.speed, low?.speed ?? 0), high.speed)
        points[index] = .init(celsius: celsius, speed: speed)
        dragging = index
        draft = FanCurve(points: points)
    }

    private func remove(_ index: Int) {
        let current = FanCurve.load()
        guard current.points.count > 1, current.points.indices.contains(index) else { return }
        var points = current.points
        points.remove(at: index)
        save(FanCurve(points: points))
        selected = nil
        hovered = nil
    }

    /// Delete or Backspace removes the hovered or selected point, unless a text field or the point editor has the keys.
    private func deleteKey(_ event: NSEvent) -> NSEvent? {
        guard [51, 117].contains(event.keyCode),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad]).isEmpty,
              editing == nil, !(event.window?.firstResponder is NSText),
              let index = hovered ?? selected, FanCurve.load().points.count > 1 else { return event }
        remove(index)
        return nil
    }

    /// New points go only inside the plot, below the locked end, at a free temperature.
    private func canAdd(at location: CGPoint, plot: CGRect) -> Bool {
        let celsius = value(at: location, plot).celsius
        return plot.insetBy(dx: -4, dy: -4).contains(location) && curve.points.count < FanCurve.maxPoints
            && celsius <= FanCurve.userCeiling && !curve.points.contains { $0.celsius == celsius }
    }

    private func addPoint(at location: CGPoint, plot: CGRect) {
        guard canAdd(at: location, plot: plot) else { return }
        let target = value(at: location, plot)
        let next = FanCurve(points: curve.points + [.init(celsius: target.celsius, speed: curve.speed(at: target.celsius))])
        save(next)
        editing = next.points.firstIndex { $0.celsius == target.celsius }
    }

}

/// Three dotted guides at 0, 50 and 100%, and 10 pt `tertiary` labels for speed and for 40-80 °C.
private struct FanCurveGrid: View {
    let plot: FanPlot
    private static let labelSize: CGFloat = 10
    private static let celsiusLabels = Array(stride(from: 40.0, through: 80.0, by: 10))

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for speed in [0.0, 0.5, 1.0] {
                    path.move(to: plot.point(FanPlot.domain.lowerBound, speed)); path.addLine(to: plot.point(FanPlot.domain.upperBound, speed))
                }
            }
            .stroke(OnePlusLinearColor.line, style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            ForEach([0.0, 0.5, 1.0], id: \.self) { speed in
                label("\(Int(speed * 100))%").frame(width: 0, alignment: .leading)
                    .position(x: plot.rect.minX + OnePlusLinearMetrics.appletRowPadding, y: plot.y(speed) - 8)
            }
            ForEach(Self.celsiusLabels, id: \.self) { celsius in
                label(celsius == Self.celsiusLabels.last ? "\(Int(celsius)) °C" : "\(Int(celsius))")
                    .position(x: plot.x(celsius), y: plot.rect.maxY + 12)
            }
        }
        .allowsHitTesting(false)
    }

    private func label(_ text: String) -> some View {
        Text(text).linearText(Self.labelSize, color: OnePlusLinearColor.tertiary).monospacedDigit().fixedSize()
    }
}

/// The curve as a 3 pt line in the heat colors, over the same colors fading from 28% to clear.
private struct FanCurveLine: View {
    let plot: FanPlot
    let curve: FanCurve

    var body: some View {
        let points = plot.samples(curve)
        ZStack {
            plot.area(points).fill(FanHeat.gradient)
                .mask(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
            Path { $0.addLines(points) }.stroke(FanHeat.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

/// The fixed end of every curve: full speed from an 80 °C CPU average. An ink dot with a lock, unlike the
/// user's white points, and its label to the left above the plot; it never moves.
private struct FanLockedEnd: View {
    let point: CGPoint
    let plot: CGRect
    var showsCaption = true
    var measured: (CGFloat) -> Void = { _ in }
    static let size: CGFloat = 16
    static let estimatedCaptionWidth: CGFloat = 130

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsCaption {
                Text("Full speed from \(Int(FanCurve.lockedEnd.celsius)) °C")
                    .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.secondary)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: measured)
                    .frame(width: 0, alignment: .trailing)
                    .position(x: point.x - Self.size, y: plot.minY - 11)
                    .allowsHitTesting(false)
            }
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(OnePlusLinearColor.window)
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(OnePlusLinearColor.ink))
                .shadow(color: OnePlusLinearColor.quietKnobShadow, radius: 1.5, y: 1)
                .position(point)
                .help("Locked: the fans always run at full speed from a \(Int(FanCurve.lockedEnd.celsius)) °C CPU average, and when one core stays at \(Int(FanInput.hotCelsius)) °C for \(Int(FanInput.hotSeconds)) s.")
        }
        .accessibilityElement()
        .accessibilityLabel("Locked end point: full speed from \(Int(FanCurve.lockedEnd.celsius)) °C")
    }
}

/// The current CPU temperature on the curve: a dot filled in its heat color with a `window` ring and a soft glow.
private struct FanCurveNow: View {
    let point: CGPoint
    let color: Color
    static let size: CGFloat = 15

    var body: some View {
        Circle().fill(color).overlay(Circle().strokeBorder(OnePlusLinearColor.window, lineWidth: 2.5))
            .shadow(color: color.opacity(0.5), radius: 4)
            .frame(width: Self.size, height: Self.size)
            .position(point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The double-click popover: exact temperature and speed for one point, each clamped so the curve keeps rising.
private struct FanPointEditor: View {
    let curve: FanCurve
    let index: Int
    let save: (FanCurve) -> Void
    let close: () -> Void

    private var point: FanCurve.Point { curve.points[index] }
    private var low: FanCurve.Point? { index > 0 ? curve.points[index - 1] : nil }
    private var high: FanCurve.Point? { index < curve.points.count - 1 ? curve.points[index + 1] : nil }

    private var celsiusRange: ClosedRange<Int> {
        let lower = low.map { Int($0.celsius) + 1 } ?? Int(FanCurve.temperatureRange.lowerBound)
        let upper = high.map { Int($0.celsius) - 1 } ?? Int(FanCurve.userCeiling)
        return lower...max(lower, upper)
    }

    private var speedRange: ClosedRange<Int> {
        let lower = low.map { Int(($0.speed * 100).rounded()) } ?? 0
        return lower...max(lower, high.map { Int(($0.speed * 100).rounded()) } ?? 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnePlusLinearMetrics.sectionCaptionBelow) {
            OnePlusLinearAppletGroup {
                OnePlusLinearAppletRow("Temperature") {
                    OnePlusStepperField("Temperature", value: binding(\.celsius, scale: 1), in: celsiusRange, unit: "°C")
                }
                OnePlusLinearAppletRow("Speed") {
                    OnePlusStepperField("Speed", value: binding(\.speed, scale: 100), in: speedRange, step: 5, unit: "%")
                }
            }
            HStack {
                if curve.points.count > 1 {
                    Button("Remove point", role: .destructive) {
                        var points = curve.points
                        points.remove(at: index)
                        save(FanCurve(points: points))
                        close()
                    }
                    .buttonStyle(OnePlusLinearButtonStyle(.destructive))
                }
                Spacer(minLength: 0)
                Button("Done", action: close).buttonStyle(OnePlusLinearButtonStyle(.soft)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(OnePlusLinearMetrics.panelRowInset + 2)
        .frame(width: 300)
        .background(OnePlusLinearColor.window)
        .environment(\.onePlusLinearControlLook, .quietRaised)
        .onePlusFocusPolicy()
        .onePlusAppAppearance()
    }

    private func binding(_ key: WritableKeyPath<FanCurve.Point, Double>, scale: Double) -> Binding<Int> {
        Binding(get: { Int((point[keyPath: key] * scale).rounded()) }, set: { value in
            var points = curve.points
            points[index][keyPath: key] = Double(value) / scale
            save(FanCurve(points: points))
        })
    }
}
