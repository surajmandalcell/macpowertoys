import AppKit
import ObjectiveC
import SwiftUI

public extension View {
    func onePlusScrollIndicators() -> some View { modifier(OnePlusScrollModifier()) }
}

private struct OnePlusPageScrollBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var onePlusPageScrollBottomInset: CGFloat {
        get { self[OnePlusPageScrollBottomInsetKey.self] }
        set { self[OnePlusPageScrollBottomInsetKey.self] = newValue }
    }
}

private struct OnePlusScrollModifier: ViewModifier {
    @Environment(\.onePlusPageScrollBottomInset) private var bottomInset
    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .background(OnePlusScrollConfigurator())
    }
}

private struct OnePlusScrollConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { OnePlusScrollProbe() }
    func updateNSView(_ view: NSView, context: Context) { (view as? OnePlusScrollProbe)?.configure() }
}

private final class OnePlusScrollProbe: NSView {
    private weak var configured: NSScrollView?
    private var pending: DispatchWorkItem?
    isolated deinit { pending?.cancel() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    override func layout() { super.layout(); configure() }

    func configure() {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.apply()
        }
        pending = work
        DispatchQueue.main.async(execute: work)
    }
    private func apply() {
        if let configured, configured.window != nil {
            configured.configureOnePlusScrollIndicators()
            return
        }
        guard window != nil, !bounds.isEmpty else { return }
        let point = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        var ancestor = superview
        while let view = ancestor {
            if let scroll = find(in: view, point: point) {
                scroll.configureOnePlusScrollIndicators()
                configured = scroll
                return
            }
            ancestor = view.superview
        }
        enclosingScrollView?.configureOnePlusScrollIndicators()
    }
    private func find(in view: NSView, point: NSPoint) -> NSScrollView? {
        for child in view.subviews {
            if let scroll = child as? NSScrollView, !isDescendant(of: scroll),
               scroll.convert(scroll.bounds, to: nil).contains(point) { return scroll }
            if let result = find(in: child, point: point) { return result }
        }
        return nil
    }
}

public extension NSScrollView {
    func configureOnePlusScrollIndicators() {
        OnePlusScrollPolicy.install(on: self)
        if hasVerticalScroller, !(verticalScroller is OnePlusOverlayScroller) { verticalScroller = OnePlusOverlayScroller() }
        if hasHorizontalScroller, !(horizontalScroller is OnePlusOverlayScroller) { horizontalScroller = OnePlusOverlayScroller() }
        if scrollerStyle != .overlay { scrollerStyle = .overlay }
        if !autohidesScrollers { autohidesScrollers = true }
        verticalScroller?.controlSize = .mini
        horizontalScroller?.controlSize = .mini
        (verticalScroller as? OnePlusOverlayScroller)?.observeScrolling(in: self)
        (horizontalScroller as? OnePlusOverlayScroller)?.observeScrolling(in: self)
    }
}

@MainActor
private final class OnePlusScrollPolicy {
    private static var key: UInt8 = 0
    private var observations: [NSKeyValueObservation] = []
    private var pending: DispatchWorkItem?
    isolated deinit { pending?.cancel() }

    static func install(on scroll: NSScrollView) {
        guard objc_getAssociatedObject(scroll, &key) == nil else { return }
        let policy = OnePlusScrollPolicy()
        objc_setAssociatedObject(scroll, &key, policy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        policy.observations = [
            scroll.observe(\.scrollerStyle) { [weak policy] scroll, _ in
                MainActor.assumeIsolated { policy?.schedule(scroll) }
            },
            scroll.observe(\.verticalScroller) { [weak policy] scroll, _ in
                MainActor.assumeIsolated { policy?.schedule(scroll) }
            },
            scroll.observe(\.horizontalScroller) { [weak policy] scroll, _ in
                MainActor.assumeIsolated { policy?.schedule(scroll) }
            }
        ]
    }

    private func schedule(_ scroll: NSScrollView) {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self, weak scroll] in
            self?.pending = nil
            scroll?.configureOnePlusScrollIndicators()
        }
        pending = work
        DispatchQueue.main.async(execute: work)
    }
}

/// Native overlay scroller with a four-point thumb. No idle timer or polling.
public final class OnePlusOverlayScroller: NSScroller {
    private weak var observedClipView: NSClipView?
    private var area: NSTrackingArea?
    private var hideTask: Task<Void, Never>?
    private var pointerInside = false
    public override class var isCompatibleWithOverlayScrollers: Bool { true }
    public static func knobThickness(increasedContrast: Bool) -> CGFloat { increasedContrast ? 6 : 4 }
    public override init(frame: NSRect) { super.init(frame: frame); alphaValue = 0 }
    public required init?(coder: NSCoder) { super.init(coder: coder); alphaValue = 0 }
    isolated deinit { hideTask?.cancel(); NotificationCenter.default.removeObserver(self) }

    public func observeScrolling(in scrollView: NSScrollView) {
        let clip = scrollView.contentView
        guard observedClipView !== clip else { return }
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        observedClipView = clip
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(positionChanged),
                                              name: NSView.boundsDidChangeNotification, object: clip)
    }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            hideTask?.cancel(); hideTask = nil
            NotificationCenter.default.removeObserver(self)
            observedClipView = nil
        } else if let scrollView = enclosingScrollView { observeScrolling(in: scrollView) }
    }
    public override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); self.area = area
        super.updateTrackingAreas()
    }
    public override func mouseEntered(with event: NSEvent) { pointerInside = true; showThumb() }
    public override func mouseExited(with event: NSEvent) { pointerInside = false; scheduleHide() }
    public override func drawKnob() {
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let thickness = Self.knobThickness(increasedContrast: contrast)
        let rect = bounds.height > bounds.width
            ? NSRect(x: knob.midX - thickness / 2, y: knob.minY, width: thickness, height: knob.height)
            : NSRect(x: knob.minX, y: knob.midY - thickness / 2, width: knob.width, height: thickness)
        NSColor(contrast ? OnePlusColor.secondary : OnePlusColor.muted).setFill()
        NSBezierPath(roundedRect: rect, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
    public override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    @objc private func positionChanged() { showThumb(); scheduleHide() }
    private func showThumb() { hideTask?.cancel(); alphaValue = 1 }
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard let self, !pointerInside else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { alphaValue = 0 }
            else { NSAnimationContext.runAnimationGroup({ $0.duration = OnePlusMotion.content; self.animator().alphaValue = 0 }, completionHandler: nil) }
        }
    }
}
