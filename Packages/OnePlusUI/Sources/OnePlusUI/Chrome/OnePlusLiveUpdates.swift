import AppKit
import SwiftUI

private struct OnePlusIsVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True only while the host window or panel is visible on screen.
    var onePlusIsVisible: Bool {
        get { self[OnePlusIsVisibleKey.self] }
        set { self[OnePlusIsVisibleKey.self] = newValue }
    }
}

public extension View {
    /// Supplies `onePlusIsVisible` from native window presentation events.
    func onePlusLiveUpdates() -> some View { modifier(OnePlusLiveUpdatesModifier()) }
}

enum OnePlusWindowVisibility {
    static func isActive(isVisible: Bool, isMiniaturized: Bool,
                         occlusionState: NSWindow.OcclusionState) -> Bool {
        isVisible && !isMiniaturized && occlusionState.contains(.visible)
    }

    @MainActor static func isActive(window: NSWindow?) -> Bool {
        guard let window else { return false }
        return isActive(isVisible: window.isVisible, isMiniaturized: window.isMiniaturized,
                        occlusionState: window.occlusionState)
    }
}

private struct OnePlusLiveUpdatesModifier: ViewModifier {
    // Visibility gates live work. Keep layout mounted so hosts can measure before showing.
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .environment(\.onePlusIsVisible, isVisible)
            .background(OnePlusVisibilityReader(isVisible: $isVisible))
    }
}

private struct OnePlusVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> OnePlusVisibilityView {
        OnePlusVisibilityView { isVisible = $0 }
    }

    func updateNSView(_ view: OnePlusVisibilityView, context: Context) {
        view.changed = { isVisible = $0 }
        view.refresh()
    }

    static func dismantleNSView(_ view: OnePlusVisibilityView, coordinator: ()) {
        view.stopObserving()
    }
}

private final class OnePlusVisibilityView: NSView {
    var changed: (Bool) -> Void
    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var lastValue: Bool?

    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    isolated deinit { pending?.cancel(); observers.forEach(NotificationCenter.default.removeObserver) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard observedWindow !== window else { refresh(); return }
        stopObserving()
        observedWindow = window
        if let window {
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification,
                         NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification,
                         NSWindow.willCloseNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
            }
        }
        refresh()
    }

    func refresh() {
        // Defer only observation delivery, never content construction or panel measurement.
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            let value = OnePlusWindowVisibility.isActive(window: self.observedWindow)
            guard value != self.lastValue else { return }
            self.lastValue = value
            self.changed(value)
        }
        pending = work
        DispatchQueue.main.async(execute: work)
    }

    func stopObserving() {
        pending?.cancel()
        pending = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observedWindow = nil
        lastValue = nil
    }
}
