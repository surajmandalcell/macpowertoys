import AppKit
import SwiftUI
import OnePlusUI

// The owner's v15 "Depth" control look for the AppKit Ruler windows: recessed tracks, raised caps with a fine
// top highlight. Only drawing changes here; values, keyboard, and accessibility stay native.
// shortcut: AppKit Depth drawing lives here because OnePlusUI 1.2.1 has SwiftUI Depth controls only; move it there when it adds AppKit ones.
enum RulerDepth {
    private static func color(_ name: String, light: UInt32, lightAlpha: Double = 1,
                              dark: UInt32, darkAlpha: Double = 1) -> NSColor {
        OnePlusLinearColor.dynamic("RulerDepth.\(name)", light: light, lightAlpha: lightAlpha,
                                   dark: dark, darkAlpha: darkAlpha)
    }

    static let recess = NSColor(OnePlusLinearColor.depthRecess)
    static let recessShadow = NSColor(OnePlusLinearColor.depthRecessShade)
    static let recessRing = NSColor(OnePlusLinearColor.depthRecessRing)
    static let recessLip = NSColor(OnePlusLinearColor.depthRecessLip)
    static let capTop = NSColor(OnePlusLinearColor.depthCapTop)
    static let capBottom = NSColor(OnePlusLinearColor.depthCapBottom)
    static let capPressedTop = NSColor(OnePlusLinearColor.depthCapPressedTop)
    static let capPressedBottom = NSColor(OnePlusLinearColor.depthCapPressedBottom)
    static let capRing = NSColor(OnePlusLinearColor.depthCapRing)
    static let capDrop = NSColor(OnePlusLinearColor.depthCapShadow)
    static let capAmbient = NSColor(OnePlusLinearColor.depthCapGlow)
    static let capHighlight = NSColor(OnePlusLinearColor.depthCapHighlight)
    static let rodTop = NSColor(OnePlusLinearColor.depthRodTop)
    static let rodBottom = NSColor(OnePlusLinearColor.depthRodBottom)
    static let rodHighlight = NSColor(OnePlusLinearColor.depthRodHighlight)
    static let ink = NSColor(OnePlusLinearColor.ink)
    static let secondary = NSColor(OnePlusLinearColor.secondary)
    static let ring = color("ring", light: 0x000000, lightAlpha: 0.3, dark: 0xFFFFFF, darkAlpha: 0.36)

