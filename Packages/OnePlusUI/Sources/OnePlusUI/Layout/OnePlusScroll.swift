import AppKit
import SwiftUI

public extension View {
    func onePlusScrollIndicators() -> some View { background(OnePlusScrollConfigurator()) }
}

private struct OnePlusScrollConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { OnePlusScrollProbe() }
    func updateNSView(_ view: NSView, context: Context) { (view as? OnePlusScrollProbe)?.configure() }
}

private final class OnePlusScrollProbe: NSView {
    private weak var configured: NSScrollView?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    override func layout() { super.layout(); configure() }

    func configure() {
        if let configured, configured.window != nil { return }
        guard window != nil, !bounds.isEmpty else { return }
        let point = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        var ancestor = superview
        while let view = ancestor {
            if let scroll = find(in: view, point: point) {
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.verticalScroller?.controlSize = .mini
                scroll.horizontalScroller?.controlSize = .mini
                configured = scroll
                return
            }
            ancestor = view.superview
        }
    }
    private func find(in view: NSView, point: NSPoint) -> NSScrollView? {
        for child in view.subviews {
            if let scroll = child as? NSScrollView, !isDescendant(of: scroll),
               scroll.convert(scroll.bounds, to: nil).contains(point) { return scroll }
            if let result = find(in: child, point: point) { return result }
        }
        return nil
    }
}
