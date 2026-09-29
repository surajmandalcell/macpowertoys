import AppKit
import SwiftUI

private struct OnePlusZoomTrailingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 70
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
    private let onZoomTrailingX: (CGFloat) -> Void

    public init(contentSize: NSSize, centerline: CGFloat = OnePlusMetrics.centerline,
                onZoomTrailingX: @escaping (CGFloat) -> Void = { _ in }) {
        self.contentSize = contentSize
        self.centerline = centerline
        self.onZoomTrailingX = onZoomTrailingX
    }

    public init(contentSize: NSSize, trafficLightVerticalOffset: CGFloat) {
        self.init(contentSize: contentSize, centerline: 16 + trafficLightVerticalOffset)
    }

    public func makeNSView(context: Context) -> NSView {
        OnePlusChromeView(size: contentSize, centerline: centerline, report: onZoomTrailingX)
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? OnePlusChromeView else { return }
        view.size = contentSize
        view.centerline = centerline
        view.report = onZoomTrailingX
        view.apply()
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? OnePlusChromeView)?.stopObserving()
    }
}

final class OnePlusChromeView: NSView {
    var size: NSSize
    var centerline: CGFloat
    var report: (CGFloat) -> Void
    private weak var observedWindow: NSWindow?
    private var applying = false
    private var lastTrailingX: CGFloat?
    private var appearanceObservation: NSKeyValueObservation?
    private var buttonObservations: [NSKeyValueObservation] = []

    init(size: NSSize, centerline: CGFloat, report: @escaping (CGFloat) -> Void) {
        self.size = size
        self.centerline = centerline
        self.report = report
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit { NotificationCenter.default.removeObserver(self) }
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
    @objc private func windowClosed(_ notification: Notification) { stopObserving() }

    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        appearanceObservation = nil
        buttonObservations.removeAll()
        observedWindow = nil
        lastTrailingX = nil
    }

    func apply() {
        guard !applying, let window = observedWindow, size.width > 0, size.height > 0 else { return }
        applying = true
        defer { applying = false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.collectionBehavior.remove([.fullScreenPrimary, .fullScreenAuxiliary])
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentMinSize = size
        window.contentMaxSize = size
        if let current = window.contentView?.bounds.size,
           abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 {
            let top = window.frame.maxY
            window.setContentSize(size)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
        window.isOpaque = true
        window.backgroundColor = NSColor(OnePlusColor.window)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
            button.isHidden = false
            if type == .zoomButton { button.isEnabled = false }
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
                    DispatchQueue.main.async { [weak self] in
                        guard let self, observedWindow != nil else { return }
                        report(trailing)
                    }
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
    @State private var zoomTrailingX: CGFloat = 70

    func body(content: Content) -> some View {
        content
            .frame(width: canvas.size.width, height: canvas.heightRange == nil ? canvas.size.height : nil)
            .background {
                GeometryReader { proxy in
                    OnePlusFixedWindowChrome(contentSize: proxy.size, centerline: canvas.centerline) {
                        zoomTrailingX = $0
                    }
                }
            }
            .environment(\.onePlusZoomTrailingX, zoomTrailingX)
            .onePlusDensity(canvas.density)
    }
}
