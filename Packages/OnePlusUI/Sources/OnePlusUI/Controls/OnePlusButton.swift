import AppKit
import SwiftUI

public enum OnePlusControlState: String, CaseIterable, Sendable {
    case rest, hover, pressed, focus
}

private struct OnePlusControlStateKey: EnvironmentKey {
    static let defaultValue = OnePlusControlState.rest
}

public extension EnvironmentValues {
    var onePlusControlState: OnePlusControlState {
        get { self[OnePlusControlStateKey.self] }
        set { self[OnePlusControlStateKey.self] = newValue }
    }
}

public struct OnePlusButtonStyle: ButtonStyle {
    public enum Variant: String, CaseIterable, Sendable { case neutral, primary, accentPrimary, ghost, destructive, icon, borderedIcon, link }
    public enum Size: Sendable { case regular, small }
    let variant: Variant
    let size: Size?
    let minWidth: CGFloat?
    let height: CGFloat?
    let horizontalPadding: CGFloat

    public init(_ variant: Variant = .neutral, size: Size? = nil, minWidth: CGFloat? = nil,
                height: CGFloat? = nil, horizontalPadding: CGFloat = 10) {
        self.variant = variant
        self.size = size
        self.minWidth = minWidth
        self.height = height
        self.horizontalPadding = horizontalPadding
    }

    public func makeBody(configuration: Configuration) -> some View {
        OnePlusButtonBody(label: configuration.label, pressed: configuration.isPressed, style: self)
    }
}

/// A matching label for native Menu controls. The Menu owns activation and keyboard handling.
public struct OnePlusControlLabel<Content: View>: View {
    private let style: OnePlusButtonStyle
    private let content: Content
    public init(variant: OnePlusButtonStyle.Variant = .neutral, size: OnePlusButtonStyle.Size? = nil,
                @ViewBuilder content: () -> Content) {
        style = OnePlusButtonStyle(variant, size: size); self.content = content()
    }
    public var body: some View { OnePlusButtonBody(label: content, pressed: false, style: style) }
}

private struct OnePlusButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.onePlusDensity) private var density
    @Environment(\.onePlusControlHeight) private var controlHeight
    @Environment(\.onePlusControlState) private var sample
    @State private var hovering = false
    let label: Label
    let pressed: Bool
    let style: OnePlusButtonStyle
    private var isPressed: Bool { enabled && (pressed || sample == .pressed) }
    private var isHovering: Bool { enabled && (hovering || sample == .hover) }
    private var isFocused: Bool { enabled && OnePlusFocusPolicy.shared.showsFocus && (focused || sample == .focus) }
    private var height: CGFloat {
        style.height ?? style.size.map { $0 == .small ? OnePlusMetrics.compactControlHeight : OnePlusMetrics.controlHeight }
            ?? controlHeight ?? density.controlHeight
    }
    private var isIcon: Bool { style.variant == .icon || style.variant == .borderedIcon }
    private var radius: CGFloat { isIcon || style.size == .small ? 5 : 6 }
    private var pointSize: CGFloat { style.size == .small ? 11 : OnePlusTextRole.control.size(for: density) }
    private var weight: Font.Weight { style.variant == .primary || style.variant == .accentPrimary ? .medium : .regular }

    var body: some View {
        OnePlusControlContentLayout(pointSize: pointSize, iconIndex: isIcon ? 0 : style.variant == .link ? 1 : nil) {
            label
            if style.variant == .link {
                Image(systemName: "arrow.right").accessibilityHidden(true)
            }
        }
        .font(.system(size: pointSize, weight: weight))
        .imageScale(.medium)
        .labelStyle(OnePlusButtonLabelStyle(pointSize: pointSize, iconOnly: isIcon))
        .foregroundStyle(foreground)
        .tint(foreground)
        .padding(.horizontal, isIcon ? 0 : style.horizontalPadding)
        .frame(minWidth: isIcon ? height : style.minWidth)
        .frame(height: height)
        .background(background, in: RoundedRectangle(cornerRadius: radius))
        .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: radius))
        .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch style.variant {
        case .primary: OnePlusColor.primaryInk
        case .accentPrimary: OnePlusColor.accentPrimaryInk
        case .destructive: OnePlusColor.danger
        case .ghost, .icon, .link: isHovering || isFocused ? OnePlusColor.ink : OnePlusColor.secondary
        case .neutral, .borderedIcon: OnePlusColor.controlInk
        }
    }

    private var background: Color {
        if style.variant == .accentPrimary {
            return isPressed ? OnePlusColor.accentPrimaryPressed : isHovering ? OnePlusColor.accentPrimaryHover : OnePlusColor.accent
        }
        if isPressed { return style.variant == .primary ? OnePlusColor.primaryPressed : OnePlusColor.pressed }
        if isFocused { return style.variant == .primary ? OnePlusColor.primaryFill : OnePlusColor.fieldFocus }
        switch style.variant {
        case .accentPrimary: return OnePlusColor.accent
        case .primary: return isHovering ? OnePlusColor.primaryHover : OnePlusColor.primaryFill
        case .destructive: return OnePlusColor.dangerFill
        case .neutral, .borderedIcon: return isHovering ? OnePlusColor.raisedHover : OnePlusColor.raised
        case .ghost, .icon: return isHovering ? OnePlusColor.raised : .clear
        case .link: return .clear
        }
    }

    private var border: Color {
        if isFocused { return style.variant == .accentPrimary ? OnePlusColor.accentPrimaryInk : OnePlusColor.focus }
        switch style.variant {
        case .neutral, .borderedIcon: return OnePlusColor.line
        case .destructive: return isHovering ? OnePlusColor.danger : OnePlusColor.dangerLine
        default: return .clear
        }
    }
}

