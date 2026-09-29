import AppKit
import OnePlusUI
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
    var title: String { self == .files ? "File count" : self == .age ? "Recent changes" : "Space used" }

    func weight(_ entry: DiskEntry, apparent: Bool) -> Int64 {
        self == .files ? Int64(entry.fileCount) : entry.bytes(apparent: apparent)
    }

    func detail(_ entry: DiskEntry, apparent: Bool) -> String {
        self == .files ? "\(entry.fileCount.formatted()) files" :
            entry.bytes(apparent: apparent).diskSize
    }

    func displayedChildren(in directory: DiskEntry, apparent: Bool, limit: Int,
                           scanComplete: Bool) -> (shown: [DiskEntry], hidden: [DiskEntry]) {
        let byPath = directory.children.sorted { $0.id < $1.id }
        guard byPath.count > limit else { return (byPath, []) }
        guard scanComplete else { return (Array(byPath.prefix(limit)), Array(byPath.dropFirst(limit))) }
        let aggregates = byPath.filter { $0.kind == .aggregate }
        let topIDs = Set(byPath.filter { $0.kind != .aggregate }.sorted {
            let left = weight($0, apparent: apparent)
            let right = weight($1, apparent: apparent)
            return left == right ? $0.id < $1.id : left > right
        }.prefix(max(0, limit - aggregates.count)).map(\.id) + aggregates.map(\.id))
        return (byPath.filter { topIDs.contains($0.id) }, byPath.filter { !topIDs.contains($0.id) })
    }
}

