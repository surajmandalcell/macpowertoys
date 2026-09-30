import AppKit
import SwiftUI

/// Native XIB surfaces. These retain AppKit controls, target/action, and key loops.
open class OnePlusNativeWindowView: NSView {
    open override func draw(_ dirtyRect: NSRect) {
        NSColor(OnePlusColor.window).setFill()
        bounds.fill()
    }

    open override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { OnePlusNativeForm.style(self) }
    }
}

open class OnePlusNativeCardView: NSView {
    open override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: OnePlusMetrics.panelRadius, yRadius: OnePlusMetrics.panelRadius)
        NSColor(OnePlusColor.panel).setFill()
        path.fill()
        NSColor(OnePlusColor.line).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor public enum OnePlusNativeForm {
    public static func style(_ view: NSView) {
        if let control = view as? NSControl {
            control.font = .systemFont(ofSize: OnePlusTextRole.control.size(for: .regular))
        }
        if let field = view as? NSTextField {
            field.textColor = NSColor(OnePlusColor.ink)
            if field.isEditable { field.backgroundColor = NSColor(OnePlusColor.field) }
            if field is OnePlusNativeCaptionLabel {
                field.font = .systemFont(ofSize: OnePlusTextRole.captionUpper.size(for: .regular), weight: .medium)
                field.textColor = NSColor(OnePlusColor.muted)
            }
        }
        if let slider = view as? NSSlider { slider.trackFillColor = NSColor(OnePlusColor.primaryFill) }
        if let segmented = view as? NSSegmentedControl {
            segmented.selectedSegmentBezelColor = NSColor(OnePlusColor.selectedControl)
        }
        if let button = view as? NSButton {
            button.bezelColor = NSColor(OnePlusColor.raised)
            button.contentTintColor = NSColor(OnePlusColor.controlInk)
        }
        for child in view.subviews { style(child) }
    }
}

open class OnePlusNativeCaptionLabel: NSTextField {}

/// An NSButton keeps native switch semantics and shortcuts with the shared switch drawing.
open class OnePlusNativeSwitchButton: NSButton {
    open override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            focusRingType = .none
            toolTip = title
        }
    }

    open override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: bounds.maxX - 30, y: bounds.midY - 8, width: 30, height: 16)
        let color = cell?.isHighlighted == true ? OnePlusColor.pressed
            : state == .on ? OnePlusColor.primaryFill : OnePlusColor.line
        NSColor(color).withAlphaComponent(isEnabled ? 1 : OnePlusMetrics.disabledOpacity).setFill()
        NSBezierPath(roundedRect: track, xRadius: 8, yRadius: 8).fill()
        let thumb = NSRect(x: state == .on ? track.maxX - 14 : track.minX + 2,
                          y: track.minY + 2, width: 12, height: 12)
        NSColor(state == .on ? OnePlusColor.primaryInk : OnePlusColor.secondary).setFill()
        NSBezierPath(ovalIn: thumb).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: OnePlusTextRole.row.size(for: .regular)),
            .foregroundColor: NSColor(OnePlusColor.ink), .paragraphStyle: paragraph,
        ]
        let titleHeight = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: 0, y: bounds.midY - titleHeight / 2,
                                         width: max(0, track.minX - OnePlusMetrics.actionSpacing),
                                         height: titleHeight), withAttributes: attributes)
        if window?.firstResponder === self, OnePlusFocusPolicy.shared.showsFocus {
            NSColor(OnePlusColor.focus).setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                         xRadius: OnePlusMetrics.controlRadius, yRadius: OnePlusMetrics.controlRadius).stroke()
        }
    }
}

/// Editable numbers plus an AppKit stepper, using the field's existing formatter and action.
open class OnePlusNativeStepperField: NSTextField {
    private let stepper = NSStepper()

    open override var stringValue: String {
        didSet { stepper.doubleValue = boundedValue(doubleValue) }
    }

    open override var doubleValue: Double {
        get { boundedValue(super.doubleValue) }
        set {
            let value = boundedValue(newValue)
            super.doubleValue = value
            stepper.doubleValue = value
        }
    }

    open override var isEnabled: Bool {
        didSet { stepper.isEnabled = isEnabled }
    }

    open override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let focused = currentEditor() != nil || window?.firstResponder === self
        NSColor(focused && OnePlusFocusPolicy.shared.showsFocus ? OnePlusColor.focus : OnePlusColor.line).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                     xRadius: OnePlusMetrics.controlRadius, yRadius: OnePlusMetrics.controlRadius).stroke()
    }

    open override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { configureStepper() }
    }

    private func configureStepper() {
        let replacement = OnePlusNativeNumberCell(textCell: stringValue)
        replacement.isEditable = true
        replacement.isSelectable = true
        replacement.isScrollable = true
        replacement.isBezeled = true
        replacement.bezelStyle = .roundedBezel
        replacement.drawsBackground = true
        cell = replacement
        stepper.controlSize = .mini
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(step(_:))
        addSubview(stepper)
    }

    open override func layout() {
        super.layout()
        stepper.sizeToFit()
        stepper.frame.origin = NSPoint(x: bounds.maxX - stepper.frame.width - 2,
                                      y: bounds.midY - stepper.frame.height / 2)
        let range = finiteRange
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.doubleValue = boundedValue(doubleValue)
        stepper.isEnabled = isEnabled
        stepper.setAccessibilityLabel(accessibilityLabel() ?? "Value")
    }

    private var finiteRange: ClosedRange<Double> {
        let formatter = formatter as? NumberFormatter
        let minimum = formatter?.minimum?.doubleValue ?? 0
        let maximum = formatter?.maximum?.doubleValue ?? 4000
        let lower = minimum.isFinite ? minimum : 0
        let upper = maximum.isFinite ? max(lower, maximum) : max(lower, 4000)
        return lower...upper
    }

    private func boundedValue(_ value: Double) -> Double {
        let range = finiteRange
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    @objc private func step(_ sender: NSStepper) {
        doubleValue = sender.doubleValue
        sendAction(action, to: target)
    }
}

private final class OnePlusNativeNumberCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var result = super.drawingRect(forBounds: rect)
        result.size.width = max(0, result.width - 18)
        let height = (font ?? .systemFont(ofSize: OnePlusTextRole.control.size(for: .regular))).boundingRectForFont.height
        result.origin.y += max(0, (result.height - height) / 2)
        result.size.height = min(result.height, height)
        return result
    }
}
