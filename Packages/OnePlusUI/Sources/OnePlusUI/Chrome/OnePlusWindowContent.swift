import AppKit
import SwiftUI

/// Keeps a scene's native window warm without retaining its closed view graph.
public struct OnePlusWindowContent<Content: View>: View {
    @ViewBuilder private let content: () -> Content
    @State private var closedSize: CGSize?

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Group {
            if let closedSize {
                Color.clear.frame(width: closedSize.width, height: closedSize.height)
            } else {
                content()
            }
        }
        .background(WindowContentReader(closedSize: $closedSize))
    }
}

private let windowContentWillOpen = Notification.Name("OnePlusWindowContent.willOpen")

public extension NSWindow {
    /// Reconstructs closed scene content before the router orders the window onscreen.
    func onePlusPrepareForOpening() {
        NotificationCenter.default.post(name: windowContentWillOpen, object: self)
        contentView?.layoutSubtreeIfNeeded()
    }
}

private struct WindowContentReader: NSViewRepresentable {
    @Binding var closedSize: CGSize?

    func makeNSView(context: Context) -> WindowContentObserver {
        WindowContentObserver { closedSize = $0 }
    }

    func updateNSView(_ view: WindowContentObserver, context: Context) {
        view.changed = { closedSize = $0 }
    }

    static func dismantleNSView(_ view: WindowContentObserver, coordinator: ()) {
        view.stopObserving()
    }
}

private final class WindowContentObserver: NSView {
    var changed: (CGSize?) -> Void
    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var isClosed = false

    init(changed: @escaping (CGSize?) -> Void) {
        self.changed = changed
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard observedWindow !== window else { return }
        stopObserving()
        observedWindow = window
        guard let window else { return }
        for name in [NSWindow.willCloseNotification, windowContentWillOpen,
                     NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.received(name) }
            })
        }
    }

    private func received(_ name: Notification.Name) {
        guard let window = observedWindow else { return }
        if name == NSWindow.willCloseNotification {
            isClosed = true
            changed(window.contentView?.frame.size ?? .zero)
            window.contentView?.layoutSubtreeIfNeeded()
        } else if isClosed, name == windowContentWillOpen || window.isVisible {
            isClosed = false
            changed(nil)
        }
    }

    func stopObserving() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observedWindow = nil
    }
}
