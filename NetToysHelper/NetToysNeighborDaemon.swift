import Foundation

final class NetToysNeighborDaemon: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service = NetToysNeighborService()

    static func run() -> Never {
        let delegate = NetToysNeighborDaemon()
        let listener = NSXPCListener(machServiceName: NetToysNeighborServiceContract.machServiceName)
        listener.setConnectionCodeSigningRequirement(NetToysNeighborServiceContract.mainAppRequirement)
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
        fatalError("NetToys neighbor daemon stopped")
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: NetToysNeighborXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

final class NetToysNeighborService: NSObject, NetToysNeighborXPCProtocol, @unchecked Sendable {
    func neighborSnapshot(reply: @escaping (Data?, String) -> Void) {
        let sourceCommit = Bundle.main.object(forInfoDictionaryKey: "MPTSourceCommit") as? String ?? ""
        reply(ARPTable.neighborCacheData(), sourceCommit)
    }
}
