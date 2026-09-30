import Darwin
import Foundation
import OnePlusUI
import SwiftUI

enum TaskManagerTheme {
    static let desktop = OnePlusTheme.desktop
    static let window = OnePlusTheme.window
    static let sidebar = OnePlusTheme.sidebar
    static let card = OnePlusTheme.card
    static let cardHover = OnePlusTheme.cardHover
    static let line = OnePlusTheme.line
    static let lineSoft = OnePlusTheme.lineSoft
    static let ink = OnePlusTheme.ink
    static let secondary = OnePlusTheme.secondary
    static let muted = OnePlusTheme.muted
    static let accent = OnePlusTheme.accent
    static let windowContentSize = OnePlusWindowCanvas.systemMonitor.size
    static let contentInset = OnePlusMetrics.taskManagerGutter
    static let pageTopInset = OnePlusMetrics.contentGap
    static let panelRadius = OnePlusMetrics.panelRadius
    static let controlRadius = OnePlusMetrics.controlRadius
}

typealias TaskManagerPanel<Content: View> = OnePlusPanel<Content>
typealias TaskManagerDitherTexture = OnePlusDitherTexture

struct TaskManagerDotTitle: View {
    let text: String
    var height: CGFloat = 17

    var body: some View {
        OnePlusDotTitle(text, height: height, dotRatio: 0.58)
    }
}

struct TaskManagerHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        OnePlusPageHeader(title: title, subtitle: subtitle, titleStyle: .dotMatrix) {
            trailing()
        }
    }
}

typealias TaskManagerControlTone = OnePlusControlTone
typealias TaskManagerSelect<Value: Hashable> = OnePlusSelect<Value>
typealias TaskManagerSearchField = OnePlusSearchField
typealias TaskManagerSegments<Value: Hashable> = OnePlusSegments<Value>

struct SystemMonitorObservationScope<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
    }
}

enum TaskManagerMetricText {
    static func parts(_ text: String) -> (value: String, unit: String) {
        guard !text.isEmpty else { return ("", "") }
        if text.hasSuffix("%") { return (String(text.dropLast()), "%") }
        guard let split = text.lastIndex(of: " "), split < text.index(before: text.endIndex) else {
            return (text, "")
        }
        return (String(text[..<split]), String(text[text.index(after: split)...]))
    }
}

extension View {
    func taskManagerControl(
        _ tone: TaskManagerControlTone = .standard,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = 27,
        horizontalPadding: CGFloat = 10
    ) -> some View {
        onePlusControl(
            tone,
            minWidth: minWidth,
            minHeight: minHeight,
            horizontalPadding: horizontalPadding
        )
    }
}

extension TaskManagerHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        trailing = { EmptyView() }
    }
}

nonisolated enum TaskManagerChartGeometry {
    static func xPositions(count: Int, capacity: Int, width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let capacity = max(capacity, count, 2)
        let step = width / CGFloat(capacity - 1)
        let start = max(0, width - step * CGFloat(count - 1))
        return (0..<count).map { start + CGFloat($0) * step }
    }

    static func sampleIndex(at x: CGFloat, count: Int, capacity: Int, width: CGFloat) -> Int {
        guard count > 1 else { return 0 }
        let positions = xPositions(count: count, capacity: capacity, width: width)
        let step = width / CGFloat(max(capacity, count, 2) - 1)
        return min(max(Int(((x - positions[0]) / max(step, 1)).rounded()), 0), count - 1)
    }
}

struct TaskManagerHistoryChart: View {
    let values: [Double]
    var secondary: [Double] = []
    var range: ClosedRange<Double> = 0...100
    var unit = "%"
    var compact = false
    var sampleCapacity = 120
    var stepped = false
    var upperScaleLabel: String?
    var middleScaleLabel: String?
    var lowerScaleLabel: String?
    var scaleLabels: [String] = []
    var primaryColor = TaskManagerTheme.ink.opacity(0.76)
    var secondaryColor = TaskManagerTheme.accent
    @State private var hoverX: CGFloat?

    @ViewBuilder
    var body: some View {
        if compact {
            plot
        } else {
            HStack(spacing: 8) {
                if let upperScaleLabel, let lowerScaleLabel {
                    let labels = scaleLabels.isEmpty
                        ? [upperScaleLabel, middleScaleLabel ?? "", lowerScaleLabel] : scaleLabels
                    GeometryReader { proxy in
                        ForEach(labels.indices, id: \.self) { index in
                            Text(labels[index])
                                .frame(width: proxy.size.width, alignment: .trailing)
                                .position(x: proxy.size.width / 2,
                                          y: proxy.size.height * gridFractions[index])
                        }
                    }
                    .font(.system(size: 8))
                    .monospacedDigit()
                    .foregroundStyle(TaskManagerTheme.muted)
                    .frame(width: 54, alignment: .trailing)
                    .allowsHitTesting(false)
                }
                plot
            }
        }
    }

