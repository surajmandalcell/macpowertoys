import Foundation

/// Watches only the stored keys used by the visible tool's preferences.
@MainActor
final class ToolSettingsPreferenceObserver {
    private let defaults: UserDefaults
    private var keys: Set<String>
    private var snapshot: NSDictionary
    private let changed: () -> Void
    private var observer: NSObjectProtocol?

    init(keys: Set<String>, defaults: UserDefaults = .standard, changed: @escaping () -> Void) {
        self.defaults = defaults
        self.keys = keys
        self.changed = changed
        snapshot = Self.values(keys: keys, defaults: defaults)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliverChange() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        keys.removeAll()
    }

    private func deliverChange() {
        guard !keys.isEmpty else { return }
        let current = Self.values(keys: keys, defaults: defaults)
        guard current != snapshot else { return }
        snapshot = current
        changed()
    }

    private static func values(keys: Set<String>, defaults: UserDefaults) -> NSDictionary {
        NSDictionary(dictionary: keys.reduce(into: [String: Any]()) { result, key in
            result[key] = defaults.object(forKey: key)
        })
    }
}
