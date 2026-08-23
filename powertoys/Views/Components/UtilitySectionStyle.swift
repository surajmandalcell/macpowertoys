import AppKit
import SwiftUI

enum UtilityLayout {
    static let horizontalInset: CGFloat = 20
    static let workspaceTitlebarHeight: CGFloat = 40
    static let workspaceTitleLeadingInset: CGFloat = 92
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
}

extension NSScrollView {
    func configureThinScrollIndicators() {
        scrollerStyle = .overlay
        autohidesScrollers = true
        verticalScroller?.controlSize = .mini
        horizontalScroller?.controlSize = .mini
    }
}

private struct ThinScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ThinScrollIndicatorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ThinScrollIndicatorView)?.configureEnclosingScrollView()
    }
}

private final class ThinScrollIndicatorView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureEnclosingScrollView()
    }

    func configureEnclosingScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let scrollView = self?.enclosingScrollView else { return }
            scrollView.configureThinScrollIndicators()
        }
    }
}
