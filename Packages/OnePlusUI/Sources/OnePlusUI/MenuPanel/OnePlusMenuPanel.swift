import AppKit
import SwiftUI

public enum OnePlusMenuMetrics {
    public static let width: CGFloat = 356
    public static let topBar: CGFloat = 35
    public static let tab: CGFloat = 26
    public static let tabGap: CGFloat = 2
    public static let bodyInset: CGFloat = 8
    public static let bodyWidth: CGFloat = 338
    public static let tileGap: CGFloat = 5
    public static let columns = 3
    public static let actionColumn: CGFloat = 84
    public static func columnWidth(span: Int = 1, available: CGFloat = bodyWidth) -> CGFloat {
        let span = CGFloat(min(max(span, 1), columns))
        return (available - CGFloat(columns - 1) * tileGap) / CGFloat(columns) * span + (span - 1) * tileGap
    }
}

private struct OnePlusMenuHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

public struct OnePlusMenuPanel<Tabs: View, Actions: View, Body: View>: View {
    let tabs: Tabs
    let actions: Actions
    let content: Body
    let maximumHeight: CGFloat?
    @State private var contentHeight: CGFloat?
    public init(maximumHeight: CGFloat? = nil, @ViewBuilder tabs: () -> Tabs,
                @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Body) {
        self.maximumHeight = maximumHeight; self.tabs = tabs(); self.actions = actions(); self.content = content()
    }
    public var body: some View {
        let cap = max(37, maximumHeight ?? ((NSScreen.main?.visibleFrame.height ?? 800) - 32))
        let bodyCap = cap - 37
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                tabs
                Spacer(minLength: 0)
                HStack(spacing: 2) { actions }.fixedSize()
            }.padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 4).frame(height: 35)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) { content }
                    .frame(width: 338).padding(.horizontal, 8).padding(.top, 3).padding(.bottom, 8)
                    .background(GeometryReader { proxy in Color.clear.preference(key: OnePlusMenuHeightKey.self, value: proxy.size.height) })
            }
            .onePlusScrollIndicators().frame(height: min(contentHeight ?? bodyCap, bodyCap))
            .onPreferenceChange(OnePlusMenuHeightKey.self) { if $0 > 0 { contentHeight = $0 } }
        }.padding(1).frame(width: 356).background(OnePlusColor.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(OnePlusColor.line, lineWidth: 1) }
            .onePlusDensity(.compact)
    }
}

public struct OnePlusMenuTab<Value: Hashable>: Identifiable {
    public let id: Value
    public let title: String
    public let systemImage: String
    public init(_ id: Value, _ title: String, systemImage: String) { self.id = id; self.title = title; self.systemImage = systemImage }
}

public struct OnePlusMenuTabStrip<Value: Hashable>: View {
    let tabs: [OnePlusMenuTab<Value>]
    @Binding var selection: Value
    let onMove: ((Int, Int) -> Void)?
    public init(tabs: [OnePlusMenuTab<Value>], selection: Binding<Value>, onMove: ((Int, Int) -> Void)? = nil) {
        self.tabs = tabs; _selection = selection; self.onMove = onMove
    }
    public var body: some View {
        ViewThatFits(in: .horizontal) {
            tabButtons
            ScrollView(.horizontal) { tabButtons }.onePlusScrollIndicators().frame(height: 26)
        }
    }
    private var tabButtons: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button { selection = tab.id } label: {
                    Image(systemName: tab.systemImage).font(.system(size: 13))
                        .foregroundStyle(selection == tab.id ? OnePlusColor.ink : OnePlusColor.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(OnePlusInteractionStyle(selected: selection == tab.id))
                .help(tab.title).accessibilityLabel(tab.title).accessibilityAddTraits(selection == tab.id ? .isSelected : [])
                .contextMenu {
                    if let onMove {
                        Button("Move left") {
                            if let index = tabs.firstIndex(where: { $0.id == tab.id }), index > 0 { onMove(index, index - 1) }
                        }.disabled(tabs.first?.id == tab.id)
                        Button("Move right") {
                            if let index = tabs.firstIndex(where: { $0.id == tab.id }), index < tabs.count - 1 { onMove(index, index + 1) }
                        }.disabled(tabs.last?.id == tab.id)
                    }
                }
            }
        }
        .onMoveCommand { direction in
            if let next = OnePlusSegmented<Value>.nextSelection(in: tabs.map(\.id), current: selection, direction: direction == .left ? -1 : 1) { selection = next }
        }
    }
}

