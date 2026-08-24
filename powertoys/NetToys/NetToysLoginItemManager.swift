import AppKit
import Observation
import ServiceManagement

@Observable
@MainActor
final class NetToysLoginItemManager {
    static let shared = NetToysLoginItemManager()
    static let helperIdentifier = "com.surajmandal.macpowertoys.nettoys-helper"

    private let service = SMAppService.loginItem(identifier: helperIdentifier)
    private(set) var errorMessage: String?

    private init() {}

    var status: SMAppService.Status { service.status }

    func setEnabled(_ enabled: Bool) async -> Bool {
        errorMessage = nil
        return enabled ? await enable() : await disable()
    }

    nonisolated static func hasFreshHeartbeat(
        _ status: NetToysHelperStatus?,
        now: Date = Date()
    ) -> Bool {
        guard let status else { return false }
        return now.timeIntervalSince(status.heartbeat) <= 7
    }

    private func enable() async -> Bool {
        if service.status == .enabled,
           Self.hasFreshHeartbeat(NetToysConfigurationStore.status()) {
            return true
        }
        do {
            if service.status == .enabled { try await service.unregister() }
            try? FileManager.default.removeItem(at: NetToysPaths.helperStatus)
            if !FileManager.default.fileExists(atPath: NetToysPaths.configuration.path) {
                try NetToysConfigurationStore.save(NetToysConfiguration())
            }
            try service.register()
        } catch {
            errorMessage = error.localizedDescription
            try? await service.unregister()
            return false
        }

        if service.status == .requiresApproval {
            errorMessage = "Allow NetToys Helper in System Settings to enable NetToys."
            SMAppService.openSystemSettingsLoginItems()
            return false
        }
        guard service.status == .enabled else {
            errorMessage = "macOS did not enable NetToys Helper."
            try? await service.unregister()
            return false
        }
        for _ in 0..<32 {
            if Self.hasFreshHeartbeat(NetToysConfigurationStore.status()) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        errorMessage = "NetToys Helper did not start."
        try? await service.unregister()
        return false
    }

    private func disable() async -> Bool {
        do {
            if service.status != .notRegistered { try await service.unregister() }
            try? FileManager.default.removeItem(at: NetToysPaths.helperStatus)
            return service.status == .notRegistered
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
