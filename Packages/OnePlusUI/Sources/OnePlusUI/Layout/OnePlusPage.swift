import AppKit
import CoreText
import SwiftUI

private struct OnePlusHeaderTopAlignedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var onePlusHeaderTopAligned: Bool {
        get { self[OnePlusHeaderTopAlignedKey.self] }
        set { self[OnePlusHeaderTopAlignedKey.self] = newValue }
    }
}

/// Keep the existing line box while placing the painted capitals on the header top line.
struct OnePlusHeaderTitleLayout: Layout {
    var text = ""
    let pointSize: CGFloat
    let height: CGFloat
    let scale: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: subviews.first?.sizeThatFits(.init(width: proposal.width, height: nil)).width ?? 0,
               height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let title = subviews.first else { return }
        let proposal = ProposedViewSize(width: bounds.width, height: nil)
        let dimensions = title.dimensions(in: proposal)
        let font = NSFont.systemFont(ofSize: pointSize, weight: .semibold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let capHeight = text.isEmpty ? font.capHeight : CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).maxY
        // SF type retains half-point cap precision even on a 1x surface.
        let precision = max(2, scale)
        let capTop = dimensions[.firstTextBaseline] - ceil(capHeight * precision) / precision
        title.place(at: CGPoint(x: bounds.minX, y: bounds.minY - capTop), anchor: .topLeading, proposal: proposal)
    }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guide == .top ? bounds.minY : nil
    }
}

public enum OnePlusTitleStyle: Sendable {
    case system, dotMatrix

    public func lineHeight(for density: OnePlusDensity) -> CGFloat {
        OnePlusTextRole.pageTitle.size(for: self == .dotMatrix ? .regular : density) * 1.2
    }
}

public struct OnePlusHeaderActions<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) { content }
    }
}

public struct OnePlusPageHeader<Actions: View>: View {
    private let title: String
    private let subtitle: String?
    private let titleStyle: OnePlusTitleStyle
    private let subtitleRole: OnePlusTextRole
    private let actions: Actions
    @Environment(\.onePlusDensity) private var density
    @Environment(\.displayScale) private var displayScale
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
                    if titleStyle == .dotMatrix {
                        let drawing = OnePlusDotGlyphs.drawing(title, height: OnePlusDotTitle.lineHeight, scale: displayScale)
                        OnePlusDotTitle(title)
                            .padding(.top, -drawing.path.boundingRect.minY)
                            .frame(height: titleHeight, alignment: .top)
                    }
                    else {
                        OnePlusHeaderTitleLayout(text: title, pointSize: OnePlusTextRole.pageTitle.size(for: density),
                                                 height: titleHeight, scale: displayScale) {
                            Text(title).onePlusText(.pageTitle).lineLimit(1).help(title)
                        }
                    }
                }.accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).onePlusText(subtitleRole).lineLimit(1)
                        .truncationMode(subtitleRole == .mono ? .middle : .tail).help(subtitle)
                }
            }
            Spacer(minLength: 0)
            OnePlusHeaderActions { actions }
                .frame(height: titleHeight, alignment: .top).fixedSize(horizontal: true, vertical: false)
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
    @Environment(\.isEnabled) private var enabled
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
                    .overlay(alignment: .bottom) {
                        if selection == tab.id {
                            OnePlusColor.accent.frame(height: 2)
                                .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityAddTraits(selection == tab.id ? .isSelected : [])
            }
            Spacer(minLength: 8)
            OnePlusHeaderActions { tools }
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
    @Environment(\.onePlusPageScrollBottomInset) private var inheritedBottomInset
    @State private var footerHeight: CGFloat = 0
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
            if !scrolls {
                footerRegion
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                if scrolls {
                    footerRegion.background(OnePlusColor.window)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                }
            }
    }
    private var gutter: CGFloat { layout == .applet ? OnePlusMetrics.appletGutter : density.gutter }
    private var bottomInset: CGFloat { layout == .applet ? 0 : OnePlusMetrics.gutter }
    private var scrollBottomInset: CGFloat {
        max(inheritedBottomInset, scrolls ? max(bottomInset, footerHeight) : footer == nil ? bottomInset : 0)
    }
    @ViewBuilder private var footerRegion: some View {
        if let footer {
            OnePlusFixedRegionLayout(gutter: gutter, bottomInset: bottomInset, emptyInset: 0) {
                VStack(alignment: .leading, spacing: OnePlusMetrics.contentGap) { footer }
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
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
