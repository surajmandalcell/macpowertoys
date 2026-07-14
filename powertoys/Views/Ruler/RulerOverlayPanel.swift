import AppKit

final class RulerOverlayPanel: NSPanel {
    private let rulerView: RulerOverlayView

    @MainActor
    init(state: RulerState, manager: RulerManager) {
        rulerView = RulerOverlayView(state: state, style: manager.style, manager: manager)
        super.init(
            contentRect: state.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        identifier = NSUserInterfaceItemIdentifier("ruler.\(state.id.uuidString)")
        title = "\(state.orientation.title) Ruler"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = manager.style.hasShadow
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = rulerView
        apply(state: state, style: manager.style)
    }

    @MainActor
    func apply(state: RulerState, style: RulerStyle) {
        level = style.floats ? .floating : .normal
        alphaValue = 1
        hasShadow = style.hasShadow
        rulerView.update(state: state, style: style)
        if frame != state.frame { setFrame(state.frame, display: true) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
