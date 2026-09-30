import AppKit
import SwiftUI

private struct OnePlusZoomTrailingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 70
}

private struct OnePlusCanvasAppliedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var onePlusZoomTrailingX: CGFloat {
        get { self[OnePlusZoomTrailingKey.self] }
        set { self[OnePlusZoomTrailingKey.self] = newValue }
    }
}

public struct OnePlusFixedWindowChrome: NSViewRepresentable {
    private let contentSize: NSSize
    private let centerline: CGFloat
    private let sizing: OnePlusChromeSizing
    private let onZoomTrailingX: (CGFloat) -> Void
    private var onTopInset: (CGFloat) -> Void = { _ in }

    public init(contentSize: NSSize, centerline: CGFloat = OnePlusMetrics.centerline,
                onZoomTrailingX: @escaping (CGFloat) -> Void = { _ in }) {
        self.contentSize = contentSize
        self.centerline = centerline
        self.sizing = .native
        self.onZoomTrailingX = onZoomTrailingX
    }

    public init(contentSize: NSSize, trafficLightVerticalOffset: CGFloat) {
        self.init(contentSize: contentSize, centerline: 16 + trafficLightVerticalOffset)
    }

    init(canvas: OnePlusWindowCanvas, onTopInset: @escaping (CGFloat) -> Void,
         onZoomTrailingX: @escaping (CGFloat) -> Void) {
        contentSize = canvas.size
        centerline = canvas.centerline
        sizing = canvas.heightRange == nil ? .swiftUI : .swiftUIHeight
        self.onZoomTrailingX = onZoomTrailingX
        self.onTopInset = onTopInset
    }

    public func makeNSView(context: Context) -> NSView {
        let view = OnePlusChromeView(size: contentSize, centerline: centerline, sizing: sizing, report: onZoomTrailingX)
        view.reportTopInset = onTopInset
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? OnePlusChromeView else { return }
        view.size = contentSize
        view.centerline = centerline
        view.sizing = sizing
        view.report = onZoomTrailingX
        view.reportTopInset = onTopInset
        view.apply()
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? OnePlusChromeView)?.stopObserving()
    }
}

enum OnePlusChromeSizing { case native, swiftUI, swiftUIHeight }

final class OnePlusChromeView: NSView {
    var size: NSSize
    var centerline: CGFloat
    var sizing: OnePlusChromeSizing
    var report: (CGFloat) -> Void
    var reportTopInset: (CGFloat) -> Void = { _ in }
    private var lastTopInset: CGFloat?
    private weak var observedWindow: NSWindow?
    private var applying = false
    private var pendingPass: DispatchWorkItem?
    private var observationGeneration = 0
    private(set) var appliedPassCount = 0
    private var lastTrailingX: CGFloat?
    private var appearanceObservation: NSKeyValueObservation?
    private var buttonObservations: [NSKeyValueObservation] = []

