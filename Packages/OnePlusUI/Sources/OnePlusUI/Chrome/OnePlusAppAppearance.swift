import AppKit
import Observation
import SwiftUI

public extension View {
    /// Keep independent native presentation hosts on the application's theme.
    func onePlusAppAppearance() -> some View {
        modifier(OnePlusAppAppearanceModifier())
    }
}

private struct OnePlusAppAppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let scheme = OnePlusAppAppearance.shared.scheme
        content.environment(\.colorScheme, scheme)
            .background(OnePlusAppAppearanceReader())
    }
}

@MainActor @Observable
private final class OnePlusAppAppearance {
    static let shared = OnePlusAppAppearance()
    private(set) var scheme = NSApplication.shared.effectiveAppearance.onePlusColorScheme
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var displayObserver: NSObjectProtocol?
    @ObservationIgnored private let windows = NSHashTable<NSWindow>.weakObjects()

    private init() {
        observation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(invalidateDisplay: true) }
            }
    }

    func configure(_ view: NSView) {
        guard let window = view.window else { return }
        windows.add(window)
        // Hosts can pin a snapshot at creation. Remove it before setting the window.
        var ancestor = view.superview
        while let view = ancestor {
            if view.appearance != nil { view.appearance = nil }
            ancestor = view.superview
        }
        apply(window)
    }

    private func refresh(invalidateDisplay: Bool = false) {
        scheme = NSApplication.shared.effectiveAppearance.onePlusColorScheme
        for window in windows.allObjects {
            apply(window)
            if invalidateDisplay { window.contentView?.needsDisplay = true }
        }
    }

    private func apply(_ window: NSWindow) {
        let appearance = NSApplication.shared.effectiveAppearance
        if window.appearance != appearance { window.appearance = appearance }
    }
}

private struct OnePlusAppAppearanceReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AppearanceView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class AppearanceView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            OnePlusAppAppearance.shared.configure(self)
        }
    }
}

private extension NSAppearance {
    var onePlusColorScheme: ColorScheme {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}
