import AppKit
import SwiftUI

public struct OnePlusTableItem: Equatable, Identifiable {
    public let id: String
    public let cells: [String]
    public let symbol: String
    public let url: URL?
    public let usage: [Int: Double]
    public init(id: String, cells: [String], symbol: String, url: URL? = nil, usage: [Int: Double] = [:]) {
        self.id = id; self.cells = cells; self.symbol = symbol; self.url = url
        self.usage = usage
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
    let open: ((Set<String>) -> Void)?
    let preview: ((Set<String>) -> Void)?
    let remove: ((Set<String>) -> Void)?
    let actions: (Set<String>) -> [OnePlusTableAction]

    public init(columns: [OnePlusGridColumn], rows: [OnePlusTableItem], selection: Binding<Set<String>>,
                sortColumn: Int = 0, ascending: Bool = true, sort: @escaping (Int, Bool) -> Void,
                open: ((Set<String>) -> Void)? = nil, preview: ((Set<String>) -> Void)? = nil,
                remove: ((Set<String>) -> Void)? = nil,
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
        table.gridStyleMask = []
        table.gridColor = NSColor(OnePlusColor.lineSoft)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.headerView = OnePlusTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 28))
        configureColumns(in: table)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.makeMenu = { [weak coordinator = context.coordinator] ids in coordinator?.menu(ids) }
        table.keyAction = { [weak coordinator = context.coordinator] key in coordinator?.key(key) ?? false }
        scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.configureOnePlusScrollIndicators()
        scroll.drawsBackground = false
        return scroll
    }
    private func configureColumns(in table: NSTableView) {
        for column in table.tableColumns { table.removeTableColumn(column) }
        for (index, item) in columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = item.title; column.width = item.width
            column.minWidth = index == 0 ? 160 : item.width
            column.maxWidth = index == 0 ? .greatestFiniteMagnitude : item.width
            column.resizingMask = index == 0 ? .autoresizingMask : []
            column.headerCell = OnePlusTableHeaderCell(
                textCell: item.title,
                leadingInset: (index == 0 ? max(OnePlusTable.primaryIconInset, item.leadingInset) + 25 : item.leadingInset) - 2 + item.headerLabelInset,
                trailingInset: item.trailingInset - 2,
                alignment: item.alignment
            )
            column.sortDescriptorPrototype = NSSortDescriptor(key: String(index), ascending: index != 2)
            table.addTableColumn(column)
        }
        let action = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actions"))
        action.width = 40; action.minWidth = 40; action.maxWidth = 40
        action.headerCell = OnePlusTableHeaderCell(textCell: "")
        table.addTableColumn(action)
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? StorageTable else { return }
        table.items = rows
        context.coordinator.update(self, in: table, density: density)
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
        private static let ellipsis = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil) ?? NSImage()

        var owner: OnePlusNativeTable
        var updating = false
        private var density = OnePlusDensity.regular
        init(_ owner: OnePlusNativeTable) { self.owner = owner }
        func update(_ next: OnePlusNativeTable, in table: NSTableView, density: OnePlusDensity) {
            let previous = owner
            let previousDensity = self.density
            owner = next
            self.density = density
            updating = true
            defer { updating = false }
            table.rowHeight = OnePlusTable.rowHeight(density)
            table.backgroundColor = NSColor(OnePlusColor.panel)
            let columnsChanged = previous.columns.map(\.id) != owner.columns.map(\.id)
            if columnsChanged { owner.configureColumns(in: table) }
            let sameOrder = previous.rows.count == owner.rows.count &&
                zip(previous.rows, owner.rows).allSatisfy { $0.id == $1.id }
            if columnsChanged || !sameOrder || table.numberOfRows != owner.rows.count ||
                previous.sortColumn != owner.sortColumn || previous.ascending != owner.ascending ||
                previousDensity != density {
                table.reloadData()
            } else {
                reloadChangedCells(previous.rows, in: table)
            }
            let selected = IndexSet(owner.rows.indices.filter { owner.selection.contains(owner.rows[$0].id) })
            if selected != table.selectedRowIndexes { table.selectRowIndexes(selected, byExtendingSelection: false) }
            let descriptors = [NSSortDescriptor(key: String(owner.sortColumn), ascending: owner.ascending)]
            if table.sortDescriptors != descriptors { table.sortDescriptors = descriptors }
        }
        private func reloadChangedCells(_ previous: [OnePlusTableItem], in table: NSTableView) {
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound else { return }
            var changed: [Int: IndexSet] = [:]
            for row in visible.location..<min(NSMaxRange(visible), owner.rows.count) {
                let item = owner.rows[row], old = previous[row]
                guard item != old else { continue }
                for column in owner.columns.indices where table.rect(ofColumn: column).intersects(table.visibleRect) {
                    let before = old.cells.indices.contains(column) ? old.cells[column] : nil
                    let after = item.cells.indices.contains(column) ? item.cells[column] : nil
                    if before != after || old.usage[column] != item.usage[column] || (column == 0 && old.symbol != item.symbol) {
                        changed[column, default: []].insert(row)
                    }
                }
                // Actions resolve from the current owner when opened; keep the existing button.
                if let button = table.view(atColumn: owner.columns.count, row: row, makeIfNecessary: false) as? NSButton {
                    button.isEnabled = !owner.actions([item.id]).isEmpty
                }
            }
            for (column, rows) in changed {
                table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: column))
            }
        }
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
            guard let index = Int(column.identifier.rawValue), owner.columns.indices.contains(index),
                  item.cells.indices.contains(index) else { return nil }
            let hasUsage = item.usage[index] != nil
            let base = index == 0 ? Self.primaryCellID.rawValue : "\(Self.textCellID.rawValue).\(index)"
            let identifier = NSUserInterfaceItemIdentifier(base + (hasUsage ? ".usage" : ""))
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? StorageTextCell
                ?? makeTextCell(identifier: identifier, includesIcon: index == 0, hasUsage: hasUsage, column: owner.columns[index])
            cell.subviews.compactMap { $0 as? OnePlusTableUsageBar }.first?.value = item.usage[index] ?? 0
            guard let text = cell.textField else { return cell }
            text.stringValue = item.cells[index]
            let role = owner.columns[index].textRole ?? (owner.columns[index].trailing || index == 3 ? .mono : .row)
            let weight: NSFont.Weight = switch role.weight {
            case .medium: .medium
            case .semibold: .semibold
            default: .regular
            }
            text.font = role == .mono ? .monospacedSystemFont(ofSize: role.size(for: density), weight: weight)
                : .systemFont(ofSize: role.size(for: density), weight: weight)
            cell.restingInk = NSColor(owner.columns[index].textColor ?? owner.columns[index].textRole.map(\.color) ?? (index == 0 ? OnePlusColor.ink : OnePlusColor.secondary))
            let semantic = owner.columns[index].textColor
            cell.preservesSemanticInk = semantic == OnePlusColor.danger || semantic == OnePlusColor.warn || semantic == OnePlusColor.ok
            cell.selected = tableView.selectedRowIndexes.contains(row)
            text.alignment = owner.columns[index].nsTextAlignment
            cell.imageView?.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
            return cell
        }
        private func makeActionButton() -> NSButton {
            let button = StorageActionButton(image: Self.ellipsis, target: self, action: #selector(showActions(_:)))
            button.identifier = Self.actionCellID
            button.isBordered = false
            button.setAccessibilityLabel("File actions")
            return button
        }
        private func makeTextCell(identifier: NSUserInterfaceItemIdentifier, includesIcon: Bool, hasUsage: Bool, column: OnePlusGridColumn) -> StorageTextCell {
            let cell = StorageTextCell()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            text.allowsExpansionToolTips = true
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text); cell.textField = text
            var inset = column.leadingInset
            if includesIcon {
                let iconInset = max(OnePlusTable.primaryIconInset, column.leadingInset)
                let icon = NSImageView()
                icon.contentTintColor = NSColor(OnePlusColor.secondary)
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.setAccessibilityElement(false)
                cell.addSubview(icon); cell.imageView = icon
                NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: iconInset),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 15),
                    icon.heightAnchor.constraint(equalToConstant: 15)])
                inset = iconInset + 15 + 10
            }
            if hasUsage {
                let bar = OnePlusTableUsageBar()
                bar.translatesAutoresizingMaskIntoConstraints = false
                bar.setAccessibilityElement(false)
                cell.addSubview(bar)
                NSLayoutConstraint.activate([
                    bar.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset),
                    bar.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    bar.widthAnchor.constraint(equalToConstant: OnePlusDiskmanMetrics.sizeBarWidth),
                    bar.heightAnchor.constraint(equalToConstant: OnePlusDiskmanMetrics.sizeBarHeight)
                ])
                inset += OnePlusDiskmanMetrics.sizeBarWidth + OnePlusMetrics.actionSpacing
            }
            NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -column.trailingInset),
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
        @objc func openSelection() { owner.open?(owner.selection) }
        func key(_ key: UInt16) -> Bool {
            guard !owner.selection.isEmpty else { return false }
            let action: ((Set<String>) -> Void)?
            switch key {
            case 36, 76: action = owner.open
            case 49: action = owner.preview
            case 51, 117: action = owner.remove
            default: return false
            }
            guard let action else { return false }
            action(owner.selection)
            return true
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

final class StorageTable: NSTableView {
    var items: [OnePlusTableItem] = []
    var makeMenu: ((Set<String>) -> NSMenu?)?
    var keyAction: ((UInt16) -> Bool)?
    var selectedIDs: Set<String> { Set(selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].id : nil }) }
    override func keyDown(with event: NSEvent) {
        if !handleActionKey(event) { super.keyDown(with: event) }
    }
    func handleActionKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty, [36, 76, 49, 51, 117].contains(event.keyCode) else { return false }
        return keyAction?(event.keyCode) == true
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard items.indices.contains(row) else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return makeMenu?(selectedIDs)
    }
}

