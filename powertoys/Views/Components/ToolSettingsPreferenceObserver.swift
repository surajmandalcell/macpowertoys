import Foundation

/// Watches only the stored keys used by the visible tool's preferences.
@MainActor
final class ToolSettingsPreferenceObserver: NSObject {
    private let defaults: UserDefaults
    private var keys: Set<String>
    private var snapshot: NSDictionary
    private let changed: () -> Void

    init(keys: Set<String>, defaults: UserDefaults = .standard, changed: @escaping () -> Void) {
        self.defaults = defaults
        self.keys = keys
        self.changed = changed
        snapshot = Self.values(keys: keys, defaults: defaults)
        super.init()
        for key in keys { defaults.addObserver(self, forKeyPath: key, options: [], context: nil) }
    }

    deinit {
        for key in keys { defaults.removeObserver(self, forKeyPath: key) }
    }

    func stop() {
        for key in keys { defaults.removeObserver(self, forKeyPath: key) }
        keys.removeAll()
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                          change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [weak self] in self?.deliverChange() }
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
