import Foundation
import Observation
import ServiceManagement

/// Registers the privileged helper daemon (fan presets and Restart audio). An app update needs no
/// re-registration: launchd starts the daemon on demand from the bundle's current binary, and a daemon
/// still running the replaced binary exits 30 s after its last connection.
@Observable
@MainActor
final class FanHelperService {
    static let shared = FanHelperService(refreshOnInit: !AppRuntime.isRunningTests)

    private(set) var status: SMAppService.Status?
    @ObservationIgnored private let service: SMAppService
    @ObservationIgnored private let readStatus: @Sendable () -> SMAppService.Status
    @ObservationIgnored private var statusGeneration = 0
    @ObservationIgnored private var checkedPendingRegistration = false
    private static let pendingRegistrationKey = "nettoys.neighbor.pendingRegistration"
    nonisolated static let legacyLoginItemIdentifier = "com.surajmandal.macpowertoys.nettoys-helper"

    init(refreshOnInit: Bool, readStatus: (@Sendable () -> SMAppService.Status)? = nil) {
        let plistName = MacPowerToysHelperContract.daemonPlistName
        service = .daemon(plistName: plistName)
        // An injected status reader never registers the real daemon.
        checkedPendingRegistration = readStatus != nil
        self.readStatus = readStatus ?? { SMAppService.daemon(plistName: plistName).status }
        if refreshOnInit { Task { await refresh() } }
    }

    var isEnabled: Bool { status == .enabled }

    @discardableResult
    func enable(openSettings: Bool = true) -> Bool {
        statusGeneration &+= 1
        do {
            let current = service.status
            if current == .notRegistered || current == .notFound { try service.register() }
        } catch {
            LogManager.shared.warning("Fan helper registration failed: \(error.localizedDescription)", source: "FanHelper")
        }
        status = service.status
        guard status == .enabled else {
            if openSettings { SMAppService.openSystemSettingsLoginItems() }
            return false
        }
        return true
    }

    /// Re-reads the Login Items approval. A read that an enable or restart overtook is dropped.
    func refresh() async {
        let generation = statusGeneration
        let status = await Task.detached(priority: .utility, operation: readStatus).value
        guard generation == statusGeneration else { return }
        if self.status != status { self.status = status }
        if status == .notRegistered { await finishPendingRegistrationOnce() }
    }

    /// Re-registers the daemon. Call only when the running helper reports another build than this app:
    /// macOS can show the Background Items notice again on every register.
    func restart() async throws {
        statusGeneration &+= 1
        defer { Task { await refresh() } }
        UserDefaults.standard.set(true, forKey: Self.pendingRegistrationKey)
        try await service.unregister()
        try await registerAfterUnregister()
    }

    /// The NetToys tool registered the same helper as a login item for its background work. That work
    /// left with the tool, so remove a login item that an older build left registered.
    nonisolated static func retireLegacyLoginItem() async {
        guard !AppRuntime.isRunningTests else { return }
        let item = SMAppService.loginItem(identifier: legacyLoginItemIdentifier)
        guard item.status == .enabled || item.status == .requiresApproval else { return }
        do { try await item.unregister() } catch {
            await LogManager.shared.warning("Old helper login item stays registered: \(error.localizedDescription)",
                                            source: "FanHelper")
        }
    }

    /// A restart that macOS refused to re-register leaves a pending flag; finish it on the next launch.
    private func finishPendingRegistrationOnce() async {
        guard !checkedPendingRegistration, UserDefaults.standard.bool(forKey: Self.pendingRegistrationKey) else { return }
        checkedPendingRegistration = true
        do { try await registerAfterUnregister() } catch {
            LogManager.shared.warning("Fan helper registration failed: \(error.localizedDescription)", source: "FanHelper")
        }
        status = service.status
    }

    /// macOS can refuse a register that follows an unregister until it finishes the removal, so retry briefly.
    private func registerAfterUnregister() async throws {
        var lastError: (any Error)?
        for attempt in 0..<6 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            do { try service.register() } catch { lastError = error }
            if service.status == .enabled || service.status == .requiresApproval {
                UserDefaults.standard.removeObject(forKey: Self.pendingRegistrationKey)
                return
            }
        }
        if let lastError { throw lastError }
    }
}