    private var plot: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    draw(values, color: primaryColor, context: &context, size: size, fills: true)
                    draw(secondary, color: secondaryColor, context: &context, size: size, fills: false)
                }
                if let hoverX, !values.isEmpty {
                    let index = TaskManagerChartGeometry.sampleIndex(
                        at: hoverX,
                        count: values.count,
                        capacity: sampleCapacity,
                        width: proxy.size.width
                    )
                    Rectangle()
                        .fill(TaskManagerTheme.secondary.opacity(0.65))
                        .frame(width: 1)
                        .overlay(alignment: .topLeading) {
                            Text(values[index].formatted(.number.precision(.fractionLength(values[index] < 10 ? 1 : 0))) + (unit.isEmpty ? "" : " " + unit))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(TaskManagerTheme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(OnePlusColor.raised,
                                            in: RoundedRectangle(cornerRadius: 4))
                                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(OnePlusColor.line) }
                                .offset(x: hoverX > proxy.size.width - 62 ? -58 : 4, y: 2)
                        }
                        .offset(x: hoverX)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverX = min(max(location.x, 0), proxy.size.width)
                case .ended: hoverX = nil
                }
            }
        }
        .clipped()
        .accessibilityLabel(values.last.map { "Latest value \($0.formatted())\(unit)" } ?? "No history")
    }

    private var gridFractions: [CGFloat] {
        let count = scaleLabels.isEmpty ? 3 : max(scaleLabels.count, 2)
        return (0..<count).map { CGFloat($0) / CGFloat(count - 1) }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for fraction in gridFractions {
            var path = Path()
            let y = min((fraction * size.height).rounded(.down), (size.height - 1).rounded(.down)) + 0.5
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(OnePlusColor.chartGrid), lineWidth: 1)
        }
    }

    private func draw(
        _ samples: [Double], color: Color, context: inout GraphicsContext,
        size: CGSize, fills: Bool
    ) {
        let samples = samples.filter(\.isFinite)
        guard !samples.isEmpty else { return }
        let span = max(range.upperBound - range.lowerBound, 0.001)
        let positions = TaskManagerChartGeometry.xPositions(
            count: samples.count,
            capacity: sampleCapacity,
            width: size.width
        )
        let points = samples.enumerated().map { index, value in
            CGPoint(
                x: positions[index],
                y: size.height - CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span) * size.height
            )
        }
        if fills {
            var area = Path()
            area.move(to: CGPoint(x: points[0].x, y: size.height))
            append(points, to: &area)
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            context.drawLayer { layer in
                layer.clip(to: area)
                let order = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
                var dots = Path()
                let pitch: CGFloat = 4
                for row in 0..<Int(ceil(size.height / pitch)) {
                    let density = (1 - CGFloat(row) * pitch / max(size.height, 1)) * 0.55
                    for column in 0..<Int(ceil(size.width / pitch))
                    where CGFloat(order[(row % 4) * 4 + column % 4]) / 16 < density {
                        dots.addEllipse(in: CGRect(x: CGFloat(column) * pitch + 1.5,
                                                   y: CGFloat(row) * pitch + 1.5,
                                                   width: 0.8, height: 0.8))
                    }
                }
                layer.fill(dots, with: .color(TaskManagerTheme.ink.opacity(0.22)))
            }
        }
        var path = Path()
        path.move(to: points[0])
        append(Array(points.dropFirst()), after: points[0], to: &path)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: compact ? 1 : 1.2, lineCap: .round, lineJoin: .round))
        if points.count == 1 {
            context.fill(
                Path(ellipseIn: CGRect(x: points[0].x - 1.5, y: points[0].y - 1.5, width: 3, height: 3)),
                with: .color(color)
            )
        }
    }

    private func append(_ points: [CGPoint], to path: inout Path) {
        guard let first = points.first else { return }
        path.addLine(to: first)
        append(Array(points.dropFirst()), after: first, to: &path)
    }

    private func append(_ points: [CGPoint], after first: CGPoint, to path: inout Path) {
        var previous = first
        for point in points {
            if stepped { path.addLine(to: CGPoint(x: point.x, y: previous.y)) }
            path.addLine(to: point)
            previous = point
        }
    }

}

enum TaskManagerHardwareSummary {
    static let coreLayout: (performance: Int, efficiency: Int)? = {
        guard let performance = sysctlInt("hw.perflevel0.logicalcpu"),
              let efficiency = sysctlInt("hw.perflevel1.logicalcpu"),
              performance > 0, efficiency > 0 else { return nil }
        return (performance, efficiency)
    }()

    static let current: String = {
        let chip = sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.model") ?? "Mac"
        let memory = ByteCountFormatter.string(
            fromByteCount: Int64(min(ProcessInfo.processInfo.physicalMemory, UInt64(Int64.max))),
            countStyle: .memory
        )
        return "\(chip) · \(ProcessInfo.processInfo.activeProcessorCount) cores · \(memory)"
    }()

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
