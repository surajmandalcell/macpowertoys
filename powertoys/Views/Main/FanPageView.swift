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

    private var curve: FanCurve {
        curveData.flatMap { try? JSONDecoder().decode(FanCurve.self, from: $0) } ?? .standard
    }

    var body: some View {
        OnePlusLinearEditorialBody {
            OnePlusLinearToolHeader(Self.title, detail: "Set how fast the fans spin in Cool as the CPU heats up.") {
                FanPageIcon(size: OnePlusLinearEditorialMetrics.headerIcon)
            } actions: { EmptyView() }
            OnePlusLinearAppletSection("Cool curve") {
                VStack(spacing: 0) {
                    FanCurveEditor(curve: curve, nowCelsius: service.display.cpuCelsius.map(Double.init)) { $0.save() }
                        .padding(.top, 12)
                    Text("Drag points · double-click to edit · right-click to add or remove")
                        .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 10)
                }
                OnePlusLinearAppletRow("Now", value: nowText, systemImage: "thermometer.medium")
            }
            Button("Reset to the standard curve", role: .destructive) { FanCurve.standard.save() }
                .buttonStyle(OnePlusLinearButtonStyle(.resetBlock))
                .disabled(curveData == nil)
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
    private static let inset = EdgeInsets(top: 22, leading: 0, bottom: 22, trailing: 0)
    private static let height: CGFloat = 240
    private static let hitTarget: CGFloat = 24
    private static let knob: CGFloat = 12
    private static let labelSize: CGFloat = 10

    private var shown: FanCurve { draft ?? curve }

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: Self.inset.leading, y: Self.inset.top,
                              width: geo.size.width - Self.inset.leading - Self.inset.trailing,
                              height: geo.size.height - Self.inset.top - Self.inset.bottom)
            ZStack(alignment: .topLeading) {
                FanCurveGrid(plot: plot, domain: Self.domain, labelSize: Self.labelSize)
                FanSafetyBand(points: [FanCurve.safetyStart, FanCurve.safetyFull, Self.domain.upperBound].map {
                    position(.init(celsius: $0, speed: FanCurve.safetyFloor(at: $0)), plot)
                }, plot: plot)
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .named(Self.space)) {
                        if case .active(let location) = $0 { pointer = location } else { pointer = nil }
                    }
                    .onTapGesture(count: 2) { addPoint(at: $0, plot: plot) }
                    .contextMenu {
                        Button("Add point here") { if let pointer { addPoint(at: pointer, plot: plot) } }
                            .disabled(pointer == nil || curve.points.count >= FanCurve.maxPoints)
                    }
                FanCurveLine(points: (Array(stride(from: plot.minX, to: plot.maxX, by: 2)) + [plot.maxX]).map { x in
                    let celsius = Self.domain.lowerBound
                        + (Self.domain.upperBound - Self.domain.lowerBound) * Double((x - plot.minX) / plot.width)
                    return position(.init(celsius: celsius, speed: shown.curveSpeed(at: celsius)), plot)
                }, plot: plot)
                if let nowCelsius {
                    FanCurveNow(point: position(.init(celsius: min(max(nowCelsius, Self.domain.lowerBound), Self.domain.upperBound),
                                                      speed: shown.speed(at: nowCelsius)), plot), plot: plot)
                }
                ForEach(shown.points.indices, id: \.self) { index in knob(index, plot: plot) }
                if let dragging, shown.points.indices.contains(dragging) {
                    bubble(shown.points[dragging], at: position(shown.points[dragging], plot))
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

    private func knob(_ index: Int, plot: CGRect) -> some View {
        let point = shown.points[index]
        let active = dragging == index || hovered == index || editing == index || selected == index
        return Circle().fill(OnePlusLinearColor.quietKnob)
            .overlay(Circle().strokeBorder(active ? OnePlusLinearColor.ink : OnePlusLinearColor.quietKnobLine,
                                           lineWidth: active ? 1.5 : 1))
            .shadow(color: OnePlusLinearColor.quietKnobShadow, radius: 1.5, y: 1)
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
                Button("Remove point", role: .destructive) { remove(index) }.disabled(curve.points.count <= 2)
            }
            .position(position(point, plot))
            .help("\(Int(point.celsius)) °C · \(Int((point.speed * 100).rounded()))%. Drag to move, double-click to type values, right-click to remove.")
            .accessibilityElement()
            .accessibilityLabel("Point \(index + 1): \(Int(point.celsius)) °C, \(Int((point.speed * 100).rounded()))%")
            .accessibilityAction(named: "Edit") { editing = index }
    }

    private static let space = "fan-curve"

    /// A dragged point stays between its neighbors: at least 1 °C apart, and never faster than the next point or
    /// slower than the one before, so the curve keeps rising.
    private func move(_ index: Int, to location: CGPoint, plot: CGRect) {
        var points = curve.points
        guard points.indices.contains(index) else { return }
        let target = value(at: location, plot)
        let low = index > 0 ? points[index - 1] : nil
        let high = index < points.count - 1 ? points[index + 1] : nil
        let celsius = min(max(target.celsius, (low?.celsius ?? Self.domain.lowerBound - 1) + 1),
                          (high?.celsius ?? Self.domain.upperBound + 1) - 1)
        let speed = min(max(target.speed, low?.speed ?? 0), high?.speed ?? 1)
        points[index] = .init(celsius: celsius, speed: speed)
        dragging = index
        draft = FanCurve(points: points)
    }

    private func remove(_ index: Int) {
        let current = FanCurve.load()
        guard current.points.count > 2, current.points.indices.contains(index) else { return }
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
              let index = hovered ?? selected, FanCurve.load().points.count > 2 else { return event }
        remove(index)
        return nil
    }

    private func addPoint(at location: CGPoint, plot: CGRect) {
        guard plot.insetBy(dx: -4, dy: -4).contains(location), curve.points.count < FanCurve.maxPoints else { return }
        let target = value(at: location, plot)
        guard !curve.points.contains(where: { $0.celsius == target.celsius }) else { return }
        let next = FanCurve(points: curve.points + [.init(celsius: target.celsius, speed: curve.curveSpeed(at: target.celsius))])
        save(next)
        editing = next.points.firstIndex { $0.celsius == target.celsius }
    }

    private func bubble(_ point: FanCurve.Point, at p: CGPoint) -> some View {
        Text("\(Int(point.celsius)) °C · \(Int((point.speed * 100).rounded()))%")
            .linearText(OnePlusLinearMetrics.caption, weight: .medium)
            .monospacedDigit()
            .padding(.horizontal, 7).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(OnePlusLinearColor.button)
                .shadow(color: OnePlusLinearColor.quietKnobShadow, radius: 3, y: 1))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(OnePlusLinearColor.buttonRing, lineWidth: 1))
            .fixedSize()
            .position(x: p.x, y: p.y - 22)
            .allowsHitTesting(false)
    }
}

