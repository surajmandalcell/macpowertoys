import OnePlusUI
import SwiftUI

/// The Fan page (owner pick "Big chart", 2026-11-20): the Cool curve as one large chart. Drag a point to move it,
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
    private var hold: Double? { holdCelsius.map { min(max($0, FanHold.range.lowerBound), FanHold.range.upperBound) } }
    private var nowCelsius: Double? { service.display.cpuCelsius.map(Double.init) }
    private var nowChip: String? { service.display.cpuCelsius.map { "\($0) °C · \(service.display.rpm)" } }

    var body: some View {
        OnePlusLinearEditorialBody {
            OnePlusLinearToolHeader(Self.title, detail: "Set how fast the fans spin in Cool as the CPU heats up.") {
                FanPageIcon(size: OnePlusLinearEditorialMetrics.headerIcon)
            } actions: { EmptyView() }
            OnePlusLinearAppletSection("Cool curve") {
                VStack(spacing: 0) {
                    if let hold {
                        FanHoldChart(target: hold, nowCelsius: nowCelsius, nowChip: nowChip).padding(.top, 12)
                        FanHintRow(text: "Holds \(Int(hold)) °C, give or take \(Int(FanHold.band)) °C, with a steady fan speed") {
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
            FanPresetCards(preset: preset, hold: hold, custom: custom)
        } footer: { EmptyView() }
        .transformEnvironment(\.onePlusLinearControlLook) { if $0 == nil { $0 = .quietRaised } }
        .onAppear { service.start(owner: Self.owner) }
        .onDisappear { service.stop(owner: Self.owner) }
        .accessibilityIdentifier("fan.page")
    }

    private var nowText: String {
        let display = service.display
        return [display.cpuCelsius.map { CPUHeat.help($0) }, display.rpm].compactMap(\.self).joined(separator: " · ")
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

/// The five picks under the chart (owner picks "Curve cards" and "By sound", 2026-11-20), each with a small picture
/// of what it does. A curve card picks its curve and turns Hold off; Hold sets its target.
private struct FanPresetCards: View {
    let preset: FanCurvePreset
    let hold: Double?
    let custom: FanCurve
    private static let gap: CGFloat = 8

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach([FanCurvePreset.silent, .quiet, .steady], id: \.self) { item in
                card(item.name, selected: hold == nil && preset == item, shape: .curve(item.curve ?? custom)) { item.pick() }
            }
            let target = hold ?? FanHold.savedTarget() ?? FanHold.defaultTarget
            card("Hold \(Int(target)) °C", selected: hold != nil, shape: .hold(target)) { FanHold.save(target) }
            card(FanCurvePreset.custom.name, selected: hold == nil && preset == .custom, shape: .curve(custom)) {
                FanCurvePreset.custom.pick()
            }
        }
    }

    private func card(_ name: String, selected: Bool, shape: FanMiniChart.Shape, pick: @escaping () -> Void) -> some View {
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
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A card's picture on the full 30-100 °C scale: the curve with a soft fill, or for Hold the target line in its band.
private struct FanMiniChart: View {
    enum Shape { case curve(FanCurve), hold(Double) }
    let shape: Shape
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let plot = FanPlot(rect: CGRect(origin: .zero, size: geo.size).insetBy(dx: 2, dy: 2))
            switch shape {
            case .curve(let curve):
                let points = plot.samples(curve)
                ZStack {
                    plot.area(points).fill(tint.opacity(0.12))
                    Path { $0.addLines(points) }.stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            case .hold(let target):
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(tint.opacity(0.12))
                        .frame(width: plot.x(target + FanHold.band) - plot.x(target - FanHold.band), height: plot.rect.height)
                        .position(x: plot.x(target), y: plot.rect.midY)
                    Path { $0.move(to: plot.point(target, 0)); $0.addLine(to: plot.point(target, 1)) }
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Temperature across (30-100 °C) and speed up (0-1) inside one rectangle.
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

/// The "Heat line" colors (owner pick, 2026-11-20): cool blue through the `CPUHeat` steps to very hot red.
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
        .init(color: OnePlusLinearColor.temperatureCool, location: 0.1), .init(color: OnePlusLinearColor.temperatureWarm, location: 0.45),
        .init(color: OnePlusLinearColor.temperatureHot, location: 0.7), .init(color: OnePlusLinearColor.temperatureVeryHot, location: 0.86),
    ], startPoint: .leading, endPoint: .trailing)
}

/// A small reading above a chart point, such as "64 °C · 3,039 RPM".
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

/// Hold has no curve: the target as a dashed `ink` line in its ±2 °C band, and the CPU now as a heat-colored line.
private struct FanHoldChart: View {
    let target: Double
    let nowCelsius: Double?
    let nowChip: String?

    var body: some View {
        GeometryReader { geo in
            let plot = FanPlot(rect: CGRect(x: 0, y: FanCurveEditor.inset.top, width: geo.size.width,
                                            height: geo.size.height - FanCurveEditor.inset.top - FanCurveEditor.inset.bottom))
            ZStack(alignment: .topLeading) {
                FanCurveGrid(plot: plot)
                Rectangle().fill(OnePlusLinearColor.ink.opacity(0.07))
                    .frame(width: plot.x(target + FanHold.band) - plot.x(target - FanHold.band), height: plot.rect.height)
                    .position(x: plot.x(target), y: plot.rect.midY)
                Path { $0.move(to: plot.point(target, 0)); $0.addLine(to: plot.point(target, 1)) }
                    .stroke(OnePlusLinearColor.ink, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Text("Hold \(Int(target)) °C").linearText(OnePlusLinearMetrics.caption, weight: .semibold)
                    .fixedSize().frame(width: 0, alignment: .trailing)
                    .position(x: plot.x(target - FanHold.band) - 8, y: plot.rect.minY + 10)
                Path { $0.move(to: plot.point(FanCurve.lockedEnd.celsius, 1)); $0.addLine(to: plot.point(FanPlot.domain.upperBound, 1)) }
                    .stroke(OnePlusLinearColor.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                FanLockedEnd(point: plot.point(FanCurve.lockedEnd.celsius, 1), plot: plot.rect)
                if let nowCelsius {
                    let x = plot.x(min(max(nowCelsius, FanPlot.domain.lowerBound), FanPlot.domain.upperBound))
                    Path { $0.move(to: CGPoint(x: x, y: plot.rect.maxY)); $0.addLine(to: CGPoint(x: x, y: plot.rect.minY + 52)) }
                        .stroke(FanHeat.color(nowCelsius), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    Circle().fill(FanHeat.color(nowCelsius)).overlay(Circle().strokeBorder(OnePlusLinearColor.window, lineWidth: 2))
                        .frame(width: 11, height: 11).position(x: x, y: plot.rect.maxY)
                    if let nowChip { FanChip(text: nowChip).position(x: x, y: plot.rect.minY + 40) }
                }
            }
        }
        .frame(height: FanCurveEditor.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold \(Int(target)) °C, give or take \(Int(FanHold.band)) °C")
    }
}

/// The page icon (owner pick "Neutral fan", 2026-11-20): Midnight in Light, Porcelain in Dark, like Portman.
struct FanPageIcon: View {
    let size: CGFloat

    var body: some View {
        Image("FanLogo")
            .resizable().scaledToFit()
            .toolIconTile(size: size)
            .accessibilityHidden(true)
    }
}

/// Temperature across (30-100 °C), speed up (0% at each fan's minimum, 100% at its maximum).
struct FanCurveEditor: View {
    let curve: FanCurve
    let nowCelsius: Double?
    let nowChip: String?
    let save: (FanCurve) -> Void

    @State private var draft: FanCurve?
    @State private var dragging: Int?
    @State private var hovered: Int?
    @State private var editing: Int?
    @State private var selected: Int?
    @State private var pointer: CGPoint?
    @State private var keyMonitor: Any?

    private static let domain = FanCurve.temperatureRange
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
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .named(Self.space)) {
                        if case .active(let location) = $0 { pointer = location } else { pointer = nil }
                    }
                    .onTapGesture(count: 2) { addPoint(at: $0, plot: plot) }
                    .contextMenu {
                        Button("Add point here") { if let pointer { addPoint(at: pointer, plot: plot) } }
                            .disabled(pointer.map { !canAdd(at: $0, plot: plot) } ?? true)
                    }
                FanCurveLine(plot: FanPlot(rect: plot), curve: shown)
                ForEach(shown.points.indices, id: \.self) { index in knob(index, plot: plot) }
                FanLockedEnd(point: position(FanCurve.lockedEnd, plot), plot: plot)
                if let now = nowPoint(plot), let nowCelsius {
                    FanCurveNow(point: now, color: FanHeat.color(nowCelsius))
                    if let nowChip, dragging == nil { FanChip(text: nowChip).position(x: now.x, y: now.y - 22) }
                }
                if let dragging, shown.points.indices.contains(dragging) {
                    let point = shown.points[dragging], at = position(shown.points[dragging], plot)
                    FanChip(text: "\(Int(point.celsius)) °C · \(Int((point.speed * 100).rounded()))%").position(x: at.x, y: at.y - 22)
                }
            }
            .coordinateSpace(name: Self.space)
            .popover(isPresented: editingBinding, attachmentAnchor: .rect(.rect(anchor(plot))), arrowEdge: .top) {
                if let editing, curve.points.indices.contains(editing) {
                    FanPointEditor(curve: curve, index: editing, save: save) { self.editing = nil }
                }
            }
        }
        .frame(height: Self.height)
        .task {
            // Screenshot checks open a point's popover without a click: `MPTDiagnosticFanEditPoint` is the 1-based point.
            try? await Task.sleep(for: .milliseconds(600))
            let point = UserDefaults.standard.integer(forKey: "MPTDiagnosticFanEditPoint")
            if curve.points.indices.contains(point - 1) { editing = point - 1 }
        }
        .onAppear { keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: deleteKey) }
        .onDisappear {
            keyMonitor.map(NSEvent.removeMonitor)
            keyMonitor = nil
            selected = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cool curve")
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

/// Three dotted guides at 0, 50 and 100%, and 10 pt `tertiary` labels for speed and for 40-90 °C.
private struct FanCurveGrid: View {
    let plot: FanPlot
    private static let labelSize: CGFloat = 10
    private static let celsiusLabels = Array(stride(from: 40.0, through: 90.0, by: 10))

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

/// The fixed end of every curve (owner, 2026-11-20): full speed from 90 °C. An ink dot with a lock, unlike the
/// user's white points, and its label to the left above the plot; it never moves.
private struct FanLockedEnd: View {
    let point: CGPoint
    let plot: CGRect
    private static let size: CGFloat = 16

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("Full speed from \(Int(FanCurve.lockedEnd.celsius)) °C")
                .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.secondary)
                .fixedSize()
                .frame(width: 0, alignment: .trailing)
                .position(x: point.x - Self.size, y: plot.minY - 11)
                .allowsHitTesting(false)
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(OnePlusLinearColor.window)
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(OnePlusLinearColor.ink))
                .shadow(color: OnePlusLinearColor.quietKnobShadow, radius: 1.5, y: 1)
                .position(point)
                .help("Locked: the fans always run at full speed from \(Int(FanCurve.lockedEnd.celsius)) °C, where the chip is close to throttling.")
        }
        .accessibilityElement()
        .accessibilityLabel("Locked end point: full speed from \(Int(FanCurve.lockedEnd.celsius)) °C")
    }
}

/// The current CPU temperature on the curve: a dot filled in its heat color with a `window` ring and a soft glow.
private struct FanCurveNow: View {
    let point: CGPoint
    let color: Color

    var body: some View {
        Circle().fill(color).overlay(Circle().strokeBorder(OnePlusLinearColor.window, lineWidth: 2.5))
            .shadow(color: color.opacity(0.5), radius: 4)
            .frame(width: 15, height: 15)
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
