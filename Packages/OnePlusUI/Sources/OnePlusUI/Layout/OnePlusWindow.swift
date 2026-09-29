import AppKit
import SwiftUI

public struct OnePlusWindowRoot<Sidebar: View, Content: View>: View {
    private let canvas: OnePlusWindowCanvas
    private let sidebar: Sidebar
    private let content: Content
    public init(canvas: OnePlusWindowCanvas, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content) {
        self.canvas = canvas; self.sidebar = sidebar(); self.content = content()
    }
    public var body: some View {
        ZStack {
            OnePlusColor.window
            OnePlusWindowTexture()
            HStack(spacing: 0) {
                if canvas.sidebarWidth > 0 {
                    sidebar.frame(width: canvas.sidebarWidth).frame(maxHeight: .infinity)
                        .background(OnePlusColor.sidebar)
                        .overlay(alignment: .trailing) { OnePlusColor.line.frame(width: 1) }
                        .clipped()
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
            }
        }
        .ignoresSafeArea().onePlusFixedCanvas(canvas)
        .tint(OnePlusColor.accent)
    }
}

public struct OnePlusSidebarTitle: View {
    private let text: String
    private let height: CGFloat
    private let leadingInset: CGFloat?
    @Environment(\.onePlusZoomTrailingX) private var zoomTrailingX
    public init(_ text: String, height: CGFloat = OnePlusMetrics.titleRow, leadingInset: CGFloat? = nil) {
        self.text = text; self.height = height; self.leadingInset = leadingInset
    }
    public var body: some View {
        Text(text).onePlusText(.sidebarTitle).lineLimit(1).help(text)
            .frame(height: height)
            .padding(.leading, leadingInset ?? OnePlusMetrics.titleStart(afterZoom: zoomTrailingX))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnePlusWindowDragArea())
    }
}

public struct OnePlusSidebar<Search: View, Navigation: View, Bottom: View>: View {
    private let title: String
    private let search: Search
    private let navigation: Navigation
    private let bottom: Bottom
    public init(title: String, @ViewBuilder search: () -> Search,
                @ViewBuilder navigation: () -> Navigation, @ViewBuilder bottom: () -> Bottom) {
        self.title = title; self.search = search(); self.navigation = navigation(); self.bottom = bottom()
    }
    public var body: some View {
        VStack(spacing: 0) {
            OnePlusSidebarTitle(title)
            if Search.self != EmptyView.self {
                search.padding(.horizontal, 12).padding(.bottom, 14)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) { navigation }
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
            }.onePlusScrollIndicators()
            if Bottom.self != EmptyView.self {
                VStack(alignment: .leading, spacing: 2) { bottom }
                    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 12)
            }
        }.background(OnePlusColor.sidebar)
    }
}

public extension OnePlusSidebar where Search == EmptyView {
    init(title: String, @ViewBuilder navigation: () -> Navigation, @ViewBuilder bottom: () -> Bottom) {
        self.init(title: title, search: { EmptyView() }, navigation: navigation, bottom: bottom)
    }
}

public extension OnePlusSidebar where Search == EmptyView, Bottom == EmptyView {
    init(title: String, @ViewBuilder navigation: () -> Navigation) {
        self.init(title: title, search: { EmptyView() }, navigation: navigation, bottom: { EmptyView() })
    }
}

public struct OnePlusNavRow: View {
    private let title: String
    private let systemImage: String
    private let image: Image?
    private let selected: Bool
    private let count: Int?
    private let external: Bool
    private let muted: Bool
    private let action: () -> Void
    @Environment(\.onePlusDensity) private var density
    public init(_ title: String, systemImage: String, image: Image? = nil, selected: Bool = false,
                count: Int? = nil, external: Bool = false, muted: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.image = image
        self.selected = selected; self.count = count; self.external = external; self.muted = muted; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let image { image.resizable().scaledToFit().frame(width: 15, height: 15).accessibilityHidden(true) }
                else { Image(systemName: systemImage).font(.system(size: 15, weight: .regular)).frame(width: 15).accessibilityHidden(true) }
                Text(title).lineLimit(1)
                    .foregroundStyle(muted ? OnePlusColor.muted : selected ? OnePlusColor.ink : OnePlusColor.secondary)
                Spacer(minLength: 4)
                if let count { OnePlusNavBadge(count) }
                if external { Image(systemName: "arrow.up.right").font(.system(size: 10)).accessibilityHidden(true) }
            }
            .font(.system(size: OnePlusTextRole.nav.size(for: density)))
            .foregroundStyle(selected ? OnePlusColor.ink : OnePlusColor.secondary)
            .padding(.horizontal, 10).frame(height: density.navRowHeight).contentShape(Rectangle())
        }
        .buttonStyle(OnePlusInteractionStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : []).help(title)
    }
}

public struct OnePlusNavCaption: View {
    let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title.uppercased()).onePlusText(.captionUpper)
            .frame(height: 20).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

public struct OnePlusNavBadge: View {
    let count: Int
    public init(_ count: Int) { self.count = count }
    public var body: some View {
        Text(String(count)).font(.system(size: 9, design: .monospaced)).foregroundStyle(OnePlusColor.muted)
    }
}

struct OnePlusWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
                if action == "Minimize" { window.performMiniaturize(nil) }
                else if action != "None", window.standardWindowButton(.zoomButton)?.isEnabled == true { window.performZoom(nil) }
            } else { window.performDrag(with: event) }
        }
    }
}
