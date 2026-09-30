import AppKit
import ObjectiveC
import SwiftUI

public extension View {
    func onePlusScrollIndicators(axes: Axis.Set = [.vertical, .horizontal]) -> some View {
        modifier(OnePlusScrollModifier(axes: axes))
    }
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
    let axes: Axis.Set
    @Environment(\.onePlusPageScrollBottomInset) private var bottomInset
    func body(content: Content) -> some View {
        content
            .scrollIndicators(.never)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .background(OnePlusScrollConfigurator(axes: axes))
    }
}

private struct OnePlusScrollConfigurator: NSViewRepresentable {
    let axes: Axis.Set
    func makeNSView(context: Context) -> NSView { OnePlusScrollProbe() }
    func updateNSView(_ view: NSView, context: Context) {
        guard let probe = view as? OnePlusScrollProbe else { return }
        probe.axes = axes; probe.configure()
    }
}

final class OnePlusScrollProbe: NSView {
    var axes: Axis.Set = [.vertical, .horizontal]
    private weak var configured: NSScrollView?
    private var pending: DispatchWorkItem?
    isolated deinit { pending?.cancel() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    override func layout() { super.layout(); configure() }

    func configure() {
        apply()
        guard configured == nil, pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.apply()
        }
        pending = work
        DispatchQueue.main.async(execute: work)
    }
    private func apply() {
        if window != nil, !bounds.isEmpty {
            let rect = convert(bounds, to: nil)
            if let configured, configured.window === window,
               matches(configured.convert(configured.bounds, to: nil), rect) {
                configured.configureOnePlusScrollIndicators(axes: axes)
                return
            }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = findMatchingScroll(in: view, rect: rect) {
                    scroll.configureOnePlusScrollIndicators(axes: axes)
                    configured = scroll
                    return
                }
                if view === enclosingScrollView { break }
                ancestor = view.superview
            }
        }
        if let scroll = enclosingScrollView {
            scroll.configureOnePlusScrollIndicators(axes: axes)
            configured = scroll
            return
        }
        if let configured, configured.window != nil {
            configured.configureOnePlusScrollIndicators(axes: axes)
            return
        }
        guard window != nil, !bounds.isEmpty else { return }
        let point = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        var ancestor = superview
        while let view = ancestor {
            if let scroll = find(in: view, point: point) {
                scroll.configureOnePlusScrollIndicators(axes: axes)
                configured = scroll
                return
            }
            ancestor = view.superview
        }
    }
    private func findMatchingScroll(in view: NSView, rect: NSRect) -> NSScrollView? {
        for child in view.subviews {
            if let scroll = child as? NSScrollView {
                let candidate = scroll.convert(scroll.bounds, to: nil)
                if matches(candidate, rect) { return scroll }
                continue
            }
            if let result = findMatchingScroll(in: child, rect: rect) { return result }
        }
        return nil
    }
    private func matches(_ candidate: NSRect, _ rect: NSRect) -> Bool {
        abs(candidate.minX - rect.minX) < 2 && abs(candidate.minY - rect.minY) < 2 &&
            abs(candidate.width - rect.width) < 2 && abs(candidate.height - rect.height) < 2
    }
    private func find(in view: NSView, point: NSPoint) -> NSScrollView? {
        for child in view.subviews {
            if let scroll = child as? NSScrollView {
                if scroll.convert(scroll.bounds, to: nil).contains(point) { return scroll }
                continue
            }
            if let result = find(in: child, point: point) { return result }
        }
        return nil
    }
}

public extension NSScrollView {
    func configureOnePlusScrollIndicators(axes: Axis.Set? = nil) {
        let policy = OnePlusScrollPolicy.install(on: self, axes: axes)
        if scrollerStyle != .overlay { scrollerStyle = .overlay }
        if let axes = policy.axes {
            if hasVerticalScroller != axes.contains(.vertical) { hasVerticalScroller = axes.contains(.vertical) }
            if hasHorizontalScroller != axes.contains(.horizontal) { hasHorizontalScroller = axes.contains(.horizontal) }
        }
        if hasVerticalScroller, !(verticalScroller is OnePlusOverlayScroller) { verticalScroller = OnePlusOverlayScroller() }
        if hasHorizontalScroller, !(horizontalScroller is OnePlusOverlayScroller) { horizontalScroller = OnePlusOverlayScroller() }
        if !autohidesScrollers { autohidesScrollers = true }
        verticalScroller?.controlSize = .mini
        horizontalScroller?.controlSize = .mini
        (verticalScroller as? OnePlusOverlayScroller)?.observeScrolling(in: self)
        (horizontalScroller as? OnePlusOverlayScroller)?.observeScrolling(in: self)
        let overlayWidth = NSScrollView.contentSize(forFrameSize: bounds.size,
            horizontalScrollerClass: nil, verticalScrollerClass: nil, borderType: borderType,
            controlSize: .mini, scrollerStyle: .overlay).width - contentInsets.left - contentInsets.right
        if abs(contentView.frame.width - overlayWidth) > 0.5 { tile() }
    }
}

@MainActor
private final class OnePlusScrollPolicy {
    var axes: Axis.Set?
    private static var key: UInt8 = 0
    private var observations: [NSKeyValueObservation] = []
    private var frameObserver: (any NSObjectProtocol)?
    private var pending: DispatchWorkItem?
    isolated deinit {
        pending?.cancel()
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    static func install(on scroll: NSScrollView, axes: Axis.Set?) -> OnePlusScrollPolicy {
        if let policy = objc_getAssociatedObject(scroll, &key) as? OnePlusScrollPolicy {
            if let axes { policy.axes = axes }
            return policy
        }
        let policy = OnePlusScrollPolicy()
        policy.axes = axes
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
            },
            scroll.observe(\.hasVerticalScroller) { [weak policy] scroll, _ in
                MainActor.assumeIsolated { policy?.schedule(scroll) }
            },
            scroll.observe(\.hasHorizontalScroller) { [weak policy] scroll, _ in
                MainActor.assumeIsolated { policy?.schedule(scroll) }
            }
        ]
        scroll.contentView.postsFrameChangedNotifications = true
        policy.frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
            object: scroll.contentView, queue: .main) { [weak policy, weak scroll] _ in
                MainActor.assumeIsolated { if let scroll { policy?.schedule(scroll) } }
            }
        return policy
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
