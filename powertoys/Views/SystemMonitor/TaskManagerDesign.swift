import AppKit
import Darwin
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

    static let windowContentSize = NSSize(width: 1_080, height: 660)
    static let sidebarWidth: CGFloat = 220
    static let headerHeight: CGFloat = 62
    static let contentInset: CGFloat = 20
    static let pageTopInset: CGFloat = 16
    static let panelRadius = OnePlusMetrics.panelRadius
    static let controlRadius = OnePlusMetrics.controlRadius
}

typealias TaskManagerPanel<Content: View> = OnePlusPanel<Content>
typealias TaskManagerDitherTexture = OnePlusDitherTexture

struct TaskManagerHeaderArtwork: View {
    var body: some View {
        Image("TaskManagerRibbon")
            .resizable()
            .interpolation(.none)
            .frame(width: 285, height: 90)
            .opacity(0.27)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.26),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct TaskManagerWorkspaceArtwork: View {
    var body: some View {
        Image("TaskManagerRibbon")
            .resizable()
            .interpolation(.none)
            .frame(width: 950, height: 300)
            .opacity(0.09)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct TaskManagerDotTitle: View {
    let text: String
    var height: CGFloat = 17

    private static let glyphs: [Character: [String]] = [
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["111", "010", "010", "010", "010", "010", "111"],
        "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        " ": ["000", "000", "000", "000", "000", "000", "000"],
    ]

    private var columns: Int {
        text.uppercased().reduce(0) { width, character in
            width + (Self.glyphs[character]?.first?.count ?? 5) + 1
        } - 1
    }

    var body: some View {
        let scale = height / 7
        Canvas { context, _ in
            var x = 0
            var path = Path()
            for character in text.uppercased() {
                let glyph = Self.glyphs[character] ?? Self.glyphs[" "]!
                for (row, line) in glyph.enumerated() {
                    for (column, bit) in line.enumerated() where bit == "1" {
                        let point = CGPoint(
                            x: (CGFloat(x + column) + 0.5) * scale,
                            y: (CGFloat(row) + 0.5) * scale
                        )
                        let diameter = max(1.15, scale * 0.58)
                        path.addEllipse(in: CGRect(
                            x: point.x - diameter / 2,
                            y: point.y - diameter / 2,
                            width: diameter,
                            height: diameter
                        ))
                    }
                }
                x += (glyph.first?.count ?? 5) + 1
            }
            context.fill(path, with: .color(TaskManagerTheme.ink))
        }
        .frame(width: CGFloat(max(columns, 1)) * scale, height: height)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

struct TaskManagerHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack(alignment: .trailing) {
            TaskManagerHeaderArtwork()
                .offset(x: -18, y: -10)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    TaskManagerDotTitle(text: title)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(TaskManagerTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                trailing()
            }
            .padding(.horizontal, TaskManagerTheme.contentInset)
        }
        .frame(height: TaskManagerTheme.headerHeight)
        .clipped()
    }
}

typealias TaskManagerControlTone = OnePlusControlTone
typealias TaskManagerSelect<Value: Hashable> = OnePlusSelect<Value>
typealias TaskManagerSearchField = OnePlusSearchField
typealias TaskManagerSegments<Value: Hashable> = OnePlusSegments<Value>

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
