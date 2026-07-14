import AppKit
import SwiftUI

enum UtilityLayout {
    static let horizontalInset: CGFloat = 20
    static let compactTitlebarHeight: CGFloat = 32
    static let compactTitlebarTrafficLightInset: CGFloat = 84
    static let headerVerticalInset: CGFloat = 10
    static let contentTopInset: CGFloat = 16
    static let contentBottomInset: CGFloat = 20
    static let floatingButtonEdgeInset: CGFloat = 8
    static let floatingButtonContentInset: CGFloat = 52
    static let sectionSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 10
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
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.controlSize = .mini
            scrollView.horizontalScroller?.controlSize = .mini
        }
    }
}
