import AppKit
import SwiftUI

public enum OnePlusMenuMetrics {
    public static let width: CGFloat = 356
    public static let topBarTop: CGFloat = 10
    public static let topBarBottom: CGFloat = 6
    public static let topBar: CGFloat = topBarTop + tab + topBarBottom + 2 * tabGroupInset + 2
    public static let tabGroupInset: CGFloat = 2
    public static let heightFraction: CGFloat = 0.9
    public static let tab: CGFloat = 26
    public static let tabGap: CGFloat = 2
    public static let bodyInset: CGFloat = 8
    public static let bodyWidth: CGFloat = 338
    public static let tileGap: CGFloat = 5
    public static let columns = 3
    public static let actionColumn: CGFloat = 84
    public static func columnWidth(span: Int = 1, available: CGFloat = bodyWidth) -> CGFloat {
        let span = CGFloat(min(max(span, 1), columns))
        let available = available.isFinite ? max(0, available) : 0
        let column = max(0, available - CGFloat(columns - 1) * tileGap) / CGFloat(columns)
        return column * span + (span - 1) * tileGap
    }
}

public struct OnePlusMenuPanel<Tabs: View, Actions: View, Body: View>: View {
    let tabs: Tabs
    let actions: Actions
    let content: () -> Body
    let maximumHeight: CGFloat?
    private let toolbar: (() -> AnyView)?
    private let footer: (() -> AnyView)?
    public init<Toolbar: View, Footer: View>(maximumHeight: CGFloat? = nil, @ViewBuilder tabs: () -> Tabs,
                @ViewBuilder actions: () -> Actions,
                @ViewBuilder toolbar: @escaping () -> Toolbar = { EmptyView() },
                @ViewBuilder footer: @escaping () -> Footer = { EmptyView() },
                @ViewBuilder content: @escaping () -> Body) {
        self.maximumHeight = maximumHeight; self.tabs = tabs(); self.actions = actions(); self.content = content
        self.toolbar = Toolbar.self == EmptyView.self ? nil : { AnyView(toolbar()) }
        self.footer = Footer.self == EmptyView.self ? nil : { AnyView(footer()) }
    }
    public var body: some View {
        OnePlusMenuPanelShell(maximumHeight: maximumHeight, tabs: tabs, actions: actions,
                              toolbar: toolbar, footer: footer, content: content)
            .onePlusLiveUpdates()
    }
}

struct OnePlusMenuPanelShell<Tabs: View, Actions: View, Body: View>: View {
    let maximumHeight: CGFloat?
    let tabs: Tabs
    let actions: Actions
    let content: () -> Body
    let toolbar: (() -> AnyView)?
    let footer: (() -> AnyView)?
    @Environment(\.onePlusMenuHeightChanged) private var heightChanged

    init(maximumHeight: CGFloat?, tabs: Tabs, actions: Actions,
         toolbar: (() -> AnyView)? = nil, footer: (() -> AnyView)? = nil,
         content: @escaping () -> Body) {
        self.maximumHeight = maximumHeight
        self.tabs = tabs
        self.actions = actions
        self.content = content
        self.toolbar = toolbar
        self.footer = footer
    }

    var body: some View {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let defaultHeight = screenHeight.isFinite ? max(0, screenHeight) * OnePlusMenuMetrics.heightFraction : 720
        let requestedHeight = maximumHeight.flatMap { $0.isFinite ? max(0, $0) : nil } ?? defaultHeight
        let cap = max(OnePlusMenuMetrics.topBar, min(requestedHeight, defaultHeight))
        OnePlusMenuPanelLayout(maximumHeight: cap - 2) {
            HStack(spacing: 7) {
                tabs
                Spacer(minLength: 0)
                HStack(spacing: 2) { actions }.fixedSize()
            }.padding(.horizontal, 8).padding(.top, OnePlusMenuMetrics.topBarTop).padding(.bottom, OnePlusMenuMetrics.topBarBottom)
                .frame(height: OnePlusMenuMetrics.topBar - 2)
            fixedRegion(toolbar?() ?? AnyView(EmptyView()), top: 3, bottom: 5)
            OnePlusMenuScrollContent(content: VStack(alignment: .leading, spacing: 5) { content() }
                .frame(width: OnePlusMenuMetrics.bodyWidth).padding(.horizontal, OnePlusMenuMetrics.bodyInset))
            fixedRegion(footer?() ?? AnyView(EmptyView()), top: 5, bottom: 8)
        }.padding(1).frame(width: 356).fixedSize(horizontal: false, vertical: true)
            .background(OnePlusMenuHeightReporter(changed: heightChanged))
            .background(OnePlusColor.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(OnePlusColor.line, lineWidth: 1) }
            .onePlusDensity(.compact)
            .environment(\.onePlusCardPadding, OnePlusMetrics.cardPadding)
            .onePlusNeutralControls()
            .onePlusFocusPolicy()
            .transaction { $0.animation = nil }
    }

    private func fixedRegion(_ view: AnyView, top: CGFloat, bottom: CGFloat) -> some View {
        OnePlusFixedRegionLayout(gutter: 0, bottomInset: bottom, emptyInset: 0, topInset: top) { view }
            .frame(width: OnePlusMenuMetrics.bodyWidth).padding(.horizontal, OnePlusMenuMetrics.bodyInset)
    }
}

private struct OnePlusMenuHeightChangedKey: EnvironmentKey {
    static var defaultValue: (CGFloat) -> Void { { _ in } }
}

private extension EnvironmentValues {
    var onePlusMenuHeightChanged: (CGFloat) -> Void {
        get { self[OnePlusMenuHeightChangedKey.self] }
        set { self[OnePlusMenuHeightChangedKey.self] = newValue }
    }
}

