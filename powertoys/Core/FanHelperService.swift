import Foundation
import Observation
import ServiceManagement

/// Registers and repairs the privileged fan helper daemon. Fan control is its only client.
@Observable
@MainActor
final class FanHelperService {
    static let shared = FanHelperService(refreshOnInit: !AppRuntime.isRunningTests)

    private(set) var status: SMAppService.Status?
    @ObservationIgnored private let service: SMAppService
    @ObservationIgnored private let readStatus: @Sendable () -> SMAppService.Status
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var checkedForStaleDaemon = false
    @ObservationIgnored private var checkedPendingRegistration = false
    private static let pendingRegistrationKey = "nettoys.neighbor.pendingRegistration"
    nonisolated static let legacyLoginItemIdentifier = "com.surajmandal.macpowertoys.nettoys-helper"

    init(refreshOnInit: Bool, readStatus: (@Sendable () -> SMAppService.Status)? = nil) {
        let plistName = MacPowerToysHelperContract.daemonPlistName
        service = .daemon(plistName: plistName)
        // An injected status reader never repairs or registers the real daemon.
        checkedForStaleDaemon = readStatus != nil
        checkedPendingRegistration = readStatus != nil
        self.readStatus = readStatus ?? { SMAppService.daemon(plistName: plistName).status }
        if refreshOnInit { refresh() }
    }

    var isEnabled: Bool { status == .enabled }

    @discardableResult
    func enable(openSettings: Bool = true) -> Bool {
        refreshTask?.cancel()
        refreshTask = nil
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

    func refresh() {
        guard refreshTask == nil else { return }
        let readStatus = readStatus
        refreshTask = Task { [weak self] in
            let status = await Task.detached(priority: .utility, operation: readStatus).value
            guard !Task.isCancelled, let self else { return }
            self.status = status
            self.refreshTask = nil
            if status == .enabled { await self.repairStaleDaemonOnce() }
            if status == .notRegistered { await self.finishPendingRegistrationOnce() }
        }
    }

    func restart() async throws {
        refreshTask?.cancel()
        refreshTask = nil
        defer { refresh() }
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

    /// An approved daemon keeps running across app updates, and its replaced binary then fails the
    /// code-signing check. Restart it once per launch.
    private func repairStaleDaemonOnce() async {
        guard !checkedForStaleDaemon else { return }
        checkedForStaleDaemon = true
        guard await Task.detached(priority: .utility, operation: { FanCommand.helperIsStale() }).value else { return }
        do { try await restart() } catch {
            LogManager.shared.warning("Fan helper restart failed: \(error.localizedDescription)", source: "FanHelper")
        }
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
