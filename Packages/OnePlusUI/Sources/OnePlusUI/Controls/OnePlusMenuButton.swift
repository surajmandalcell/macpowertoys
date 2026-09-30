import SwiftUI

public struct OnePlusMenuButton: View {
    public enum Variant: Sendable { case neutral, ghost, borderedIcon }

    private let title: String
    private let systemImage: String
    private let variant: Variant
    private let items: () -> [OnePlusPopupMenuEntry]
    @Environment(\.onePlusDensity) private var density
    @FocusState private var focused: Bool
    @State private var expanded = false
    @State private var anchor = OnePlusPopupAnchorReference()

    public init(_ title: String, systemImage: String = "ellipsis", variant: Variant = .ghost,
                items: [OnePlusPopupMenuEntry]) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.items = { items }
    }

    public init(_ title: String, systemImage: String = "ellipsis", variant: Variant = .ghost,
                items: @escaping () -> [OnePlusPopupMenuEntry]) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.items = items
    }

    public var body: some View {
        Button(action: toggle) {
            if variant == .borderedIcon {
                Image(systemName: systemImage).accessibilityHidden(true)
            } else {
                HStack(spacing: 6) {
                    Text(title)
                    Image(systemName: "chevron.down").font(.system(size: 10)).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(OnePlusButtonStyle(buttonVariant,
                                       height: variant == .borderedIcon ? density.controlHeight : nil))
        .environment(\.onePlusControlState, expanded ? .hover : .rest)
        .fixedSize()
        .focused($focused)
        .background { OnePlusPopupAnchor(reference: anchor) }
        .onMoveCommand { direction in
            if direction == .down, !expanded { toggle() }
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(expanded ? "Menu open" : "Opens menu")
    }

    private var buttonVariant: OnePlusButtonStyle.Variant {
        switch variant {
        case .neutral: .neutral
        case .ghost: .ghost
        case .borderedIcon: .borderedIcon
        }
    }

    private func toggle() {
        let items = items()
        let entries = items.isEmpty
            ? [.item(OnePlusPopupMenuItem("No actions", isEnabled: false) {})]
            : items
        OnePlusPopupPresenter.shared.toggle(anchor: anchor.view, entries: entries, density: density,
                                            initialID: entries.compactMap(\.item).first(where: \.isEnabled)?.id) { reason in
            expanded = false
            if reason == .escape { focused = true }
        }
        expanded = OnePlusPopupPresenter.shared.isOpen(for: anchor.view)
    }
}
