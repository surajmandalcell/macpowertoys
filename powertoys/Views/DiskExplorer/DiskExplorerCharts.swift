import AppKit
import OnePlusUI
import SwiftUI

nonisolated enum DiskChartGeometry {
    static func fraction(_ value: Double, of total: Double) -> Double {
        guard value.isFinite, total.isFinite, value > 0, total > 0 else { return 0 }
        return min(value, total) / total
    }

    static func isDrawable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite &&
            rect.size.width.isFinite && rect.size.height.isFinite &&
            rect.size.width > 0 && rect.size.height > 0 &&
            rect.maxX.isFinite && rect.maxY.isFinite
    }

    static func partitionWidth(bytes: Int64, total: Int64, available: CGFloat) -> CGFloat {
        guard available.isFinite, available > 0 else { return 0 }
        return available * CGFloat(fraction(Double(bytes), of: Double(total)))
    }
}

nonisolated enum DiskChartStyle: String, CaseIterable, Identifiable, Sendable {
    case treemap = "Treemap"
    case sunburst = "Rings"

    var id: String { rawValue }
    var symbol: String { self == .treemap ? "square.grid.3x3.fill" : "circle.hexagongrid.fill" }
}

nonisolated enum DiskChartMeasure: String, CaseIterable, Identifiable, Sendable {
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
            entry.bytes(apparent: apparent).formatted(.byteCount(style: .file))
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

nonisolated enum DiskChartColor: Sendable, Equatable {
    case storage(Int)
    case muted

    @MainActor var color: Color {
        switch self {
        case .storage(let index):
            OnePlusColor.storageSeries[index % OnePlusColor.storageSeries.count]
        case .muted:
            OnePlusColor.muted
        }
    }
}

nonisolated enum DiskChartPalette {
    @MainActor static func color(_ index: Int, depth: Int = 0) -> Color {
        DiskChartColor.storage(index).color
    }

    static func style(for entry: DiskEntry, index: Int, measure: DiskChartMeasure,
                      depth: Int = 0) -> DiskChartColor {
        guard measure == .age else { return .storage(index) }
        let days = Date().timeIntervalSince(entry.modifiedAt) / 86_400
        if days <= 7 { return .storage(1) }
        if days <= 30 { return .storage(6) }
        if days <= 365 { return .storage(0) }
        return .storage(3)
    }
}

nonisolated struct DiskChartCacheKey: Hashable, Sendable {
    let revision: Date
    let tab: DiskChartStyle
    let directoryID: String
    let measure: DiskChartMeasure
    let apparent: Bool
    let scanComplete: Bool
    let width: Int
    let height: Int
}

nonisolated struct DiskChartInput: Sendable {
    let directory: DiskEntry
    let apparent: Bool
    let measure: DiskChartMeasure
    let scanComplete: Bool
}

@MainActor final class DiskChartLayoutCache {
    private var revision: Date?
    private var treemaps: [DiskChartCacheKey: [DiskChartTile]] = [:]
    private var rings: [DiskChartCacheKey: [DiskRingSegment]] = [:]

    func treemap(for key: DiskChartCacheKey) -> [DiskChartTile]? {
        guard revision == key.revision else { return nil }
        return treemaps[key]
    }

    func rings(for key: DiskChartCacheKey) -> [DiskRingSegment]? {
        guard revision == key.revision else { return nil }
        return rings[key]
    }

    func store(_ layout: [DiskChartTile], for key: DiskChartCacheKey) {
        prepare(for: key.revision)
        if treemaps.count >= 12 { treemaps.removeAll(keepingCapacity: true) }
        treemaps[key] = layout
    }

    func store(_ layout: [DiskRingSegment], for key: DiskChartCacheKey) {
        prepare(for: key.revision)
        if rings.count >= 12 { rings.removeAll(keepingCapacity: true) }
        rings[key] = layout
    }

    private func prepare(for revision: Date) {
        guard self.revision != revision else { return }
        self.revision = revision
        treemaps.removeAll(keepingCapacity: true)
        rings.removeAll(keepingCapacity: true)
    }
}

nonisolated struct DiskChartTile: Sendable {
    let entry: DiskEntry?
    let label: String
    let weight: Int64
    let detail: String
    let style: DiskChartColor
    var rect: CGRect = .zero
    var id: String { entry?.id ?? "other" }
}

struct DiskTreemapView: View {
    let directory: DiskEntry
    let apparent: Bool
    let measure: DiskChartMeasure
    let scanComplete: Bool
    var revision: Date = .distantPast
    var cache = DiskChartLayoutCache()
    let select: (DiskEntry) -> Void
    var onHoverDetail: (String?) -> Void = { _ in }
    var selectedEntryID: String?
    var open: (DiskEntry) -> Void = { _ in }
    var preview: (DiskEntry) -> Void = { _ in }
    var actions: ([DiskEntry]) -> [OnePlusTableAction] = { _ in [] }
    @State private var hoveredID: String?
    @State private var displayedLayout: [DiskChartTile] = []
    @State private var displayedTileIDs: [String] = []
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var chartAnimation: Animation? { OnePlusMotion.animation(reduceMotion: reduceMotion, duration: OnePlusMotion.content) }

    var tiles: [DiskChartTile] { Self.tiles(for: input, hiding: []) }

    private var input: DiskChartInput {
        DiskChartInput(directory: directory, apparent: apparent, measure: measure,
                       scanComplete: scanComplete)
    }

    nonisolated private static func tiles(for input: DiskChartInput,
                                          hiding ids: Set<String>) -> [DiskChartTile] {
        let selection = input.measure.displayedChildren(in: input.directory, apparent: input.apparent,
                                                        limit: 80, scanComplete: input.scanComplete)
        let shown = selection.shown.filter { !ids.contains($0.id) }
        let hidden = selection.hidden + selection.shown.filter { ids.contains($0.id) }
        var result = shown.enumerated().map { index, entry in
            DiskChartTile(entry: entry, label: DiskEntryPresentation.name(entry),
                          weight: max(1, input.measure.weight(entry, apparent: input.apparent)),
                          detail: input.measure.detail(entry, apparent: input.apparent),
                          style: DiskChartPalette.style(for: entry, index: index, measure: input.measure))
        }
        let remaining = hidden.reduce(Int64(0)) {
            $0 + max(1, input.measure.weight($1, apparent: input.apparent))
        }
        if !hidden.isEmpty {
            let measured = hidden.reduce(Int64(0)) {
                $0 + input.measure.weight($1, apparent: input.apparent)
            }
            let detail = input.measure == .files ? "\(measured.formatted()) files" :
                measured.formatted(.byteCount(style: .file))
            result.append(DiskChartTile(entry: nil, label: "Other items", weight: remaining, detail: detail,
                                        style: .storage(OnePlusColor.storageSeries.count - 1)))
        }
        return result
    }

    func tiles(in rect: CGRect) -> [DiskChartTile] {
        Self.tiles(for: input, in: rect)
    }

    nonisolated static func tiles(for input: DiskChartInput, in rect: CGRect) -> [DiskChartTile] {
        var hidden: Set<String> = []
        var result = layout(tiles(for: input, hiding: []), in: rect)
        guard input.scanComplete else { return result }
        // Keep scanner aggregates explicit. Fold other sub-control targets once
        // sizes are final, so live membership cannot churn as weights arrive.
        while true {
            let small = result.filter {
                $0.entry != nil && $0.entry?.kind != .aggregate &&
                    min($0.rect.width, $0.rect.height) < OnePlusMetrics.controlHeight
            }
            guard !small.isEmpty else { return result }
            hidden.formUnion(small.map(\.id))
            result = layout(tiles(for: input, hiding: hidden), in: rect)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            if DiskChartGeometry.isDrawable(bounds) {
                let key = DiskChartCacheKey(revision: revision, tab: .treemap,
                                            directoryID: directory.id, measure: measure,
                                            apparent: apparent, scanComplete: scanComplete,
                                            width: Int(geometry.size.width.rounded()),
                                            height: Int(geometry.size.height.rounded()))
                let layout = cache.treemap(for: key) ?? displayedLayout
                ZStack {
                    ForEach(layout, id: \.id) { tile in tileView(tile) }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .animation(chartAnimation, value: displayedTileIDs)
                .task(id: key) {
                    if let cached = cache.treemap(for: key) {
                        displayedLayout = cached
                        displayedTileIDs = cached.map(\.id)
                        return
                    }
                    let input = self.input
                    let next = await Task.detached(priority: .userInitiated) {
                        Self.tiles(for: input, in: bounds)
                    }.value
                    guard !Task.isCancelled else { return }
                    cache.store(next, for: key)
                    displayedLayout = next
                    displayedTileIDs = next.map(\.id)
                }
                .focusable().focused($focused).focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
                .onMoveCommand { direction in
                    if let next = DiskChartNavigation.next(layout.compactMap(\.entry), selected: selectedEntryID, direction: direction) { select(next) }
                }
                .onKeyPress(.space) { if let entry = layout.compactMap(\.entry).first(where: { $0.id == selectedEntryID && $0.kind != .aggregate }) { preview(entry) }; return .handled }
                .onKeyPress(.return) { if let entry = layout.compactMap(\.entry).first(where: { $0.id == selectedEntryID && $0.kind != .aggregate }) { open(entry) }; return .handled }
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Treemap of \(directory.name)")
        .accessibilityHint("Click to select. Double-click a folder to explore.")
        .accessibilityIdentifier("diskExplorer.treemap")
        .onChange(of: directory.id) { _, _ in hoveredID = nil }
    }

    @ViewBuilder private func tileView(_ tile: DiskChartTile) -> some View {
        let rect = tile.rect.insetBy(dx: 1, dy: 1)
        if tile.rect.width > 2, tile.rect.height > 2, DiskChartGeometry.isDrawable(rect) {
            Button {
                focused = true
                guard let entry = tile.entry else { return }
                select(entry)
                if NSApp.currentEvent?.clickCount == 2 && entry.kind != .aggregate { open(entry) }
            } label: {
                OnePlusStorageTile(color: tile.style.color, selected: selectedEntryID == tile.id, hovered: hoveredID == tile.id) {
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
            .frame(width: rect.width, height: rect.height).clipped()
            .position(x: rect.midX, y: rect.midY)
            .onHover { inside in
                if inside {
                    hoveredID = tile.id; onHoverDetail("\(tile.label) · \(tile.detail)")
                } else if hoveredID == tile.id {
                    hoveredID = nil; onHoverDetail(nil)
                }
            }.animation(chartAnimation, value: rect)
        }
    }

    nonisolated static func layout(_ tiles: [DiskChartTile], in rect: CGRect, depth: Int = 0) -> [DiskChartTile] {
        guard !tiles.isEmpty, DiskChartGeometry.isDrawable(rect) else { return [] }
        let total = tiles.reduce(0.0) { $0 + Double(max(0, $1.weight)) }
        guard total.isFinite, total > 0 else { return [] }
        if tiles.count == 1 {
            var tile = tiles[0]
            tile.rect = rect
            return [tile]
        }
        let split = tiles.count / 2
        let firstTotal = tiles[..<split].reduce(0.0) { $0 + Double(max(0, $1.weight)) }
        let fraction = CGFloat(DiskChartGeometry.fraction(firstTotal, of: total))
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

nonisolated struct DiskRingSegment: Sendable {
    let id: String
    let entry: DiskEntry?
    let label: String
    let detail: String
    let start: Double
    let end: Double
    let inner: CGFloat
    let outer: CGFloat
    let style: DiskChartColor

    func contains(angle: Double, radius: CGFloat) -> Bool {
        angle >= start && angle < end && radius >= inner && radius <= outer
    }
}

struct DiskRingShape: Shape {
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
        guard DiskChartGeometry.isDrawable(rect), start.isFinite, end.isFinite,
              (end - start).isFinite, end > start,
              inner.isFinite, outer.isFinite, inner >= 0, outer > inner else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard DiskChartGeometry.isDrawable(CGRect(x: center.x - outer, y: center.y - outer,
                                                   width: outer * 2, height: outer * 2)) else { return Path() }
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
    var revision: Date = .distantPast
    var cache = DiskChartLayoutCache()
    let select: (DiskEntry) -> Void
    var onHoverDetail: (String?) -> Void = { _ in }
    var selectedEntryID: String?
    var open: (DiskEntry) -> Void = { _ in }
    var preview: (DiskEntry) -> Void = { _ in }
    var actions: ([DiskEntry]) -> [OnePlusTableAction] = { _ in [] }
    @State private var hoveredID: String?
    @State private var displayedSegments: [DiskRingSegment] = []
    @State private var displayedSegmentIDs: [String] = []
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var chartAnimation: Animation? { OnePlusMotion.animation(reduceMotion: reduceMotion, duration: OnePlusMotion.content) }

    var body: some View {
        GeometryReader { geometry in
            if DiskChartGeometry.isDrawable(CGRect(origin: .zero, size: geometry.size)) {
                let plotHeight = geometry.size.height
                let radius = max(0, min(geometry.size.width, plotHeight) / 2 - 10)
                let key = DiskChartCacheKey(revision: revision, tab: .sunburst,
                                            directoryID: directory.id, measure: measure,
                                            apparent: apparent, scanComplete: scanComplete,
                                            width: Int(geometry.size.width.rounded()),
                                            height: Int(geometry.size.height.rounded()))
                let segments = cache.rings(for: key) ?? displayedSegments
                let center = CGPoint(x: geometry.size.width / 2, y: plotHeight / 2)
                ZStack {
                    ForEach(segments, id: \.id) { segment in segmentView(segment) }
                        .animation(chartAnimation, value: displayedSegmentIDs)
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
                .task(id: key) {
                    if let cached = cache.rings(for: key) {
                        displayedSegments = cached
                        displayedSegmentIDs = cached.map(\.id)
                        return
                    }
                    let input = DiskChartInput(directory: directory, apparent: apparent,
                                               measure: measure, scanComplete: scanComplete)
                    let next = await Task.detached(priority: .userInitiated) {
                        Self.segments(for: input, radius: radius)
                    }.value
                    guard !Task.isCancelled else { return }
                    cache.store(next, for: key)
                    displayedSegments = next
                    displayedSegmentIDs = next.map(\.id)
                }
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
            shape.fill(segment.style.color)
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
            let rect = CGRect(x: geometry.size.width / 2 + cos(angle) * radius - side / 2,
                              y: geometry.size.height / 2 + sin(angle) * radius - side / 2,
                              width: side, height: side)
            if side > OnePlusDiskmanMetrics.tileLabelWidth, DiskChartGeometry.isDrawable(rect) {
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
                    .position(x: rect.midX, y: rect.midY)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    static func hitTest(_ segments: [DiskRingSegment], at point: CGPoint, center: CGPoint) -> DiskRingSegment? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        guard dx.isFinite, dy.isFinite else { return nil }
        var angle = atan2(dy, dx)
        if angle < -.pi / 2 { angle += 2 * .pi }
        return segments.reversed().first { $0.contains(angle: angle, radius: hypot(dx, dy)) }
    }

    nonisolated static func segments(for root: DiskEntry, apparent: Bool,
                                     measure: DiskChartMeasure, radius: CGFloat,
                                     scanComplete: Bool) -> [DiskRingSegment] {
        segments(for: DiskChartInput(directory: root, apparent: apparent,
                                     measure: measure, scanComplete: scanComplete),
                 radius: radius)
    }

    nonisolated static func segments(for input: DiskChartInput,
                                     radius: CGFloat) -> [DiskRingSegment] {
        guard radius.isFinite, radius > 0, (radius * 2).isFinite else { return [] }
        let root = input.directory
        let apparent = input.apparent
        let measure = input.measure
        let scanComplete = input.scanComplete
        var result: [DiskRingSegment] = []
        let levels = !scanComplete || root.children.contains { $0.children.contains { !$0.children.isEmpty } } ? 3 :
            root.children.contains { !$0.children.isEmpty } ? 2 : 1
        let band = CGFloat(0.68) / CGFloat(levels)
        func add(_ parent: DiskEntry, start: Double, end: Double, depth: Int, colorIndex: Int) {
            guard depth < 3, start.isFinite, end.isFinite, end > start else { return }
            let total = parent.children.reduce(0.0) { $0 + Double(max(1, measure.weight($1, apparent: apparent))) }
            guard total.isFinite, total > 0 else { return }
            var angle = start
            let limit = depth == 0 ? OnePlusDiskmanMetrics.inspectorChildren : 12
            let selection: (shown: [DiskEntry], hidden: [DiskEntry])
            if depth == 0 {
                let ranked = parent.children.sorted {
                    let left = measure.weight($0, apparent: apparent)
                    let right = measure.weight($1, apparent: apparent)
                    return left == right ? $0.id < $1.id : left > right
                }
                selection = (Array(ranked.prefix(limit)), Array(ranked.dropFirst(limit)))
            } else {
                selection = measure.displayedChildren(in: parent, apparent: apparent,
                                                      limit: limit, scanComplete: scanComplete)
            }
            let inner = radius * (0.30 + CGFloat(depth) * band)
            let outer = radius * (0.30 + CGFloat(depth + 1) * band) - 2
            guard inner.isFinite, outer.isFinite, inner >= 0, outer > inner else { return }
            let smallIDs = Set(selection.shown.filter { child in
                scanComplete && child.kind != .aggregate &&
                    (end - start) * DiskChartGeometry.fraction(Double(max(1, measure.weight(child, apparent: apparent))), of: total) *
                    Double((inner + outer) / 2) < Double(OnePlusMetrics.controlHeight)
            }.map(\.id))
            let children = selection.shown.filter { !smallIDs.contains($0.id) }
            let hidden = selection.hidden + selection.shown.filter { smallIDs.contains($0.id) }
            for (index, child) in children.enumerated() {
                let next = min(end, angle + (end - start) * DiskChartGeometry.fraction(Double(max(1, measure.weight(child, apparent: apparent))), of: total))
                guard next.isFinite, next > angle else { continue }
                let style = DiskChartPalette.style(for: child, index: depth == 0 ? index : colorIndex,
                                                   measure: measure, depth: depth)
                result.append(DiskRingSegment(id: child.id, entry: child, label: DiskEntryPresentation.name(child),
                                              detail: measure.detail(child, apparent: apparent),
                                              start: angle, end: next,
                                              inner: inner, outer: outer,
                                              style: style))
                add(child, start: angle, end: next, depth: depth + 1,
                    colorIndex: depth == 0 ? index : colorIndex)
                angle = next
            }
            if !hidden.isEmpty, end > angle {
                let remaining = hidden.reduce(Int64(0)) {
                    $0 + measure.weight($1, apparent: apparent)
                }
                let detail = measure == .files ? "\(remaining.formatted()) files" :
                    remaining.formatted(.byteCount(style: .file))
                result.append(DiskRingSegment(id: parent.id + "\0other", entry: nil,
                                              label: "Other items", detail: detail,
                                              start: angle, end: end,
                                              inner: inner, outer: outer,
                                              style: .muted))
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
