import AppKit
import SwiftUI

public struct OnePlusTextField: View {
    private let title: String
    @Binding private var text: String
    private let error: String?
    private let onSubmit: () -> Void
    @Environment(\.onePlusDensity) private var density
    @Environment(\.onePlusControlHeight) private var controlHeight
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    @State private var hover = false

    public init(_ title: String, text: Binding<String>, error: String? = nil, onSubmit: @escaping () -> Void = {}) {
        self.title = title; _text = text; self.error = error; self.onSubmit = onSubmit
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $text)
                .textFieldStyle(.plain).onePlusText(.control).focused($focused)
                .padding(.horizontal, 8).frame(height: controlHeight ?? density.controlHeight)
                .background(focused || (enabled && hover) ? OnePlusColor.fieldFocus : OnePlusColor.field,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(error != nil ? OnePlusColor.dangerLine : focused ? OnePlusColor.focus : OnePlusColor.line, lineWidth: 1) }
                .onHover { hover = $0 }.onSubmit(onSubmit)
                .accessibilityLabel(title).accessibilityHint(error ?? "")
                .focusEffectDisabled()
            if let error { Text(error).onePlusText(.caption).foregroundStyle(OnePlusColor.danger) }
        }.opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
    }
}

public struct OnePlusStepperField: View {
    private let title: String
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let unit: String?
    @State private var draft: String
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.onePlusDensity) private var density
    @Environment(\.onePlusControlHeight) private var controlHeight
    @Environment(\.isEnabled) private var enabled

    public init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1, unit: String? = nil) {
        self.title = title; _value = value; self.range = range; self.step = max(1, step); self.unit = unit
        _draft = State(initialValue: String(value.wrappedValue))
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                TextField(title, text: $draft).textFieldStyle(.plain).onePlusText(.control)
                    .padding(.horizontal, 8).focused($focused).onSubmit(commit)
                    .onKeyPress(.upArrow) { change(by: step); return .handled }
                    .onKeyPress(.downArrow) { change(by: -step); return .handled }
                    .accessibilityLabel(title).accessibilityHint(error ?? "")
                if let unit { Text(unit).font(.system(size: 9, design: .monospaced)).foregroundStyle(OnePlusColor.muted).padding(.trailing, 8) }
                OnePlusColor.line.frame(width: 1)
                OnePlusNativeStepper(title: title, value: $value, range: range, step: step, enabled: enabled)
                    .frame(width: 17).clipped()
            }
            .frame(height: controlHeight ?? density.controlHeight)
            .background(focused ? OnePlusColor.fieldFocus : OnePlusColor.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(error != nil ? OnePlusColor.dangerLine : focused ? OnePlusColor.focus : OnePlusColor.line, lineWidth: 1) }
            if let error { Text(error).onePlusText(.caption).foregroundStyle(OnePlusColor.danger) }
        }
        .opacity(enabled ? 1 : OnePlusMetrics.disabledOpacity)
        .onChange(of: value) { _, newValue in draft = String(newValue); error = nil }
        .onChange(of: focused) { _, newValue in if !newValue { commit() } }
    }
    private func commit() {
        guard let parsed = Int(draft), range.contains(parsed) else {
            error = "Enter a whole number from \(range.lowerBound) to \(range.upperBound)."
            return
        }
        value = parsed; error = nil
    }
    private func change(by delta: Int) {
        guard let next = Self.nextValue(value, by: delta, in: range) else { return }
        value = next; draft = String(next); error = nil
    }
    static func nextValue(_ value: Int, by delta: Int, in range: ClosedRange<Int>) -> Int? {
        let (next, overflow) = value.addingReportingOverflow(delta)
        return !overflow && range.contains(next) ? next : nil
    }
    static func nativeValue(_ value: Double, in range: ClosedRange<Int>) -> Int? {
        guard value.isFinite, let integer = Int(exactly: value), range.contains(integer) else { return nil }
        return integer
    }
}