public extension View {
    /// Called with the final natural or capped height during the panel's layout pass.
    func onOnePlusMenuHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        transformEnvironment(\.onePlusMenuHeightChanged) { inherited in
            let parent = inherited
            inherited = { height in parent(height); action(height) }
        }
    }
}

private struct OnePlusMenuHeightReporter: NSViewRepresentable {
    let changed: (CGFloat) -> Void
    func makeNSView(context: Context) -> HeightView { HeightView(changed: changed) }
    func updateNSView(_ view: HeightView, context: Context) { view.changed = changed }
    final class HeightView: NSView {
        var changed: (CGFloat) -> Void
        init(changed: @escaping (CGFloat) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func setFrameSize(_ newSize: NSSize) {
            let previous = frame.height
            super.setFrameSize(newSize)
            if newSize.height > 0, previous != newSize.height { changed(newSize.height) }
        }
    }
}

private struct OnePlusMenuPanelLayout: Layout {
    let maximumHeight: CGFloat
    private func heights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let natural = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)).height }
        let topGap: CGFloat = natural[1] > 0 ? 0 : 3
        let bottomGap: CGFloat = natural[3] > 0 ? 0 : 8
        let bodyCap = max(0, maximumHeight - natural[0] - natural[1] - natural[3] - topGap - bottomGap)
        return [natural[0], natural[1], topGap, min(natural[2], bodyCap), bottomGap, natural[3]]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = OnePlusMenuMetrics.width - 2
        return CGSize(width: width, height: heights(subviews, width: width).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = heights(subviews, width: bounds.width)
        var y = bounds.minY
        let indices: [Int?] = [0, 1, nil, 2, nil, 3]
        for (index, height) in sizes.enumerated() {
            if let viewIndex = indices[index] {
                subviews[viewIndex].place(at: CGPoint(x: bounds.minX, y: y), proposal: .init(width: bounds.width, height: height))
            }
            y += height
        }
    }
}

private struct OnePlusMenuScrollContent<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = OnePlusMenuScrollView()
        scroll.drawsBackground = false
        let host = OnePlusMenuHostingView(rootView: AnyView(content.environment(\.self, context.environment)
            .accessibilityElement(children: .contain)))
        host.scroll = scroll
        scroll.documentView = host
        scroll.configureOnePlusScrollIndicators(axes: .vertical)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(content.environment(\.self, context.environment)
            .accessibilityElement(children: .contain))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let host = scroll.documentView else { return nil }
        let width = proposal.width ?? OnePlusMenuMetrics.width - 2
        host.frame.size.width = width
        let height = host.fittingSize.height
        host.frame.size.height = height
        return CGSize(width: width, height: min(height, proposal.height ?? height))
    }
}

private final class OnePlusMenuScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: documentView?.fittingSize.height ?? 0)
    }
}

private final class OnePlusMenuHostingView<Content: View>: NSHostingView<Content> {
    weak var scroll: NSScrollView?
    private var measuredHeight: CGFloat?
    override func layout() {
        super.layout()
        let height = fittingSize.height
        if measuredHeight != height {
            measuredHeight = height
            scroll?.invalidateIntrinsicContentSize()
        }
    }
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        scroll?.invalidateIntrinsicContentSize()
    }
}

public struct OnePlusMenuTab<Value: Hashable>: Identifiable {
    public let id: Value
    public let title: String
    public let systemImage: String
    public let accessibilityIdentifier: String?
    public init(_ id: Value, _ title: String, systemImage: String, accessibilityIdentifier: String? = nil) {
        self.id = id; self.title = title; self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
    }
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
            tabButtons.onePlusMenuTabGroup()
            ScrollView(.horizontal) { tabButtons }.onePlusScrollIndicators().frame(height: 26).onePlusMenuTabGroup()
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
                .focusEffectDisabled()
                .help(tab.title).accessibilityLabel(tab.title).accessibilityAddTraits(selection == tab.id ? .isSelected : [])
                .modifier(OnePlusOptionalIdentifier(value: tab.accessibilityIdentifier))
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

public extension View {
    func onePlusMenuTabGroup() -> some View {
        padding(OnePlusMenuMetrics.tabGroupInset)
            .background(OnePlusColor.track, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(OnePlusColor.line, lineWidth: 1) }
    }
}

private struct OnePlusOptionalIdentifier: ViewModifier {
    let value: String?
    @ViewBuilder func body(content: Content) -> some View {
        if let value { content.accessibilityIdentifier(value) }
        else { content }
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
    let textured: Bool
    let action: (() -> Void)?
    let content: Content
    @State private var hover = false
    public init(span: Int = 1, height: CGFloat = 70, textured: Bool = true,
                action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.span = min(max(span, 1), OnePlusMenuMetrics.columns)
        self.height = height.isFinite ? max(0, height) : 0
        self.textured = textured
        self.action = action; self.content = content()
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
            .overlay { if textured { OnePlusDitherTexture(strength: 0.11) } }
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
    let compactAction: Bool
    public init(_ title: String, actionTitle: String? = nil, compactAction: Bool = false,
                action: (() -> Void)? = nil) {
        self.title = title; self.actionTitle = actionTitle
        self.compactAction = compactAction; self.action = action
    }
    public var body: some View {
        VStack(spacing: 7) {
            OnePlusColor.line.frame(height: 1)
            HStack {
                Text(title).font(.system(size: 9.5)).foregroundStyle(OnePlusColor.secondary).accessibilityAddTraits(.isHeader)
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(OnePlusButtonStyle(.link, size: .small,
                                                        height: compactAction ? 13 : nil,
                                                        horizontalPadding: compactAction ? 0 : 10))
                }
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
