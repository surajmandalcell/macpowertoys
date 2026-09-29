import AppKit
import SwiftUI

public struct OnePlusTableItem: Equatable, Identifiable {
    public let id: String
    public let cells: [String]
    public let symbol: String
    public let url: URL?
    public init(id: String, cells: [String], symbol: String, url: URL? = nil) {
        self.id = id; self.cells = cells; self.symbol = symbol; self.url = url
    }
}

public struct OnePlusTableAction {
    public let title: String
    public let enabled: Bool
    public let action: () -> Void
    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.enabled = enabled; self.action = action
    }
}

/// A native selectable table with the OnePlus row and header geometry.
public struct OnePlusNativeTable: NSViewRepresentable {
    @Environment(\.onePlusDensity) private var density
    let columns: [OnePlusGridColumn]
    let rows: [OnePlusTableItem]
    @Binding var selection: Set<String>
    let sortColumn: Int
    let ascending: Bool
    let sort: (Int, Bool) -> Void
    let open: (Set<String>) -> Void
    let preview: (Set<String>) -> Void
    let remove: (Set<String>) -> Void
    let actions: (Set<String>) -> [OnePlusTableAction]

    public init(columns: [OnePlusGridColumn], rows: [OnePlusTableItem], selection: Binding<Set<String>>,
                sortColumn: Int = 0, ascending: Bool = true, sort: @escaping (Int, Bool) -> Void,
                open: @escaping (Set<String>) -> Void, preview: @escaping (Set<String>) -> Void,
                remove: @escaping (Set<String>) -> Void,
                actions: @escaping (Set<String>) -> [OnePlusTableAction]) {
        self.columns = columns; self.rows = rows; _selection = selection
        self.sortColumn = sortColumn; self.ascending = ascending; self.sort = sort
        self.open = open; self.preview = preview; self.remove = remove; self.actions = actions
    }
    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let table = StorageTable()
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.openSelection)
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.style = .plain; table.rowHeight = OnePlusTable.rowHeight(density)
        table.intercellSpacing = .zero
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = NSColor(OnePlusColor.lineSoft)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.headerView = OnePlusTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 28))
        for (index, item) in columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = item.title; column.width = item.width
            column.minWidth = index == 0 ? 160 : item.width
            column.maxWidth = index == 0 ? .greatestFiniteMagnitude : item.width
            column.resizingMask = index == 0 ? .autoresizingMask : []
            column.headerCell = OnePlusTableHeaderCell(textCell: item.title)
            column.sortDescriptorPrototype = NSSortDescriptor(key: String(index), ascending: index != 2)
            table.addTableColumn(column)
        }
        let action = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actions"))
        action.width = 40; action.minWidth = 40; action.maxWidth = 40
        action.headerCell = OnePlusTableHeaderCell(textCell: "")
        table.addTableColumn(action)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.makeMenu = { [weak coordinator = context.coordinator] ids in coordinator?.menu(ids) }
        table.keyAction = { [weak coordinator = context.coordinator] key in coordinator?.key(key) }
        scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.configureOnePlusScrollIndicators()
        scroll.drawsBackground = false
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? StorageTable else { return }
        let changed = context.coordinator.owner.rows != rows
        context.coordinator.owner = self
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        table.items = rows
        table.rowHeight = OnePlusTable.rowHeight(density)
        table.backgroundColor = NSColor(OnePlusColor.panel)
        if changed || table.numberOfRows != rows.count { table.reloadData() }
        let selected = IndexSet(rows.indices.filter { selection.contains(rows[$0].id) })
        if selected != table.selectedRowIndexes { table.selectRowIndexes(selected, byExtendingSelection: false) }
        let descriptors = [NSSortDescriptor(key: String(sortColumn), ascending: ascending)]
        if table.sortDescriptors != descriptors { table.sortDescriptors = descriptors }
    }
    public static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let table = scroll.documentView as? StorageTable else { return }
        table.delegate = nil; table.dataSource = nil; table.target = nil
        table.makeMenu = nil; table.keyAction = nil; table.items = []
    }

    @MainActor public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let actionCellID = NSUserInterfaceItemIdentifier("OnePlusNativeTable.action")
        private static let primaryCellID = NSUserInterfaceItemIdentifier("OnePlusNativeTable.primary")
        private static let rowID = NSUserInterfaceItemIdentifier("OnePlusNativeTable.row")
        private static let textCellID = NSUserInterfaceItemIdentifier("OnePlusNativeTable.text")

        var owner: OnePlusNativeTable
        var updating = false
        init(_ owner: OnePlusNativeTable) { self.owner = owner }
        public func numberOfRows(in tableView: NSTableView) -> Int { owner.rows.count }
        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard owner.rows.indices.contains(row), let column = tableColumn else { return nil }
            let item = owner.rows[row]
            if column.identifier.rawValue == "actions" {
                let button = tableView.makeView(withIdentifier: Self.actionCellID, owner: self) as? NSButton
                    ?? makeActionButton()
                button.tag = row
                button.contentTintColor = NSColor(OnePlusColor.secondary)
                button.isEnabled = !owner.actions([item.id]).isEmpty
                return button
            }
            guard let index = Int(column.identifier.rawValue), item.cells.indices.contains(index) else { return nil }
            let identifier = index == 0 ? Self.primaryCellID : Self.textCellID
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeTextCell(identifier: identifier, includesIcon: index == 0)
            guard let text = cell.textField else { return cell }
            text.stringValue = item.cells[index]
            text.font = owner.columns[index].trailing || index == 3 ? .monospacedSystemFont(ofSize: OnePlusTextRole.mono.size(for: owner.density), weight: .regular) : .systemFont(ofSize: OnePlusTextRole.row.size(for: owner.density))
            text.textColor = NSColor(index == 0 ? OnePlusColor.ink : OnePlusColor.secondary)
            text.alignment = owner.columns[index].trailing ? .right : .left
            cell.imageView?.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
            return cell
        }
        private func makeActionButton() -> NSButton {
            let image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil) ?? NSImage()
            let button = NSButton(image: image, target: self, action: #selector(showActions(_:)))
            button.identifier = Self.actionCellID
            button.isBordered = false
            button.setAccessibilityLabel("File actions")
            return button
        }
        private func makeTextCell(identifier: NSUserInterfaceItemIdentifier, includesIcon: Bool) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text); cell.textField = text
            var inset: CGFloat = 12
            if includesIcon {
                let icon = NSImageView()
                icon.contentTintColor = NSColor(OnePlusColor.secondary)
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.setAccessibilityElement(false)
                cell.addSubview(icon); cell.imageView = icon
                NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 15),
                    icon.heightAnchor.constraint(equalToConstant: 15)])
                inset = 35
            }
            NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            return cell
        }
        public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            if let view = tableView.makeView(withIdentifier: Self.rowID, owner: self) as? StorageRow {
                return view
            }
            let view = StorageRow()
            view.identifier = Self.rowID
            return view
        }
        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? StorageTable else { return }
            owner.selection = table.selectedIDs
        }
        public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !updating, let first = tableView.sortDescriptors.first, let key = first.key, let index = Int(key) else { return }
            owner.sort(index, first.ascending)
        }
        public func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            owner.rows[row].cells.first
        }
        public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            owner.rows[row].url as NSURL?
        }
        @objc func openSelection() { owner.open(owner.selection) }
        func key(_ key: UInt16) {
            switch key { case 36, 76: owner.open(owner.selection)
            case 49: owner.preview(owner.selection)
            case 51, 117: owner.remove(owner.selection)
            default: break }
        }
        func menu(_ ids: Set<String>) -> NSMenu? {
            let actions = owner.actions(ids)
            guard !actions.isEmpty else { return nil }
            let menu = NSMenu(); menu.autoenablesItems = false
            for action in actions {
                let item = StorageMenuItem(action)
                menu.addItem(item)
            }
            return menu
        }
        @objc func showActions(_ sender: NSButton) {
            guard owner.rows.indices.contains(sender.tag), let menu = menu([owner.rows[sender.tag].id]) else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
        }
    }
}

