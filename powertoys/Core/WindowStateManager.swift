//
//  WindowStateManager.swift
//  powertoys
//

import Foundation
import AppKit

@Observable
@MainActor
final class WindowStateManager {
    static let shared = WindowStateManager()

    private let userDefaultsPrefix = "windowState"
    private var observers: [NSObjectProtocol] = []

    private init() {
        setupObservers()
    }

    deinit {
        MainActor.assumeIsolated {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }

    private func setupObservers() {
        let moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let window = notification.object as? NSWindow else { return }
                self.saveState(for: window)
            }
        }

        let resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let window = notification.object as? NSWindow else { return }
                self.saveState(for: window)
            }
        }

        observers = [moveObserver, resizeObserver]
    }

    private static let knownWindowPrefixes = ["main", "cc-history", "rclone", "logs"]

    private static func isTrackedIdentifier(_ identifier: String) -> Bool {
        knownWindowPrefixes.contains { identifier.hasPrefix($0) }
    }

    func saveState(for window: NSWindow) {
        guard let identifier = window.identifier?.rawValue, Self.isTrackedIdentifier(identifier) else { return }

        let frame = window.frame
        let state = WindowState(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )

        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key(for: identifier))
        }
    }

    func restoreState(for window: NSWindow) {
        guard let identifier = window.identifier?.rawValue, Self.isTrackedIdentifier(identifier) else { return }

        guard let data = UserDefaults.standard.data(forKey: key(for: identifier)),
              let state = try? JSONDecoder().decode(WindowState.self, from: data) else {
            return
        }

        let frame = NSRect(x: state.x, y: state.y, width: state.width, height: state.height)

        let sufficientlyVisible = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= 200 && overlap.height >= 100
        }

        if sufficientlyVisible {
            window.setFrame(frame, display: true)
        }
    }

    private func key(for windowId: String) -> String {
        "\(userDefaultsPrefix).\(windowId)"
    }
}

private struct WindowState: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}
