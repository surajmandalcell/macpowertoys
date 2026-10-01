import AppKit
import QuartzCore
import SwiftUI
import os.signpost

public struct OnePlusPanelTiming: Codable, Sendable {
    public let panel: String
    public let tab: String
    public let operation: String
    public let input: String
    public let cold: Bool
    public let milliseconds: Double
    public let width: Double
    public let height: Double
    public let timestamp: Double
}

@MainActor
public final class OnePlusPanelTimings {
    public static let shared = OnePlusPanelTimings()
    public enum Operation: String { case open, tabSwitch, windowOpen, pageSwitch }
    private struct Pending {
        let id: OSSignpostID
        let operation: Operation
        let input: String
        let started: TimeInterval
        let tab: String
    }
    private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.surajmandal.macpowertoys",
                            category: .pointsOfInterest)
    private var pending: [String: Pending] = [:]
    private var opened = Set<String>()
    public private(set) var records: [OnePlusPanelTiming] = []

    public func begin(panel: String, operation: Operation = .open, tab: String = "",
                      input: String = "action", started: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        cancel(panel: panel)
        let interval = Pending(id: OSSignpostID(log: log), operation: operation, input: input,
                               started: started, tab: tab)
        pending[panel] = interval
        os_signpost(.begin, log: log, name: name(operation), signpostID: interval.id,
                    "%{public}s %{public}s", panel, tab)
    }

    public func cancel(panel: String) {
        guard let interval = pending.removeValue(forKey: panel) else { return }
        os_signpost(.end, log: log, name: name(interval.operation), signpostID: interval.id, "cancelled")
    }

    public func beginOpenIfNeeded(panel: String) {
        if pending[panel] == nil { begin(panel: panel) }
    }

    public func hasPending(_ panel: String) -> Bool { pending[panel] != nil }

    public func finish(panel: String, tab: String?, size: NSSize,
                at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite,
              let interval = pending[panel], tab == nil || interval.tab.isEmpty || interval.tab == tab else { return }
        let tab = tab ?? interval.tab
        pending[panel] = nil
        let opening = interval.operation == .open || interval.operation == .windowOpen
        let cold = opening && !opened.contains(panel)
        if opening { opened.insert(panel) }
        records.append(OnePlusPanelTiming(panel: panel, tab: tab, operation: interval.operation.rawValue,
            input: interval.input, cold: cold, milliseconds: max(0, time - interval.started) * 1_000,
            width: size.width, height: size.height, timestamp: Date().timeIntervalSince1970))
        if records.count > 50 { records.removeFirst(records.count - 50) }
        os_signpost(.end, log: log, name: name(interval.operation), signpostID: interval.id,
                    "%{public}s %{public}s display-submitted", panel, tab)
    }

    private func name(_ operation: Operation) -> StaticString {
        switch operation {
        case .open: "PanelOpen"
        case .tabSwitch: "PanelTabSwitch"
        case .windowOpen: "WindowOpen"
        case .pageSwitch: "PageSwitch"
        }
    }
}

public extension View {
    /// Ends an interaction after native layout and display submission. No idle timer.
    func onePlusPanelTimings(panel: String, tab: String?) -> some View {
        background(OnePlusPanelFrameReader(panel: panel, tab: tab))
    }
}

private struct OnePlusPanelFrameReader: NSViewRepresentable {
    let panel: String
    let tab: String?
    func makeNSView(context: Context) -> FrameView { FrameView(panel: panel, tab: tab) }
    func updateNSView(_ view: FrameView, context: Context) {
        view.tab = tab
        view.submit()
    }
    static func dismantleNSView(_ view: FrameView, coordinator: ()) { view.stop() }

    final class FrameView: NSView {
        let panel: String
        var tab: String?
        private var observers: [NSObjectProtocol] = []
        private var scheduled = false
        init(panel: String, tab: String?) {
            self.panel = panel; self.tab = tab
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            for name in [NSWindow.didUpdateNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    let closing = notification.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if closing {
                            OnePlusPanelTimings.shared.cancel(panel: self.panel)
                        } else { self.submit() }
                    }
                })
            }
            submit()
        }
        func submit() {
            guard !scheduled, OnePlusPanelTimings.shared.hasPending(panel),
                  window?.isVisible == true else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let window = self.window, window.isVisible,
                      OnePlusPanelTimings.shared.hasPending(self.panel) else { self.scheduled = false; return }
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                CATransaction.flush()
                OnePlusPanelTimings.shared.finish(panel: self.panel, tab: self.tab,
                                                  size: window.contentView?.frame.size ?? .zero)
                self.scheduled = false
            }
        }
        func stop() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
    }
}
