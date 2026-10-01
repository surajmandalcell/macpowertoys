import AppKit
import SwiftUI

private struct OnePlusIsVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True while the host is presented, subject to its occlusion policy.
    var onePlusIsVisible: Bool {
        get { self[OnePlusIsVisibleKey.self] }
        set { self[OnePlusIsVisibleKey.self] = newValue }
    }
}

public extension View {
    /// Supplies `onePlusIsVisible` from native window presentation events.
    func onePlusLiveUpdates(includeOccluded: Bool = false) -> some View {
        modifier(OnePlusLiveUpdatesModifier(includeOccluded: includeOccluded))
    }
}

enum OnePlusWindowVisibility {
    static func isActive(isVisible: Bool, isMiniaturized: Bool,
                         occlusionState: NSWindow.OcclusionState, includeOccluded: Bool = false) -> Bool {
        isVisible && !isMiniaturized && (includeOccluded || occlusionState.contains(.visible))
    }

    @MainActor static func isActive(window: NSWindow?, includeOccluded: Bool = false) -> Bool {
        guard let window else { return false }
        return isActive(isVisible: window.isVisible, isMiniaturized: window.isMiniaturized,
                        occlusionState: window.occlusionState, includeOccluded: includeOccluded)
    }
}

private struct OnePlusLiveUpdatesModifier: ViewModifier {
    let includeOccluded: Bool
    // Visibility gates live work. Keep layout mounted so hosts can measure before showing.
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .environment(\.onePlusIsVisible, isVisible)
            .background(OnePlusVisibilityReader(isVisible: $isVisible, includeOccluded: includeOccluded))
    }
}

private struct OnePlusVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool
    let includeOccluded: Bool

    func makeNSView(context: Context) -> OnePlusVisibilityView {
        OnePlusVisibilityView(includeOccluded: includeOccluded) { isVisible = $0 }
    }

    func updateNSView(_ view: OnePlusVisibilityView, context: Context) {
        view.changed = { isVisible = $0 }
        view.includeOccluded = includeOccluded
        view.refresh()
    }

    static func dismantleNSView(_ view: OnePlusVisibilityView, coordinator: ()) {
        view.stopObserving()
    }
}

private final class OnePlusVisibilityView: NSView {
    var changed: (Bool) -> Void
    var includeOccluded: Bool
    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var lastValue: Bool?

    init(includeOccluded: Bool, changed: @escaping (Bool) -> Void) {
        self.includeOccluded = includeOccluded
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
            let notifications = [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification,
                         NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification,
                         NSWindow.willCloseNotification]
                + (includeOccluded ? [NSWindow.didUpdateNotification] : [])
            for name in notifications {
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
            let value = OnePlusWindowVisibility.isActive(window: self.observedWindow,
                                                         includeOccluded: self.includeOccluded)
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
