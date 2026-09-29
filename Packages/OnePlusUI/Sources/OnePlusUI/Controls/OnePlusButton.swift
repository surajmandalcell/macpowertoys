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
    public enum Variant: String, CaseIterable, Sendable { case neutral, primary, ghost, destructive, icon, link }
    public enum Size: Sendable { case regular, small }
    let variant: Variant
    let size: Size
    let minWidth: CGFloat?
    let height: CGFloat?
    let horizontalPadding: CGFloat

    public init(_ variant: Variant = .neutral, size: Size = .regular, minWidth: CGFloat? = nil,
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
    public init(variant: OnePlusButtonStyle.Variant = .neutral, size: OnePlusButtonStyle.Size = .regular,
                @ViewBuilder content: () -> Content) {
        style = OnePlusButtonStyle(variant, size: size); self.content = content()
    }
    public var body: some View { OnePlusButtonBody(label: content, pressed: false, style: style) }
}

private struct OnePlusButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.onePlusDensity) private var density
    @Environment(\.onePlusControlState) private var sample
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    let label: Label
    let pressed: Bool
    let style: OnePlusButtonStyle
    private var isPressed: Bool { enabled && (pressed || sample == .pressed) }
    private var isHovering: Bool { enabled && (hovering || sample == .hover) }
    private var isFocused: Bool { enabled && (focused || sample == .focus) }
    private var height: CGFloat { style.height ?? (style.size == .small ? 24 : density.controlHeight) }
    private var radius: CGFloat { style.variant == .icon || style.size == .small ? 5 : 6 }

    var body: some View {
        HStack(spacing: 6) {
            label
            if style.variant == .link {
                Image(systemName: "arrow.right").font(.system(size: 10)).accessibilityHidden(true)
            }
        }
        .font(.system(size: style.variant == .icon ? 14 : style.size == .small ? 11 : OnePlusTextRole.control.size(for: density),
                      weight: style.variant == .primary ? .medium : .regular))
        .foregroundStyle(foreground)
        .padding(.horizontal, style.variant == .icon ? 0 : style.horizontalPadding)
        .frame(minWidth: style.variant == .icon ? height : style.minWidth)
        .frame(height: height)
        .background(background, in: RoundedRectangle(cornerRadius: radius))
        .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: radius))
        .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
        .onHover { hovering = $0 }
        .animation(OnePlusMotion.animation(reduceMotion: reduceMotion), value: isHovering || isPressed)
        .focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
    }

    private var foreground: Color {
        switch style.variant {
        case .primary: OnePlusColor.primaryInk
        case .destructive: OnePlusColor.danger
        case .ghost, .icon, .link: isHovering || isFocused ? OnePlusColor.ink : OnePlusColor.secondary
        case .neutral: OnePlusColor.controlInk
        }
    }

    private var background: Color {
        if isPressed { return style.variant == .primary ? OnePlusColor.primaryPressed : OnePlusColor.pressed }
        if isFocused { return style.variant == .primary ? OnePlusColor.primaryFill : OnePlusColor.fieldFocus }
        switch style.variant {
        case .primary: return isHovering ? OnePlusColor.primaryHover : OnePlusColor.primaryFill
        case .destructive: return OnePlusColor.dangerFill
        case .neutral: return isHovering ? OnePlusColor.raisedHover : OnePlusColor.raised
        case .ghost, .icon: return isHovering ? OnePlusColor.raised : .clear
        case .link: return .clear
        }
    }

    private var border: Color {
        if isFocused { return OnePlusColor.focus }
        switch style.variant {
        case .neutral: return OnePlusColor.line
        case .destructive: return OnePlusColor.dangerLine
        default: return .clear
        }
    }
}

/// Paint-only feedback for caller-owned row geometry.
public struct OnePlusInteractionStyle: ButtonStyle {
    let selected: Bool
    let radius: CGFloat
    public init(selected: Bool = false, radius: CGFloat = 5) {
        self.selected = selected
        self.radius = radius
    }
    public func makeBody(configuration: Configuration) -> some View {
        OnePlusInteractionBody(label: configuration.label, pressed: configuration.isPressed, selected: selected, radius: radius)
    }
}

private struct OnePlusInteractionBody<Label: View>: View {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    let label: Label
    let pressed: Bool
    let selected: Bool
    let radius: CGFloat
    var body: some View {
        label
            .background(enabled && pressed ? OnePlusColor.pressed : selected || (enabled && focused) ? OnePlusColor.selection : enabled && hover ? OnePlusColor.raised : .clear,
                        in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(enabled && focused ? OnePlusColor.focus : .clear, lineWidth: 1) }
            .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hover = $0 }
            .animation(OnePlusMotion.animation(reduceMotion: reduceMotion), value: hover || pressed)
            .focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
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
    func onePlusControl(_ tone: OnePlusControlTone = .standard, minWidth: CGFloat? = nil,
                        minHeight: CGFloat = OnePlusMetrics.controlHeight,
                        horizontalPadding: CGFloat = OnePlusMetrics.controlHorizontalPadding) -> some View {
        buttonStyle(OnePlusControlButtonStyle(tone: tone, minWidth: minWidth, minHeight: minHeight, horizontalPadding: horizontalPadding))
    }
}
