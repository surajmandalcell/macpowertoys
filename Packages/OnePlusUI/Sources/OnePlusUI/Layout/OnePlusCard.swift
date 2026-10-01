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
    @Environment(\.onePlusCardPadding) private var cardPadding
    @State private var errors: [String] = []
    public init(textured: Bool = false, @ViewBuilder content: () -> Content) {
        self.textured = textured; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content.environment(\.onePlusGroupedFieldErrors, true)
            if !errors.isEmpty { OnePlusBanner(errors.joined(separator: "\n"), tone: .error).padding(cardPadding) }
        }
            .onPreferenceChange(OnePlusFieldErrorPreference.self) { errors = $0 }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { OnePlusColor.panel.overlay { if textured { OnePlusMetricTexture() } } }
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
            .background { OnePlusColor.panelHover.overlay { if textured { OnePlusMetricTexture() } } }
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
    private let subtitle: String?
    private let icon: String?
    private let image: Image?
    private let iconRotation: Double
    private let accessory: Accessory
    @Environment(\.onePlusCardPadding) private var cardPadding
    public init(_ title: String, systemImage: String? = nil, image: Image? = nil, iconRotation: Double = 0, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.subtitle = subtitle; icon = systemImage; self.image = image; self.iconRotation = iconRotation; self.accessory = accessory()
    }
    public var body: some View {
        HStack(spacing: 8) {
            if let image {
                image.onePlusAssetGlyph(size: 13)
                    .foregroundStyle(OnePlusColor.secondary).accessibilityHidden(true)
            } else if let icon {
                Image(systemName: icon).font(.system(size: 13)).rotationEffect(.degrees(iconRotation)).frame(width: 13)
                    .foregroundStyle(OnePlusColor.secondary).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).onePlusText(.cardTitle).lineLimit(1).help(title).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).onePlusText(.caption).lineLimit(1).help(subtitle) }
            }
            Spacer(minLength: 8)
            OnePlusHeaderActions { accessory }
        }.padding(.horizontal, cardPadding).frame(height: 40)
            .overlay(alignment: .bottom) { OnePlusColor.lineSoft.frame(height: 1) }
    }
}

public extension OnePlusCardHeader where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil, image: Image? = nil, iconRotation: Double = 0, subtitle: String? = nil) {
        self.init(title, systemImage: systemImage, image: image, iconRotation: iconRotation, subtitle: subtitle, accessory: { EmptyView() })
    }
}

public extension View {
    func onePlusRowHover(selected: Bool = false, radius: CGFloat = 0) -> some View {
        modifier(OnePlusRowHoverModifier(selected: selected, radius: radius))
    }
}

private struct OnePlusRowHoverModifier: ViewModifier {
    let selected: Bool
    let radius: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.onePlusControlState) private var sample
    @State private var hover = false
    private var hovering: Bool { enabled && (hover || sample == .hover) }
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? OnePlusColor.selection : hovering ? OnePlusColor.raised : .clear,
                        in: RoundedRectangle(cornerRadius: radius))
            .onHover { hover = $0 }
    }
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
    @State private var hovering = false
    public init(_ label: String, caption: String? = nil, help: String? = nil, reset: (() -> Void)? = nil,
                controlWidth: CGFloat = 160, separator: Bool = true, @ViewBuilder control: () -> Control) {
        self.label = label; self.caption = caption; self.help = help; self.reset = reset
        self.controlWidth = controlWidth; self.separator = separator; self.control = control()
    }
    public var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label).onePlusText(.row).lineLimit(1).help(help ?? label).accessibilityHint(help ?? "")
                    if let help { OnePlusSettingHelp(label: label, explanation: help, hovering: hovering) }
                    Group {
                        if let reset {
                            Button(action: reset) { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(OnePlusButtonStyle(.icon, size: .small))
                                .help("Reset \(label)").accessibilityLabel("Reset \(label)")
                        } else { Color.clear.accessibilityHidden(true) }
                    }.frame(width: 24, height: 24)
                }
                if let caption { Text(caption).onePlusText(.caption).lineLimit(1).help(caption) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control.frame(width: controlWidth, alignment: .trailing)
        }
        .padding(.horizontal, cardPadding)
        .frame(height: caption == nil ? OnePlusMetrics.settingRow : OnePlusMetrics.captionedSettingRow)
        .contentShape(Rectangle()).onHover { hovering = $0 }
        // Keep the separator inside the row's declared pitch.
        .overlay(alignment: .bottom) { if separator { OnePlusColor.lineSoft.frame(height: 1) } }
    }
}

private struct OnePlusSettingHelp: View {
    let label: String
    let explanation: String
    let hovering: Bool
    @Environment(\.onePlusDensity) private var density
    @FocusState private var focused: Bool
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: OnePlusTextRole.row.size(for: density)))
                .foregroundStyle(OnePlusColor.muted).frame(width: 12, height: 24)
        }
        .buttonStyle(OnePlusInteractionStyle()).focused($focused)
        .opacity(hovering || (focused && OnePlusFocusPolicy.shared.showsFocus) ? 1 : 0)
        .help(explanation).accessibilityLabel("Help for \(label)").accessibilityHint(explanation)
        .popover(isPresented: $presented) { Text(explanation).onePlusText(.row).padding(16).frame(maxWidth: 320) }
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
