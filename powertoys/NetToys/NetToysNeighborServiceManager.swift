import Observation
import ServiceManagement

@Observable
@MainActor
final class NetToysNeighborServiceManager {
    static let shared = NetToysNeighborServiceManager()

    private let service = SMAppService.daemon(
        plistName: NetToysNeighborServiceContract.daemonPlistName
    )
    private(set) var revision = 0
    private(set) var errorMessage: String?
    private(set) var status: SMAppService.Status?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let readStatus: @Sendable () -> SMAppService.Status

    init(readStatus: @escaping @Sendable () -> SMAppService.Status = {
        SMAppService.daemon(plistName: NetToysNeighborServiceContract.daemonPlistName).status
    }) {
        self.readStatus = readStatus
        refresh()
    }

    var isEnabled: Bool { status == .enabled }

    @discardableResult
    func enable(openSettings: Bool = true) -> Bool {
        refreshTask?.cancel()
        refreshTask = nil
        errorMessage = nil
        do {
            let current = service.status
            if current == .notRegistered || current == .notFound { try service.register() }
        } catch {
            errorMessage = error.localizedDescription
        }
        status = service.status
        revision &+= 1
        guard status == .enabled else {
            if errorMessage == nil {
                errorMessage = status == .requiresApproval
                    ? "Allow MAC Address Access in System Settings > Login Items."
                    : "macOS could not start MAC Address Access."
            }
            if openSettings { SMAppService.openSystemSettingsLoginItems() }
            return false
        }
        return true
    }

    func refresh() {
        guard refreshTask == nil else { return }
        let readStatus = readStatus
        refreshTask = Task { [weak self] in
            let status = await Task.detached(priority: .utility, operation: readStatus).value
            guard !Task.isCancelled, let self else { return }
            self.status = status
            self.revision &+= 1
            self.refreshTask = nil
        }
    }

    func restart() async throws {
        refreshTask?.cancel()
        refreshTask = nil
        defer { refresh() }
        try await service.unregister()
        try service.register()
    }
}
