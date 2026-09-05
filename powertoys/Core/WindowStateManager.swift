//
//  WindowStateManager.swift
//  powertoys
//

import Foundation
import AppKit
import CoreGraphics

@Observable
@MainActor
final class WindowStateManager {
    static let shared = WindowStateManager()
    static weak var current: WindowStateManager?

    private let userDefaultsPrefix = "windowState"
    private var observers: [NSObjectProtocol] = []
    private let restoredWindows = NSHashTable<NSWindow>.weakObjects()

    var observerOwnerCount: Int { observers.count }

    private init() {
        Self.current = self
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

    nonisolated private static let knownWindowIdentifiers = [
        "main",
        "cc-history",
        "rclone",
        "logs",
        "awake",
        "color-picker",
        "text-extractor",
        "input-devices",
        "system-care",
        "system-monitor",
        "nettoys"
    ]

    nonisolated private static let fixedSizeIdentifiers: Set<String> = [
        "main",
        "awake",
        "color-picker",
        "text-extractor"
    ]

    nonisolated static func storageIdentifier(for identifier: String) -> String? {
        knownWindowIdentifiers.first { knownIdentifier in
            identifier == knownIdentifier || identifier.hasPrefix("\(knownIdentifier)-")
        }
    }

    nonisolated static func restoresPositionOnly(_ identifier: String) -> Bool {
        guard let storageIdentifier = storageIdentifier(for: identifier) else { return false }
        return fixedSizeIdentifiers.contains(storageIdentifier)
    }

    nonisolated static func positionOnlyFrame(saved: NSRect, currentSize: NSSize) -> NSRect {
        NSRect(
            x: saved.minX,
            y: saved.maxY - currentSize.height,
            width: currentSize.width,
            height: currentSize.height
        )
    }

    func saveState(for window: NSWindow) {
        guard !AppRuntime.isUITesting else { return }
        guard restoredWindows.contains(window) else { return }
        guard let identifier = window.identifier?.rawValue,
              let storageIdentifier = Self.storageIdentifier(for: identifier) else { return }

        let frame = window.frame
        let screen = window.screen
        let state = WindowState(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height,
            screenIdentifier: screen.flatMap(Self.screenIdentifier(for:)),
            screenOriginX: screen?.visibleFrame.minX,
            screenOriginY: screen?.visibleFrame.minY
        )

        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key(for: storageIdentifier))
        }
    }

    func restoreState(for window: NSWindow) {
        guard !AppRuntime.isUITesting else { return }
        guard let identifier = window.identifier?.rawValue,
              let storageIdentifier = Self.storageIdentifier(for: identifier) else { return }
        defer { restoredWindows.add(window) }

        let data = Self.storedStateData(for: storageIdentifier, in: .standard)
        guard let data,
              let state = try? JSONDecoder().decode(WindowState.self, from: data) else {
            return
        }

        var frame = NSRect(x: state.x, y: state.y, width: state.width, height: state.height)

        if Self.restoresPositionOnly(storageIdentifier) {
            frame = Self.positionOnlyFrame(saved: frame, currentSize: window.frame.size)
        }

        if let savedScreenIdentifier = state.screenIdentifier,
           let savedScreenOriginX = state.screenOriginX,
           let savedScreenOriginY = state.screenOriginY,
           let screen = NSScreen.screens.first(where: {
               Self.screenIdentifier(for: $0) == savedScreenIdentifier
           }) {
            frame.origin.x += screen.visibleFrame.minX - savedScreenOriginX
            frame.origin.y += screen.visibleFrame.minY - savedScreenOriginY
            window.setFrame(Self.clamped(frame, to: screen.visibleFrame), display: false)
            return
        }

        let sufficientlyVisible = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= 200 && overlap.height >= 100
        }

        if sufficientlyVisible {
            window.setFrame(frame, display: false)
        }
    }

    static func storedStateData(for storageIdentifier: String, in defaults: UserDefaults) -> Data? {
        let key: (String) -> String = { "windowState.\($0)" }
        return defaults.data(forKey: key(storageIdentifier))
            ?? (storageIdentifier == "system-monitor"
                ? defaults.data(forKey: key("power-stats"))
                : nil)
    }

    private static func screenIdentifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    nonisolated static func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(result.width, visibleFrame.width)
        result.size.height = min(result.height, visibleFrame.height)
        result.origin.x = min(
            max(result.minX, visibleFrame.minX),
            visibleFrame.maxX - result.width
        )
        result.origin.y = min(
            max(result.minY, visibleFrame.minY),
            visibleFrame.maxY - result.height
        )
        return result
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
    let screenIdentifier: String?
    let screenOriginX: CGFloat?
    let screenOriginY: CGFloat?
}
