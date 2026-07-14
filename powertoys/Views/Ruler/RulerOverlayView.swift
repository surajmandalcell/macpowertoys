import AppKit

final class RulerOverlayView: NSView {
    private var state: RulerState
    private var style: RulerStyle
    private weak var manager: RulerManager?
    private var startLocation: CGPoint?
    private var startFrame: CGRect?
    private var resizesWidth = false
    private var resizesHeight = false
    private var cursorLocation: CGPoint?
    private var tracking: NSTrackingArea?

    @MainActor
    init(state: RulerState, style: RulerStyle, manager: RulerManager) {
        self.state = state
        self.style = style
        self.manager = manager
        super.init(frame: CGRect(origin: .zero, size: state.frame.size))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(state.orientation.title) Ruler")
        setAccessibilityIdentifier("ruler.\(state.orientation.rawValue).overlay")
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
        style.color.withAlphaComponent(style.backgroundOpacity).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 0.75
        path.stroke()
        drawHorizontalTicksIfNeeded()
        drawVerticalTicksIfNeeded()
        drawCursorMarker()
        drawResizeHandle()
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        startLocation = NSEvent.mouseLocation
        startFrame = window?.frame
        let local = convert(event.locationInWindow, from: nil)
        switch state.orientation {
        case .horizontal:
            resizesWidth = local.x > bounds.maxX - 18
            resizesHeight = false
        case .vertical:
            resizesWidth = false
            resizesHeight = local.y < bounds.minY + 18
        case .joined:
            resizesWidth = local.x > bounds.maxX - 18
            resizesHeight = local.y < bounds.minY + 18
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation, let startFrame else { return }
        let now = NSEvent.mouseLocation
        let delta = CGPoint(x: now.x - startLocation.x, y: now.y - startLocation.y)
        var frame = startFrame
        if resizesWidth || resizesHeight {
            if resizesWidth { frame.size.width = max(RulerGeometry.thickness, startFrame.width + delta.x) }
            if resizesHeight {
                let maximumY = startFrame.maxY
                frame.size.height = max(RulerGeometry.thickness, startFrame.height - delta.y)
                frame.origin.y = maximumY - frame.height
            }
        } else {
            frame.origin.x += delta.x
            frame.origin.y += delta.y
        }
        let previous = window?.frame.origin ?? frame.origin
        manager?.updateFrame(id: state.id, frame: frame, persistChanges: false)
        if !resizesWidth && !resizesHeight {
            let actual = window?.frame.origin ?? frame.origin
            manager?.moveGroup(
                containing: state.id,
                delta: CGPoint(x: actual.x - previous.x, y: actual.y - previous.y),
                persistChanges: false
            )
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(item("New Horizontal Ruler", #selector(newHorizontal), "ruler"))
        menu.addItem(item("New Vertical Ruler", #selector(newVertical), "ruler.fill"))
        menu.addItem(item("New Joined Ruler", #selector(newJoined), "square.dashed"))
        menu.addItem(.separator())
        menu.addItem(item("Measure Region", #selector(measureRegion), "viewfinder"))
        menu.addItem(item(
            RulerGuideController.shared.isVisible ? "Hide Crosshair" : "Show Crosshair",
            #selector(toggleCrosshair),
            "scope"
        ))
        menu.addItem(.separator())
        menu.addItem(item("Set Origin at Pointer", #selector(setOrigin), "scope"))
        menu.addItem(item("Reset Ruler", #selector(resetRuler), "arrow.counterclockwise"))
        menu.addItem(item(state.isVisible ? "Hide Ruler" : "Show Ruler", #selector(hideRuler), "eye.slash"))
        menu.addItem(.separator())
        if manager?.isGrouped(state.id) == true {
            menu.addItem(item("Ungroup Rulers", #selector(ungroupRulers), "rectangle.3.group"))
        } else {
            menu.addItem(item("Group Visible Rulers", #selector(groupRulers), "rectangle.3.group.fill"))
        }
        menu.addItem(.separator())
        menu.addItem(item("Ruler Settings…", #selector(openSettings), "gearshape"))
        menu.addItem(item("Remove Ruler", #selector(removeRuler), "trash"))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func item(_ title: String, _ action: Selector, _ symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    @objc private func newHorizontal() { manager?.create(.horizontal) }
    @objc private func newVertical() { manager?.create(.vertical) }
    @objc private func newJoined() { manager?.create(.joined) }
    @objc private func measureRegion() { MeasurementOverlayController.shared.begin() }
    @objc private func toggleCrosshair() { RulerGuideController.shared.toggleCrosshair() }
    @objc private func setOrigin() { manager?.setOriginAtPointer(state.id) }
    @objc private func resetRuler() { manager?.reset(state.id) }
    @objc private func hideRuler() { manager?.hide(state.id) }
    @objc private func groupRulers() { manager?.groupVisible() }
    @objc private func ungroupRulers() { manager?.ungroup(containing: state.id) }
    @objc private func openSettings() { manager?.openSettings() }
    @objc private func removeRuler() { manager?.remove(state.id) }

    private func rulerShape() -> NSBezierPath {
        switch state.orientation {
        case .horizontal, .vertical:
            return NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        case .joined:
            let path = NSBezierPath()
            if state.showsHorizontalArm {
                let y = style.zeroCorner == .topLeft || style.zeroCorner == .topRight
                    ? bounds.height - RulerGeometry.thickness
                    : 0
                path.append(NSBezierPath(rect: NSRect(
                    x: 0.5,
                    y: y + 0.5,
                    width: bounds.width - 1,
                    height: RulerGeometry.thickness - 1
                )))
            }
            if state.showsVerticalArm {
                let x = style.zeroCorner.reversesHorizontal ? bounds.width - RulerGeometry.thickness : 0
                path.append(NSBezierPath(rect: NSRect(
                    x: x + 0.5,
                    y: 0.5,
                    width: RulerGeometry.thickness - 1,
                    height: bounds.height - 1
                )))
            }
            return path
        }
    }

    private func drawHorizontalTicksIfNeeded() {
        guard state.orientation != .vertical, state.orientation != .joined || state.showsHorizontalArm else { return }
        let scale = RulerGeometry.pointsPerUnit(style.unit, screen: window?.screen, calibration: style.calibration(for: window?.screen))
        let ticks = RulerGeometry.ticks(length: bounds.width, pointsPerUnit: scale, reversed: style.zeroCorner.reversesHorizontal)
        let drawsFromTop = state.orientation != .joined || style.zeroCorner == .topLeft || style.zeroCorner == .topRight
        let edge = drawsFromTop ? bounds.maxY : bounds.minY
        let path = NSBezierPath()
        for tick in ticks {
            let length: CGFloat = tick.level == 2 ? 18 : (tick.level == 1 ? 12 : 7)
            path.move(to: CGPoint(x: tick.position, y: edge))
            path.line(to: CGPoint(x: tick.position, y: edge + (drawsFromTop ? -length : length)))
            if tick.level == 2 {
                drawLabel(tick.value, at: CGPoint(x: tick.position + 3, y: edge + (drawsFromTop ? -30 : 20)))
            }
        }
        NSColor.labelColor.withAlphaComponent(0.68).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    private func drawVerticalTicksIfNeeded() {
        guard state.orientation != .horizontal, state.orientation != .joined || state.showsVerticalArm else { return }
        let scale = RulerGeometry.pointsPerUnit(style.unit, screen: window?.screen, calibration: style.calibration(for: window?.screen))
        let ticks = RulerGeometry.ticks(length: bounds.height, pointsPerUnit: scale, reversed: style.zeroCorner.reversesVertical)
        let drawsFromRight = state.orientation == .joined && style.zeroCorner.reversesHorizontal
        let path = NSBezierPath()
        for tick in ticks {
            let length: CGFloat = tick.level == 2 ? 18 : (tick.level == 1 ? 12 : 7)
            let edge = drawsFromRight ? bounds.maxX : bounds.minX
            path.move(to: CGPoint(x: edge, y: tick.position))
            path.line(to: CGPoint(x: edge + (drawsFromRight ? -length : length), y: tick.position))
            if tick.level == 2 {
                let labelX = drawsFromRight ? bounds.maxX - RulerGeometry.thickness + 4 : 20
                drawLabel(tick.value, at: CGPoint(x: labelX, y: tick.position - 6))
            }
        }
        NSColor.labelColor.withAlphaComponent(0.68).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    private func drawLabel(_ value: Double, at point: CGPoint) {
        let text = value.formatted(.number.precision(.fractionLength(0...1)))
        text.draw(at: point, withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.74)
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
            let rightArm = state.orientation == .joined && style.zeroCorner.reversesHorizontal
            path.move(to: CGPoint(
                x: rightArm ? bounds.maxX - RulerGeometry.thickness : bounds.minX,
                y: cursorLocation.y
            ))
            path.line(to: CGPoint(
                x: rightArm ? bounds.maxX : min(RulerGeometry.thickness, bounds.maxX),
                y: cursorLocation.y
            ))
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
            path.lineWidth = 0.75
            path.stroke()
        }
    }
}