private final class StorageTextCell: NSTableCellView {
    var restingInk = NSColor(OnePlusColor.ink) { didSet { updateInk() } }
    var preservesSemanticInk = false { didSet { updateInk() } }
    var selected = false { didSet { updateInk() } }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { updateInk() } }
    private func updateInk() {
        textField?.cell?.backgroundStyle = .normal
        textField?.textColor = selected && !preservesSemanticInk ? NSColor(OnePlusColor.ink) : restingInk
    }
}

private final class StorageRow: NSTableRowView {
    private var hovering = false
    private var hoverArea: NSTrackingArea?
    override var isSelected: Bool { didSet { updateCells(); needsDisplay = true } }
    override var isEmphasized: Bool { didSet { needsDisplay = true } }
    override func layout() { super.layout(); updateCells() }
    private func updateCells() {
        for column in 0..<numberOfColumns { (view(atColumn: column) as? StorageTextCell)?.selected = isSelected }
        updateActionVisibility()
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSeparator(in: dirtyRect)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true; updateActionVisibility() }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true; updateActionVisibility() }
    func updateActionVisibility() {
        guard numberOfColumns > 0, let button = view(atColumn: numberOfColumns - 1) as? StorageActionButton else { return }
        let opacity: CGFloat = hovering || isSelected || button.keyboardFocused ? 1 : 0
        if button.alphaValue != opacity { button.alphaValue = opacity }
    }
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(hovering ? OnePlusColor.raised : OnePlusColor.panel).setFill(); bounds.fill()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor(isEmphasized ? OnePlusColor.selection : OnePlusColor.selectionInactive).setFill(); bounds.fill()
    }
    override func drawSeparator(in dirtyRect: NSRect) {
        NSColor(OnePlusColor.lineSoft).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}

