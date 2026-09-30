import AppKit
import SwiftUI

struct OnePlusNativeTableSkin: ViewModifier {
    let columns: [OnePlusGridColumn]
    @Environment(\.onePlusDensity) private var density
    func body(content: Content) -> some View {
        content.tableStyle(.inset(alternatesRowBackgrounds: false))
            .environment(\.defaultMinListRowHeight, OnePlusTable.rowHeight(density))
            .scrollContentBackground(.hidden).background(OnePlusColor.panel)
            .onePlusText(.row).onePlusScrollIndicators()
            .background(OnePlusTableConfigurator(density: density, columns: columns))
    }
}

private struct OnePlusTableConfigurator: NSViewRepresentable {
    let density: OnePlusDensity
    let columns: [OnePlusGridColumn]
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.density = density; view.columns = columns; view.configure()
    }

    final class Probe: NSView {
        var density = OnePlusDensity.regular
        var columns: [OnePlusGridColumn] = []
        private weak var table: NSTableView?
        private var borderObservation: NSKeyValueObservation?
        private var pending: DispatchWorkItem?
        isolated deinit { pending?.cancel() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        override func layout() { super.layout(); configure() }
        func configure() {
            guard pending == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pending = nil
                guard self.window != nil, !self.bounds.isEmpty else { return }
                if self.table == nil {
                    var ancestor = self.superview
                    while let view = ancestor, self.table == nil {
                        self.table = self.findTable(in: view)
                        ancestor = view.superview
                    }
                }
                if let table = self.table {
                    if self.borderObservation == nil {
                        self.borderObservation = table.enclosingScrollView?.observe(\.borderType) { [weak self] _, _ in
                            MainActor.assumeIsolated { self?.configure() }
                        }
                    }
                    Self.apply(to: table, density: self.density, columns: self.columns)
                }
            }
            pending = work
            DispatchQueue.main.async(execute: work)
        }
        private func findTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView {
                let container = table.enclosingScrollView ?? table
                let point = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
                if container.convert(container.bounds, to: nil).contains(point) { return table }
            }
            return view.subviews.lazy.compactMap { self.findTable(in: $0) }.first
        }
        private static func apply(to table: NSTableView, density: OnePlusDensity, columns: [OnePlusGridColumn]) {
            // Keep SwiftUI's native style and gridColor. A custom gridColor
            // makes AppKit ask new SwiftUI rows for cells before they exist.
            if table.rowSizeStyle != .custom { table.rowSizeStyle = .custom }
            if table.rowHeight != OnePlusTable.rowHeight(density) { table.rowHeight = OnePlusTable.rowHeight(density) }
            if table.intercellSpacing != .zero { table.intercellSpacing = .zero }
            table.backgroundColor = NSColor(OnePlusColor.panel)
            if !table.gridStyleMask.isEmpty { table.gridStyleMask = [] }
            if let scroll = table.enclosingScrollView, scroll.borderType != .noBorder {
                scroll.borderType = .noBorder
            }
            if !table.subviews.contains(where: { $0 is OnePlusTableLines }) {
                table.addSubview(OnePlusTableLines(table: table))
            }
            table.focusRingType = .none
            if !(table.headerView is OnePlusTableHeaderView) {
                table.headerView = OnePlusTableHeaderView(frame: NSRect(x: 0, y: 0, width: table.bounds.width, height: 28))
            }
            for (index, column) in table.tableColumns.enumerated() {
                let model = columns.indices.contains(index) ? columns[index] : nil
                let alignment: OnePlusGridColumn.Alignment = switch column.headerCell.alignment {
                case .center: .center
                case .right: .trailing
                default: .leading
                }
                let leading = model.map { $0.leadingInset + $0.headerLabelInset } ?? (index == 0 ? 16 : 12)
                let trailing = model?.trailingInset ?? 12
                let resolvedAlignment = model?.alignment ?? (column.headerCell as? OnePlusTableHeaderCell)?.columnAlignment ?? alignment
                let header = column.headerCell as? OnePlusTableHeaderCell
                if header == nil || header?.leadingInset != leading || header?.trailingInset != trailing ||
                    header?.columnAlignment != resolvedAlignment {
                    column.headerCell = OnePlusTableHeaderCell(textCell: column.title,
                        leadingInset: leading, trailingInset: trailing, alignment: resolvedAlignment)
                }
            }
            table.headerView?.needsDisplay = true
        }
    }
}

/// View-based SwiftUI rows draw the system separator independently of gridColor.
/// Paint the shared line above their backgrounds, without replacing their delegate.
final class OnePlusTableLines: NSView {
    private weak var table: NSTableView?
    init(table: NSTableView) {
        self.table = table
        super.init(frame: table.bounds)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.zPosition = 1
        setAccessibilityElement(false)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let table else { return }
        let rows = table.rows(in: dirtyRect)
        guard rows.location != NSNotFound else { return }
        NSColor(OnePlusColor.lineSoft).setFill()
        for row in rows.location..<NSMaxRange(rows) {
            let rect = table.rect(ofRow: row)
            NSRect(x: 0, y: rect.maxY - 1, width: bounds.width, height: 1).fill()
        }
    }
}
