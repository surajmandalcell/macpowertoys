import AppKit

final class RulerOverlayView: NSView {
    private var state: RulerState
    private var style: RulerStyle
    private weak var manager: RulerManager?
    private var startLocation: CGPoint?
    private var startFrame: CGRect?
    private var isResizing = false
    private var cursorLocation: CGPoint?
    private var tracking: NSTrackingArea?

    @MainActor
    init(state: RulerState, style: RulerStyle, manager: RulerManager) {
        self.state = state
        self.style = style
        self.manager = manager
        super.init(frame: CGRect(origin: .zero, size: state.frame.size))
        wantsLayer = true
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) { nil }

    func update(state: RulerState, style: RulerStyle) {
        self.state = state
        self.style = style
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = rulerShape()
        style.color.setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.84).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawHorizontalTicksIfNeeded()
        drawVerticalTicksIfNeeded()
        drawCursorMarker()
        drawResizeHandle()
    }

    override func mouseDown(with event: NSEvent) {
        startLocation = NSEvent.mouseLocation
        startFrame = window?.frame
        let local = convert(event.locationInWindow, from: nil)
        isResizing = switch state.orientation {
        case .horizontal: local.x > bounds.maxX - 18
        case .vertical: local.y < bounds.minY + 18
        case .joined: local.x > bounds.maxX - 18 || local.y < bounds.minY + 18
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation, let startFrame else { return }
        let now = NSEvent.mouseLocation
        let delta = CGPoint(x: now.x - startLocation.x, y: now.y - startLocation.y)
        var frame = startFrame
        if isResizing {
            switch state.orientation {
            case .horizontal:
                frame.size.width = max(54, startFrame.width + delta.x)
            case .vertical:
                frame.size.height = max(54, startFrame.height + delta.y)
            case .joined:
                frame.size.width = max(54, startFrame.width + delta.x)
                frame.size.height = max(54, startFrame.height + delta.y)
            }
        } else {
            frame.origin.x += delta.x
            frame.origin.y += delta.y
        }
        let previous = window?.frame.origin ?? frame.origin
        manager?.updateFrame(id: state.id, frame: frame)
        if !isResizing {
            let actual = window?.frame.origin ?? frame.origin
            manager?.moveGroup(containing: state.id, delta: CGPoint(x: actual.x - previous.x, y: actual.y - previous.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        startLocation = nil
        startFrame = nil
        manager?.updateScreen(id: state.id, screen: window?.screen)
    }

    override func mouseMoved(with event: NSEvent) {
        cursorLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        cursorLocation = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Set Origin at Pointer", action: #selector(setOrigin), keyEquivalent: "")
        menu.addItem(withTitle: "Reset Ruler", action: #selector(resetRuler), keyEquivalent: "")
        menu.addItem(withTitle: state.isVisible ? "Hide Ruler" : "Show Ruler", action: #selector(hideRuler), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove Ruler", action: #selector(removeRuler), keyEquivalent: "")
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func setOrigin() { manager?.setOriginAtPointer(state.id) }
    @objc private func resetRuler() { manager?.reset(state.id) }
    @objc private func hideRuler() { manager?.hide(state.id) }
    @objc private func removeRuler() { manager?.remove(state.id) }

    private func rulerShape() -> NSBezierPath {
        switch state.orientation {
        case .horizontal, .vertical:
            return NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        case .joined:
            let path = NSBezierPath()
            if state.showsHorizontalArm {
                path.appendRoundedRect(NSRect(x: 0, y: bounds.height - 54, width: bounds.width, height: 54), xRadius: 6, yRadius: 6)
            }
            if state.showsVerticalArm {
                path.appendRoundedRect(NSRect(x: 0, y: 0, width: 54, height: bounds.height), xRadius: 6, yRadius: 6)
            }
            return path
        }
    }

    private func drawHorizontalTicksIfNeeded() {
        guard state.orientation != .vertical, state.orientation != .joined || state.showsHorizontalArm else { return }
        let scale = RulerGeometry.pointsPerUnit(style.unit, screen: window?.screen, calibration: style.calibration(for: window?.screen))
        let ticks = RulerGeometry.ticks(length: bounds.width, pointsPerUnit: scale, reversed: style.zeroCorner.reversesHorizontal)
        let top = state.orientation == .joined ? bounds.maxY : bounds.maxY
        for tick in ticks {
            let length: CGFloat = tick.level == 2 ? 20 : (tick.level == 1 ? 13 : 8)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: tick.position, y: top))
            path.line(to: CGPoint(x: tick.position, y: top - length))
            path.stroke()
            if tick.level == 2 { drawLabel(tick.value, at: CGPoint(x: tick.position + 3, y: top - 34)) }
        }
    }

    private func drawVerticalTicksIfNeeded() {
        guard state.orientation != .horizontal, state.orientation != .joined || state.showsVerticalArm else { return }
        let scale = RulerGeometry.pointsPerUnit(style.unit, screen: window?.screen, calibration: style.calibration(for: window?.screen))
        let ticks = RulerGeometry.ticks(length: bounds.height, pointsPerUnit: scale, reversed: style.zeroCorner.reversesVertical)
        for tick in ticks {
            let length: CGFloat = tick.level == 2 ? 20 : (tick.level == 1 ? 13 : 8)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: tick.position))
            path.line(to: CGPoint(x: length, y: tick.position))
            path.stroke()
            if tick.level == 2 { drawLabel(tick.value, at: CGPoint(x: 22, y: tick.position - 6)) }
        }
    }

    private func drawLabel(_ value: Double, at point: CGPoint) {
        let text = value.formatted(.number.precision(.fractionLength(0...1)))
        text.draw(at: point, withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.82)
        ])
    }

    private func drawCursorMarker() {
        guard let cursorLocation else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath()
        if state.orientation != .vertical {
            path.move(to: CGPoint(x: cursorLocation.x, y: bounds.minY))
            path.line(to: CGPoint(x: cursorLocation.x, y: bounds.maxY))
        }
        if state.orientation != .horizontal {
            path.move(to: CGPoint(x: bounds.minX, y: cursorLocation.y))
            path.line(to: CGPoint(x: min(54, bounds.maxX), y: cursorLocation.y))
        }
        path.lineWidth = 1
        path.stroke()
    }

    private func drawResizeHandle() {
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        for offset in stride(from: 5.0, through: 13.0, by: 4.0) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: bounds.maxX - offset, y: bounds.minY + 3))
            path.line(to: CGPoint(x: bounds.maxX - 3, y: bounds.minY + offset))
            path.stroke()
        }
    }
}
