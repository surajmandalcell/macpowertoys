import SwiftUI

public enum OnePlusCatalogMetrics {
    public static let columns = 4
    public static let gap: CGFloat = 12
    public static let cardHeight: CGFloat = 151
    public static let rowHeight: CGFloat = 52
    public static let iconSize: CGFloat = 40
    public static let cardInset: CGFloat = 12
    public static let titleGap: CGFloat = 2
    public static let smallGap: CGFloat = 6
    public static let openHeight: CGFloat = 26
    public static let openWidth: CGFloat = 56
    public static let viewControlWidth: CGFloat = 64
    public static let placementWidth: CGFloat = 228
    public static let listNameWidth: CGFloat = 180
}

/// The catalog header keeps the title and actions on the window centerline.
public struct OnePlusToolPageHeader<Icon: View, Actions: View>: View {
    private let title: String
    private let subtitle: String
    private let icon: Icon
    private let actions: Actions
    @Environment(\.onePlusDensity) private var density

    public init(title: String, subtitle: String, @ViewBuilder icon: () -> Icon,
                @ViewBuilder actions: () -> Actions) {
        self.title = title; self.subtitle = subtitle; self.icon = icon(); self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: OnePlusCatalogMetrics.gap) {
            icon.frame(width: OnePlusCatalogMetrics.iconSize, height: OnePlusCatalogMetrics.iconSize)
                .padding(.top, OnePlusMetrics.top(of: OnePlusCatalogMetrics.iconSize))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OnePlusCatalogMetrics.titleGap) {
                Text(title).onePlusText(.pageTitle).lineLimit(1).help(title)
                    .frame(height: OnePlusTextRole.pageTitle.size(for: density) * 1.2)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).onePlusText(.subtitle).lineLimit(1).help(subtitle)
            }
            .padding(.top, OnePlusMetrics.top(of: OnePlusTextRole.pageTitle.size(for: density) * 1.2))
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: OnePlusMetrics.actionSpacing) { actions }
                .frame(height: OnePlusMetrics.titleRow).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, density.gutter)
        .frame(height: 68, alignment: .top)
        .background(OnePlusWindowDragArea())
    }
}

public extension OnePlusButtonStyle {
    static var catalogOpen: Self {
        Self(.neutral, size: .small, minWidth: OnePlusCatalogMetrics.openWidth,
             height: OnePlusCatalogMetrics.openHeight)
    }
}
