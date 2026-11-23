import AppKit
import SwiftUI
import OnePlusUI

// The owner's v15 "Quiet Raised" control look for the AppKit Ruler windows, drawn 1:1 with the OnePlusUI SwiftUI
// controls: quiet sunken tracks, one solid knob with one soft shadow, coral only for "on". Only drawing changes here;
// values, keyboard, and accessibility stay native.
// shortcut: AppKit Quiet Raised drawing lives here because OnePlusUI 1.3.0 has SwiftUI controls only; move it there when it adds AppKit ones.
enum RulerQuietRaised {
    static let track = NSColor(OnePlusLinearColor.quietTrack)
    static let trackLine = NSColor(OnePlusLinearColor.quietTrackLine)
    static let trackShade = NSColor(OnePlusLinearColor.quietTrackShade)
    static let field = NSColor(OnePlusLinearColor.quietField)
    static let fieldLine = NSColor(OnePlusLinearColor.quietFieldLine)
    static let knob = NSColor(OnePlusLinearColor.quietKnob)
    static let knobOn = NSColor(OnePlusLinearColor.quietKnobOn)
    static let knobPressed = NSColor(OnePlusLinearColor.quietKnobPressed)
    static let knobLine = NSColor(OnePlusLinearColor.quietKnobLine)
    static let knobShadow = NSColor(OnePlusLinearColor.quietKnobShadow)
    static let fillTrack = NSColor(OnePlusLinearColor.fillTrack)
    static let fillThumb = NSColor(OnePlusLinearColor.fillThumb)
    static let on = NSColor(OnePlusLinearColor.accent)
    static let pressed = NSColor(OnePlusLinearColor.pressed)
    static let ink = NSColor(OnePlusLinearColor.ink)
    static let secondary = NSColor(OnePlusLinearColor.appletSecondary)
    static let label = NSColor(OnePlusLinearColor.secondary)

    /// The menu panel's control well, as `OnePlusLinearSegmented` and `OnePlusLinearStepper` draw it on a page:
    /// a flat `fillTrack` well and flat `fillThumb` parts 2 pt inside it.
    static let wellInset = look.segmentInset
    static var innerRadius: CGFloat { look.radius - wellInset }

    static func fill(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    static let focus = NSColor(OnePlusLinearColor.hover)

    /// The look's sizes, equal to `OnePlusLinearControlLook.quietRaised`.
    static let look = OnePlusLinearControlLook.quietRaised

    static var reducesMotion: Bool { OnePlusMotion.reducesMotion }

    /// A control-height rect centered vertically in `bounds`.
    static func controlRect(in bounds: NSRect, width: CGFloat? = nil, trailing: Bool = false) -> NSRect {
        let width = width ?? bounds.width
        return NSRect(x: trailing ? bounds.maxX - width : bounds.minX, y: (bounds.midY - look.height / 2).rounded(),
                      width: width, height: look.height)
    }

    /// A sunken track or field: the fill, a soft 1 pt inner top shade, and a 1 physical pixel inner line.
    static func drawWell(_ rect: NSRect, radius: CGFloat, fill: NSColor = track, line: NSColor = trackLine) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = trackShade
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 2
        shadow.set()
        let outside = NSBezierPath(rect: rect.insetBy(dx: -8, dy: -8))
        outside.append(path.reversed)
        NSColor.black.setFill()
        outside.fill()
        NSGraphicsContext.restoreGraphicsState()
        strokeInside(rect, radius: radius, color: line)
    }