private struct OnePlusNativeStepper: NSViewRepresentable {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let enabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(value: $value, range: range) }
    func makeNSView(context: Context) -> NSStepper {
        let view = NSStepper()
        view.target = context.coordinator
        view.action = #selector(Coordinator.changed(_:))
        view.autorepeat = false
        view.valueWraps = false
        view.controlSize = .small
        return view
    }
    func updateNSView(_ view: NSStepper, context: Context) {
        context.coordinator.value = $value
        context.coordinator.range = range
        view.minValue = Double(range.lowerBound); view.maxValue = Double(range.upperBound)
        view.increment = Double(step); view.integerValue = value; view.isEnabled = enabled
        view.setAccessibilityLabel(title)
    }
    @MainActor final class Coordinator: NSObject {
        var value: Binding<Int>
        var range: ClosedRange<Int>
        init(value: Binding<Int>, range: ClosedRange<Int>) { self.value = value; self.range = range }
        @objc func changed(_ sender: NSStepper) {
            guard let next = OnePlusStepperField.nativeValue(sender.doubleValue, in: range) else { return }
            value.wrappedValue = next
        }
    }
}

public struct OnePlusTextEditor: NSViewRepresentable {
    @Binding private var text: String
    private let label: String
    @Environment(\.isEnabled) private var enabled
    @Environment(\.onePlusDensity) private var density
    public init(_ label: String, text: Binding<String>) { self.label = label; _text = text }
    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = OnePlusEditorScrollView()
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 6
        scroll.layer?.masksToBounds = true
        let editor = NSTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        editor.textContainerInset = NSSize(width: 12, height: 11)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        scroll.documentView = editor
        scroll.configureOnePlusScrollIndicators()
        scroll.installBezel()
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
        editor.isEditable = enabled
        editor.font = .monospacedSystemFont(ofSize: OnePlusTextRole.mono.size(for: density), weight: .regular)
        editor.textColor = NSColor(OnePlusColor.controlInk)
        editor.insertionPointColor = NSColor(OnePlusColor.ink)
        editor.selectedTextAttributes = [.backgroundColor: NSColor(OnePlusColor.selection), .foregroundColor: NSColor(OnePlusColor.ink)]
        editor.setAccessibilityLabel(label)
        (scroll as? OnePlusEditorScrollView)?.updateSurface()
        scroll.alphaValue = enabled ? 1 : OnePlusMetrics.disabledOpacity
    }
    @MainActor public final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        public func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
        }
        public func textDidBeginEditing(_ notification: Notification) { updateFocus(notification, focused: true) }
        public func textDidEndEditing(_ notification: Notification) { updateFocus(notification, focused: false) }
        private func updateFocus(_ notification: Notification, focused: Bool) {
            guard let editor = notification.object as? NSTextView else { return }
            guard let scroll = editor.enclosingScrollView as? OnePlusEditorScrollView else { return }
            scroll.focused = focused
            scroll.updateSurface()
        }
    }
}

private final class OnePlusEditorScrollView: NSScrollView {
    var focused = false
    private let bezel = OnePlusEditorBezel()
    override func layout() {
        super.layout()
        bezel.frame = bounds
    }
    func installBezel() {
        bezel.frame = bounds
        bezel.autoresizingMask = [.width, .height]
        bezel.setAccessibilityElement(false)
        addSubview(bezel, positioned: .above, relativeTo: nil)
    }
    func updateSurface() {
        guard let editor = documentView as? NSTextView else { return }
        editor.backgroundColor = NSColor(focused ? OnePlusColor.fieldFocus : OnePlusColor.track)
        bezel.focused = focused
        bezel.needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateSurface()
    }
}

final class OnePlusEditorBezel: NSView {
    var focused = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(focused ? OnePlusColor.focus : OnePlusColor.line).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5.5, yRadius: 5.5)
        path.lineWidth = 1
        path.stroke()
    }
}
