import AppKit
import SwiftUI

public struct OnePlusSearchField: View {
    private let prompt: String
    @Binding private var text: String
    private let width: CGFloat?
    private let height: CGFloat
    private let focusTrigger: Int
    private let identifier: String?
    private let shortcutHint: String?
    @Environment(\.onePlusDensity) private var density
    @Environment(\.isEnabled) private var enabled

    public init(prompt: String, text: Binding<String>, width: CGFloat? = 300,
                focusTrigger: Int = 0, accessibilityIdentifier: String? = nil,
                height: CGFloat = 28, shortcutHint: String? = nil) {
        self.prompt = prompt
        _text = text
        self.width = width
        self.height = height
        self.focusTrigger = focusTrigger
        identifier = accessibilityIdentifier
        self.shortcutHint = shortcutHint
    }

    public var body: some View {
        OnePlusNativeSearch(prompt: prompt, text: $text, focusTrigger: focusTrigger,
                            identifier: identifier, hint: shortcutHint,
                            fontSize: OnePlusTextRole.control.size(for: density), enabled: enabled)
            .frame(width: width, height: height)
            .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
    }
}

public struct OnePlusSidebarSearch: View {
    @Binding private var text: String
    private let prompt: String
    private let alternateShortcut: KeyEquivalent?
    private let identifier: String?
    @State private var focusTrigger = 0
    public init(_ prompt: String = "Search", text: Binding<String>, alternateShortcut: KeyEquivalent? = nil,
                accessibilityIdentifier: String? = nil) {
        self.prompt = prompt; _text = text; self.alternateShortcut = alternateShortcut
        identifier = accessibilityIdentifier
    }
    public var body: some View {
        OnePlusSearchField(prompt: prompt, text: $text, width: nil, focusTrigger: focusTrigger,
                           accessibilityIdentifier: identifier, height: 32, shortcutHint: "⌘K")
            .background {
                Button("Focus search") { focusTrigger += 1 }.keyboardShortcut("k").hidden()
                if let alternateShortcut {
                    Button("Find a tool") { focusTrigger += 1 }.keyboardShortcut(alternateShortcut).hidden()
                }
            }
    }
}

private struct OnePlusNativeSearch: NSViewRepresentable {
    let prompt: String
    @Binding var text: String
    let focusTrigger: Int
    let identifier: String?
    let hint: String?
    let fontSize: CGFloat
    let enabled: Bool

    func makeNSView(context: Context) -> OnePlusSearchView { OnePlusSearchView() }
    func updateNSView(_ view: OnePlusSearchView, context: Context) {
        view.changed = { text = $0 }
        view.field.placeholderString = prompt
        view.field.setAccessibilityLabel(prompt)
        view.field.setAccessibilityIdentifier(identifier)
        view.field.isEnabled = enabled
        view.field.focusRingType = .none
        view.field.font = .systemFont(ofSize: fontSize)
        if view.field.stringValue != text { view.field.stringValue = text }
        view.hint.stringValue = hint ?? ""
        view.hint.isHidden = hint == nil || !text.isEmpty
        view.needsLayout = true
        if view.focusTrigger != focusTrigger {
            view.focusTrigger = focusTrigger
            DispatchQueue.main.async { [weak view] in
                guard let view, view.field.isEnabled else { return }
                view.window?.makeFirstResponder(view.field)
            }
        }
    }
}

final class OnePlusSearchView: NSView, NSSearchFieldDelegate {
    let field: NSSearchField = OnePlusNativeSearchField()
    let hint = NSTextField(labelWithString: "")
    var changed: (String) -> Void = { _ in }
    var focusTrigger = 0
    private var focused = false
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    private let textLayout = NSLayoutManager()
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.delegate = self
        field.textColor = NSColor(OnePlusColor.controlInk)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        hint.textColor = NSColor(OnePlusColor.muted)
        hint.setAccessibilityElement(false)
        addSubview(field)
        addSubview(hint)
    }
    convenience init() { self.init(frame: .zero) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        let hintWidth: CGFloat = hint.isHidden ? 0 : 28
        // Borderless NSSearchField draws its line at the top of its frame.
        // Fit that frame to the line so native text, placeholder, and editor agree.
        let lineHeight = field.font.map { textLayout.defaultLineHeight(for: $0) } ?? 15
        field.frame = NSRect(x: 8, y: (bounds.height - lineHeight) / 2,
                             width: max(0, bounds.width - 16 - hintWidth), height: lineHeight)
        hint.frame = NSRect(x: bounds.width - 32, y: (bounds.height - 14) / 2, width: 26, height: 14)
    }
    override func mouseDown(with event: NSEvent) {
        guard field.isEnabled else { return }
        window?.makeFirstResponder(field)
    }
    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor(focused ? OnePlusColor.fieldFocus : hovered && field.isEnabled ? OnePlusColor.raised : OnePlusColor.field).setFill()
        path.fill()
        NSColor(focused ? OnePlusColor.focus : OnePlusColor.line).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    func controlTextDidBeginEditing(_ notification: Notification) {
        focused = true; needsDisplay = true
        (field.currentEditor() as? NSTextView)?.selectedTextAttributes = [
            .backgroundColor: NSColor(OnePlusColor.selection),
            .foregroundColor: NSColor(OnePlusColor.ink)
        ]
    }
    func controlTextDidEndEditing(_ notification: Notification) { focused = false; needsDisplay = true }
    func controlTextDidChange(_ notification: Notification) { changed(field.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard command == #selector(NSResponder.cancelOperation(_:)), !field.stringValue.isEmpty else { return false }
        field.stringValue = ""
        changed("")
        return true
    }
}

private final class OnePlusNativeSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { OnePlusSearchCell.self }
        set {}
    }
}

private final class OnePlusSearchCell: NSSearchFieldCell {
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: view, editor: editor, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
    }
}

// Kept for clients that use the native single-line cell through @testable.
final class OnePlusCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let drawing = super.drawingRect(forBounds: rect)
        let height = min(cellSize(forBounds: rect).height, drawing.height)
        return NSRect(x: drawing.minX, y: floor(rect.midY - height / 2), width: drawing.width, height: height)
    }
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
    }
}
