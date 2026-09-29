import AppKit
import SwiftUI

struct OnePlusNativeTableSkin: ViewModifier {
    @Environment(\.onePlusDensity) private var density
    func body(content: Content) -> some View {
        content.tableStyle(.bordered(alternatesRowBackgrounds: false))
            .environment(\.defaultMinListRowHeight, OnePlusTable.rowHeight(density))
            .scrollContentBackground(.hidden).background(OnePlusColor.panel)
            .onePlusText(.row).onePlusScrollIndicators()
            .background(OnePlusTableConfigurator(density: density))
    }
}

private struct OnePlusTableConfigurator: NSViewRepresentable {
    let density: OnePlusDensity
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.density = density; view.configure() }

    final class Probe: NSView {
        var density = OnePlusDensity.regular
        private weak var table: NSTableView?
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
                guard self.window != nil else { return }
                if self.table == nil {
                    var ancestor = self.superview
                    while let view = ancestor, self.table == nil {
                        self.table = self.findTable(in: view)
                        ancestor = view.superview
                    }
                }
                if let table = self.table { Self.apply(to: table, density: self.density) }
            }
            pending = work
            DispatchQueue.main.async(execute: work)
        }
        private func findTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            return view.subviews.lazy.compactMap { self.findTable(in: $0) }.first
        }
        private static func apply(to table: NSTableView, density: OnePlusDensity) {
            if table.style != .plain { table.style = .plain }
            if table.rowSizeStyle != .custom { table.rowSizeStyle = .custom }
            if table.rowHeight != OnePlusTable.rowHeight(density) { table.rowHeight = OnePlusTable.rowHeight(density) }
            if table.intercellSpacing != .zero { table.intercellSpacing = .zero }
            table.backgroundColor = NSColor(OnePlusColor.panel)
            table.gridColor = NSColor(OnePlusColor.lineSoft)
            if table.gridStyleMask != .solidHorizontalGridLineMask { table.gridStyleMask = .solidHorizontalGridLineMask }
            table.focusRingType = .none
            if !(table.headerView is OnePlusTableHeaderView) {
                table.headerView = OnePlusTableHeaderView(frame: NSRect(x: 0, y: 0, width: table.bounds.width, height: 28))
            }
            for column in table.tableColumns where !(column.headerCell is OnePlusTableHeaderCell) {
                column.headerCell = OnePlusTableHeaderCell(textCell: column.title)
            }
            table.headerView?.needsDisplay = true
        }
    }
}
