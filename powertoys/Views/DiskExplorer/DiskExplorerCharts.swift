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
    private static let colors: [Color] = [
        Color(red: 0.22, green: 0.48, blue: 0.76),
        Color(red: 0.19, green: 0.54, blue: 0.48),
        Color(red: 0.73, green: 0.39, blue: 0.30),
        Color(red: 0.51, green: 0.40, blue: 0.70),
        Color(red: 0.65, green: 0.48, blue: 0.19),
        Color(red: 0.70, green: 0.33, blue: 0.43),
        Color(red: 0.30, green: 0.48, blue: 0.62),
        Color(red: 0.38, green: 0.51, blue: 0.36)
    ]

    static func color(_ index: Int, depth: Int = 0) -> Color {
        colors[index % colors.count].opacity(max(0.72, 1 - Double(depth) * 0.12))
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

struct DiskChartTile {
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
    private var chartAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.45) }

    private var tiles: [DiskChartTile] {
        let largest = directory.children.sorted {
            measure.weight($0, apparent: apparent) > measure.weight($1, apparent: apparent)
        }
        let shown = largest.prefix(80).sorted { $0.id < $1.id }
        var result = shown.enumerated().map { index, entry in
            DiskChartTile(entry: entry, label: entry.name, weight: max(1, measure.weight(entry, apparent: apparent)),
                          detail: measure.detail(entry, apparent: apparent),
                          color: DiskChartPalette.color(for: entry, index: index, measure: measure))
        }
        let remaining = largest.dropFirst(80).reduce(Int64(0)) {
            $0 + max(1, measure.weight($1, apparent: apparent))
        }
        if largest.count > 80 {
            let measured = largest.dropFirst(80).reduce(Int64(0)) {
                $0 + measure.weight($1, apparent: apparent)
            }
            let detail = measure == .files ? "\(measured.formatted()) files" :
                ByteCountFormatter.string(fromByteCount: measured, countStyle: .file)
            result.append(DiskChartTile(entry: nil, label: "Other items", weight: remaining, detail: detail,
                                        color: .secondary))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let layout = Self.layout(tiles, in: CGRect(origin: .zero, size: geometry.size).insetBy(dx: 4, dy: 4))
                ForEach(layout, id: \.id) { tile in
                    let rect = tile.rect.insetBy(dx: 1, dy: 1)
                    Button {
                        guard let entry = tile.entry else { return }
                        selectedID = entry.id
                        select(entry)
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(tile.color.opacity(hoveredID == nil || tile.id == hoveredID ||
                                                     tile.id == selectedID ? 1 : 0.62))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(hoveredID == tile.id || selectedID == tile.id ?
                                                  Color.white.opacity(0.94) : Color.white.opacity(0.16),
                                                  lineWidth: hoveredID == tile.id || selectedID == tile.id ? 2 : 1)
                            }
                            .overlay(alignment: .topLeading) {
                                if rect.width > 80 && rect.height > 36 {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tile.label).font(.system(size: 11, weight: .semibold))
                                        Text(tile.detail).font(.system(size: 10)).opacity(0.88)
                                    }
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(8)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .accessibilityLabel("\(tile.label), \(tile.detail)")
                    .frame(width: max(0, rect.width), height: max(0, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .onHover { inside in hoveredID = inside ? tile.id : (hoveredID == tile.id ? nil : hoveredID) }
                    .animation(chartAnimation, value: rect)
                    .animation(UtilityMotion.animation(reduceMotion: reduceMotion,
                                                      duration: UtilityMotion.interactionDuration), value: hoveredID)
                    .transition(reduceMotion ? .identity : .opacity)
                }
                .animation(chartAnimation, value: layout.map(\.id))
            }
            QuietDivider()
            let hovered = tiles.first { $0.id == hoveredID } ?? tiles.first { $0.id == selectedID }
            HStack(spacing: 10) {
                Image(systemName: hovered?.entry?.kind == .directory ? "folder.fill" : "circle.grid.2x2")
                    .foregroundStyle(hovered?.color ?? .secondary)
                Text(hovered?.label ?? "Point to a block to inspect it")
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                if let hovered {
                    Text(hovered.detail).monospacedDigit().fixedSize()
                    if let entry = hovered.entry, measure.weight(entry, apparent: apparent) > 0,
                       measure.weight(directory, apparent: apparent) > 0 {
                        Text(Double(measure.weight(entry, apparent: apparent)) /
                             Double(measure.weight(directory, apparent: apparent)),
                             format: .percent.precision(.fractionLength(1)))
                            .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentTransition(.opacity)
        }
        .accessibilityLabel("Treemap of \(directory.name)")
        .accessibilityValue(hoveredID.flatMap { id in tiles.first { $0.id == id }?.label } ??
                            "\(tiles.count) items")
        .accessibilityHint("Point to a block for its name and size; select it to inspect or open")
        .accessibilityIdentifier("diskExplorer.treemap")
        .onChange(of: directory.id) { _, _ in hoveredID = nil; selectedID = nil }
    }

    static func layout(_ tiles: [DiskChartTile], in rect: CGRect, depth: Int = 0) -> [DiskChartTile] {
        guard !tiles.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let total = tiles.reduce(Int64(0)) { $0 + $1.weight }
        guard total > 0 else { return [] }
        if tiles.count == 1 {
            var tile = tiles[0]
            tile.rect = rect
            return [tile]
        }
        let split = tiles.count / 2
        let firstTotal = tiles[..<split].reduce(Int64(0)) { $0 + $1.weight }
        let fraction = CGFloat(Double(firstTotal) / Double(total))
        if depth.isMultiple(of: 2) {
            let first = CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)
            let second = CGRect(x: first.maxX, y: rect.minY, width: rect.maxX - first.maxX, height: rect.height)
            return layout(Array(tiles[..<split]), in: first, depth: depth + 1) +
                layout(Array(tiles[split...]), in: second, depth: depth + 1)
        }
        let first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * fraction)
        let second = CGRect(x: rect.minX, y: first.maxY, width: rect.width, height: rect.maxY - first.maxY)
        return layout(Array(tiles[..<split]), in: first, depth: depth + 1) +
            layout(Array(tiles[split...]), in: second, depth: depth + 1)
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

private struct DiskRingShape: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(start, AnimatablePair(end, AnimatablePair(inner, outer))) }
        set {
            start = newValue.first
            end = newValue.second.first
            inner = newValue.second.second.first
            outer = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: outer,
                    startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        path.addArc(center: center, radius: inner,
                    startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct DiskSunburstView: View {
    let directory: DiskEntry
    let apparent: Bool
    let measure: DiskChartMeasure
    let select: (DiskEntry) -> Void
    @State private var hoveredID: String?
    @State private var hoveredLabel: String?
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var chartAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.45) }

    var body: some View {
        GeometryReader { geometry in
            let radius = max(0, min(geometry.size.width, geometry.size.height) / 2 - 10)
            let segments = Self.segments(for: directory, apparent: apparent, measure: measure, radius: radius)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let focused = segments.first { $0.id == hoveredID } ?? segments.first { $0.id == selectedID }
            ForEach(segments, id: \.id) { segment in
                DiskRingShape(start: segment.start, end: segment.end,
                              inner: segment.inner, outer: segment.outer)
                    .fill(segment.color.opacity(hoveredID == nil ||
                        segment.id == hoveredID || segment.id == selectedID ? 0.96 : 0.55))
                    .overlay {
                        DiskRingShape(start: segment.start, end: segment.end,
                                      inner: segment.inner, outer: segment.outer)
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                    }
                    .animation(chartAnimation, value: segment.start)
                    .animation(chartAnimation, value: segment.end)
                    .animation(chartAnimation, value: segment.inner)
                    .animation(chartAnimation, value: segment.outer)
                    .transition(reduceMotion ? .identity : .opacity)
            }
            .animation(chartAnimation, value: segments.map(\.id))
            Rectangle().fill(.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
                let next: DiskRingSegment?
                switch phase {
                case .active(let point): next = Self.hitTest(segments, at: point, center: center)
                case .ended: next = nil
                }
                if hoveredID != next?.id {
                    withAnimation(UtilityMotion.animation(reduceMotion: reduceMotion,
                                                          duration: UtilityMotion.interactionDuration)) {
                        hoveredID = next?.id
                        hoveredLabel = next?.label
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
                DiskRingShape(start: focused.start, end: focused.end,
                              inner: focused.inner, outer: focused.outer)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ring chart of \(directory.name)")
        .accessibilityValue(hoveredLabel ?? "\(directory.children.count) items")
        .accessibilityHint("Point to a segment for its name and size; select it to inspect or open")
        .accessibilityIdentifier("diskExplorer.rings")
        .onChange(of: directory.id) { _, _ in hoveredID = nil; hoveredLabel = nil; selectedID = nil }
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
            let ranked = parent.children
                .sorted { measure.weight($0, apparent: apparent) > measure.weight($1, apparent: apparent) }
            let total = ranked.reduce(Int64(0)) { $0 + max(1, measure.weight($1, apparent: apparent)) }
            guard total > 0 else { return }
            var angle = start
            let limit = depth == 0 ? 24 : 12
            let children = ranked.prefix(limit).sorted { $0.id < $1.id }
            let inner = radius * (0.30 + CGFloat(depth) * band)
            let outer = radius * (0.30 + CGFloat(depth + 1) * band) - 2
            for (index, child) in children.enumerated() {
                let next = angle + (end - start) * Double(max(1, measure.weight(child, apparent: apparent))) / Double(total)
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
            if ranked.count > limit {
                let remaining = ranked.dropFirst(limit).reduce(Int64(0)) {
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