public struct OnePlusMenuOpenApp: View {
    let action: () -> Void
    public init(action: @escaping () -> Void) { self.action = action }
    public var body: some View {
        Button("Open App", action: action).buttonStyle(OnePlusButtonStyle(.ghost, size: .small, minWidth: 70, horizontalPadding: 7))
            .frame(width: 70, height: 24)
    }
}

public struct OnePlusMenuTile<Content: View>: View {
    let span: Int
    let height: CGFloat
    let action: (() -> Void)?
    let content: Content
    @State private var hover = false
    public init(span: Int = 1, height: CGFloat = 70, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.span = span; self.height = height; self.action = action; self.content = content()
    }
    public var body: some View {
        Group {
            if let action { Button(action: action) { tile }.buttonStyle(OnePlusInteractionStyle(radius: 6)) }
            else { tile }
        }.onHover { hover = $0 }
    }
    private var tile: some View {
        content.padding(.horizontal, 8).padding(.vertical, height == 70 ? 7 : 6)
            .frame(width: OnePlusMenuMetrics.columnWidth(span: span), height: height, alignment: .topLeading)
            .background(hover && action != nil ? OnePlusColor.raisedHover : OnePlusColor.panelHover)
            .onePlusGrain(opacity: 0.11).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(OnePlusColor.line, lineWidth: 1) }
    }
}

public struct OnePlusMenuControlRow<Control: View>: View {
    let title: String
    let icon: String
    let status: String
    let control: Control
    public init(_ title: String, systemImage: String, status: String = "", @ViewBuilder control: () -> Control) {
        self.title = title; icon = systemImage; self.status = status; self.control = control()
    }
    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13)).accessibilityHidden(true)
                Text(title).onePlusText(.row)
                Text(status).font(.system(size: 9, design: .monospaced)).foregroundStyle(OnePlusColor.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            control.fixedSize()
        }.padding(.horizontal, 1).frame(height: 30).onePlusDensity(.compact)
    }
}

public struct OnePlusMenuSectionHeader: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?
    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title; self.actionTitle = actionTitle; self.action = action
    }
    public var body: some View {
        VStack(spacing: 7) {
            OnePlusColor.line.frame(height: 1)
            HStack {
                Text(title).font(.system(size: 9.5)).foregroundStyle(OnePlusColor.secondary).accessibilityAddTraits(.isHeader)
                Spacer()
                if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(OnePlusButtonStyle(.link, size: .small)) }
            }.frame(minHeight: 13)
        }
    }
}

public struct OnePlusMenuMetric: Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String
    public let unit: String
    public init(_ label: String, value: String, unit: String = "") { self.label = label; self.value = value; self.unit = unit }
}

public struct OnePlusMenuItemCard<Detail: View, Actions: View>: View {
    let title: String
    let status: String
    let online: Bool
    let metrics: [OnePlusMenuMetric]
    let detail: Detail
    let actions: Actions
    public init(_ title: String, status: String, online: Bool = true, metrics: [OnePlusMenuMetric],
                @ViewBuilder detail: () -> Detail, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.status = status; self.online = online; self.metrics = metrics
        self.detail = detail(); self.actions = actions()
    }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(OnePlusColor.ink)
                Spacer()
                OnePlusStatus(status, state: online ? .online : .offline)
            }.padding(.horizontal, 7).frame(height: 20).background(OnePlusColor.panelHover)
            OnePlusColor.line.frame(height: 1)
            HStack(spacing: 0) {
                ForEach(metrics.indices, id: \.self) { index in
                    let metric = metrics[index]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label).font(.system(size: 8)).foregroundStyle(OnePlusColor.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(metric.value).font(.system(size: 11)).monospacedDigit().foregroundStyle(OnePlusColor.ink)
                            Text(metric.unit).font(.system(size: 7.5)).foregroundStyle(OnePlusColor.secondary)
                        }
                    }.padding(.horizontal, 7).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                    if index < metrics.count - 1 { OnePlusColor.line.frame(width: 1) }
                }
            }.frame(height: 36)
            OnePlusColor.line.frame(height: 1)
            HStack(spacing: 0) {
                detail.padding(.horizontal, 7).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                OnePlusColor.line.frame(width: 1)
                VStack(spacing: 0) { actions }.frame(width: 84)
                    .buttonStyle(OnePlusButtonStyle(.ghost, size: .small, horizontalPadding: 8))
            }.frame(minHeight: 51)
        }.background(OnePlusColor.panel).clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(OnePlusColor.line, lineWidth: 1) }
            .onePlusDensity(.compact)
    }
}
