import SwiftUI

public enum OnePlusTitleStyle: Sendable {
    case system, dotMatrix

    public func lineHeight(for density: OnePlusDensity) -> CGFloat {
        self == .dotMatrix ? OnePlusDotTitle.lineHeight : OnePlusTextRole.pageTitle.size(for: density) * 1.2
    }
}

public struct OnePlusPageHeader<Actions: View>: View {
    private let title: String
    private let subtitle: String?
    private let titleStyle: OnePlusTitleStyle
    private let subtitleRole: OnePlusTextRole
    private let actions: Actions
    @Environment(\.onePlusDensity) private var density
    public init(title: String, subtitle: String? = nil, titleStyle: OnePlusTitleStyle = .system,
                subtitleRole: OnePlusTextRole = .subtitle,
                @ViewBuilder actions: () -> Actions) {
        self.title = title; self.subtitle = subtitle; self.titleStyle = titleStyle; self.actions = actions()
        self.subtitleRole = subtitleRole
    }
    public var body: some View {
        let titleHeight = titleStyle.lineHeight(for: density)
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if titleStyle == .dotMatrix { OnePlusDotTitle(title) }
                    else { Text(title).onePlusText(.pageTitle).lineLimit(1).help(title) }
                }.frame(height: titleHeight).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).onePlusText(subtitleRole).lineLimit(1)
                        .truncationMode(subtitleRole == .mono ? .middle : .tail).help(subtitle)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { actions }.frame(height: titleHeight).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, density.gutter)
        .padding(.top, OnePlusMetrics.contentTop)
        .padding(.bottom, OnePlusMetrics.pageHeaderBottom)
        .background(OnePlusWindowDragArea())
    }
}

public extension OnePlusPageHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil, titleStyle: OnePlusTitleStyle = .system,
         subtitleRole: OnePlusTextRole = .subtitle) {
        self.init(title: title, subtitle: subtitle, titleStyle: titleStyle,
                  subtitleRole: subtitleRole, actions: { EmptyView() })
    }
}

public struct OnePlusTab<Value: Hashable>: Identifiable {
    public let id: Value
    public let title: String
    public let count: Int?
    public let countDigits: Int
    public init(_ id: Value, _ title: String, count: Int? = nil, countDigits: Int = 3) {
        self.id = id; self.title = title; self.count = count; self.countDigits = countDigits
    }
}

public struct OnePlusTabStrip<Value: Hashable, Tools: View>: View {
    public enum Layout { case workspace, applet }
    private let tabs: [OnePlusTab<Value>]
    private let layout: Layout
    @Binding private var selection: Value
    private let tools: Tools
    @Environment(\.onePlusDensity) private var density
    @Environment(\.onePlusTimingWindow) private var timingWindow
    public init(tabs: [OnePlusTab<Value>], selection: Binding<Value>, layout: Layout = .workspace,
                @ViewBuilder tools: () -> Tools) {
        self.tabs = tabs; _selection = selection; self.layout = layout; self.tools = tools()
    }
    public var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs) { tab in
                Button { select(tab.id) } label: {
                    HStack(spacing: 6) {
                        Text(tab.title)
                        if let count = tab.count { OnePlusNavBadge(count, minimumDigits: tab.countDigits) }
                    }
                }.buttonStyle(OnePlusTabButtonStyle(selected: selection == tab.id))
                    .accessibilityAddTraits(selection == tab.id ? .isSelected : [])
            }
            Spacer(minLength: 8)
            tools
        }
        .padding(.horizontal, layout == .applet ? OnePlusMetrics.appletGutter : density.gutter).frame(height: 36)
        .background(alignment: .bottom) {
            OnePlusColor.lineSoft.frame(height: 1)
                .padding(.horizontal, layout == .applet ? OnePlusMetrics.appletGutter : density.gutter)
        }
        .onMoveCommand { direction in
            if let next = OnePlusSegmented<Value>.nextSelection(in: tabs.map(\.id), current: selection,
                                                               direction: direction == .left || direction == .up ? -1 : 1) { select(next) }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Pages")
    }

    private func select(_ id: Value) {
        if selection != id, !timingWindow.isEmpty {
            OnePlusPanelTimings.shared.begin(panel: timingWindow, operation: .pageSwitch,
                                            tab: tabs.first { $0.id == id }?.title ?? "", input: "tab-strip")
        }
        selection = id
    }
}

struct OnePlusTabButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        OnePlusTabButtonBody(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
}