struct OnePlusButtonLabelStyle: LabelStyle {
    let pointSize: CGFloat
    var iconOnly = false
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon.accessibilityLabel { _ in configuration.title }
        }
        else {
            OnePlusControlContentLayout(pointSize: pointSize) {
                configuration.icon
                configuration.title
            }
        }
    }
}

struct OnePlusControlContentLayout: Layout {
    let pointSize: CGFloat
    var spacing: CGFloat = 6
    var iconIndex: Int? = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = dimensions(in: proposal, subviews: subviews)
        return CGSize(width: sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, sizes.count - 1)) * spacing,
                      height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = dimensions(in: ProposedViewSize(bounds.size), subviews: subviews)
        var x = bounds.minX
        for index in subviews.indices {
            let dimensions = sizes[index]
            // ponytail: SF Symbols use a half-point optical correction; add symbol metrics if bitmap checks exceed 0.5 pt.
            let center = index == iconIndex ? dimensions.height / 2 + 0.5
                : dimensions[.firstTextBaseline] - NSFont.systemFont(ofSize: pointSize).capHeight / 2
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY - center), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: dimensions.width, height: dimensions.height))
            x += dimensions.width + spacing
        }
    }

    private func dimensions(in proposal: ProposedViewSize, subviews: Subviews) -> [ViewDimensions] {
        let iconWidth = iconIndex.flatMap { subviews.indices.contains($0) ? subviews[$0].sizeThatFits(.unspecified).width : nil } ?? 0
        let labelWidth = proposal.width.map { max(0, $0 - iconWidth - CGFloat(max(0, subviews.count - 1)) * spacing) }
        return subviews.indices.map { index in
            subviews[index].dimensions(in: index == iconIndex ? .unspecified : ProposedViewSize(width: labelWidth, height: proposal.height))
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        return bounds.midY + NSFont.systemFont(ofSize: pointSize).capHeight / 2
    }
}

/// Paint-only feedback for caller-owned row geometry.
public struct OnePlusInteractionStyle: ButtonStyle {
    let selected: Bool
    let radius: CGFloat
    let disabledOpacity: Double
    public init(selected: Bool = false, radius: CGFloat = 5, disabledOpacity: Double = OnePlusMetrics.disabledOpacity) {
        self.selected = selected
        self.radius = radius
        self.disabledOpacity = disabledOpacity
    }
    public func makeBody(configuration: Configuration) -> some View {
        OnePlusInteractionBody(label: configuration.label, pressed: configuration.isPressed, selected: selected, radius: radius, disabledOpacity: disabledOpacity)
    }
}

private struct OnePlusInteractionBody<Label: View>: View {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hover = false
    let label: Label
    let pressed: Bool
    let selected: Bool
    let radius: CGFloat
    let disabledOpacity: Double
    var body: some View {
        label
            .tint(OnePlusColor.secondary)
            .background(enabled && pressed ? OnePlusColor.pressed : selected || (enabled && focused && OnePlusFocusPolicy.shared.showsFocus) ? OnePlusColor.selection : enabled && hover ? OnePlusColor.raised : .clear,
                        in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(enabled && focused && OnePlusFocusPolicy.shared.showsFocus ? OnePlusColor.focus : .clear, lineWidth: 1) }
            .opacity(enabled ? 1 : disabledOpacity)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hover = $0 }
    }
}

public enum OnePlusControlTone: Equatable, Sendable {
    case standard, primary, destructive, quiet
    var variant: OnePlusButtonStyle.Variant {
        switch self {
        case .standard: .neutral
        case .primary: .primary
        case .destructive: .destructive
        case .quiet: .ghost
        }
    }
}

public struct OnePlusControlButtonStyle: ButtonStyle {
    private let style: OnePlusButtonStyle
    public init(tone: OnePlusControlTone = .standard, minWidth: CGFloat? = nil,
                minHeight: CGFloat = OnePlusMetrics.controlHeight,
                horizontalPadding: CGFloat = OnePlusMetrics.controlHorizontalPadding) {
        style = OnePlusButtonStyle(tone.variant, minWidth: minWidth, height: minHeight, horizontalPadding: horizontalPadding)
    }
    public func makeBody(configuration: Configuration) -> some View { style.makeBody(configuration: configuration) }
}

public extension View {
    /// Native menus and template images inherit neutral ink instead of the app accent.
    func onePlusNeutralControls() -> some View {
        tint(OnePlusColor.controlInk).accentColor(OnePlusColor.controlInk)
    }

    func onePlusControl(_ tone: OnePlusControlTone = .standard, minWidth: CGFloat? = nil,
                        minHeight: CGFloat = OnePlusMetrics.controlHeight,
                        horizontalPadding: CGFloat = OnePlusMetrics.controlHorizontalPadding) -> some View {
        buttonStyle(OnePlusControlButtonStyle(tone: tone, minWidth: minWidth, minHeight: minHeight, horizontalPadding: horizontalPadding))
    }
}
