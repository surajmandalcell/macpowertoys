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

private struct OnePlusPopupItemView: View {
    let item: OnePlusPopupMenuItem
    @ObservedObject var session: OnePlusPopupSession

    var body: some View {
        Button { session.choose(item.id) } label: {
            HStack(spacing: OnePlusPopupMetrics.columnGap) {
                if session.showsSelectionColumn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(item.isSelected ? 1 : 0)
                        .frame(width: OnePlusPopupMetrics.checkColumn)
                }
                if session.showsSymbolColumn {
                    Group {
                        if let symbol = item.systemImage { Image(systemName: symbol) }
                        else { Color.clear }
                    }
                    .font(.system(size: 12))
                    .frame(width: OnePlusPopupMetrics.symbolColumn)
                }
                Text(item.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
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
        view.update(entries: session.entries, density: session.density,
                    highlightedID: session.highlightedID, choose: session.choose)
    }
}

private final class OnePlusPopupAccessibilityHost: NSView {
    private var entries: [OnePlusPopupMenuEntry] = []
    private var density = OnePlusDensity.regular
    private var highlightedID: UUID?
    private var choose: (UUID) -> Void = { _ in }
    private var menuItems: [OnePlusPopupAccessibilityItem] = []
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("Menu")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(entries: [OnePlusPopupMenuEntry], density: OnePlusDensity,
                highlightedID: UUID?, choose: @escaping (UUID) -> Void) {
        self.entries = entries
        self.density = density
        self.highlightedID = highlightedID
        self.choose = choose
        rebuildAccessibilityItems()
    }

    override func layout() {
        super.layout()
        rebuildAccessibilityItems()
    }

    private func rebuildAccessibilityItems() {
        guard let window else { return }
        var offset = OnePlusPopupMetrics.padding
        menuItems = entries.compactMap { entry in
            let height = OnePlusPopupMetrics.entryHeight(entry, density: density)
            defer { offset += height }
            guard let item = entry.item else { return nil }
            let rect = NSRect(x: OnePlusPopupMetrics.padding, y: offset,
                              width: max(0, bounds.width - OnePlusPopupMetrics.padding * 2), height: height)
            let element = OnePlusPopupAccessibilityItem(id: item.id) { [weak self] id in self?.choose(id) }
            element.setAccessibilityRole(.menuItem)
            element.setAccessibilityLabel(item.title)
            element.setAccessibilityEnabled(item.isEnabled)
            element.setAccessibilitySelected(item.isSelected)
            element.setAccessibilityFocused(item.id == highlightedID)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window.convertToScreen(convert(rect, to: nil)))
            return element
        }
        setAccessibilityChildren(menuItems)
    }
}

private final class OnePlusPopupAccessibilityItem: NSAccessibilityElement {
    let id: UUID
    private let choose: (UUID) -> Void

    init(id: UUID, choose: @escaping (UUID) -> Void) {
        self.id = id
        self.choose = choose
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        choose(id)
        return true
    }
}