    init(size: NSSize, centerline: CGFloat, sizing: OnePlusChromeSizing = .native, report: @escaping (CGFloat) -> Void) {
        self.size = size
        self.centerline = centerline
        self.sizing = sizing
        self.report = report
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    isolated deinit {
        pendingPass?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        observedWindow = window
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification] {
            center.addObserver(self, selector: #selector(nativeLayoutChanged), name: name, object: window)
        }
        center.addObserver(self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: window)
        center.addObserver(self, selector: #selector(windowUpdated), name: NSWindow.didUpdateNotification, object: window)
        appearanceObservation = window.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            // Native titlebar layout can reset buttons without resizing the window.
            button.postsFrameChangedNotifications = true
            center.addObserver(self, selector: #selector(nativeLayoutChanged), name: NSView.frameDidChangeNotification, object: button)
            if let parent = button.superview {
                parent.postsFrameChangedNotifications = true
                center.addObserver(self, selector: #selector(nativeLayoutChanged), name: NSView.frameDidChangeNotification, object: parent)
            }
            buttonObservations.append(button.observe(\.isHidden) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        }
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply()
    }

    @objc private func nativeLayoutChanged(_ notification: Notification) { apply() }
    @objc private func windowUpdated(_ notification: Notification) {
        guard !applying, pendingPass == nil, let window = observedWindow else { return }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            if abs(window.frame.height - button.convert(button.bounds, to: nil).midY - centerline) > 0.01 {
                apply()
                return
            }
        }
    }
    @objc private func windowClosed(_ notification: Notification) { stopObserving() }

    func stopObserving() {
        pendingPass?.cancel()
        pendingPass = nil
        observationGeneration += 1
        NotificationCenter.default.removeObserver(self)
        appearanceObservation = nil
        buttonObservations.removeAll()
        observedWindow = nil
        lastTrailingX = nil
        lastTopInset = nil
    }

    func apply() {
        // AppKit and SwiftUI both call us from layout. Never change their inputs there.
        guard !applying, pendingPass == nil, observedWindow != nil else { return }
        let generation = observationGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.observationGeneration else { return }
            self.pendingPass = nil
            self.applyDeferred()
        }
        pendingPass = work
        DispatchQueue.main.async(execute: work)
    }

    private func applyDeferred() {
        guard let window = observedWindow, size.width > 0, size.height > 0 else { return }
        applying = true
        appliedPassCount += 1
        defer { applying = false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let style = window.styleMask.union(.fullSizeContentView).subtracting(.resizable)
        if window.styleMask != style { window.styleMask = style }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        let topInset = window.contentView?.safeAreaInsets.top ?? 0
        if lastTopInset != topInset {
            lastTopInset = topInset
            reportTopInset(topInset)
        }
        if window.tabbingMode != .disallowed { window.tabbingMode = .disallowed }
        if window.isRestorable { window.isRestorable = false }
        let behavior = window.collectionBehavior.subtracting([.fullScreenPrimary, .fullScreenAuxiliary]).union(.fullScreenNone)
        if window.collectionBehavior != behavior { window.collectionBehavior = behavior }
        let minimum = NSSize(width: size.width, height: sizing == .native ? size.height : window.contentMinSize.height)
        let maximum = NSSize(width: size.width, height: sizing == .native ? size.height : window.contentMaxSize.height)
        if window.contentMinSize != minimum { window.contentMinSize = minimum }
        if window.contentMaxSize != maximum { window.contentMaxSize = maximum }
        if sizing == .native, let current = window.contentView?.bounds.size,
           abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 {
            let top = window.frame.maxY
            window.setContentSize(size)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
        if !window.isOpaque { window.isOpaque = true }
        let background = NSColor(OnePlusColor.window)
        if window.backgroundColor != background { window.backgroundColor = background }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
            if button.isHidden { button.isHidden = false }
            if type == .zoomButton, button.isEnabled { button.isEnabled = false }
            let parentRect = parent.convert(parent.bounds, to: nil)
            let target = window.frame.height - centerline
            let localY = parent.isFlipped ? parentRect.maxY - target : target - parentRect.minY
            let y = localY - button.frame.height / 2
            if abs(button.frame.minY - y) > 0.01 {
                button.setFrameOrigin(NSPoint(x: button.frame.minX, y: y))
            }
            if type == .zoomButton {
                let trailing = button.convert(button.bounds, to: nil).maxX
                if lastTrailingX != trailing {
                    lastTrailingX = trailing
                    report(trailing)
                }
            }
        }
    }
}

public extension View {
    /// Applets with a height range keep the height proposed by their body.
    func onePlusFixedCanvas(_ canvas: OnePlusWindowCanvas) -> some View {
        modifier(OnePlusFixedCanvasModifier(canvas: canvas))
    }
}

private struct OnePlusFixedCanvasModifier: ViewModifier {
    let canvas: OnePlusWindowCanvas
    @Environment(\.self) private var environment
    @State private var zoomTrailingX: CGFloat = 70
    @State private var topInset: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if environment[OnePlusCanvasAppliedKey.self] {
            content
        } else {
            content
            .frame(width: canvas.size.width, height: canvas.heightRange == nil ? canvas.size.height : nil)
            // The host adds its native titlebar inset to the measured content size.
            // Extend the content into that inset without adding it to the canvas.
            .padding(.top, -topInset)
            .background {
                OnePlusFixedWindowChrome(canvas: canvas, onTopInset: { topInset = $0 }) {
                    zoomTrailingX = $0
                }
            }
            .transformEnvironment(\.self) { $0[OnePlusCanvasAppliedKey.self] = true }
            .environment(\.onePlusZoomTrailingX, zoomTrailingX)
            .onePlusDensity(canvas.density)
            .onePlusLiveUpdates()
        }
    }
}
