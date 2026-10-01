import AppKit
import SwiftUI

@MainActor
final class OnePlusPopupSession: ObservableObject {
    let entries: [OnePlusPopupMenuEntry]
    let density: OnePlusDensity
    let showsSelectionColumn: Bool
    let showsSymbolColumn: Bool
    @Published private(set) var highlightedID: UUID?
    private var navigation = OnePlusPopupNavigationState()
    var select: (UUID) -> Void = { _ in }
    var close: (Bool) -> Void = { _ in }
    weak var accessibilityHost: OnePlusPopupAccessibilityHost?
    var rowAnchors: [UUID: OnePlusPopupRowAnchor] = [:]

    init(entries: [OnePlusPopupMenuEntry], density: OnePlusDensity, initialID: UUID?) {
        self.entries = entries
        self.density = density
        showsSelectionColumn = entries.contains { $0.item?.isSelected == true }
        showsSymbolColumn = entries.contains { $0.item?.systemImage != nil }
        navigation.open(entries: entries, initialID: initialID)
        highlightedID = navigation.highlightedID
    }

    func hover(_ id: UUID?) {
        navigation.highlight(id, entries: entries)
        highlightedID = navigation.highlightedID
    }

    func handle(_ key: OnePlusPopupKey) -> Bool {
        let result = navigation.handle(key, entries: entries)
        highlightedID = navigation.highlightedID
        switch result {
        case .none:
            return false
        case .highlight:
            return true
        case let .select(id):
            select(id)
            return true
        case .closeAndRestoreFocus:
            close(true)
            return true
        }
    }

    func choose(_ id: UUID) { select(id) }
}

struct OnePlusPopupMenuView: View {
    @ObservedObject var session: OnePlusPopupSession

    var body: some View {
        Group {
            if session.entries.filter({ $0.item != nil }).count > OnePlusPopupMetrics.maxVisibleItems {
                ScrollViewReader { proxy in
                    ScrollView { entries }
                        .onePlusScrollIndicators(axes: .vertical)
                        .onChange(of: session.highlightedID) { _, id in
                            guard let id else { return }
                            proxy.scrollTo(id, anchor: .center)
                        }
                }
            } else {
                entries
            }
        }
        .padding(OnePlusPopupMetrics.padding)
        .background(OnePlusColor.raised)
        .clipShape(RoundedRectangle(cornerRadius: OnePlusPopupMetrics.radius))
        .overlay {
            RoundedRectangle(cornerRadius: OnePlusPopupMetrics.radius)
                .strokeBorder(OnePlusColor.line, lineWidth: 1)
        }
        .overlay {
            OnePlusPopupAccessibilityView(session: session)
                .allowsHitTesting(false)
        }
        .onePlusDensity(session.density)
        .onePlusAppAppearance()
    }

