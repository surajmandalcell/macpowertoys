import AppKit
import SwiftUI

enum UtilityLayout {
    static let horizontalInset: CGFloat = 20
    static let compactSidebarWidth: CGFloat = 220
    static let dataSidebarWidth: CGFloat = 240
    static let conversationSidebarWidth: CGFloat = 260
    static let sidebarRowHeight: CGFloat = 28
    static let workspaceTitlebarHeight: CGFloat = 40
    static let workspaceContentTopInset: CGFloat = 44
    static let workspaceActionHeight: CGFloat = 24
    static let workspaceTitleLeadingInset: CGFloat = 84
    static let workspaceTrafficLightVerticalOffset: CGFloat = 4
    static let compactTitlebarHeight: CGFloat = 40
    static let compactTitlebarTopInset: CGFloat = 4
    static let compactTitlebarControlHeight: CGFloat = 24
    static let compactTitlebarControlRadius: CGFloat = 6
    static let compactTitlebarTrafficLightVerticalOffset: CGFloat = 6
    static let compactTitlebarTrafficLightInset: CGFloat = 60
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
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 10
    static let separatorOpacity: Double = 0.22
    static let increasedContrastSeparatorOpacity: Double = 0.44
}

enum UtilityMotion {
    static let standardDuration = 0.16

    static func animation(
        reduceMotion: Bool,
        duration: Double = standardDuration
    ) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}

struct QuietDivider: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Divider()
            .opacity(
                contrast == .increased
                    ? UtilityLayout.increasedContrastSeparatorOpacity
                    : UtilityLayout.separatorOpacity
            )
    }
}

final class UtilityMaterialView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureMaterial()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureMaterial()
    }

    private func configureMaterial() {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
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
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
            layer?.cornerRadius = UtilityLayout.cardRadius
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

extension View {
    func utilitySectionHeader() -> some View {
        font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    func utilitySectionCard() -> some View {
        padding(UtilityLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: UtilityLayout.cardRadius))
    }

    func utilityWindowBackground() -> some View {
        background {
            VisualEffectBackground(material: .hudWindow)
                .ignoresSafeArea()
        }
    }

    func thinScrollIndicators() -> some View {
        background(ThinScrollIndicatorConfigurator())
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
        content.transaction { transaction in
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
        if hasVerticalScroller, !(verticalScroller is ThinOverlayScroller) {
            verticalScroller = ThinOverlayScroller()
        }
        if hasHorizontalScroller, !(horizontalScroller is ThinOverlayScroller) {
            horizontalScroller = ThinOverlayScroller()
        }
        scrollerStyle = .overlay
        autohidesScrollers = true
        verticalScroller?.controlSize = .mini
        horizontalScroller?.controlSize = .mini
    }
}

final class ThinOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    static func knobThickness(increasedContrast: Bool) -> CGFloat {
        increasedContrast ? 6 : 4
    }

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return }

        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let thickness = Self.knobThickness(increasedContrast: increasedContrast)
        let isVertical = bounds.height > bounds.width
        let thinKnob = isVertical
            ? NSRect(x: knob.midX - thickness / 2, y: knob.minY, width: thickness, height: knob.height)
            : NSRect(x: knob.minX, y: knob.midY - thickness / 2, width: knob.width, height: thickness)

        (increasedContrast ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
        NSBezierPath(
            roundedRect: thinKnob,
            xRadius: thickness / 2,
            yRadius: thickness / 2
        ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

private struct ThinScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ThinScrollIndicatorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ThinScrollIndicatorView)?.configureScrollIndicators()
    }
}

private final class ThinScrollIndicatorView: NSView {
    private weak var configuredScrollView: NSScrollView?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureScrollIndicators()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScrollIndicators()
    }

    func configureScrollIndicators() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let configuredScrollView, configuredScrollView.window != nil {
                configuredScrollView.configureThinScrollIndicators()
                return
            }
            if let scrollView = enclosingScrollView {
                configuredScrollView = scrollView
                scrollView.configureThinScrollIndicators()
                return
            }

            // SwiftUI hosts a background beside its scroll view, not inside it.
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view.firstDescendantScrollView {
                    configuredScrollView = scrollView
                    scrollView.configureThinScrollIndicators()
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

private extension NSView {
    var firstDescendantScrollView: NSScrollView? {
        for view in subviews {
            if let scrollView = view as? NSScrollView { return scrollView }
            if let scrollView = view.firstDescendantScrollView { return scrollView }
        }
        return nil
    }
}
