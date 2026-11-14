import Darwin
import Foundation
import NetToysCore

@main
struct NetToysHelperApp {
    static func main() async {
        if geteuid() == 0 { NetToysNeighborDaemon.run() }
        let runtime = NetToysHelperRuntime(owner: .macPowerToys)
        var locationAccess: NetToysHelperLocationAccess?
        // launchd relaunches a login item that exits, so wait idle until work or the lock appears.
        while true {
            if let lock = try? NetToysProcessLock(),
               !NetToysConfigurationStore.load().backgroundRequests.isEmpty {
                if locationAccess == nil {
                    let access = await MainActor.run {
                        NetToysHelperLocationAccess { state in Task { await runtime.setSSIDAccess(state) } }
                    }
                    await MainActor.run { access.start() }
                    locationAccess = access
                }
                await runtime.run()
                withExtendedLifetime(lock) {}
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