private struct OnePlusTabButtonBody<Label: View>: View {
    let label: Label
    let selected: Bool
    let pressed: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.onePlusControlState) private var sample
    @State private var hover = false
    private var hovering: Bool { enabled && (hover || sample == .hover) }
    private var pressing: Bool { enabled && (pressed || sample == .pressed) }
    var body: some View {
        label.onePlusText(.tab, color: selected || hovering ? OnePlusColor.ink : OnePlusColor.secondary)
            .background {
                RoundedRectangle(cornerRadius: OnePlusMetrics.navRowRadius)
                    .fill(pressing ? OnePlusColor.pressed : hovering ? OnePlusColor.raised : .clear)
                    .padding(.horizontal, -8).padding(.vertical, -4)
                    .allowsHitTesting(false)
            }
            .frame(height: 36)
            .overlay(alignment: .bottom) {
                OnePlusColor.accent.frame(height: 2).opacity(selected ? 1 : 0)
            }
            .overlay {
                if enabled && focused && OnePlusFocusPolicy.shared.showsFocus {
                    RoundedRectangle(cornerRadius: OnePlusMetrics.navRowRadius).strokeBorder(OnePlusColor.focus, lineWidth: 1)
                }
            }
            .contentShape(Rectangle()).opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
            .onHover { hover = $0 }
    }
}

public extension OnePlusTabStrip where Tools == EmptyView {
    init(tabs: [OnePlusTab<Value>], selection: Binding<Value>, layout: Layout = .workspace) {
        self.init(tabs: tabs, selection: selection, layout: layout, tools: { EmptyView() })
    }
}

public struct OnePlusPage<Header: View, Tabs: View, Content: View>: View {
    public enum Layout: Sendable { case workspace, applet }
    private let header: Header
    private let tabs: Tabs
    private let content: Content
    private let toolbar: AnyView?
    private let footer: AnyView?
    private let scrolls: Bool
    private let layout: Layout
    @Environment(\.onePlusDensity) private var density
    public init<Toolbar: View, Footer: View>(scrolls: Bool = true, layout: Layout = .workspace,
                @ViewBuilder header: () -> Header, @ViewBuilder tabs: () -> Tabs,
                @ViewBuilder toolbar: () -> Toolbar = { EmptyView() },
                @ViewBuilder footer: () -> Footer = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.scrolls = scrolls; self.layout = layout
        self.header = header(); self.tabs = tabs(); self.content = content()
        self.toolbar = Toolbar.self == EmptyView.self ? nil : AnyView(toolbar())
        self.footer = Footer.self == EmptyView.self ? nil : AnyView(footer())
    }
    public var body: some View {
        VStack(spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            tabs.fixedSize(horizontal: false, vertical: true)
            if let toolbar {
                toolbar.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, gutter).padding(.top, OnePlusMetrics.contentGap)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if scrolls {
                GeometryReader { viewport in
                    ScrollView { bodyContent.frame(width: viewport.size.width, alignment: .leading) }
                        .onePlusScrollIndicators()
                        .environment(\.onePlusPageScrollBottomInset, scrollBottomInset)
                }
            } else {
                bodyContent.frame(maxHeight: .infinity, alignment: .topLeading)
                    .padding(.bottom, footer == nil ? bottomInset : 0)
            }
            if let footer {
                OnePlusFixedRegionLayout(gutter: gutter, bottomInset: bottomInset,
                                        emptyInset: scrolls ? 0 : bottomInset) {
                    footer
                }.fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var gutter: CGFloat { layout == .applet ? OnePlusMetrics.appletGutter : density.gutter }
    private var bottomInset: CGFloat { layout == .applet ? 0 : scrolls ? OnePlusMetrics.gutter : density.gutter }
    private var scrollBottomInset: CGFloat { footer == nil ? bottomInset : 0 }
    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) { content }
            .frame(maxWidth: .infinity, maxHeight: scrolls ? nil : .infinity, alignment: .topLeading)
            .padding(.horizontal, gutter)
            .padding(.top, OnePlusMetrics.contentGap)
    }
}

struct OnePlusFixedRegionLayout: Layout {
    let gutter: CGFloat
    let bottomInset: CGFloat
    let emptyInset: CGFloat
    let topInset: CGFloat
    init(gutter: CGFloat, bottomInset: CGFloat, emptyInset: CGFloat, topInset: CGFloat = OnePlusMetrics.contentGap) {
        self.gutter = gutter; self.bottomInset = bottomInset; self.emptyInset = emptyInset; self.topInset = topInset
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let height = subviews.first?.sizeThatFits(.init(width: max(0, width - 2 * gutter), height: nil)).height ?? 0
        return CGSize(width: width, height: height > 0 ? height + topInset + bottomInset : emptyInset)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = max(0, bounds.width - 2 * gutter)
        let height = subviews.first?.sizeThatFits(.init(width: width, height: nil)).height ?? 0
        subviews.first?.place(at: CGPoint(x: bounds.minX + gutter,
                                         y: bounds.minY + (height > 0 ? topInset : 0)),
                              proposal: .init(width: width, height: height))
    }
}

public extension OnePlusPage where Tabs == EmptyView {
    init<Toolbar: View, Footer: View>(scrolls: Bool = true, layout: Layout = .workspace,
         @ViewBuilder header: () -> Header, @ViewBuilder toolbar: () -> Toolbar = { EmptyView() },
         @ViewBuilder footer: () -> Footer = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.init(scrolls: scrolls, layout: layout, header: header, tabs: { EmptyView() },
                  toolbar: toolbar, footer: footer, content: content)
    }
}
