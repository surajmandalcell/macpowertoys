import AppKit
import OnePlusUI
import SwiftUI

enum UtilityLayout {
    static let horizontalInset = OnePlusMetrics.gutter
    static let workspaceActionHeight = OnePlusMetrics.controlHeight
    static let compactTitlebarHeight = OnePlusMetrics.appletTitlebar
    static let hiddenTitlebarBottomSurplus = NSWindow.frameRect(
        forContentRect: .zero,
        styleMask: .titled
    ).height
}

enum UtilityMotion {
    static let standardDuration = OnePlusMotion.content
    static let interactionDuration = OnePlusMotion.hover

    static func animation(
        reduceMotion: Bool,
        duration: Double = standardDuration
    ) -> Animation? {
        OnePlusMotion.animation(reduceMotion: reduceMotion, duration: duration)
    }
}

struct QuietDivider: View {
    var body: some View {
        OnePlusColor.lineSoft.frame(height: 1).accessibilityHidden(true)
    }
}

struct UtilityInteractionButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        OnePlusInteractionStyle(radius: cornerRadius).makeBody(configuration: configuration)
    }
}

extension View {
    func utilitySectionHeader() -> some View {
        onePlusText(.captionUpper)
    }

    func utilitySectionCard() -> some View {
        OnePlusCard { self.padding(OnePlusMetrics.cardPadding) }
    }

    func thinScrollIndicators() -> some View {
        onePlusScrollIndicators()
    }

    func utilityAnimation<Value: Equatable>(
        value: Value,
        duration: Double = UtilityMotion.standardDuration
    ) -> some View {
        modifier(UtilityAnimationModifier(value: value, duration: duration))
    }

    func utilityContentTransition<Value: Hashable>(value _: Value) -> some View {
        self
    }

    func utilityMotionPolicy() -> some View {
        modifier(UtilityMotionPolicyModifier())
    }
}

private struct UtilityMotionPolicyModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onePlusFocusPolicy().transaction { transaction in
            guard reduceMotion else { return }
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

private struct UtilityAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Value
    let duration: Double

    func body(content: Content) -> some View {
        content.animation(
            UtilityMotion.animation(reduceMotion: reduceMotion, duration: duration),
            value: value
        )
    }
}
