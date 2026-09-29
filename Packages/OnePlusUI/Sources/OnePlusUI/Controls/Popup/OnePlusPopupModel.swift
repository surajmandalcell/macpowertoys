import AppKit

public enum OnePlusPopupMenuRole: Sendable {
    case standard
    case destructive
}

public struct OnePlusPopupMenuItem: Identifiable {
    public let id: UUID
    public let title: String
    public let systemImage: String?
    public let role: OnePlusPopupMenuRole
    public let isEnabled: Bool
    public let isSelected: Bool
    let action: @MainActor () -> Void

    public init(_ title: String, id: UUID = UUID(), systemImage: String? = nil,
                role: OnePlusPopupMenuRole = .standard, isEnabled: Bool = true,
                isSelected: Bool = false, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.action = action
    }
}

public enum OnePlusPopupMenuEntry: Identifiable {
    case item(OnePlusPopupMenuItem)
    case section(id: UUID, title: String)
    case separatorItem(id: UUID)

    public static func section(_ title: String, id: UUID = UUID()) -> Self {
        .section(id: id, title: title)
    }

    public static func separator(id: UUID = UUID()) -> Self {
        .separatorItem(id: id)
    }

    public var id: UUID {
        switch self {
        case let .item(item): item.id
        case let .section(id, _), let .separatorItem(id): id
        }
    }

    var item: OnePlusPopupMenuItem? {
        guard case let .item(item) = self else { return nil }
        return item
    }
}

enum OnePlusPopupKey: Equatable {
    case up
    case down
    case select
    case escape
    case type(String)
}

struct OnePlusPopupNavigationState {
    enum Result: Equatable {
        case none
        case highlight(UUID)
        case select(UUID)
        case closeAndRestoreFocus
    }

    private(set) var isOpen = false
    private(set) var highlightedID: UUID?
    private var typeBuffer = ""
    private var lastTypeTime: TimeInterval = 0

    mutating func open(entries: [OnePlusPopupMenuEntry], initialID: UUID?) {
        isOpen = true
        highlightedID = enabledItems(in: entries).contains { $0.id == initialID }
            ? initialID
            : enabledItems(in: entries).first?.id
        typeBuffer = ""
        lastTypeTime = 0
    }

    mutating func highlight(_ id: UUID?, entries: [OnePlusPopupMenuEntry]) {
        guard let id, enabledItems(in: entries).contains(where: { $0.id == id }) else { return }
        highlightedID = id
    }

    mutating func handle(_ key: OnePlusPopupKey, entries: [OnePlusPopupMenuEntry],
                         time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Result {
        guard isOpen else { return .none }
        switch key {
        case .up:
            return move(by: -1, entries: entries)
        case .down:
            return move(by: 1, entries: entries)
        case .select:
            guard let highlightedID else { return .none }
            isOpen = false
            return .select(highlightedID)
        case .escape:
            isOpen = false
            return .closeAndRestoreFocus
        case let .type(characters):
            return typeSelect(characters, entries: entries, time: time)
        }
    }

    mutating func close() {
        isOpen = false
        highlightedID = nil
        typeBuffer = ""
        lastTypeTime = 0
    }

    private mutating func move(by delta: Int, entries: [OnePlusPopupMenuEntry]) -> Result {
        let items = enabledItems(in: entries)
        guard !items.isEmpty else { return .none }
        let current = highlightedID.flatMap { id in items.firstIndex { $0.id == id } }
        let base = current ?? (delta > 0 ? -1 : 0)
        let index = (base + delta + items.count) % items.count
        highlightedID = items[index].id
        return .highlight(items[index].id)
    }

    private mutating func typeSelect(_ characters: String, entries: [OnePlusPopupMenuEntry],
                                     time: TimeInterval) -> Result {
        guard let character = characters.first, !character.isWhitespace else { return .none }
        if time - lastTypeTime > OnePlusPopupMetrics.typeSelectReset { typeBuffer = "" }
        lastTypeTime = time
        typeBuffer.append(character)
        let items = enabledItems(in: entries)
        let match = firstMatch(for: typeBuffer, in: items) ?? {
            typeBuffer = String(character)
            return firstMatch(for: typeBuffer, in: items)
        }()
        guard let match else { return .none }
        highlightedID = match.id
        return .highlight(match.id)
    }

    private func enabledItems(in entries: [OnePlusPopupMenuEntry]) -> [OnePlusPopupMenuItem] {
        entries.compactMap(\.item).filter(\.isEnabled)
    }

    private func firstMatch(for prefix: String, in items: [OnePlusPopupMenuItem]) -> OnePlusPopupMenuItem? {
        items.first {
            $0.title.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

enum OnePlusPopupPlacement {
    static func frame(trigger: CGRect, popupSize: CGSize, screen: CGRect,
                      gap: CGFloat = OnePlusPopupMetrics.triggerGap) -> CGRect {
        let maxX = max(screen.minX, screen.maxX - popupSize.width)
        let x = min(max(trigger.minX, screen.minX), maxX)
        let belowY = trigger.minY - gap - popupSize.height
        let aboveY = trigger.maxY + gap
        let y: CGFloat
        if belowY >= screen.minY {
            y = belowY
        } else if aboveY + popupSize.height <= screen.maxY {
            y = aboveY
        } else {
            y = min(max(belowY, screen.minY), max(screen.minY, screen.maxY - popupSize.height))
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: popupSize)
    }
}

enum OnePlusPopupMetrics {
    static let padding: CGFloat = 5
    static let radius: CGFloat = 7
    static let itemRadius: CGFloat = 4
    static let itemPadding: CGFloat = 9
    static let itemHeight: CGFloat = 28
    static let compactItemHeight: CGFloat = 24
    static let triggerGap: CGFloat = 4
    static let checkColumn: CGFloat = 14
    static let symbolColumn: CGFloat = 16
    static let columnGap: CGFloat = 6
    static let sectionHeight: CGFloat = 20
    static let separatorHeight: CGFloat = 9
    static let maxVisibleItems = 12
    static let minimumContentWidth: CGFloat = 80
    static let typeSelectReset: TimeInterval = 0.7

    static func itemHeight(for density: OnePlusDensity) -> CGFloat {
        density == .compact ? compactItemHeight : itemHeight
    }

    static func entryHeight(_ entry: OnePlusPopupMenuEntry, density: OnePlusDensity) -> CGFloat {
        switch entry {
        case .item: itemHeight(for: density)
        case .section: sectionHeight
        case .separatorItem: separatorHeight
        }
    }

    static func contentHeight(entries: [OnePlusPopupMenuEntry], density: OnePlusDensity) -> CGFloat {
        entries.reduce(padding * 2) { $0 + entryHeight($1, density: density) }
    }

    static func maximumHeight(density: OnePlusDensity) -> CGFloat {
        padding * 2 + CGFloat(maxVisibleItems) * itemHeight(for: density)
    }
}
