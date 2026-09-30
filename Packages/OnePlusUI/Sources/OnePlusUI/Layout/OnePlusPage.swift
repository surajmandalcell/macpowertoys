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
    public init(_ id: Value, _ title: String, count: Int? = nil) { self.id = id; self.title = title; self.count = count }
}

public struct OnePlusTabStrip<Value: Hashable, Tools: View>: View {
    public enum Layout { case workspace, applet }
    private let tabs: [OnePlusTab<Value>]
    private let layout: Layout
    @Binding private var selection: Value
    private let tools: Tools
    @Environment(\.onePlusDensity) private var density
    public init(tabs: [OnePlusTab<Value>], selection: Binding<Value>, layout: Layout = .workspace,
                @ViewBuilder tools: () -> Tools) {
        self.tabs = tabs; _selection = selection; self.layout = layout; self.tools = tools()
    }
    public var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs) { tab in
                Button { selection = tab.id } label: {
                    HStack(spacing: 6) {
                        Text(tab.title).onePlusText(.tab, selected: selection == tab.id)
                        if let count = tab.count { OnePlusNavBadge(count) }
                    }.frame(height: 36)
                        .overlay(alignment: .bottom) { Rectangle().fill(selection == tab.id ? OnePlusColor.accent : .clear).frame(height: 2) }
                        .contentShape(Rectangle())
                }.buttonStyle(OnePlusInteractionStyle())
                    .accessibilityAddTraits(selection == tab.id ? .isSelected : [])
            }
            Spacer(minLength: 8)
            tools
        }
        .padding(.horizontal, layout == .applet ? OnePlusMetrics.appletGutter : density.gutter).frame(height: 36)
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1).offset(y: 1) }
        .onMoveCommand { direction in
            if let next = OnePlusSegmented<Value>.nextSelection(in: tabs.map(\.id), current: selection,
                                                               direction: direction == .left || direction == .up ? -1 : 1) { selection = next }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Pages")
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
                    .environment(\.onePlusPageScrollBottomInset, scrollBottomInset)
            }
            if let footer {
                footer.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, gutter).padding(.top, OnePlusMetrics.contentGap)
                    .padding(.bottom, bottomInset).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var gutter: CGFloat { layout == .applet ? OnePlusMetrics.appletGutter : density.gutter }
    private var bottomInset: CGFloat { layout == .applet ? 0 : OnePlusMetrics.gutter }
    private var scrollBottomInset: CGFloat { footer == nil ? bottomInset : 0 }
    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: OnePlusMetrics.cardGap) { content }
            .frame(maxWidth: .infinity, maxHeight: scrolls ? nil : .infinity, alignment: .topLeading)
            .padding(.horizontal, gutter)
            .padding(.top, OnePlusMetrics.contentGap)
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