    /// A knob or segment thumb: one solid part with a 1 physical pixel line and one soft contact shadow.
    static func drawCap(_ rect: NSRect, radius: CGFloat, fill: NSColor, line: NSColor = knobLine) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = knobShadow
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 2
        shadow.set()
        fill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        strokeInside(rect, radius: radius, color: line)
    }

    /// The subtle keyboard focus fill over a control (never a ring), shown only under the shared focus policy.
    static func drawFocus(_ rect: NSRect, radius: CGFloat) {
        focus.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// An SF Symbol at `pointSize` and `weight` in `color`, centered on `center`.
    static func drawSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor, center: NSPoint) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: NSRect(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded(),
                              width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func strokeInside(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        let inset = hairline / 2
        let line = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: radius - inset, yRadius: radius - inset)
        line.lineWidth = hairline
        color.setStroke()
        line.stroke()
    }

    /// One physical pixel, so lines stay crisp at every backing scale.
    static var hairline: CGFloat {
        let scale = NSGraphicsContext.current.map { abs($0.cgContext.userSpaceToDeviceSpaceTransform.a) } ?? 1
        return 1 / max(scale, 1)
    }

    static func run(_ changes: @escaping () -> Void, animated: Bool, duration: TimeInterval = OnePlusMotion.knob) {
        guard animated, !reducesMotion else { changes(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = OnePlusMotion.easeOutTiming
            changes()
        }
    }
}

/// Switch: a 32 x 18 sunken track, the accent when on, and a 14 pt knob that slides in 140 ms.
final class RulerQuietRaisedSwitch: OnePlusNativeSwitchButton {
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
        guard window?.isVisible == true, !RulerQuietRaised.reducesMotion else { knobProgress = target; return }
        RulerQuietRaised.run({ [weak self] in self?.animator().knobProgress = target }, animated: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        let look = RulerQuietRaised.look
        let alpha = isEnabled ? 1 : OnePlusMetrics.disabledOpacity
        let size = look.switchSize
        let track = NSRect(x: bounds.maxX - size.width, y: (bounds.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        let radius = size.height / 2
        let inset = (size.height - look.switchKnob) / 2
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        RulerQuietRaised.drawWell(track, radius: radius)
        if knobProgress > 0 {
            RulerQuietRaised.on.withAlphaComponent(knobProgress).setFill()
            NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        }
        let travel = size.width - size.height
        let knob = NSRect(x: track.minX + inset + knobProgress * travel, y: track.minY + inset, width: look.switchKnob, height: look.switchKnob)
        let fill = cell?.isHighlighted == true ? RulerQuietRaised.knobPressed : knobProgress > 0.5 ? RulerQuietRaised.knobOn : RulerQuietRaised.knob
        RulerQuietRaised.drawCap(knob, radius: look.switchKnob / 2, fill: fill)
        if window?.firstResponder === self, OnePlusFocusPolicy.shared.showsFocus {
            RulerQuietRaised.drawFocus(track, radius: radius)
        }
        NSGraphicsContext.restoreGraphicsState()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: RulerQuietRaised.ink.withAlphaComponent(alpha), .paragraphStyle: paragraph,
        ]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: 0, y: bounds.midY - height / 2,
                                            width: max(0, track.minX - 12), height: height),
                                 withAttributes: attributes)
    }
}

