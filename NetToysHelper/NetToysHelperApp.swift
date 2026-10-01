import Darwin
import Foundation
import NetToysCore

@main
struct NetToysHelperApp {
    static func main() async {
        if geteuid() == 0 { NetToysNeighborDaemon.run() }
        guard let lock = try? NetToysProcessLock(),
              !NetToysConfigurationStore.load().backgroundRequests.isEmpty else { return }
        let runtime = NetToysHelperRuntime(owner: .macPowerToys)
        let locationAccess = await MainActor.run {
            NetToysHelperLocationAccess { state in Task { await runtime.setSSIDAccess(state) } }
        }
        await MainActor.run { locationAccess.start() }
        await runtime.run()
        withExtendedLifetime(lock) {}
    }
}
