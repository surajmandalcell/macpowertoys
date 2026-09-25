import SwiftUI

enum DiskChartStyle: String, CaseIterable, Identifiable {
    case treemap = "Treemap"
    case sunburst = "Rings"

    var id: String { rawValue }
    var symbol: String { self == .treemap ? "square.grid.3x3.fill" : "circle.hexagongrid.fill" }
}

enum DiskChartMeasure: String, CaseIterable, Identifiable {
    case space = "Space"
    case files = "Files"
    case age = "Age"

    var id: String { rawValue }

    func weight(_ entry: DiskEntry, apparent: Bool) -> Int64 {
        self == .files ? Int64(entry.fileCount) : entry.bytes(apparent: apparent)
    }

    func detail(_ entry: DiskEntry, apparent: Bool) -> String {
        self == .files ? "\(entry.fileCount.formatted()) files" :
            ByteCountFormatter.string(fromByteCount: entry.bytes(apparent: apparent), countStyle: .file)
    }
}

enum DiskChartPalette {
    private static let hues: [Double] = [0.59, 0.47, 0.035, 0.74, 0.12, 0.88, 0.53, 0.33]

    static func color(_ index: Int, depth: Int = 0) -> Color {
        Color(hue: hues[index % hues.count], saturation: max(0.56, 0.77 - Double(depth) * 0.08),
              brightness: min(0.87, 0.72 + Double(depth) * 0.07))
    }

    static func color(for entry: DiskEntry, index: Int, measure: DiskChartMeasure,
                      depth: Int = 0) -> Color {
        guard measure == .age else { return color(index, depth: depth) }
        let days = Date().timeIntervalSince(entry.modifiedAt) / 86_400
        if days <= 7 { return color(1, depth: depth) }
        if days <= 30 { return color(6, depth: depth) }
        if days <= 365 { return color(0, depth: depth) }
        return color(3, depth: depth)
    }
}

private struct DiskChartTile {
    let entry: DiskEntry?
    let label: String
    let weight: Int64
    let detail: String
    let color: Color
    var rect: CGRect = .zero
    var id: String { entry?.id ?? "other" }
}

