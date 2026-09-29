import SwiftUI

public struct OnePlusMetricTile<Chart: View>: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let caption: String?
    let action: (() -> Void)?
    let chart: Chart
    @State private var hover = false
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
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(OnePlusColor.secondary).accessibilityHidden(true)
                Text(title).onePlusText(.cardTitle)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(OnePlusColor.muted)
                    .opacity(action != nil && hover ? 1 : 0).accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).onePlusText(.metric)
                Text(unit).onePlusText(.unit)
            }
            if let caption { Text(caption).onePlusText(.caption).lineLimit(1).help(caption) }
            chart
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(action != nil && hover ? OnePlusColor.panelHover : OnePlusColor.panel)
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
        }.frame(minHeight: 28).accessibilityElement(children: .combine)
    }
}

public enum OnePlusTable {
    public static let cellInset: CGFloat = 12
    public static let primaryTextInset: CGFloat = 35
    static let nativeHeaderInset: CGFloat = 10
    static let nativePrimaryHeaderInset: CGFloat = 33
    public static func rowHeight(_ density: OnePlusDensity) -> CGFloat { density == .regular ? 34 : 28 }
}

public extension View {
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
    @State private var hover = false
    func body(content: Content) -> some View {
        content.onePlusText(.row).padding(.horizontal, OnePlusTable.cellInset).frame(height: OnePlusTable.rowHeight(density))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? OnePlusColor.selection : hover ? OnePlusColor.raised : .clear)
            .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
            .onHover { hover = $0 }
    }
}

public struct OnePlusGridColumn: Identifiable, Sendable {
    public enum Alignment: Sendable { case leading, center, trailing }
    public var id: String { title }
    public let title: String
    public let width: CGFloat
    public let alignment: Alignment
    public var trailing: Bool { alignment == .trailing }
    public init(_ title: String, width: CGFloat, trailing: Bool = false) {
        self.title = title
        self.width = width.isFinite ? max(0, width) : 0
        self.alignment = trailing ? .trailing : .leading
    }
    public init(_ title: String, width: CGFloat, alignment: Alignment) {
        self.title = title
        self.width = width.isFinite ? max(0, width) : 0
        self.alignment = alignment
    }
}

/// Small read-only tables. Use native Table for selectable or sortable data.
public struct OnePlusGridTable: View {
    let columns: [OnePlusGridColumn]
    let rows: [[String]]
    public init(columns: [OnePlusGridColumn], rows: [[String]]) { self.columns = columns; self.rows = rows }
    public var body: some View {
        VStack(spacing: 0) {
            cells(columns.map(\.title)).onePlusTableHeader()
            ForEach(rows.indices, id: \.self) { index in cells(rows[index]).onePlusTableRow().textSelection(.enabled) }
        }
    }
    private func cells(_ values: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { index in
                Text(values.indices.contains(index) ? values[index] : "")
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
