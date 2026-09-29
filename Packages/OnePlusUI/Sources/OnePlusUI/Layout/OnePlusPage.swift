import SwiftUI

public enum OnePlusTitleStyle: Sendable { case system, dotMatrix }

public struct OnePlusPageHeader<Actions: View>: View {
    private let title: String
    private let subtitle: String?
    private let titleStyle: OnePlusTitleStyle
    private let actions: Actions
    @Environment(\.onePlusDensity) private var density
    public init(title: String, subtitle: String? = nil, titleStyle: OnePlusTitleStyle = .system,
                @ViewBuilder actions: () -> Actions) {
        self.title = title; self.subtitle = subtitle; self.titleStyle = titleStyle; self.actions = actions()
    }
    public var body: some View {
        let titleHeight = titleStyle == .dotMatrix ? CGFloat(20) : OnePlusTextRole.pageTitle.size(for: density) * 1.2
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if titleStyle == .dotMatrix { OnePlusDotTitle(title) }
                    else { Text(title).onePlusText(.pageTitle).lineLimit(1).help(title) }
                }.frame(height: titleHeight).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).onePlusText(.subtitle).lineLimit(1).help(subtitle) }
            }.padding(.top, OnePlusMetrics.top(of: titleHeight))
            Spacer(minLength: 0)
            HStack(spacing: 8) { actions }.frame(height: 54).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, density.gutter)
        .frame(height: subtitle == nil ? 54 : 68, alignment: .top)
        .background(OnePlusWindowDragArea())
    }
}

public extension OnePlusPageHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil, titleStyle: OnePlusTitleStyle = .system) {
        self.init(title: title, subtitle: subtitle, titleStyle: titleStyle, actions: { EmptyView() })
    }
}

public struct OnePlusTab<Value: Hashable>: Identifiable {
    public let id: Value
    public let title: String
    public let count: Int?
    public init(_ id: Value, _ title: String, count: Int? = nil) { self.id = id; self.title = title; self.count = count }
}

public struct OnePlusTabStrip<Value: Hashable, Tools: View>: View {
    private let tabs: [OnePlusTab<Value>]
    @Binding private var selection: Value
    private let tools: Tools
    @Environment(\.onePlusDensity) private var density
    public init(tabs: [OnePlusTab<Value>], selection: Binding<Value>, @ViewBuilder tools: () -> Tools) {
        self.tabs = tabs; _selection = selection; self.tools = tools()
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
        .padding(.horizontal, density.gutter).frame(height: 36)
        .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1).offset(y: 1) }
        .onMoveCommand { direction in
            if let next = OnePlusSegmented<Value>.nextSelection(in: tabs.map(\.id), current: selection,
                                                               direction: direction == .left || direction == .up ? -1 : 1) { selection = next }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Pages")
    }
}

public extension OnePlusTabStrip where Tools == EmptyView {
    init(tabs: [OnePlusTab<Value>], selection: Binding<Value>) {
        self.init(tabs: tabs, selection: selection, tools: { EmptyView() })
    }
}

public struct OnePlusPage<Header: View, Tabs: View, Content: View>: View {
    private let header: Header
    private let tabs: Tabs
    private let content: Content
    private let scrolls: Bool
    @Environment(\.onePlusDensity) private var density
    public init(scrolls: Bool = true, @ViewBuilder header: () -> Header,
                @ViewBuilder tabs: () -> Tabs, @ViewBuilder content: () -> Content) {
        self.scrolls = scrolls; self.header = header(); self.tabs = tabs(); self.content = content()
    }
    public var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            if scrolls { ScrollView { bodyContent }.onePlusScrollIndicators() }
            else { bodyContent.frame(maxHeight: .infinity, alignment: .topLeading) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(.horizontal, density.gutter).padding(.top, 16).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension OnePlusPage where Tabs == EmptyView {
    init(scrolls: Bool = true, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.init(scrolls: scrolls, header: header, tabs: { EmptyView() }, content: content)
    }
}
