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

    private init() {}

    var status: SMAppService.Status { service.status }
    var isEnabled: Bool { status == .enabled }

    @discardableResult
    func enable(openSettings: Bool = true) -> Bool {
        errorMessage = nil
        do {
            if status == .notRegistered || status == .notFound { try service.register() }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
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

    func refresh() { revision &+= 1 }
}
