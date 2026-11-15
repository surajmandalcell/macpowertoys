import AppKit
import SwiftUI
import OnePlusUI

// shortcut: v15 applet values live here until OnePlusUI has them; move to OnePlusUI 1.2.0 applet tokens when the app adopts it.
enum RulerAppletColor {
    private static func dynamic(_ name: String, light: UInt32, lightAlpha: Double = 1,
                                dark: UInt32, darkAlpha: Double = 1) -> NSColor {
        OnePlusLinearColor.dynamic("RulerApplet.\(name)", light: light, lightAlpha: lightAlpha,
                                   dark: dark, darkAlpha: darkAlpha)
    }

    static let window = dynamic("window", light: 0xFDFDFD, dark: 0x1A1A1D)
    static let group = dynamic("group", light: 0xF5F5F6, dark: 0x28282B)
    static let line = dynamic("line", light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let ink = NSColor(OnePlusLinearColor.ink)
    static let secondary = dynamic("secondary", light: 0x68686F, dark: 0xC1C1C7)
    static let muted = dynamic("muted", light: 0x82828A, dark: 0xAAABB2)
    static let softButton = dynamic("softButton", light: 0xEBEBED, dark: 0x2C2C30)
    static let softButtonHover = dynamic("softButtonHover", light: 0xE2E2E5, dark: 0x34343A)
    static let softButtonPressed = dynamic("softButtonPressed", light: 0xD8D8DC, dark: 0x3C3C42)
    static let destructiveFill = dynamic("destructiveFill", light: 0xE0493E, lightAlpha: 0.10,
                                         dark: 0xFF6B5E, darkAlpha: 0.18)
    static let destructiveHover = dynamic("destructiveHover", light: 0xE0493E, lightAlpha: 0.14,
                                          dark: 0xFF6B5E, darkAlpha: 0.23)
    static let destructivePressed = dynamic("destructivePressed", light: 0xE0493E, lightAlpha: 0.18,
                                            dark: 0xFF6B5E, darkAlpha: 0.28)
    /// Dark uses the rendered mockup value; `#FFA8A0` stays below APCA Lc 60 on the red tint.
    static let destructiveText = dynamic("destructiveText", light: 0xB02D24, dark: 0xFFB8AF)
}

enum RulerAppletMetrics {
    static let windowSize = NSSize(width: 420, height: 500)
    static let titleArea: CGFloat = 48
    static let centerline = OnePlusMetrics.appletCenterline
    static let titleAfterZoom: CGFloat = 14
    static let gutter: CGFloat = 16
    static let row: CGFloat = 36
    static let rowPadding: CGFloat = 12
    static let groupRadius: CGFloat = 10
    static let buttonRadius: CGFloat = 8
    static let caption: CGFloat = 12
    static let body: CGFloat = 13
}

/// The one place that styles the Ruler applet bodies. Switch, slider, and segmented drawing are the
/// Depth classes in `RulerDepthControls.swift`, set as the XIB custom classes.
@MainActor
enum RulerAppletStyle {
    static func apply(to root: NSView) {
        OnePlusNativeForm.style(root)
        styleText(in: root)
    }

    private static func styleText(in view: NSView) {
        switch view {
        case let caption as RulerAppletCaptionLabel:
            caption.font = .systemFont(ofSize: RulerAppletMetrics.caption, weight: .medium)
            caption.textColor = RulerAppletColor.muted
        case let value as RulerAppletValueLabel:
            value.font = .monospacedDigitSystemFont(ofSize: RulerAppletMetrics.body, weight: .regular)
            value.textColor = RulerAppletColor.secondary
        case let field as RulerDepthStepperField:
            field.font = .monospacedDigitSystemFont(ofSize: RulerAppletMetrics.body, weight: .regular)
            field.textColor = RulerAppletColor.ink
        case let label as NSTextField where !label.isEditable:
            label.font = .systemFont(ofSize: RulerAppletMetrics.body)
            label.textColor = RulerAppletColor.ink
            label.lineBreakMode = .byTruncatingTail
        case let toggle as OnePlusNativeSwitchButton:
            toggle.font = .systemFont(ofSize: RulerAppletMetrics.body)
            toggle.clipsToBounds = false
        case let slider as NSSlider:
            slider.clipsToBounds = false
        default:
            break
        }
        view.subviews.forEach(styleText(in:))
    }
}

final class RulerAppletCaptionLabel: NSTextField {}

final class RulerAppletValueLabel: NSTextField {}

/// A filled group with no border; hairlines separate its 36 pt rows.
final class RulerAppletGroupView: NSView {
    var separatorOffsets: [CGFloat] {
        let rows = Int((bounds.height / RulerAppletMetrics.row).rounded())
        return rows > 1 ? (1..<rows).map { CGFloat($0) * RulerAppletMetrics.row } : []
    }

