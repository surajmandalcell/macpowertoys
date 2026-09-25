import SwiftUI

enum DiskChartStyle: String, CaseIterable, Identifiable {
    case treemap = "Treemap"
    case sunburst = "Rings"

    var id: String { rawValue }
    var symbol: String { self == .treemap ? "square.grid.3x3.fill" : "circle.hexagongrid.fill" }
}

private enum DiskChartPalette {
    static let colors: [Color] = [
        .blue, .teal, .orange, .indigo, .mint, .pink, .purple, .cyan, .brown, .green
    ]

    static func color(_ index: Int) -> Color { colors[index % colors.count] }
}

private struct DiskChartTile {
    let entry: DiskEntry?
    let label: String
    let bytes: Int64
    let color: Color
    var rect: CGRect = .zero
}

struct DiskTreemapView: View {
    let directory: DiskEntry
    let apparent: Bool
    let select: (DiskEntry) -> Void

    private var tiles: [DiskChartTile] {
        let positive = directory.children.filter { $0.bytes(apparent: apparent) > 0 }
        var result = Array(positive.prefix(80)).enumerated().map { index, entry in
            DiskChartTile(entry: entry, label: entry.name, bytes: entry.bytes(apparent: apparent),
                          color: DiskChartPalette.color(index))
        }
        let remaining = positive.dropFirst(80).reduce(Int64(0)) { $0 + $1.bytes(apparent: apparent) }
        if remaining > 0 {
            result.append(DiskChartTile(entry: nil, label: "Other items", bytes: remaining,
                                        color: .secondary))
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = Self.layout(tiles, in: CGRect(origin: .zero, size: geometry.size).insetBy(dx: 4, dy: 4))
            Canvas { context, _ in
                for tile in layout where tile.rect.width > 1 && tile.rect.height > 1 {
                    let rect = tile.rect.insetBy(dx: 1, dy: 1)
                    context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(tile.color.opacity(0.78)))
                    if rect.width > 80 && rect.height > 36 {
                        context.draw(
                            Text(tile.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.white),
                            at: CGPoint(x: rect.minX + 8, y: rect.minY + 7), anchor: .topLeading
                        )
                        context.draw(
                            Text(ByteCountFormatter.string(fromByteCount: tile.bytes, countStyle: .file))
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.85)),
                            at: CGPoint(x: rect.minX + 8, y: rect.minY + 23), anchor: .topLeading
                        )
                    }
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                guard let tile = layout.first(where: { $0.rect.contains(value.location) }),
                      let entry = tile.entry else { return }
                select(entry)
            })
        }
        .accessibilityLabel("Treemap of \(directory.name)")
        .accessibilityHint("Select a block to inspect a file or folder")
    }

    private static func layout(_ tiles: [DiskChartTile], in rect: CGRect) -> [DiskChartTile] {
        guard !tiles.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let total = tiles.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > 0 else { return [] }
        if tiles.count == 1 {
            var tile = tiles[0]
            tile.rect = rect
            return [tile]
        }
        let halfway = Double(total) / 2
        var firstTotal: Int64 = 0
        var split = 0
        while split < tiles.count - 1 && Double(firstTotal) < halfway {
            firstTotal += tiles[split].bytes
            split += 1
        }
        let fraction = CGFloat(Double(firstTotal) / Double(total))
        if rect.width >= rect.height {
            let first = CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)
            let second = CGRect(x: first.maxX, y: rect.minY, width: rect.maxX - first.maxX, height: rect.height)
            return layout(Array(tiles[..<split]), in: first) + layout(Array(tiles[split...]), in: second)
        }
        let first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * fraction)
        let second = CGRect(x: rect.minX, y: first.maxY, width: rect.width, height: rect.maxY - first.maxY)
        return layout(Array(tiles[..<split]), in: first) + layout(Array(tiles[split...]), in: second)
    }
}

private struct DiskRingSegment {
    let entry: DiskEntry?
    let start: Double
    let end: Double
    let inner: CGFloat
    let outer: CGFloat
    let color: Color

    func contains(angle: Double, radius: CGFloat) -> Bool {
        angle >= start && angle < end && radius >= inner && radius <= outer
    }
}

struct DiskSunburstView: View {
    let directory: DiskEntry
    let apparent: Bool
    let select: (DiskEntry) -> Void

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2 - 8
            let segments = Self.segments(for: directory, apparent: apparent, radius: radius)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            Canvas { context, _ in
                for segment in segments {
                    var path = Path()
                    path.addArc(center: center, radius: segment.outer,
                                startAngle: .radians(segment.start), endAngle: .radians(segment.end),
                                clockwise: false)
                    path.addArc(center: center, radius: segment.inner,
                                startAngle: .radians(segment.end), endAngle: .radians(segment.start),
                                clockwise: true)
                    path.closeSubpath()
                    context.fill(path, with: .color(segment.color))
                    context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1.5)
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                let distance = hypot(dx, dy)
                var angle = atan2(dy, dx)
                if angle < -.pi / 2 { angle += 2 * .pi }
                if let segment = segments.reversed().first(where: { $0.contains(angle: angle, radius: distance) }),
                   let entry = segment.entry {
                    select(entry)
                }
            })
            VStack(spacing: 3) {
                Text(directory.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: directory.bytes(apparent: apparent), countStyle: .file))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: radius * 0.52)
            .position(center)
            .allowsHitTesting(false)
        }
        .accessibilityLabel("Ring chart of \(directory.name)")
        .accessibilityHint("Select a ring segment to inspect a file or folder")
    }

    private static func segments(for root: DiskEntry, apparent: Bool, radius: CGFloat) -> [DiskRingSegment] {
        var result: [DiskRingSegment] = []
        func add(_ parent: DiskEntry, start: Double, end: Double, depth: Int, colorIndex: Int) {
            guard depth < 3 else { return }
            let children = parent.children.filter { $0.bytes(apparent: apparent) > 0 }
            let total = children.reduce(Int64(0)) { $0 + $1.bytes(apparent: apparent) }
            guard total > 0 else { return }
            var angle = start
            let limit = depth == 0 ? 24 : 12
            let inner = radius * (0.30 + CGFloat(depth) * 0.23)
            let outer = radius * (0.52 + CGFloat(depth) * 0.23)
            for (index, child) in children.prefix(limit).enumerated() {
                let next = angle + (end - start) * Double(child.bytes(apparent: apparent)) / Double(total)
                let tint = DiskChartPalette.color(depth == 0 ? index : colorIndex)
                result.append(DiskRingSegment(entry: child, start: angle, end: next,
                                              inner: inner, outer: outer,
                                              color: tint.opacity(depth == 0 ? 0.82 : 0.55 + Double(depth) * 0.1)))
                add(child, start: angle, end: next, depth: depth + 1,
                    colorIndex: depth == 0 ? index : colorIndex)
                angle = next
            }
            if children.count > limit {
                result.append(DiskRingSegment(entry: nil, start: angle, end: end,
                                              inner: inner, outer: outer,
                                              color: .secondary.opacity(0.45)))
            }
        }
        add(root, start: -.pi / 2, end: 3 * .pi / 2, depth: 0, colorIndex: 0)
        return result
    }
}
