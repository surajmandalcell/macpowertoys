import Foundation
import NetToysCore

final class NetToysNeighborDaemon: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service = NetToysNeighborService()
    private let idleExit = NetToysDaemonIdleExit()

    static func run() -> Never {
        let delegate = NetToysNeighborDaemon()
        let listener = NSXPCListener(machServiceName: MacPowerToysHelperContract.neighbor.machServiceName)
        listener.setConnectionCodeSigningRequirement(MacPowerToysHelperContract.neighbor.mainAppRequirement)
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
        fatalError("NetToys neighbor daemon stopped")
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MacPowerToysHelperXPCProtocol.self)
        connection.exportedObject = service
        idleExit.track(connection)
        connection.resume()
        return true
    }
}

final class NetToysNeighborService: NSObject, MacPowerToysHelperXPCProtocol, @unchecked Sendable {
    func neighborSnapshot(reply: @escaping (Data?, String) -> Void) {
        let sourceCommit = Bundle.main.object(forInfoDictionaryKey: "MPTSourceCommit") as? String ?? ""
        reply(ARPTable.neighborCacheData(), sourceCommit)
    }

    func applyFanPreset(_ preset: String, reply: @escaping (String) -> Void) {
        guard let mode = FanPreset(rawValue: preset) else {
            reply("Unsupported fan preset.")
            return
        }
        do {
            try NativeFanReader.apply(mode)
            reply("")
        } catch {
            reply(error.localizedDescription)
        }
    }
}
