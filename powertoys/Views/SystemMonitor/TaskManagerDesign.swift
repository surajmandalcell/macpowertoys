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
    static let pageTopInset = OnePlusMetrics.contentTop
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

struct TaskManagerHistoryChart: View {
    let values: [Double]
    var secondary: [Double] = []
    var range: ClosedRange<Double> = 0...100
    var unit = "%"
    var compact = false
    var upperScaleLabel: String?
    var lowerScaleLabel: String?
    var primaryColor = TaskManagerTheme.ink.opacity(0.76)
    var secondaryColor = TaskManagerTheme.accent
    @State private var hoverX: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    draw(values, color: primaryColor, context: &context, size: size, fills: true)
                    draw(secondary, color: secondaryColor, context: &context, size: size, fills: false)
                }
                if !compact, let upperScaleLabel, let lowerScaleLabel {
                    VStack(alignment: .trailing) {
                        Text(upperScaleLabel)
                        Spacer()
                        Text(lowerScaleLabel)
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(TaskManagerTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(4)
                    .allowsHitTesting(false)
                }
                if let hoverX, !values.isEmpty {
                    let index = min(max(Int((hoverX / max(proxy.size.width, 1)) * CGFloat(values.count - 1)), 0), values.count - 1)
                    Rectangle()
                        .fill(TaskManagerTheme.secondary.opacity(0.65))
                        .frame(width: 1)
                        .overlay(alignment: .topLeading) {
                            Text(values[index].formatted(.number.precision(.fractionLength(values[index] < 10 ? 1 : 0))) + unit)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(TaskManagerTheme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.97),
                                            in: RoundedRectangle(cornerRadius: 4))
                                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.18)) }
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
        .frame(minHeight: compact ? 12 : 118)
        .accessibilityLabel(values.last.map { "Latest value \($0.formatted())\(unit)" } ?? "No history")
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for fraction in [CGFloat(0), 0.5, 1] {
            var path = Path()
            let y = fraction * size.height
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(TaskManagerTheme.lineSoft), lineWidth: 0.65)
        }
    }

    private func draw(
        _ samples: [Double], color: Color, context: inout GraphicsContext,
        size: CGSize, fills: Bool
    ) {
        let samples = samples.filter(\.isFinite)
        guard !samples.isEmpty else { return }
        let span = max(range.upperBound - range.lowerBound, 0.001)
        let points = samples.enumerated().map { index, value in
            CGPoint(
                x: samples.count == 1 ? size.width : CGFloat(index) / CGFloat(samples.count - 1) * size.width,
                y: size.height - CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span) * size.height
            )
        }
        if fills {
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            points.forEach { area.addLine(to: $0) }
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
                layer.fill(dots, with: .color(Color.white.opacity(0.22)))
            }
        }
        var path = Path()
        path.addLines(points)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: compact ? 1 : 1.2, lineCap: .round, lineJoin: .round))
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