private final class StorageMenuItem: NSMenuItem {
    let perform: () -> Void
    init(_ action: OnePlusTableAction) {
        perform = action.action
        super.init(title: action.title, action: #selector(invoke), keyEquivalent: "")
        target = self; isEnabled = action.enabled
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func invoke() { perform() }
}

private final class StorageTable: NSTableView {
    var items: [OnePlusTableItem] = []
    var makeMenu: ((Set<String>) -> NSMenu?)?
    var keyAction: ((UInt16) -> Void)?
    var selectedIDs: Set<String> { Set(selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].id : nil }) }
    override func keyDown(with event: NSEvent) {
        if [36, 76, 49, 51, 117].contains(event.keyCode) { keyAction?(event.keyCode) }
        else { super.keyDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard items.indices.contains(row) else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return makeMenu?(selectedIDs)
    }
}

private final class StorageRow: NSTableRowView {
    private var hovering = false
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(hovering ? OnePlusColor.raised : OnePlusColor.panel).setFill(); bounds.fill()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor(OnePlusColor.selection).setFill(); bounds.fill()
    }
    override func drawSeparator(in dirtyRect: NSRect) {
        NSColor(OnePlusColor.lineSoft).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}

final class OnePlusTableHeaderCell: NSTableHeaderCell {
    var label: NSAttributedString {
        NSAttributedString(string: stringValue.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor(OnePlusColor.muted), .kern: 0.4
        ])
    }
    override var cellSize: NSSize { NSSize(width: ceil(label.size().width) + 24, height: 28) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor(OnePlusColor.sidebar).setFill(); cellFrame.fill()
        drawInterior(withFrame: cellFrame, in: controlView)
        NSColor(OnePlusColor.lineSoft).setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
    }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let text = label
        text.draw(in: NSRect(x: cellFrame.minX + 12, y: cellFrame.midY - text.size().height / 2,
                            width: max(0, cellFrame.width - 24), height: text.size().height))
    }
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        draw(withFrame: cellFrame, in: controlView)
    }
}

final class OnePlusTableHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(OnePlusColor.sidebar).setFill(); bounds.fill()
        super.draw(dirtyRect)
    }
}
