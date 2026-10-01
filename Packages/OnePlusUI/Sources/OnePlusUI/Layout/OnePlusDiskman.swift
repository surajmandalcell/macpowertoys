import AppKit
import SwiftUI

/// Storage-specific geometry from the Diskman recipe and its surface brief.
public enum OnePlusDiskmanMetrics {
    public static let inspectorWidth: CGFloat = 260
    public static let folderSheetWidth: CGFloat = 460
    public static let folderListHeight: CGFloat = 336
    public static let statsHeight: CGFloat = 88
    public static let partitionHeight: CGFloat = 72
    public static let tileRadius: CGFloat = 4
    public static let tileInset: CGFloat = 8
    public static let tileLabelWidth: CGFloat = 80
    public static let tileLabelHeight: CGFloat = 56
    public static let tileCountsHeight: CGFloat = 104
    public static let inspectorChildren = 5
}

public struct OnePlusDiskmanHeader<Actions: View>: View {
    let title: String
    let path: String
    let actions: Actions
    public init(_ title: String, path: String, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.path = path; self.actions = actions()
    }
    public var body: some View {
        OnePlusPageHeader(title: title, subtitle: path, subtitleRole: .mono) { actions }
    }
}

public struct OnePlusDeviceNavRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let selected: Bool
    let locked: Bool
    let identifier: String
    let action: () -> Void
    let trailing: Trailing
    public init(_ title: String, subtitle: String, systemImage: String, selected: Bool,
                locked: Bool, accessibilityIdentifier: String = "", action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; icon = systemImage
        self.selected = selected; self.locked = locked; self.action = action; self.trailing = trailing()
        identifier = accessibilityIdentifier
    }
    public var body: some View {
        HStack(spacing: 2) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: icon).frame(width: 15).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).onePlusText(.nav, selected: selected).lineLimit(1).help(title)
                        Text(subtitle).onePlusText(.mono).lineLimit(1).help(subtitle)
                    }
                    Spacer(minLength: 0)
                    if locked { Image(systemName: "lock.fill").onePlusText(.caption) }
                }.padding(.leading, 10).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(OnePlusInteractionStyle(selected: selected))
                .accessibilityLabel("\(title), \(subtitle), \(locked ? "write locked" : "unlocked")")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(identifier)
            trailing
        }.onePlusRowHover(selected: selected, radius: OnePlusMetrics.navRowRadius)
    }
}

public struct OnePlusStorageTexture: View {
    let selected: Bool
    let partition: Bool
    public init(selected: Bool = false, partition: Bool = false) {
        self.selected = selected; self.partition = partition
    }
    public var body: some View {
        GeometryReader { _ in
            if let image = (partition ? OnePlusTextureAsset.partitionBand : .diskDither).image {
                Image(nsImage: image).resizable().interpolation(.none)
                    .frame(width: partition ? 768 : 384, height: partition ? 128 : 384)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(partition ? 0.24 : selected ? 0.22 : 0.17)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

public enum OnePlusStorageStyle {
    public static let ink = Color.white
    public static let secondary = Color.white.opacity(0.8)
    public static let line = Color.white.opacity(0.16)
    public static let selectedLine = Color.white.opacity(0.94)
    public static let hoverLine = Color.white.opacity(0.55)
}

public struct OnePlusStorageTile<Content: View>: View {
    let color: Color
    let selected: Bool
    let hovered: Bool
    let partition: Bool
    let content: Content
    public init(color: Color, selected: Bool = false, hovered: Bool = false, partition: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.color = color; self.selected = selected; self.hovered = hovered
        self.partition = partition; self.content = content()
    }
    public var body: some View {
        ZStack(alignment: .topLeading) {
            color
            OnePlusStorageTexture(selected: selected, partition: partition)
            content.padding(OnePlusDiskmanMetrics.tileInset)
        }
        .clipShape(RoundedRectangle(cornerRadius: OnePlusDiskmanMetrics.tileRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OnePlusDiskmanMetrics.tileRadius)
                .strokeBorder(selected ? OnePlusStorageStyle.selectedLine : hovered ? OnePlusStorageStyle.hoverLine : OnePlusStorageStyle.line, lineWidth: 1)
        }
    }
}

public extension OnePlusSheet {
    init(diskmanFolderTitle title: String, @ViewBuilder content: () -> Body, @ViewBuilder footer: () -> Footer) {
        self.title = title; width = OnePlusDiskmanMetrics.folderSheetWidth; close = nil
        self.content = content(); self.footer = footer()
    }
}
