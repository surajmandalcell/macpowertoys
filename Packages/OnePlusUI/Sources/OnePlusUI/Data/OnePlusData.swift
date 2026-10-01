import SwiftUI

public struct OnePlusMetricTile<Chart: View>: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let caption: String?
    let action: (() -> Void)?
    let chart: Chart
    @Environment(\.isEnabled) private var enabled
    @Environment(\.onePlusControlState) private var sample
    @State private var hover = false
    private var hovering: Bool { enabled && (hover || sample == .hover) }
    public init(_ title: String, systemImage: String, value: String, unit: String = "", caption: String? = nil,
                action: (() -> Void)? = nil, @ViewBuilder chart: () -> Chart) {
        self.title = title; icon = systemImage; self.value = value; self.unit = unit
        self.caption = caption; self.action = action; self.chart = chart()
    }
    public var body: some View {
        Group {
            if let action { Button(action: action) { tile }.buttonStyle(OnePlusInteractionStyle(radius: 8)) }
            else { tile }
        }.onHover { hover = $0 }
    }
    private var tile: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 13)).foregroundStyle(OnePlusColor.secondary).accessibilityHidden(true)
                    Text(title).onePlusText(.cardTitle)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value).onePlusText(.metric)
                        Text(unit).onePlusText(.unit)
                    }
                    if action != nil {
                        Image(systemName: "chevron.right").font(.system(size: 9))
                            .foregroundStyle(hovering ? OnePlusColor.ink : OnePlusColor.muted).accessibilityHidden(true)
                    }
                }
                if let caption { Text(caption).onePlusText(.caption).lineLimit(1).help(caption) }
            }
            chart
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .background(action != nil && hovering ? OnePlusColor.panelHover : OnePlusColor.panel)
        .onePlusGrain().clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(OnePlusColor.line, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

public extension OnePlusMetricTile where Chart == EmptyView {
    init(_ title: String, systemImage: String, value: String, unit: String = "", caption: String? = nil, action: (() -> Void)? = nil) {
        self.init(title, systemImage: systemImage, value: value, unit: unit, caption: caption, action: action, chart: { EmptyView() })
    }
}

public struct OnePlusStatus: View {
    public enum State: Sendable { case neutral, online, offline, warning, error, success }
    let title: String
    let state: State
    let textRole: OnePlusTextRole
    public init(_ title: String, state: State = .neutral, textRole: OnePlusTextRole = .caption) {
        self.title = title; self.state = state; self.textRole = textRole
    }
    var color: Color {
        switch state {
        case .neutral, .online: OnePlusColor.secondary
        case .offline: OnePlusColor.muted
        case .warning: OnePlusColor.warn
        case .error: OnePlusColor.danger
        case .success: OnePlusColor.ok
        }
    }
    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state == .offline ? .clear : color)
                .overlay { Circle().strokeBorder(color, lineWidth: state == .offline ? 1 : 0) }
                .frame(width: 4, height: 4).accessibilityHidden(true)
            Text(title).onePlusText(textRole, color: color)
        }.accessibilityElement(children: .combine)
    }
}

public struct OnePlusBadge: View {
    let count: Int
    let pending: Bool
    public init(_ count: Int, pending: Bool = false) { self.count = count; self.pending = pending }
    public var body: some View {
        Text(String(count)).font(.system(size: 9, design: .monospaced))
            .foregroundStyle(pending ? OnePlusColor.danger : OnePlusColor.muted)
            .padding(.horizontal, pending ? 6 : 0).frame(height: 16)
            .background(pending ? OnePlusColor.dangerFill : .clear, in: Capsule())
    }
}

