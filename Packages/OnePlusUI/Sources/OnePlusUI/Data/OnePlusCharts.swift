import SwiftUI

public struct OnePlusSparkline: View {
    private let values: [Double]
    private let range: ClosedRange<Double>
    private let color: Color
    public init(values: [Double], range: ClosedRange<Double> = 0...100, color: Color = OnePlusColor.chartLine) {
        self.values = values; self.range = range; self.color = color
    }
    public var body: some View { OnePlusPlot(values: values, range: range, color: color, area: false) }
}

public struct OnePlusAreaChart: View {
    private let values: [Double]
    private let range: ClosedRange<Double>
    private let color: Color
    public init(values: [Double], range: ClosedRange<Double> = 0...100, color: Color = OnePlusColor.chartLine) {
        self.values = values; self.range = range; self.color = color
    }
    public var body: some View { OnePlusPlot(values: values, range: range, color: color, area: true) }
}

private struct OnePlusPlot: View {
    @Environment(\.colorScheme) private var colorScheme
    let values: [Double]
    let range: ClosedRange<Double>
    let color: Color
    let area: Bool
    var body: some View {
        let paths = OnePlusChartPaths.cached(values: values, range: range)
        Canvas { context, size in
            let transform = CGAffineTransform(scaleX: size.width, y: max(0, size.height - 2)).translatedBy(x: 0, y: 0)
            let line = paths.line.applying(transform)
            if area {
                for y in [CGFloat(0), 0.5, 1] {
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y * size.height))
                    grid.addLine(to: CGPoint(x: size.width, y: y * size.height))
                    context.stroke(grid, with: .color(OnePlusColor.chartGrid), lineWidth: 1)
                }
                context.withCGContext { cg in
                    cg.saveGState()
                    cg.addPath(paths.area.applying(transform).cgPath)
                    cg.clip()
                    cg.beginTransparencyLayer(auxiliaryInfo: nil)
                    cg.setFillColorSpace(CGColorSpace(patternBaseSpace: CGColorSpaceCreateDeviceRGB())!)
                    let gray: CGFloat = colorScheme == .dark ? 1 : 0
                    var components: [CGFloat] = [gray, gray, gray, 1]
                    cg.setFillPattern(OnePlusChartPattern.pattern, colorComponents: &components)
                    cg.fill(CGRect(origin: .zero, size: size))
                    cg.setBlendMode(.destinationIn)
                    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                              colors: [CGColor(gray: 0, alpha: 0.63), CGColor(gray: 0, alpha: 0.06)] as CFArray,
                                              locations: [0, 1])!
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                    cg.endTransparencyLayer()
                    cg.restoreGState()
                }
            }
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .clipped().accessibilityElement(children: .ignore)
        .accessibilityLabel(values.last.flatMap { $0.isFinite ? "Latest value \($0.formatted())" : nil } ?? "No history")
    }
}

@MainActor
final class OnePlusChartPaths {
    let line: Path
    let area: Path
    private static let cache: NSCache<NSString, OnePlusChartPaths> = {
        let cache = NSCache<NSString, OnePlusChartPaths>(); cache.countLimit = 128; return cache
    }()
    static func cached(values: [Double], range: ClosedRange<Double>) -> OnePlusChartPaths {
        let key = "\(range)|\(values)" as NSString
        if let result = cache.object(forKey: key) { return result }
        let result = OnePlusChartPaths(values: values, range: range)
        cache.setObject(result, forKey: key)
        return result
    }
    init(values: [Double], range: ClosedRange<Double>) {
        var line = Path()
        var area = Path()
        let span = max(range.upperBound - range.lowerBound, 0.001)
        var last: CGPoint?
        for (index, value) in values.enumerated() {
            guard value.isFinite else {
                if let last { area.addLine(to: CGPoint(x: last.x, y: 1)); area.closeSubpath() }
                last = nil
                continue
            }
            let x = values.count == 1 ? 0 : Double(index) / Double(values.count - 1)
            let point = CGPoint(x: x, y: 1 - min(max((value - range.lowerBound) / span, 0), 1))
            if last == nil {
                line.move(to: point)
                area.move(to: CGPoint(x: point.x, y: 1))
            } else { line.addLine(to: point) }
            area.addLine(to: point)
            last = point
        }
        if let last {
            if values.count == 1 {
                line.addLine(to: CGPoint(x: 1, y: last.y)); area.addLine(to: CGPoint(x: 1, y: last.y))
            }
            area.addLine(to: CGPoint(x: values.count == 1 ? 1 : last.x, y: 1)); area.closeSubpath()
        }
        self.line = line; self.area = area
    }
}

public struct OnePlusUsageBar: View {
    let value: Double
    let color: Color
    public init(value: Double, color: Color = OnePlusColor.chartSeries[0]) { self.value = value; self.color = color }
    public var body: some View {
        GeometryReader { proxy in
            Capsule().fill(OnePlusColor.line)
                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: proxy.size.width * CGFloat(value.isFinite ? min(max(value, 0), 1) : 0)) }
        }.frame(height: 5)
            .accessibilityElement(children: .ignore).accessibilityLabel("Usage")
            .accessibilityValue(value.isFinite ? "\(Int(min(max(value, 0), 1) * 100)) percent" : "Unavailable")
    }
}

public struct OnePlusSegmentBar: View {
    private let values: [Double]
    private let colors: [Color]
    public init(values: [Double], colors: [Color] = OnePlusColor.chartSeries) { self.values = values; self.colors = colors }
    public var body: some View {
        GeometryReader { proxy in
            let usable = values.map { $0.isFinite ? max(0, $0) : 0 }
            let total = usable.reduce(0, +)
            let count = usable.filter { $0 > 0 }.count
            let width = max(0, proxy.size.width - CGFloat(max(0, count - 1)) * 2)
            HStack(spacing: 2) {
                ForEach(usable.indices, id: \.self) { index in
                    if usable[index] > 0, total > 0 {
                        Capsule().fill(colors.isEmpty ? OnePlusColor.chartLine : colors[index % colors.count])
                            .frame(width: width * usable[index] / total)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).background(OnePlusColor.line, in: Capsule())
        }.frame(height: 5).accessibilityElement(children: .ignore)
            .accessibilityLabel("Usage by category").accessibilityValue(values.map { $0.formatted() }.joined(separator: ", "))
    }
}