/// Slider: a 4 pt sunken track, the accent fill, and a 14 pt knob. Tick marks keep snapping but are not drawn.
final class RulerQuietRaisedSliderCell: NSSliderCell {
    private static let knobSize = RulerQuietRaised.look.knob
    private static let trackHeight = RulerQuietRaised.look.sliderTrack

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
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(isEnabled ? 1 : OnePlusMetrics.disabledOpacity)
        RulerQuietRaised.drawWell(track, radius: radius)
        let fill = NSRect(x: track.minX, y: track.minY,
                          width: Self.knobSize / 2 + (track.width - Self.knobSize) * fraction, height: track.height)
        RulerQuietRaised.on.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        if controlView?.window?.firstResponder === controlView, OnePlusFocusPolicy.shared.showsFocus {
            RulerQuietRaised.drawFocus(track, radius: radius)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let knob = self.knobRect(flipped: controlView?.isFlipped ?? false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(isEnabled ? 1 : OnePlusMetrics.disabledOpacity)
        RulerQuietRaised.drawCap(knob, radius: Self.knobSize / 2, fill: isHighlighted ? RulerQuietRaised.knobPressed : RulerQuietRaised.knob)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Segmented control, drawn like `OnePlusLinearSegmented`: a flat `fillTrack` well, one flat `fillThumb` thumb
/// 2 pt inside it that slides in 140 ms, and a `pressed` shade on the hovered segment.
final class RulerQuietRaisedSegmentedControl: NSSegmentedControl {
    @objc dynamic var thumbPosition: CGFloat = 0 { didSet { needsDisplay = true } }
    private(set) var hoveredSegment: Int? { didSet { if hoveredSegment != oldValue { needsDisplay = true } } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let track = RulerQuietRaised.controlRect(in: bounds).insetBy(dx: RulerQuietRaised.wellInset, dy: 0)
        let index = Int((x - track.minX) / (track.width / CGFloat(max(segmentCount, 1))))
        hoveredSegment = (0..<segmentCount).contains(index) && isEnabled ? index : nil
    }

    override func mouseExited(with event: NSEvent) { hoveredSegment = nil }

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
        guard window?.isVisible == true, !RulerQuietRaised.reducesMotion else { thumbPosition = target; return }
        RulerQuietRaised.run({ [weak self] in self?.animator().thumbPosition = target }, animated: true,
                             duration: OnePlusMotion.segment)
    }
}

final class RulerQuietRaisedSegmentedCell: NSSegmentedCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let look = RulerQuietRaised.look
        let track = RulerQuietRaised.controlRect(in: controlView.bounds)
        let alpha = isEnabled ? 1 : OnePlusMetrics.disabledOpacity
        let count = max(segmentCount, 1)
        let inset = RulerQuietRaised.wellInset
        let radius = RulerQuietRaised.innerRadius
        let segmentWidth = (track.width - 2 * inset) / CGFloat(count)
        let segmentRect = { (position: CGFloat) in
            NSRect(x: track.minX + inset + position * segmentWidth, y: track.minY + inset,
                   width: segmentWidth, height: track.height - 2 * inset)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        RulerQuietRaised.fill(track, radius: look.radius, RulerQuietRaised.fillTrack)
        let control = controlView as? RulerQuietRaisedSegmentedControl
        if selectedSegment >= 0 {
            let thumb = segmentRect(control?.thumbPosition ?? CGFloat(selectedSegment))
            RulerQuietRaised.fill(thumb, radius: radius, RulerQuietRaised.fillThumb)
            if isHighlighted { RulerQuietRaised.fill(thumb, radius: radius, RulerQuietRaised.pressed) }
        }
        if let hovered = control?.hoveredSegment, hovered != selectedSegment {
            RulerQuietRaised.fill(segmentRect(CGFloat(hovered)), radius: radius, RulerQuietRaised.pressed)
        }
        if controlView.window?.firstResponder === controlView, OnePlusFocusPolicy.shared.showsFocus {
            RulerQuietRaised.drawFocus(track, radius: look.radius)
        }
        NSGraphicsContext.restoreGraphicsState()
        for segment in 0..<segmentCount {
            let selected = segment == selectedSegment
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: OnePlusLinearMetrics.body, weight: selected ? .medium : .regular),
                .foregroundColor: (selected ? RulerQuietRaised.ink : RulerQuietRaised.label).withAlphaComponent(alpha),
            ]
            let label = self.label(forSegment: segment) ?? ""
            let size = (label as NSString).size(withAttributes: attributes)
            let cell = NSRect(x: track.minX + inset + CGFloat(segment) * segmentWidth, y: track.minY,
                              width: segmentWidth, height: track.height)
            // Lowercase-only labels center their x-height, as in the SwiftUI control.
            let lift = OnePlusLinearSegmented<Int>.opticalOffset(label)
            let y = cell.midY - size.height / 2 + (controlView.isFlipped ? lift : -lift)
            (label as NSString).draw(at: NSPoint(x: cell.midX - size.width / 2, y: y), withAttributes: attributes)
        }
    }
}

