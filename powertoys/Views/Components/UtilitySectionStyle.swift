import AppKit
import OnePlusUI
import SwiftUI

enum UtilityLayout {
    static let horizontalInset = OnePlusMetrics.gutter
    static let compactSidebarWidth = OnePlusWindowCanvas.main.sidebarWidth
    static let launcherCardMinimumWidth: CGFloat = 220
    static let launcherGridSpacing: CGFloat = 16
    static let launcherContentInset: CGFloat = 24
    static let launcherColumnCount = 4
    static let launcherGridColumns = Array(
        repeating: GridItem(.flexible(), spacing: launcherGridSpacing),
        count: launcherColumnCount
    )
    static let launcherContentSize = OnePlusWindowCanvas.main.size
    static let launcherWindowSize = OnePlusWindowCanvas.main.size

    static func launcherGridColumns(for width: CGFloat) -> [GridItem] {
        let available = width - 2 * launcherContentInset + launcherGridSpacing
        let columnWidth = launcherCardMinimumWidth + launcherGridSpacing
        let count = min(launcherColumnCount, max(1, Int(available / columnWidth)))
        return Array(repeating: GridItem(.flexible(), spacing: launcherGridSpacing), count: count)
    }
    static let dataSidebarWidth = OnePlusWindowCanvas.rclone.sidebarWidth
    static let workspaceMinimumContentWidth: CGFloat = 640
    static let workspaceMinimumHeight: CGFloat = 600
    static let netToysMinimumContentSize = OnePlusWindowCanvas.netToys.size
    static let netToysDefaultContentSize = OnePlusWindowCanvas.netToys.size
    static let sidebarRowHeight = OnePlusMetrics.navRowHeight
    static let workspaceTitlebarHeight = OnePlusMetrics.titleRow
    static let workspaceContentTopInset = OnePlusMetrics.titleRow
    static let workspaceActionHeight = OnePlusMetrics.controlHeight
    static let workspaceTitleLeadingInset: CGFloat = 84
    static let workspaceTrafficLightVerticalOffset = OnePlusMetrics.trafficLightVerticalOffset
    static let compactTitlebarHeight: CGFloat = 40
    static let compactTitlebarTopInset: CGFloat = 4
    static let compactTitlebarControlHeight: CGFloat = 24
    static let compactTitlebarControlRadius: CGFloat = 6
    static let compactTitlebarTrafficLightVerticalOffset: CGFloat = 6
    static let compactTitlebarTrafficLightInset = OnePlusMetrics.titleLeadingInset
    static let headerVerticalInset: CGFloat = 10
    static let contentTopInset: CGFloat = 16
    static let contentBottomInset: CGFloat = 20
    static let floatingButtonEdgeInset: CGFloat = 8
    static let floatingButtonContentInset: CGFloat = 52
    static let hiddenTitlebarBottomSurplus = NSWindow.frameRect(
        forContentRect: .zero,
        styleMask: .titled
    ).height
    static let sectionSpacing: CGFloat = 16
    static let cardPadding = OnePlusMetrics.cardPadding
    static let cardRadius = OnePlusMetrics.panelRadius
    static let separatorOpacity: Double = 1
    static let increasedContrastSeparatorOpacity: Double = 1

    static func minimumContentSize(for identifier: String) -> NSSize? {
        OnePlusWindowCanvas.tool(identifier)?.size
    }
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
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        OnePlusColor.lineSoft.frame(height: 1).accessibilityHidden(true)
    }
}

struct UtilityInteractionButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8

    static func highlightOpacity(
        isEnabled: Bool,
        isHovering: Bool,
        isPressed: Bool
    ) -> Double {
        guard isEnabled else { return 0 }
        if isPressed { return 0.1 }
        if isHovering { return 0.06 }
        return 0
    }

    func makeBody(configuration: Configuration) -> some View {
        OnePlusInteractionStyle(radius: cornerRadius).makeBody(configuration: configuration)
    }

}

class UtilityMaterialView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureMaterial()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureMaterial()
    }

    private func configureMaterial() {
        wantsLayer = true
        updateLayer()
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor(OnePlusColor.sidebar).cgColor }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
}

final class UtilitySectionCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        updateLayer()
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor(OnePlusColor.panel).cgColor
            layer?.borderColor = NSColor(OnePlusColor.line).cgColor
            layer?.borderWidth = 1
            layer?.cornerRadius = UtilityLayout.cardRadius
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

extension View {
    func utilityActionLabel() -> some View {
        padding(.horizontal, OnePlusMetrics.controlHorizontalPadding)
            .frame(minHeight: OnePlusMetrics.controlHeight)
    }

    func utilitySectionHeader() -> some View {
        onePlusText(.captionUpper)
    }

    func utilitySectionCard() -> some View {
        OnePlusCard { self.padding(OnePlusMetrics.cardPadding) }
    }

    func utilityWindowBackground() -> some View {
        background(OnePlusColor.window.ignoresSafeArea())
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

    func utilityContentTransition<Value: Hashable>(value: Value) -> some View {
        modifier(UtilityContentTransitionModifier(value: value))
    }

    func utilityMotionPolicy() -> some View {
        modifier(UtilityMotionPolicyModifier())
    }
}

private struct UtilityMotionPolicyModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled).transaction { transaction in
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

private struct UtilityContentTransitionModifier<Value: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Value

    func body(content: Content) -> some View {
        content
            .id(value)
            .transition(reduceMotion ? .identity : .opacity)
            .animation(UtilityMotion.animation(reduceMotion: reduceMotion), value: value)
    }
}

extension NSScrollView {
    func configureThinScrollIndicators() {
        configureOnePlusScrollIndicators()
    }
}

typealias ThinOverlayScroller = OnePlusOverlayScroller
