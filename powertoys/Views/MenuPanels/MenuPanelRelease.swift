import Foundation

/// Closed menu panels keep their view tree for a short time so a warm reopen stays within 100 ms.
@MainActor
final class MenuPanelRelease {
    static let standardDelay: Duration = .seconds(60)
    static let shared = MenuPanelRelease()

    private let delay: Duration
    private var tasks: [String: Task<Void, Never>] = [:]

    init(delay: Duration = MenuPanelRelease.standardDelay) {
        self.delay = delay
    }

    var pendingCount: Int { tasks.count }

    func schedule(_ key: String, release: @escaping () -> Void) {
        tasks[key]?.cancel()
        tasks[key] = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.tasks[key] = nil
            release()
        }
    }

    func cancel(_ key: String) {
        tasks.removeValue(forKey: key)?.cancel()
    }
}