struct DiskTreemapView: View {
    let directory: DiskEntry
    let apparent: Bool
    let measure: DiskChartMeasure
    let select: (DiskEntry) -> Void
    @State private var hoveredID: String?
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tiles: [DiskChartTile] {
        let positive = directory.children.filter { measure.weight($0, apparent: apparent) > 0 }
            .sorted { measure.weight($0, apparent: apparent) > measure.weight($1, apparent: apparent) }
        var result = Array(positive.prefix(80)).enumerated().map { index, entry in
            DiskChartTile(entry: entry, label: entry.name, weight: measure.weight(entry, apparent: apparent),
                          detail: measure.detail(entry, apparent: apparent),
                          color: DiskChartPalette.color(for: entry, index: index, measure: measure))
        }
        let remaining = positive.dropFirst(80).reduce(Int64(0)) { $0 + measure.weight($1, apparent: apparent) }
        if remaining > 0 {
            let detail = measure == .files ? "\(remaining.formatted()) files" :
                ByteCountFormatter.string(fromByteCount: remaining, countStyle: .file)
            result.append(DiskChartTile(entry: nil, label: "Other items", weight: remaining, detail: detail,
                                        color: .secondary))
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = Self.layout(tiles, in: CGRect(origin: .zero, size: geometry.size).insetBy(dx: 4, dy: 4))
            let hovered = layout.first { $0.id == hoveredID }
            Canvas { context, _ in
                for tile in layout where tile.rect.width > 1 && tile.rect.height > 1 {
                    let rect = tile.rect.insetBy(dx: 1, dy: 1)
                    let path = Path(roundedRect: rect, cornerRadius: 4)
                    context.fill(path, with: .color(tile.color.opacity(hoveredID == nil ||
                        tile.id == hoveredID || tile.id == selectedID ? 0.94 : 0.64)))
                    context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 1)
                    if rect.width > 80 && rect.height > 36 {
                        context.draw(
                            Text(tile.label).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white),
                            in: CGRect(x: rect.minX + 8, y: rect.minY + 6,
                                       width: rect.width - 16, height: 17)
                        )
                        context.draw(
                            Text(tile.detail)
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.88)),
                            in: CGRect(x: rect.minX + 8, y: rect.minY + 23,
                                       width: rect.width - 16, height: 15)
                        )
                    }
                }
            }
            .onContinuousHover { phase in
                let next: String?
                switch phase {
                case .active(let point): next = layout.first { $0.rect.contains(point) }?.id
                case .ended: next = nil
                }
                if hoveredID != next {
                    withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion,
                                                          duration: UtilityMotion.interactionDuration)) {
                        hoveredID = next
                    }
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                guard let tile = layout.first(where: { $0.rect.contains(value.location) }),
                      let entry = tile.entry else { return }
                selectedID = entry.id
                select(entry)
            })
            if let outlined = layout.first(where: { $0.id == hoveredID }) ??
                layout.first(where: { $0.id == selectedID }) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(0.94), lineWidth: 2)
                    .shadow(color: .black.opacity(0.44), radius: 7, y: 3)
                    .frame(width: max(0, outlined.rect.width - 2), height: max(0, outlined.rect.height - 2))
                    .position(x: outlined.rect.midX, y: outlined.rect.midY)
                    .allowsHitTesting(false)
                    .utilityAnimation(value: outlined.id, duration: UtilityMotion.interactionDuration)
            }
            if let hovered {
                HStack(spacing: 10) {
                    Image(systemName: hovered.entry?.kind == .directory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(hovered.color)
                    Text(hovered.label).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(hovered.detail).monospacedDigit().fixedSize()
                    Text(Double(hovered.weight) / Double(max(1, measure.weight(directory, apparent: apparent))),
                         format: .percent.precision(.fractionLength(1)))
                        .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(reduceMotion ? .identity : .opacity)
                .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Treemap of \(directory.name)")
        .accessibilityValue(hoveredID.flatMap { id in tiles.first { $0.id == id }?.label } ??
                            "\(tiles.count) items")
        .accessibilityHint("Point to a block for its name and size; select it to inspect or open")
        .onChange(of: directory.id) { _, _ in hoveredID = nil; selectedID = nil }
    }

    private static func layout(_ tiles: [DiskChartTile], in rect: CGRect) -> [DiskChartTile] {
        guard !tiles.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let total = tiles.reduce(Int64(0)) { $0 + $1.weight }
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
            firstTotal += tiles[split].weight
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
    let id: String
    let entry: DiskEntry?
    let label: String
    let detail: String
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
    let measure: DiskChartMeasure
    let select: (DiskEntry) -> Void
    @State private var hoveredID: String?
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let radius = max(0, min(geometry.size.width, geometry.size.height) / 2 - 10)
            let segments = Self.segments(for: directory, apparent: apparent, measure: measure, radius: radius)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let focused = segments.first { $0.id == hoveredID } ?? segments.first { $0.id == selectedID }
            Canvas { context, _ in
                for segment in segments {
                    let path = Self.path(for: segment, center: center)
                    context.fill(path, with: .color(segment.color.opacity(hoveredID == nil ||
                        segment.id == hoveredID || segment.id == selectedID ? 0.96 : 0.53)))
                    context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 2)
                }
            }
            .onContinuousHover { phase in
                let next: String?
                switch phase {
                case .active(let point): next = Self.hitTest(segments, at: point, center: center)?.id
                case .ended: next = nil
                }
                if hoveredID != next {
                    withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion,
                                                          duration: UtilityMotion.interactionDuration)) {
                        hoveredID = next
                    }
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                if let segment = Self.hitTest(segments, at: value.location, center: center),
                   let entry = segment.entry {
                    selectedID = entry.id
                    select(entry)
                }
            })
            if let focused {
                Self.path(for: focused, center: center)
                    .stroke(.white.opacity(0.98), lineWidth: 2.5)
                    .shadow(color: focused.color.opacity(0.65), radius: 8)
                    .transition(reduceMotion ? .identity : .opacity)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 3) {
                Text(focused?.label ?? directory.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2).multilineTextAlignment(.center)
                Text(focused?.detail ?? measure.detail(directory, apparent: apparent))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: radius * 0.56)
            .position(center)
            .allowsHitTesting(false)
            .utilityContentTransition(value: focused?.id ?? directory.id)
        }
        .accessibilityLabel("Ring chart of \(directory.name)")
        .accessibilityValue("\(directory.children.count) items")
        .accessibilityHint("Point to a segment for its name and size; select it to inspect or open")
        .onChange(of: directory.id) { _, _ in hoveredID = nil; selectedID = nil }
    }

    private static func path(for segment: DiskRingSegment, center: CGPoint) -> Path {
        var path = Path()
        path.addArc(center: center, radius: segment.outer,
                    startAngle: .radians(segment.start), endAngle: .radians(segment.end), clockwise: false)
        path.addArc(center: center, radius: segment.inner,
                    startAngle: .radians(segment.end), endAngle: .radians(segment.start), clockwise: true)
        path.closeSubpath()
        return path
    }

    private static func hitTest(_ segments: [DiskRingSegment], at point: CGPoint,
                                center: CGPoint) -> DiskRingSegment? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        var angle = atan2(dy, dx)
        if angle < -.pi / 2 { angle += 2 * .pi }
        return segments.reversed().first { $0.contains(angle: angle, radius: distance) }
    }

    private static func segments(for root: DiskEntry, apparent: Bool,
                                 measure: DiskChartMeasure, radius: CGFloat) -> [DiskRingSegment] {
        var result: [DiskRingSegment] = []
        let levels = root.children.contains { $0.children.contains { !$0.children.isEmpty } } ? 3 :
            root.children.contains { !$0.children.isEmpty } ? 2 : 1
        let band = CGFloat(0.68) / CGFloat(levels)
        func add(_ parent: DiskEntry, start: Double, end: Double, depth: Int, colorIndex: Int) {
            guard depth < 3 else { return }
            let children = parent.children.filter { measure.weight($0, apparent: apparent) > 0 }
                .sorted { measure.weight($0, apparent: apparent) > measure.weight($1, apparent: apparent) }
            let total = children.reduce(Int64(0)) { $0 + measure.weight($1, apparent: apparent) }
            guard total > 0 else { return }
            var angle = start
            let limit = depth == 0 ? 24 : 12
            let inner = radius * (0.30 + CGFloat(depth) * band)
            let outer = radius * (0.30 + CGFloat(depth + 1) * band) - 2
            for (index, child) in children.prefix(limit).enumerated() {
                let next = angle + (end - start) * Double(measure.weight(child, apparent: apparent)) / Double(total)
                let tint = DiskChartPalette.color(for: child, index: depth == 0 ? index : colorIndex,
                                                  measure: measure, depth: depth)
                result.append(DiskRingSegment(id: child.id, entry: child, label: child.name,
                                              detail: measure.detail(child, apparent: apparent),
                                              start: angle, end: next,
                                              inner: inner, outer: outer,
                                              color: tint))
                add(child, start: angle, end: next, depth: depth + 1,
                    colorIndex: depth == 0 ? index : colorIndex)
                angle = next
            }
            if children.count > limit {
                let remaining = children.dropFirst(limit).reduce(Int64(0)) {
                    $0 + measure.weight($1, apparent: apparent)
                }
                let detail = measure == .files ? "\(remaining.formatted()) files" :
                    ByteCountFormatter.string(fromByteCount: remaining, countStyle: .file)
                result.append(DiskRingSegment(id: parent.id + "/other", entry: nil,
                                              label: "Other items", detail: detail,
                                              start: angle, end: end,
                                              inner: inner, outer: outer,
                                              color: .gray.opacity(0.55)))
            }
        }
        add(root, start: -.pi / 2, end: 3 * .pi / 2, depth: 0, colorIndex: 0)
        return result
    }
}