private final class StorageActionButton: NSButton {
    private(set) var keyboardFocused = false
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); alphaValue = 0 }
    required init?(coder: NSCoder) { super.init(coder: coder); alphaValue = 0 }
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        keyboardFocused = true; alphaValue = 1
        return true
    }
    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        keyboardFocused = false
        var ancestor = superview
        while let view = ancestor {
            if let row = view as? StorageRow { row.updateActionVisibility(); break }
            ancestor = view.superview
        }
        return true
    }
}

final class OnePlusTableHeaderCell: NSTableHeaderCell {
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let columnAlignment: OnePlusGridColumn.Alignment
    init(textCell string: String, leadingInset: CGFloat = OnePlusTable.nativeHeaderInset,
         trailingInset: CGFloat = OnePlusTable.nativeHeaderInset,
         alignment: OnePlusGridColumn.Alignment = .leading) {
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.columnAlignment = alignment
        super.init(textCell: string)
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    var label: NSAttributedString {
        NSAttributedString(string: stringValue.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor(OnePlusColor.muted), .kern: 0.4
        ])
    }
    override var cellSize: NSSize {
        NSSize(width: ceil(label.size().width) + leadingInset + trailingInset, height: 28)
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor(OnePlusColor.sidebar).setFill(); cellFrame.fill()
        drawInterior(withFrame: cellFrame, in: controlView)
        NSColor(OnePlusColor.lineSoft).setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
    }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let text = label
        text.draw(in: labelRect(for: cellFrame))
    }
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        draw(withFrame: cellFrame, in: controlView)
    }
    func labelRect(for cellFrame: NSRect) -> NSRect {
        let size = label.size()
        let available = max(0, cellFrame.width - leadingInset - trailingInset)
        let x = switch columnAlignment {
        case .leading: cellFrame.minX + leadingInset
        case .center: cellFrame.minX + leadingInset + (available - size.width) / 2
        case .trailing: cellFrame.maxX - trailingInset - size.width
        }
        return NSRect(x: x, y: cellFrame.midY - size.height / 2,
                      width: min(size.width, available), height: size.height)
    }
}

private extension OnePlusGridColumn {
    var nsTextAlignment: NSTextAlignment {
        switch alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }
}

final class OnePlusTableHeaderView: NSTableHeaderView {
    override func setFrameSize(_ newSize: NSSize) {
        // AppKit retiles the floating header after native appearance/layout changes.
        // Keep its reserved extent identical to the header cells in both themes.
        super.setFrameSize(NSSize(width: newSize.width, height: 28))
    }

    override func headerRect(ofColumn column: Int) -> NSRect {
        guard let tableView, tableView.tableColumns.indices.contains(column) else { return super.headerRect(ofColumn: column) }
        let rect = tableView.rect(ofColumn: column)
        return NSRect(x: rect.minX, y: 0, width: rect.width, height: 28)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(OnePlusColor.sidebar).setFill(); bounds.fill()
        super.draw(dirtyRect)
    }
}