public struct OnePlusKeyValueRow: View {
    let label: String
    let value: String
    let monospaced: Bool
    public init(_ label: String, value: String, monospaced: Bool = false) { self.label = label; self.value = value; self.monospaced = monospaced }
    public var body: some View {
        HStack(spacing: 12) {
            Text(label).onePlusText(.caption)
            Spacer(minLength: 8)
            Text(value).onePlusText(monospaced ? .mono : .row).lineLimit(1).truncationMode(.middle).help(value).textSelection(.enabled)
        }.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

public enum OnePlusTable {
    public enum CellPosition { case first, middle, last }
    public static let cellInset: CGFloat = 12
    public static let primaryIconInset: CGFloat = 16
    public static let primaryTextInset: CGFloat = primaryIconInset + 15 + 10
    static let nativeHeaderInset: CGFloat = cellInset - 2
    public static func rowHeight(_ density: OnePlusDensity) -> CGFloat { density == .regular ? 34 : 28 }
}

public extension View {
    /// Use the same column for this cell and `onePlusNativeTable(columns:)`.
    func onePlusTableCell(_ column: OnePlusGridColumn, position: OnePlusTable.CellPosition = .middle) -> some View {
        // ponytail: AppKit's bordered Table reserves 6pt at each outside edge;
        // the native geometry regression test gates updates to that platform inset.
        onePlusText(column.textRole ?? .row, color: column.textColor)
            .frame(maxWidth: .infinity, alignment: column.swiftUIAlignment)
            .padding(.leading, max(0, column.leadingInset - (position == .first ? 6 : 0)))
            .padding(.trailing, max(0, column.trailingInset - (position == .last ? 6 : 0)))
    }
    func onePlusTableHeader() -> some View {
        onePlusText(.tableHeader).frame(height: 28).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OnePlusTable.cellInset).background(OnePlusColor.sidebar)
            .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
    }
    func onePlusTableRow(selected: Bool = false) -> some View { modifier(OnePlusTableRowModifier(selected: selected)) }
}

private struct OnePlusTableRowModifier: ViewModifier {
    let selected: Bool
    @Environment(\.onePlusDensity) private var density
    func body(content: Content) -> some View {
        content.onePlusText(.row).padding(.horizontal, OnePlusTable.cellInset).frame(height: OnePlusTable.rowHeight(density))
            .onePlusRowHover(selected: selected)
            .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
    }
}

public struct OnePlusGridColumn: Identifiable, Sendable {
    public enum Alignment: Sendable { case leading, center, trailing }
    public var id: String { title }
    public let title: String
    public let width: CGFloat
    public let alignment: Alignment
    public let textRole: OnePlusTextRole?
    public let textColor: Color?
    public let leadingInset: CGFloat
    public let trailingInset: CGFloat
    public let headerLabelInset: CGFloat
    public var trailing: Bool { alignment == .trailing }
    public init(_ title: String, width: CGFloat, trailing: Bool = false, textRole: OnePlusTextRole? = nil, textColor: Color? = nil,
                leadingInset: CGFloat = OnePlusTable.cellInset, trailingInset: CGFloat = OnePlusTable.cellInset,
                headerLabelInset: CGFloat = 0) {
        self.init(title, width: width, alignment: trailing ? .trailing : .leading, textRole: textRole,
                  textColor: textColor, leadingInset: leadingInset, trailingInset: trailingInset, headerLabelInset: headerLabelInset)
    }
    public init(_ title: String, width: CGFloat, alignment: Alignment, textRole: OnePlusTextRole? = nil, textColor: Color? = nil,
                leadingInset: CGFloat = OnePlusTable.cellInset, trailingInset: CGFloat = OnePlusTable.cellInset,
                headerLabelInset: CGFloat = 0) {
        self.title = title
        self.width = width.isFinite ? max(0, width) : 0
        self.alignment = alignment
        self.textRole = textRole
        self.textColor = textColor
        self.leadingInset = leadingInset.isFinite ? max(0, leadingInset) : OnePlusTable.cellInset
        self.trailingInset = trailingInset.isFinite ? max(0, trailingInset) : OnePlusTable.cellInset
        self.headerLabelInset = headerLabelInset.isFinite ? max(0, headerLabelInset) : 0
    }
}

/// Small read-only tables. Use native Table for selectable or sortable data.
public struct OnePlusGridTable: View {
    let columns: [OnePlusGridColumn]
    let rows: [[String]]
    public init(columns: [OnePlusGridColumn], rows: [[String]]) { self.columns = columns; self.rows = rows }
    public var body: some View {
        VStack(spacing: 0) {
            cells(columns.map(\.title), header: true).onePlusTableHeader()
            ForEach(rows.indices, id: \.self) { index in cells(rows[index]).onePlusTableRow().textSelection(.enabled) }
        }
    }
    private func cells(_ values: [String], header: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { index in
                Text(values.indices.contains(index) ? values[index] : "")
                    .onePlusText(header ? .tableHeader : columns[index].textRole ?? .row, color: header ? nil : columns[index].textColor)
                    .lineLimit(1).frame(width: columns[index].width, alignment: columns[index].swiftUIAlignment)
                    .help(values.indices.contains(index) ? values[index] : "")
            }
        }
    }
}

private extension OnePlusGridColumn {
    var swiftUIAlignment: SwiftUI.Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