private struct FanCurveGrid: View {
    let plot: CGRect
    let domain: ClosedRange<Double>
    let labelSize: CGFloat
    private let pad = OnePlusLinearMetrics.appletRowPadding

    private func x(_ celsius: Double) -> CGFloat {
        plot.minX + plot.width * (celsius - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
    }

    private func y(_ speed: Double) -> CGFloat { plot.maxY - plot.height * speed }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for speed in stride(from: 0.0, through: 1.0, by: 0.25) {
                    path.move(to: CGPoint(x: plot.minX, y: y(speed))); path.addLine(to: CGPoint(x: plot.maxX, y: y(speed)))
                }
                for celsius in stride(from: domain.lowerBound, through: domain.upperBound, by: 10) {
                    path.move(to: CGPoint(x: x(celsius), y: plot.minY)); path.addLine(to: CGPoint(x: x(celsius), y: plot.maxY))
                }
            }
            .stroke(OnePlusLinearColor.line, lineWidth: 1)
            ForEach([0.0, 0.5, 1.0], id: \.self) { speed in
                Text("\(Int(speed * 100))%").linearText(labelSize, color: OnePlusLinearColor.secondary).monospacedDigit()
                    .fixedSize().frame(width: 0, alignment: .leading)
                    .position(x: plot.minX + pad, y: y(speed) - labelSize * 0.8)
            }
            ForEach(Array(stride(from: domain.lowerBound, through: domain.upperBound, by: 10)), id: \.self) { celsius in
                let first = celsius == domain.lowerBound, last = celsius == domain.upperBound
                Text(last ? "100 °C" : "\(Int(celsius))")
                    .linearText(labelSize, color: OnePlusLinearColor.secondary).monospacedDigit()
                    .fixedSize().frame(width: 0, alignment: first ? .leading : last ? .trailing : .center)
                    .position(x: first ? plot.minX + pad : last ? plot.maxX - pad : x(celsius), y: plot.maxY + 12)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FanCurveLine: View {
    let points: [CGPoint]
    let plot: CGRect

    var body: some View {
        ZStack {
            // `addLines` would start a new subpath, so the fill adds each sample to the bottom-left start instead.
            Path { path in
                path.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                points.forEach { path.addLine(to: $0) }
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                path.closeSubpath()
            }
            .fill(OnePlusLinearColor.ink.opacity(0.06))
            Path { $0.addLines(points) }
                .stroke(OnePlusLinearColor.ink, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

/// The safety floor (90-95 °C ramp to full speed): a fixed red-tinted band no point can move, with its label above.
private struct FanSafetyBand: View {
    let points: [CGPoint]
    let plot: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: points[0].x, y: plot.maxY))
                points.forEach { path.addLine(to: $0) }
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                path.closeSubpath()
            }
            .fill(OnePlusLinearColor.temperatureCritical.opacity(0.1))
            Path { $0.addLines(points) }
                .stroke(OnePlusLinearColor.temperatureCritical.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Text("Safety: full speed by 95 °C")
                .linearText(OnePlusLinearMetrics.caption, color: OnePlusLinearColor.temperatureCritical)
                .fixedSize()
                .frame(width: 0, alignment: .trailing)
                .position(x: plot.maxX - OnePlusLinearMetrics.appletRowPadding, y: plot.minY - 11)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Safety floor: the fans reach full speed by 95 °C whatever the curve says")
    }
}

/// The current CPU temperature on the curve: an accent dot with a dashed guide down to the axis.
private struct FanCurveNow: View {
    let point: CGPoint
    let plot: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { $0.move(to: CGPoint(x: point.x, y: plot.maxY)); $0.addLine(to: point) }
                .stroke(OnePlusLinearColor.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Circle().fill(OnePlusLinearColor.accent.opacity(0.22)).frame(width: 16, height: 16).position(point)
            Circle().fill(OnePlusLinearColor.accent).frame(width: 8, height: 8).position(point)
        }
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
        let upper = high.map { Int($0.celsius) - 1 } ?? Int(FanCurve.temperatureRange.upperBound)
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
                if curve.points.count > 2 {
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