    override func draw(_ dirtyRect: NSRect) {
        RulerAppletColor.group.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: RulerAppletMetrics.groupRadius,
                     yRadius: RulerAppletMetrics.groupRadius).fill()
        RulerAppletColor.line.setFill()
        let width = bounds.width - 2 * RulerAppletMetrics.rowPadding
        for offset in separatorOffsets {
            NSRect(x: RulerAppletMetrics.rowPadding, y: bounds.maxY - offset, width: width, height: 1).fill()
        }
    }
}

/// The window body: the applet body color runs under a transparent title area with no separator.
/// Native traffic lights and dragging stay; the house chrome centers the lights on the applet centerline.
final class RulerAppletWindowView: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    private var titleLeading: NSLayoutConstraint?
    private var chrome: NSView?

    override func draw(_ dirtyRect: NSRect) {
        RulerAppletColor.window.setFill()
        dirtyRect.fill()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.font = .systemFont(ofSize: RulerAppletMetrics.body, weight: .semibold)
        titleLabel.textColor = RulerAppletColor.ink
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setAccessibilityElement(false)
        titleLabel.stringValue = window?.title ?? ""
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        let leading = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 80)
        titleLeading = leading
        NSLayoutConstraint.activate([
            leading,
            titleLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: RulerAppletMetrics.centerline),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -RulerAppletMetrics.gutter),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = RulerAppletColor.window
        titleLabel.stringValue = window.title
        // Frames saved by the old 571 pt layout must not stretch the fixed applet; keep the saved top-left.
        let frame = window.frame
        if frame.size != RulerAppletMetrics.windowSize {
            window.setFrame(NSRect(x: frame.minX, y: frame.maxY - RulerAppletMetrics.windowSize.height,
                                   width: RulerAppletMetrics.windowSize.width,
                                   height: RulerAppletMetrics.windowSize.height), display: false)
        }
        guard chrome == nil else { return }
        let host = NSHostingView(rootView: OnePlusFixedWindowChrome(
            contentSize: RulerAppletMetrics.windowSize,
            centerline: RulerAppletMetrics.centerline,
            onZoomTrailingX: { [weak self] zoomTrailing in
                self?.titleLeading?.constant = zoomTrailing + RulerAppletMetrics.titleAfterZoom
            }
        ))
        host.frame = .zero
        host.setAccessibilityElement(false)
        addSubview(host)
        chrome = host
    }
}

/// Applet footer buttons. Hover and press change only the fill; nothing moves.
final class RulerAppletButton: NSButton {
    enum Role { case primary, plain, destructive }

    var role: Role = .plain { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var hoverArea: NSTrackingArea?

    override func awakeFromNib() {
        super.awakeFromNib()
        isBordered = false
        focusRingType = .none
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    var fillColor: NSColor {
        let pressed = cell?.isHighlighted == true
        switch role {
        case .primary, .plain:
            return pressed ? RulerAppletColor.softButtonPressed
                : isHovered ? RulerAppletColor.softButtonHover : RulerAppletColor.softButton
        case .destructive:
            return pressed ? RulerAppletColor.destructivePressed
                : isHovered ? RulerAppletColor.destructiveHover : RulerAppletColor.destructiveFill
        }
    }

    var titleColor: NSColor { role == .destructive ? RulerAppletColor.destructiveText : RulerAppletColor.ink }

    override func draw(_ dirtyRect: NSRect) {
        let alpha = isEnabled ? 1 : OnePlusMetrics.disabledOpacity
        let shape = NSBezierPath(roundedRect: bounds, xRadius: RulerAppletMetrics.buttonRadius,
                                 yRadius: RulerAppletMetrics.buttonRadius)
        fillColor.withAlphaComponent(fillColor.alphaComponent * alpha).setFill()
        shape.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: RulerAppletMetrics.body, weight: role == .primary ? .medium : .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: titleColor.withAlphaComponent(alpha), .paragraphStyle: paragraph,
        ]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: RulerAppletMetrics.rowPadding, y: bounds.midY - height / 2,
                                            width: bounds.width - 2 * RulerAppletMetrics.rowPadding, height: height),
                                 withAttributes: attributes)
        if window?.firstResponder === self, OnePlusFocusPolicy.shared.showsFocus {
            NSColor(OnePlusColor.focus).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                    xRadius: RulerAppletMetrics.buttonRadius - 1,
                                    yRadius: RulerAppletMetrics.buttonRadius - 1)
            ring.stroke()
        }
    }
}