/// Stepper field, drawn like `OnePlusLinearStepper`: the value trails on a flat `fillTrack` well and a 16 pt
/// `fillThumb` key on the right holds a chevron up over a chevron down; each half shades on hover and press. The
/// text stays a native editable NSTextField (formatter, field editor, undo); Up and Down arrows and the key step by 1.
final class RulerQuietRaisedStepperField: NSTextField {
    static let keyWidth: CGFloat = 16
    static let valuePadding: CGFloat = 8
    private var pressedHalf: Int?
    private var hoveredHalf: Int? { didSet { if hoveredHalf != oldValue { needsDisplay = true } } }

    override func awakeFromNib() {
        super.awakeFromNib()
        focusRingType = .none
        alignment = .right
    }

    // The well fills the whole frame, so the label's default 2 pt side insets would push it past the row inset.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    private var fieldRect: NSRect { RulerQuietRaised.controlRect(in: bounds) }

    private var keyRect: NSRect {
        let inset = RulerQuietRaised.wellInset
        let field = fieldRect
        return NSRect(x: field.maxX - inset - Self.keyWidth, y: field.minY + inset,
                      width: Self.keyWidth, height: field.height - 2 * inset)
    }

    /// The key half that steps by `delta`: +1 is the top half, -1 the bottom half.
    private func halfRect(_ delta: Int) -> NSRect {
        let key = keyRect
        let top = (delta > 0) == isFlipped
        return NSRect(x: key.minX, y: top ? key.minY : key.midY, width: key.width, height: key.height / 2)
    }

    private func half(at point: NSPoint) -> Int? { [1, -1].first { halfRect($0).contains(point) } }

    override func draw(_ dirtyRect: NSRect) {
        let field = fieldRect
        let key = keyRect
        let radius = RulerQuietRaised.innerRadius
        let alpha = isEnabled ? 1 : OnePlusMetrics.disabledOpacity
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        RulerQuietRaised.fill(field, radius: RulerQuietRaised.look.radius, RulerQuietRaised.fillTrack)
        RulerQuietRaised.fill(key, radius: radius, RulerQuietRaised.fillThumb)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: key, xRadius: radius, yRadius: radius).addClip()
        for delta in [1, -1] where hoveredHalf == delta || pressedHalf == delta {
            RulerQuietRaised.pressed.setFill()
            halfRect(delta).fill()
            if pressedHalf == delta { halfRect(delta).fill() }
        }
        NSGraphicsContext.restoreGraphicsState()
        for (delta, symbol) in [(1, "chevron.up"), (-1, "chevron.down")] {
            let rect = halfRect(delta)
            let lit = hoveredHalf == delta || pressedHalf == delta
            let nudge: CGFloat = (delta > 0) == isFlipped ? 0.5 : -0.5
            RulerQuietRaised.drawSymbol(symbol, pointSize: 7, weight: .bold, color: lit ? RulerQuietRaised.ink : RulerQuietRaised.label,
                                        center: NSPoint(x: rect.midX, y: rect.midY + nudge))
        }
        if currentEditor() != nil, OnePlusFocusPolicy.shared.showsFocus {
            RulerQuietRaised.drawFocus(field, radius: RulerQuietRaised.look.radius)
        }
        NSGraphicsContext.restoreGraphicsState()
        super.draw(dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        hoveredHalf = isEnabled ? half(at: convert(event.locationInWindow, from: nil)) : nil
    }

    override func mouseExited(with event: NSEvent) { hoveredHalf = nil }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let delta = half(at: convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
        pressedHalf = delta
        needsDisplay = true
        step(by: Double(delta))
    }

    override func mouseUp(with event: NSEvent) {
        guard pressedHalf != nil else { return super.mouseUp(with: event) }
        pressedHalf = nil
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

/// Keeps the value left of the key, 8 pt from it, and vertically centered on one text line.
final class RulerQuietRaisedStepperCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let font = self.font ?? .systemFont(ofSize: 13)
        let height = ceil(font.ascender - font.descender + font.leading)
        let pad = RulerQuietRaisedStepperField.valuePadding
        let trailing = RulerQuietRaised.wellInset + RulerQuietRaisedStepperField.keyWidth + pad
        return NSRect(x: rect.minX + pad, y: rect.midY - height / 2, width: max(0, rect.width - pad - trailing), height: height)
    }
}
