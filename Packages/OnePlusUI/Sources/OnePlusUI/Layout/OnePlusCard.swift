import SwiftUI

private struct OnePlusCardPaddingKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

public extension EnvironmentValues {
    var onePlusCardPadding: CGFloat {
        get { self[OnePlusCardPaddingKey.self] ?? (onePlusDensity == .compact ? OnePlusMetrics.compactCardPadding : OnePlusMetrics.cardPadding) }
        set { self[OnePlusCardPaddingKey.self] = newValue }
    }
}

public struct OnePlusCard<Content: View>: View {
    private let textured: Bool
    private let content: Content
    public init(textured: Bool = false, @ViewBuilder content: () -> Content) {
        self.textured = textured; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnePlusColor.panel)
            .overlay { if textured { OnePlusDitherTexture() } }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(OnePlusColor.line, lineWidth: 1) }
    }
}

public struct OnePlusMenuCard<Content: View>: View {
    private let textured: Bool
    private let padded: Bool
    private let content: Content
    public init(textured: Bool = false, padded: Bool = true, @ViewBuilder content: () -> Content) {
        self.textured = textured; self.padded = padded; self.content = content()
    }
    public var body: some View {
        content.padding(padded ? OnePlusMenuMetrics.bodyInset : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnePlusColor.panelHover)
            .overlay { if textured { OnePlusDitherTexture(strength: 0.11) } }
            .clipShape(RoundedRectangle(cornerRadius: OnePlusMetrics.menuTileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: OnePlusMetrics.menuTileRadius)
                    .strokeBorder(OnePlusColor.line, lineWidth: 1)
            }
    }
}

public struct OnePlusPanel<Content: View>: View {
    private let textured: Bool
    private let content: Content
    public init(textured: Bool = false, @ViewBuilder content: () -> Content) { self.textured = textured; self.content = content() }
    public var body: some View {
        OnePlusCard(textured: textured) { content }
    }
}

public struct OnePlusCardHeader<Accessory: View>: View {
    private let title: String
    private let icon: String?
    private let iconRotation: Double
    private let accessory: Accessory
    @Environment(\.onePlusCardPadding) private var cardPadding
    public init(_ title: String, systemImage: String? = nil, iconRotation: Double = 0, @ViewBuilder accessory: () -> Accessory) {
        self.title = title; icon = systemImage; self.iconRotation = iconRotation; self.accessory = accessory()
    }
    public var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13)).rotationEffect(.degrees(iconRotation)).frame(width: 13)
                    .foregroundStyle(OnePlusColor.secondary).accessibilityHidden(true)
            }
            Text(title).onePlusText(.cardTitle).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            accessory
        }.padding(.horizontal, cardPadding).frame(height: 40)
            .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
    }
}

public extension OnePlusCardHeader where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil, iconRotation: Double = 0) { self.init(title, systemImage: systemImage, iconRotation: iconRotation, accessory: { EmptyView() }) }
}

public struct OnePlusSettingRow<Control: View>: View {
    private let label: String
    private let caption: String?
    private let help: String?
    private let reset: (() -> Void)?
    private let controlWidth: CGFloat
    private let separator: Bool
    private let control: Control
    @Environment(\.onePlusCardPadding) private var cardPadding
    public init(_ label: String, caption: String? = nil, help: String? = nil, reset: (() -> Void)? = nil,
                controlWidth: CGFloat = 160, separator: Bool = true, @ViewBuilder control: () -> Control) {
        self.label = label; self.caption = caption; self.help = help; self.reset = reset
        self.controlWidth = controlWidth; self.separator = separator; self.control = control()
    }
    public var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label).onePlusText(.row).lineLimit(1).help(label)
                    if let help { Image(systemName: "questionmark.circle").foregroundStyle(OnePlusColor.muted).help(help).accessibilityLabel(help) }
                }
                if let caption { Text(caption).onePlusText(.caption).lineLimit(1).help(caption) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let reset {
                Button(action: reset) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                    .help("Reset \(label)").accessibilityLabel("Reset \(label)")
            }
            control.frame(width: controlWidth, alignment: .trailing)
        }
        .padding(.horizontal, cardPadding)
        .frame(height: caption == nil ? OnePlusMetrics.settingRow : OnePlusMetrics.captionedSettingRow)
        // Keep the separator inside the row's declared pitch.
        .overlay(alignment: .bottom) { if separator { OnePlusColor.lineSoft.frame(height: 1) } }
    }
}

public struct OnePlusSectionTitle: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?
    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title; self.actionTitle = actionTitle; self.action = action
    }
    public var body: some View {
        HStack {
            Text(title).onePlusText(.sectionTitle).accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(OnePlusButtonStyle(.link, size: .small)) }
        }
    }
}
