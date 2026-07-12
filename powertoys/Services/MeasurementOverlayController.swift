import AppKit

@MainActor
final class MeasurementOverlayController {
    static let shared = MeasurementOverlayController()
    private var panels: [NSPanel] = []

    func begin() {
        cancel()
        panels = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = MeasurementSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
                self?.finish(rect: rect, screen: screen)
            } cancel: { [weak self] in self?.cancel() }
            panel.orderFrontRegardless()
            return panel
        }
    }

    func cancel() {
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    private func finish(rect: CGRect, screen: NSScreen) {
        let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        RulerManager.shared.recordMeasurement(global)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(RulerCopyFormat.plain.render(frame: global), forType: .string)
        cancel()
    }
}

private final class MeasurementSelectionView: NSView {
    private let completion: (CGRect) -> Void
    private let cancellation: () -> Void
    private var start: CGPoint?
    private var selection = CGRect.zero
    private var pointer: CGPoint?
    private var tracking: NSTrackingArea?

    init(frame: CGRect, completion: @escaping (CGRect) -> Void, cancel: @escaping () -> Void) {
        self.completion = completion
        cancellation = cancel
        super.init(frame: frame)
        window?.acceptsMouseMovedEvents = true
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()
        if let pointer {
            NSColor.white.withAlphaComponent(0.45).setStroke()
            let guides = NSBezierPath()
            guides.setLineDash([4, 4], count: 2, phase: 0)
            guides.move(to: CGPoint(x: bounds.minX, y: pointer.y))
            guides.line(to: CGPoint(x: bounds.maxX, y: pointer.y))
            guides.move(to: CGPoint(x: pointer.x, y: bounds.minY))
            guides.line(to: CGPoint(x: pointer.x, y: bounds.maxY))
            guides.stroke()
        }
        guard !selection.isEmpty else { return }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 1
        path.stroke()
        let label = RulerCopyFormat.plain.render(frame: selection)
        label.draw(at: CGPoint(x: selection.minX + 6, y: selection.maxY + 6), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ])
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if selection.width >= 2, selection.height >= 2 { completion(selection) }
        else { cancellation() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancellation() } else { super.keyDown(with: event) }
    }
}