    private var entries: some View {
        LazyVStack(spacing: 0) {
            ForEach(session.entries) { entry in
                switch entry {
                case let .item(item):
                    OnePlusPopupItemView(item: item, session: session).id(item.id)
                case let .section(_, title):
                    Text(title)
                        .onePlusText(.captionUpper)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OnePlusPopupMetrics.itemPadding + leadingColumns)
                        .frame(height: OnePlusPopupMetrics.sectionHeight)
                        .accessibilityHidden(true)
                case .separatorItem:
                    Rectangle().fill(OnePlusColor.lineSoft).frame(height: 1)
                        .padding(.horizontal, OnePlusPopupMetrics.itemPadding)
                        .frame(height: OnePlusPopupMetrics.separatorHeight)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var leadingColumns: CGFloat {
        (session.showsSelectionColumn ? OnePlusPopupMetrics.checkColumn + OnePlusPopupMetrics.columnGap : 0)
            + (session.showsSymbolColumn ? OnePlusPopupMetrics.symbolColumn + OnePlusPopupMetrics.columnGap : 0)
    }
}

struct OnePlusPopupItemView: View {
    let item: OnePlusPopupMenuItem
    @ObservedObject var session: OnePlusPopupSession

    var body: some View {
        Button { session.choose(item.id) } label: {
            HStack(spacing: OnePlusPopupMetrics.columnGap) {
                if session.showsSelectionColumn {
                    OnePlusControlContentLayout(pointSize: OnePlusTextRole.control.size(for: session.density)) {
                        Image(systemName: "checkmark")
                    }
                        .opacity(item.isSelected ? 1 : 0)
                        .frame(width: OnePlusPopupMetrics.checkColumn)
                }
                if session.showsSymbolColumn {
                    OnePlusControlContentLayout(pointSize: OnePlusTextRole.control.size(for: session.density)) {
                        if let symbol = item.systemImage { Image(systemName: symbol) }
                        else { Color.clear }
                    }
                    .frame(width: OnePlusPopupMetrics.symbolColumn)
                }
                OnePlusControlContentLayout(pointSize: OnePlusTextRole.control.size(for: session.density), iconIndex: nil) {
                    Text(item.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onePlusText(.control, color: item.role == .destructive ? OnePlusColor.danger : nil)
            .padding(.horizontal, OnePlusPopupMetrics.itemPadding)
            .frame(maxWidth: .infinity)
            .frame(height: OnePlusPopupMetrics.itemHeight(for: session.density))
            .background(session.highlightedID == item.id ? OnePlusColor.selection : .clear,
                        in: RoundedRectangle(cornerRadius: OnePlusPopupMetrics.itemRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background { OnePlusPopupRowGeometry(id: item.id, session: session) }
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : OnePlusMetrics.disabledOpacity)
        .onHover { hovering in
            guard item.isEnabled else { return }
            session.hover(hovering ? item.id : nil)
        }
        .accessibilityHidden(true)
    }
}

private struct OnePlusPopupAccessibilityView: NSViewRepresentable {
    @ObservedObject var session: OnePlusPopupSession

    func makeNSView(context: Context) -> OnePlusPopupAccessibilityHost {
        OnePlusPopupAccessibilityHost()
    }

    func updateNSView(_ view: OnePlusPopupAccessibilityHost, context: Context) {
        session.accessibilityHost = view
        view.update(session: session)
    }
}

final class OnePlusPopupAccessibilityHost: NSView {
    private weak var session: OnePlusPopupSession?
    private var highlightedID: UUID?
    private var itemsByID: [UUID: OnePlusPopupAccessibilityItem] = [:]
    private weak var clipView: NSClipView?
    private var boundsObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("Menu")
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    isolated deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(session: OnePlusPopupSession) {
        self.session = session
        let oldHighlight = highlightedID
        highlightedID = session.highlightedID
        let items = session.entries.compactMap(\.item)
        let ids = Set(items.map(\.id))
        itemsByID = itemsByID.filter { ids.contains($0.key) }
        let children = items.map { item in
            let element = itemsByID[item.id] ?? OnePlusPopupAccessibilityItem(id: item.id) { [weak session] id in
                session?.choose(id)
            }
            itemsByID[item.id] = element
            element.setAccessibilityRole(.menuItem)
            element.setAccessibilityLabel(item.title)
            element.setAccessibilityEnabled(item.isEnabled)
            element.setAccessibilitySelected(item.isSelected)
            element.setAccessibilityFocused(item.id == highlightedID)
            element.setAccessibilityParent(self)
            return element
        }
        setAccessibilityChildren(children)
        updateFrames()
        if oldHighlight != highlightedID, let id = highlightedID, let element = itemsByID[id] {
            NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
        }
    }

    override func layout() { super.layout(); updateFrames() }
    func updateFrames() {
        guard let session else { return }
        for (id, element) in itemsByID {
            guard let row = session.rowAnchors[id]?.view, let window = row.window else {
                element.setAccessibilityFrame(.zero)
                continue
            }
            let visible = row.visibleRect.intersection(row.bounds)
            element.setAccessibilityFrame(visible.isEmpty ? .zero : window.convertToScreen(row.convert(visible, to: nil)))
            observe(row.enclosingScrollView?.contentView)
        }
    }

    private func observe(_ clip: NSClipView?) {
        guard let clip, clip !== clipView else { return }
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        clipView = clip
        clip.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                               object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrames() }
        }
    }
}

final class OnePlusPopupAccessibilityItem: NSAccessibilityElement {
    let id: UUID
    private let choose: (UUID) -> Void
    init(id: UUID, choose: @escaping (UUID) -> Void) {
        self.id = id; self.choose = choose
        super.init()
    }
    override func accessibilityPerformPress() -> Bool {
        guard isAccessibilityEnabled() else { return false }
        choose(id)
        return true
    }
}

final class OnePlusPopupRowAnchor {
    weak var view: NSView?
}

private struct OnePlusPopupRowGeometry: NSViewRepresentable {
    let id: UUID
    let session: OnePlusPopupSession
    func makeNSView(context: Context) -> OnePlusPopupRowGeometryView { OnePlusPopupRowGeometryView() }
    func updateNSView(_ view: OnePlusPopupRowGeometryView, context: Context) {
        let anchor = session.rowAnchors[id] ?? OnePlusPopupRowAnchor()
        anchor.view = view
        session.rowAnchors[id] = anchor
        view.changed = { [weak session] in session?.accessibilityHost?.updateFrames() }
    }
}
private final class OnePlusPopupRowGeometryView: NSView {
    var changed: () -> Void = {}
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); changed() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); changed() }
}