    static let duration: TimeInterval = 0.14
    static let curve = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)

    static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// A track cut into the surface: lip below, inner shadow at the top, fine ring.
    static func drawRecess(_ rect: NSRect, radius: CGFloat, fill: (NSBezierPath) -> Void = { path in recess.setFill(); path.fill() }) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        recessLip.setFill()
        NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: belowOffset(1)), xRadius: radius, yRadius: radius).fill()
        fill(path)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = recessShadow
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.set()
        let outside = NSBezierPath(rect: rect.insetBy(dx: -8, dy: -8))
        outside.append(path.reversed)
        NSColor.black.setFill()
        outside.fill()
        NSGraphicsContext.restoreGraphicsState()
        recessRing.setStroke()
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        ring.lineWidth = 0.5
        ring.stroke()
    }

    /// A raised cap: soft drop shadows, gradient body, bright top edge, fine ring.
    static func drawCap(_ rect: NSRect, radius: CGFloat, pressed: Bool = false) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        for (color, offset, blur) in [(capAmbient, CGFloat(2), CGFloat(6)), (capDrop, 1, 2)] {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = color
            shadow.shadowOffset = NSSize(width: 0, height: -offset)
            shadow.shadowBlurRadius = blur
            shadow.set()
            capBottom.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        drawVerticalGradient(in: rect, radius: radius, top: pressed ? capPressedTop : capTop,
                             bottom: pressed ? capPressedBottom : capBottom, highlight: capHighlight)
        capRing.setStroke()
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -0.25, dy: -0.25), xRadius: radius + 0.25, yRadius: radius + 0.25)
        ring.lineWidth = 0.5
        ring.stroke()
    }

    static func drawRod(_ rect: NSRect, radius: CGFloat) {
        drawVerticalGradient(in: rect, radius: radius, top: rodTop, bottom: rodBottom, highlight: rodHighlight)
    }

    /// Fills `rect` top to bottom and keeps a 1 pt highlight line along its top edge.
    private static func drawVerticalGradient(in rect: NSRect, radius: CGFloat, top: NSColor, bottom: NSColor, highlight: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        highlight.setFill()
        path.fill()
        let body = rect.offsetBy(dx: 0, dy: belowOffset(1))
        NSGradient(starting: top, ending: bottom)?.draw(
            in: NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius), angle: isFlipped ? 90 : -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static var isFlipped: Bool { NSGraphicsContext.current?.isFlipped ?? false }
    /// One physical pixel, so highlights and lips stay crisp at every backing scale.
    private static var hairline: CGFloat {
        let scale = NSGraphicsContext.current.map { abs($0.cgContext.userSpaceToDeviceSpaceTransform.a) } ?? 1
        return 1 / max(scale, 1)
    }
    private static func belowOffset(_ points: CGFloat) -> CGFloat {
        let offset = points * hairline
        return isFlipped ? offset : -offset
    }

    static func run(_ changes: @escaping () -> Void, animated: Bool) {
        guard animated, !reducesMotion else { changes(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = curve
            changes()
        }
    }
}

/// Switch: a 30 x 18 recessed track, a dark rod when on, and a 14 pt cap that slides in 140 ms.
final class RulerDepthSwitch: OnePlusNativeSwitchButton {
    @objc dynamic var knobProgress: CGFloat = 0 { didSet { needsDisplay = true } }

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "knobProgress" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        knobProgress = state == .on ? 1 : 0
    }

    override var state: NSControl.StateValue {
        didSet { syncKnob() }
    }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        syncKnob()
        return super.sendAction(action, to: target)
    }

    private func syncKnob() {
        let target: CGFloat = state == .on ? 1 : 0
        guard abs(knobProgress - target) > 0.001 else { return }
        guard window?.isVisible == true, !RulerDepth.reducesMotion else { knobProgress = target; return }
        RulerDepth.run({ [weak self] in self?.animator().knobProgress = target }, animated: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha = isEnabled ? 1 : OnePlusMetrics.disabledOpacity
        let track = NSRect(x: bounds.maxX - 30, y: bounds.midY - 9, width: 30, height: 18)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        RulerDepth.drawRecess(track, radius: 9) { path in
            RulerDepth.recess.setFill()
            path.fill()
            if knobProgress > 0 {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                NSGraphicsContext.current?.cgContext.setAlpha(alpha * knobProgress)
                RulerDepth.drawRod(track, radius: 9)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        let knob = NSRect(x: track.minX + 2 + knobProgress * 12, y: track.midY - 7, width: 14, height: 14)
        RulerDepth.drawCap(knob, radius: 7, pressed: cell?.isHighlighted == true)
        NSGraphicsContext.restoreGraphicsState()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: RulerDepth.ink.withAlphaComponent(alpha), .paragraphStyle: paragraph,
        ]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: 0, y: bounds.midY - height / 2,
                                            width: max(0, track.minX - 12), height: height),
                                 withAttributes: attributes)
        if window?.firstResponder === self, OnePlusFocusPolicy.shared.showsFocus {
            RulerDepth.ring.setStroke()
            let ring = NSBezierPath(roundedRect: track.insetBy(dx: -2, dy: -2), xRadius: 11, yRadius: 11)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

/// Slider: a 6 pt recessed track, a rod fill, and a 16 pt round cap. Tick marks keep snapping but are not drawn.
final class RulerDepthSliderCell: NSSliderCell {
    private static let knobSize: CGFloat = 16
    private static let trackHeight: CGFloat = 6

    private var fraction: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat((doubleValue - minValue) / (maxValue - minValue))
    }

    private func trackRect(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.minX, y: bounds.midY - Self.trackHeight / 2, width: bounds.width, height: Self.trackHeight)
    }

    private var controlBounds: NSRect { controlView?.bounds ?? .zero }

    override var knobThickness: CGFloat { Self.knobSize }

    override func barRect(flipped: Bool) -> NSRect { trackRect(in: controlBounds) }

    override func knobRect(flipped: Bool) -> NSRect {
        let bounds = controlBounds
        return NSRect(x: bounds.minX + (bounds.width - Self.knobSize) * fraction,
                      y: bounds.midY - Self.knobSize / 2, width: Self.knobSize, height: Self.knobSize)
    }

    override func drawTickMarks() {}

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = trackRect(in: controlBounds)
        let radius = Self.trackHeight / 2
        let alpha = isEnabled ? 1 : OnePlusMetrics.disabledOpacity
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        RulerDepth.drawRecess(track, radius: radius) { path in
            RulerDepth.recess.setFill()
            path.fill()
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let fill = NSRect(x: track.minX, y: track.minY,
                              width: Self.knobSize / 2 + (track.width - Self.knobSize) * self.fraction, height: track.height)
            RulerDepth.drawRod(fill, radius: 0)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let knob = self.knobRect(flipped: controlView?.isFlipped ?? false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(isEnabled ? 1 : OnePlusMetrics.disabledOpacity)
        RulerDepth.drawCap(knob, radius: Self.knobSize / 2, pressed: isHighlighted)
        if controlView?.window?.firstResponder === controlView, OnePlusFocusPolicy.shared.showsFocus {
            RulerDepth.ring.setStroke()
            let ring = NSBezierPath(ovalIn: knob.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 2
            ring.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Segmented control: a recessed track with 2 pt padding and a raised thumb that slides in 140 ms.
final class RulerDepthSegmentedControl: NSSegmentedControl {
    @objc dynamic var thumbPosition: CGFloat = 0 { didSet { needsDisplay = true } }

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "thumbPosition" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        focusRingType = .none
        thumbPosition = CGFloat(max(selectedSegment, 0))
    }

    override func draw(_ dirtyRect: NSRect) {
        cell?.draw(withFrame: bounds, in: self)
    }

    override var selectedSegment: Int {
        didSet { syncThumb() }
    }

    override func setSelected(_ selected: Bool, forSegment segment: Int) {
        super.setSelected(selected, forSegment: segment)
        syncThumb()
    }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        syncThumb()
        return super.sendAction(action, to: target)
    }

    private func syncThumb() {
        let target = CGFloat(max(selectedSegment, 0))
        guard abs(thumbPosition - target) > 0.001 else { return }
        guard window?.isVisible == true, !RulerDepth.reducesMotion else { thumbPosition = target; return }
        RulerDepth.run({ [weak self] in self?.animator().thumbPosition = target }, animated: true)
    }
}

final class RulerDepthSegmentedCell: NSSegmentedCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let bounds = controlView.bounds
        let alpha = isEnabled ? 1 : OnePlusMetrics.disabledOpacity
        let count = max(segmentCount, 1)
        let segmentWidth = (bounds.width - 4) / CGFloat(count)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        RulerDepth.drawRecess(bounds, radius: 7)
        let position = (controlView as? RulerDepthSegmentedControl)?.thumbPosition ?? CGFloat(max(selectedSegment, 0))
        if selectedSegment >= 0 {
            let thumb = NSRect(x: bounds.minX + 2 + position * segmentWidth, y: bounds.minY + 2,
                               width: segmentWidth, height: bounds.height - 4)
            RulerDepth.drawCap(thumb, radius: 5)
            if controlView.window?.firstResponder === controlView, OnePlusFocusPolicy.shared.showsFocus {
                RulerDepth.ring.setStroke()
                let ring = NSBezierPath(roundedRect: thumb.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2
                ring.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        for segment in 0..<segmentCount {
            let selected = segment == selectedSegment
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular),
                .foregroundColor: (selected ? RulerDepth.ink : RulerDepth.secondary).withAlphaComponent(alpha),
            ]
            let label = (self.label(forSegment: segment) ?? "") as NSString
            let size = label.size(withAttributes: attributes)
            let cell = NSRect(x: bounds.minX + 2 + CGFloat(segment) * segmentWidth, y: bounds.minY,
                              width: segmentWidth, height: bounds.height)
            label.draw(at: NSPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2), withAttributes: attributes)
        }
    }
}

/// Stepper field: a recessed 24 pt field with raised minus and plus caps around the value. The text stays a native
/// editable NSTextField (formatter, field editor, undo); Up and Down arrows and the caps step by 1.
final class RulerDepthStepperField: NSTextField {
    private static let cap: CGFloat = 20
    private static let inset: CGFloat = 2
    private var pressedCap: Int?

    override func awakeFromNib() {
        super.awakeFromNib()
        focusRingType = .none
    }

    private func capRect(_ index: Int) -> NSRect {
        let x = index < 0 ? bounds.minX + Self.inset : bounds.maxX - Self.inset - Self.cap
        return NSRect(x: x, y: bounds.midY - Self.cap / 2, width: Self.cap, height: Self.cap)
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha = isEnabled ? 1 : OnePlusMetrics.disabledOpacity
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        RulerDepth.drawRecess(bounds, radius: 6)
        for index in [-1, 1] {
            let rect = capRect(index)
            RulerDepth.drawCap(rect, radius: 4, pressed: pressedCap == index)
            RulerDepth.ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.midX - 4, y: rect.midY - 0.75, width: 8, height: 1.5),
                         xRadius: 0.75, yRadius: 0.75).fill()
            if index > 0 {
                NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.75, y: rect.midY - 4, width: 1.5, height: 8),
                             xRadius: 0.75, yRadius: 0.75).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        super.draw(dirtyRect)
        if currentEditor() != nil, OnePlusFocusPolicy.shared.showsFocus {
            RulerDepth.ring.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isEnabled, let index = [-1, 1].first(where: { capRect($0).contains(point) }) else {
            super.mouseDown(with: event)
            return
        }
        pressedCap = index
        needsDisplay = true
        step(by: Double(index))
    }

    override func mouseUp(with event: NSEvent) {
        guard pressedCap != nil else { return super.mouseUp(with: event) }
        pressedCap = nil
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)): step(by: 1); return true
        case #selector(NSResponder.moveDown(_:)): step(by: -1); return true
        default: return delegate?.control?(self, textView: textView, doCommandBy: commandSelector) ?? false
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 126: step(by: 1)
        case 125: step(by: -1)
        default: super.keyDown(with: event)
        }
    }

    private func step(by delta: Double) {
        let formatter = formatter as? NumberFormatter
        let lower = formatter?.minimum?.doubleValue ?? 0
        let upper = formatter?.maximum?.doubleValue ?? 4000
        if currentEditor() != nil { validateEditing() }
        let next = min(max((doubleValue + delta).rounded(), lower), upper)
        if let editor = currentEditor() {
            editor.string = formatter?.string(from: NSNumber(value: next)) ?? String(next)
            editor.selectAll(nil)
            validateEditing()
        } else {
            doubleValue = next
        }
        sendAction(action, to: target)
    }

    override func accessibilityPerformIncrement() -> Bool { step(by: 1); return true }
    override func accessibilityPerformDecrement() -> Bool { step(by: -1); return true }
}

/// Keeps the value between the two caps and vertically centered on one text line.
final class RulerDepthStepperCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let font = self.font ?? .systemFont(ofSize: 13)
        let height = ceil(font.ascender - font.descender + font.leading)
        return NSRect(x: rect.minX + 23, y: rect.midY - height / 2, width: max(0, rect.width - 46), height: height)
    }
}