enum DiskChartPalette {
    static func color(_ index: Int, depth: Int = 0) -> Color {
        OnePlusColor.storageSeries[index % OnePlusColor.storageSeries.count]
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
    let scanComplete: Bool
    let select: (DiskEntry) -> Void
    var onHoverDetail: (String?) -> Void = { _ in }
    var selectedEntryID: String?
    var open: (DiskEntry) -> Void = { _ in }
    var preview: (DiskEntry) -> Void = { _ in }
    var actions: ([DiskEntry]) -> [OnePlusTableAction] = { _ in [] }
    @State private var hoveredID: String?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var chartAnimation: Animation? { OnePlusMotion.animation(reduceMotion: reduceMotion, duration: OnePlusMotion.content) }

    var tiles: [DiskChartTile] {
        let selection = measure.displayedChildren(in: directory, apparent: apparent,
                                                  limit: 80, scanComplete: scanComplete)
        let shown = selection.shown
        var result = shown.enumerated().map { index, entry in
            DiskChartTile(entry: entry, label: DiskEntryPresentation.name(entry), weight: max(1, measure.weight(entry, apparent: apparent)),
                          detail: measure.detail(entry, apparent: apparent),
                          color: DiskChartPalette.color(for: entry, index: index, measure: measure))
        }
        let remaining = selection.hidden.reduce(Int64(0)) {
            $0 + max(1, measure.weight($1, apparent: apparent))
        }
        if !selection.hidden.isEmpty {
            let measured = selection.hidden.reduce(Int64(0)) {
                $0 + measure.weight($1, apparent: apparent)
            }
            let detail = measure == .files ? "\(measured.formatted()) files" :
                measured.diskSize
            result.append(DiskChartTile(entry: nil, label: "Other items", weight: remaining, detail: detail,
                                        color: OnePlusColor.storageSeries.last!))
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = Self.layout(tiles, in: CGRect(origin: .zero, size: geometry.size))
            ForEach(layout, id: \.id) { tile in tileView(tile) }
                .animation(chartAnimation, value: layout.map(\.id))
        }
        .focusable().focused($focused).focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
        .onMoveCommand { direction in
            let entries = tiles.compactMap(\.entry)
            if let next = DiskChartNavigation.next(entries, selected: selectedEntryID, direction: direction) { select(next) }
        }
        .onKeyPress(.space) { if let entry = tiles.compactMap(\.entry).first(where: { $0.id == selectedEntryID && $0.kind != .aggregate }) { preview(entry) }; return .handled }
        .onKeyPress(.return) { if let entry = tiles.compactMap(\.entry).first(where: { $0.id == selectedEntryID && $0.kind != .aggregate }) { open(entry) }; return .handled }
        .accessibilityElement(children: .contain).accessibilityLabel("Treemap of \(directory.name)")
        .accessibilityHint("Click to select. Double-click a folder to explore.")
        .accessibilityIdentifier("diskExplorer.treemap")
        .onChange(of: directory.id) { _, _ in hoveredID = nil }
    }

    private func tileView(_ tile: DiskChartTile) -> some View {
        let rect = tile.rect.insetBy(dx: 1, dy: 1)
        return Button {
            focused = true
            guard let entry = tile.entry else { return }
            select(entry)
            if NSApp.currentEvent?.clickCount == 2 && entry.kind != .aggregate { open(entry) }
        } label: {
            OnePlusStorageTile(color: tile.color, selected: selectedEntryID == tile.id, hovered: hoveredID == tile.id) {
                if rect.width > OnePlusDiskmanMetrics.tileLabelWidth && rect.height > OnePlusDiskmanMetrics.tileLabelHeight {
                    VStack(alignment: .leading, spacing: OnePlusMetrics.spacing[0]) {
                        Text(tile.label).font(.system(size: OnePlusTextRole.cardTitle.size(for: .regular), weight: .semibold))
                        Text(tile.detail).font(.system(size: OnePlusTextRole.mono.size(for: .regular), design: .monospaced))
                        if rect.height > OnePlusDiskmanMetrics.tileCountsHeight, let entry = tile.entry {
                            Spacer(minLength: OnePlusMetrics.actionSpacing)
                            Text("\(entry.fileCount.formatted()) files · \(max(0, entry.directoryCount - (entry.kind == .directory ? 1 : 0))) folders")
                                .font(.system(size: OnePlusTextRole.caption.size(for: .regular)))
                        }
                    }.foregroundStyle(OnePlusStorageStyle.ink).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain).focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
        .modifier(DiskChartFileActions(entry: tile.entry, actions: actions))
        .accessibilityLabel("\(tile.label), \(tile.detail)")
        .accessibilityAddTraits(selectedEntryID == tile.id ? .isSelected : [])
        .help("\(tile.label) · \(tile.detail)")
        .frame(width: max(0, rect.width), height: max(0, rect.height)).clipped()
        .position(x: rect.midX, y: rect.midY)
        .onHover { inside in
            hoveredID = inside ? tile.id : (hoveredID == tile.id ? nil : hoveredID)
            onHoverDetail(tiles.first { $0.id == hoveredID }.map { "\($0.label) · \($0.detail)" })
        }.animation(chartAnimation, value: rect)
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

struct DiskRingSegment {
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
    let scanComplete: Bool
    let select: (DiskEntry) -> Void
    var onHoverDetail: (String?) -> Void = { _ in }
    var selectedEntryID: String?
    var open: (DiskEntry) -> Void = { _ in }
    var preview: (DiskEntry) -> Void = { _ in }
    var actions: ([DiskEntry]) -> [OnePlusTableAction] = { _ in [] }
    @State private var hoveredID: String?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var chartAnimation: Animation? { OnePlusMotion.animation(reduceMotion: reduceMotion, duration: OnePlusMotion.content) }

    var body: some View {
        GeometryReader { geometry in
            let plotHeight = geometry.size.height
            let radius = max(0, min(geometry.size.width, plotHeight) / 2 - 10)
            let segments = Self.segments(for: directory, apparent: apparent, measure: measure,
                                         radius: radius, scanComplete: scanComplete)
            let center = CGPoint(x: geometry.size.width / 2, y: plotHeight / 2)
            ZStack {
                    ForEach(segments, id: \.id) { segment in segmentView(segment) }
                        .animation(chartAnimation, value: segments.map(\.id))
                    VStack(spacing: OnePlusMetrics.spacing[1]) {
                        Text(directory.name)
                            .onePlusText(.cardTitle)
                            .lineLimit(2).multilineTextAlignment(.center)
                        Text(measure.detail(directory, apparent: apparent))
                            .onePlusText(.mono)
                    }
                    .frame(width: radius * 0.56)
                    .position(center)
                    .allowsHitTesting(false)
                }
                .frame(height: plotHeight)
                .onContinuousHover { phase in
                    let next: DiskRingSegment?
                    switch phase {
                    case .active(let point): next = Self.hitTest(segments, at: point, center: center)
                    case .ended: next = nil
                    }
                    hoveredID = next?.id
                    onHoverDetail(next.map { "\($0.label) · \($0.detail)" })
                }
                .focusable().focused($focused).focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
                .onMoveCommand { direction in
                    if let entry = DiskChartNavigation.next(segments.compactMap(\.entry), selected: selectedEntryID, direction: direction) { select(entry) }
                }
                .onKeyPress(.space) {
                    if let entry = segments.compactMap(\.entry).first(where: { $0.id == selectedEntryID && $0.kind != .aggregate }) { preview(entry) }
                    return .handled
                }
                .onKeyPress(.return) {
                    if let entry = segments.compactMap(\.entry).first(where: { $0.id == selectedEntryID && $0.kind != .aggregate }) { open(entry) }
                    return .handled
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Ring chart of \(directory.name)")
                .accessibilityValue(segments.first { $0.id == hoveredID }.map { "\($0.label), \($0.detail)" } ?? "\(directory.children.count) items")
                .accessibilityHint("Click to select. Double-click a folder to explore.")
                .accessibilityIdentifier("diskExplorer.rings")
        }
        .onChange(of: directory.id) { _, _ in hoveredID = nil }
    }

    private func segmentView(_ segment: DiskRingSegment) -> some View {
        let shape = DiskRingShape(start: segment.start, end: segment.end, inner: segment.inner, outer: segment.outer)
        return Button {
            focused = true
            guard let entry = segment.entry else { return }
            select(entry)
            if NSApp.currentEvent?.clickCount == 2 && entry.kind != .aggregate { open(entry) }
        } label: {
            shape.fill(segment.color)
                .overlay { OnePlusStorageTexture(selected: selectedEntryID == segment.id).mask(shape) }
                .overlay { shape.stroke(selectedEntryID == segment.id ? OnePlusStorageStyle.selectedLine : hoveredID == segment.id ? OnePlusStorageStyle.hoverLine : OnePlusStorageStyle.line, lineWidth: 1) }
                .overlay { ringLabel(segment) }
                .contentShape(shape)
        }
        .buttonStyle(.plain).focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled).contentShape(shape)
        .modifier(DiskChartFileActions(entry: segment.entry, actions: actions))
        .help("\(segment.label) · \(segment.detail)")
        .accessibilityLabel("\(segment.label), \(segment.detail)")
        .accessibilityAddTraits(selectedEntryID == segment.id ? .isSelected : [])
        .animation(chartAnimation, value: segment.start).animation(chartAnimation, value: segment.end)
        .animation(chartAnimation, value: segment.inner).animation(chartAnimation, value: segment.outer)
    }

    private func ringLabel(_ segment: DiskRingSegment) -> some View {
        let angle = (segment.start + segment.end) / 2
        let radius = (segment.inner + segment.outer) / 2
        let inset = OnePlusDiskmanMetrics.tileInset
        let halfBand = (segment.outer - segment.inner) / 2
        let halfArc = radius * sin(min(.pi / 2, (segment.end - segment.start) / 2))
        // Fit the text square inside the wedge, including its inner edge.
        let side = max(0, min(halfBand, halfArc) * sqrt(2) - inset * 2)
        return GeometryReader { geometry in
            if side > OnePlusDiskmanMetrics.tileLabelWidth {
                VStack(spacing: OnePlusMetrics.spacing[0]) {
                    Text(segment.label).font(.system(size: OnePlusTextRole.cardTitle.size(for: .regular), weight: .semibold))
                    Text(segment.detail).font(.system(size: OnePlusTextRole.mono.size(for: .regular), design: .monospaced))
                    if side > OnePlusDiskmanMetrics.tileCountsHeight, let entry = segment.entry {
                        Text("\(entry.fileCount.formatted()) files").font(.system(size: OnePlusTextRole.caption.size(for: .regular)))
                        Text("\(max(0, entry.directoryCount - (entry.kind == .directory ? 1 : 0))) folders")
                            .font(.system(size: OnePlusTextRole.caption.size(for: .regular)))
                    }
                }.foregroundStyle(OnePlusStorageStyle.ink).lineLimit(1)
                    .frame(width: side, height: side).clipped()
                    .position(x: geometry.size.width / 2 + cos(angle) * radius,
                              y: geometry.size.height / 2 + sin(angle) * radius)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private static func hitTest(_ segments: [DiskRingSegment], at point: CGPoint, center: CGPoint) -> DiskRingSegment? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx)
        if angle < -.pi / 2 { angle += 2 * .pi }
        return segments.reversed().first { $0.contains(angle: angle, radius: hypot(dx, dy)) }
    }

    static func segments(for root: DiskEntry, apparent: Bool,
                         measure: DiskChartMeasure, radius: CGFloat,
                         scanComplete: Bool) -> [DiskRingSegment] {
        var result: [DiskRingSegment] = []
        let levels = root.children.contains { $0.children.contains { !$0.children.isEmpty } } ? 3 :
            root.children.contains { !$0.children.isEmpty } ? 2 : 1
        let band = CGFloat(0.68) / CGFloat(levels)
        func add(_ parent: DiskEntry, start: Double, end: Double, depth: Int, colorIndex: Int) {
            guard depth < 3 else { return }
            let total = parent.children.reduce(Int64(0)) { $0 + max(1, measure.weight($1, apparent: apparent)) }
            guard total > 0 else { return }
            var angle = start
            let limit = depth == 0 ? 24 : 12
            let selection = measure.displayedChildren(in: parent, apparent: apparent,
                                                      limit: limit, scanComplete: scanComplete)
            let children = selection.shown
            let inner = radius * (0.30 + CGFloat(depth) * band)
            let outer = radius * (0.30 + CGFloat(depth + 1) * band) - 2
            for (index, child) in children.enumerated() {
                let next = angle + (end - start) * Double(max(1, measure.weight(child, apparent: apparent))) / Double(total)
                let tint = DiskChartPalette.color(for: child, index: depth == 0 ? index : colorIndex,
                                                  measure: measure, depth: depth)
                result.append(DiskRingSegment(id: child.id, entry: child, label: DiskEntryPresentation.name(child),
                                              detail: measure.detail(child, apparent: apparent),
                                              start: angle, end: next,
                                              inner: inner, outer: outer,
                                              color: tint))
                add(child, start: angle, end: next, depth: depth + 1,
                    colorIndex: depth == 0 ? index : colorIndex)
                angle = next
            }
            if !selection.hidden.isEmpty {
                let remaining = selection.hidden.reduce(Int64(0)) {
                    $0 + measure.weight($1, apparent: apparent)
                }
                let detail = measure == .files ? "\(remaining.formatted()) files" :
                    remaining.diskSize
                result.append(DiskRingSegment(id: parent.id + "/other", entry: nil,
                                              label: "Other items", detail: detail,
                                              start: angle, end: end,
                                              inner: inner, outer: outer,
                                              color: OnePlusColor.storageSeries.last!))
            }
        }
        add(root, start: -.pi / 2, end: 3 * .pi / 2, depth: 0, colorIndex: 0)
        return result
    }
}

enum DiskChartNavigation {
    static func next(_ entries: [DiskEntry], selected: String?, direction: MoveCommandDirection) -> DiskEntry? {
        guard !entries.isEmpty else { return nil }
        guard let index = entries.firstIndex(where: { $0.id == selected }) else { return entries.first }
        let delta = direction == .left || direction == .up ? -1 : 1
        return entries[min(max(index + delta, 0), entries.count - 1)]
    }
}

struct DiskChartFileActions: ViewModifier {
    let entry: DiskEntry?
    let actions: ([DiskEntry]) -> [OnePlusTableAction]
    @ViewBuilder func body(content: Content) -> some View {
        if let entry, entry.kind != .aggregate {
            content.contextMenu {
                let options = actions([entry])
                ForEach(options.indices, id: \.self) { index in
                    Button(options[index].title, action: options[index].action).disabled(!options[index].enabled)
                }
            }.onDrag { NSItemProvider(object: entry.url as NSURL) }
        } else { content }
    }
}
