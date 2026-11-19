import Foundation

nonisolated final class FanHelperDaemon: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service = FanHelperXPCService()
    private let idleExit = FanHelperIdleExit()

    static func run() -> Never {
        let delegate = FanHelperDaemon()
        let listener = NSXPCListener(machServiceName: MacPowerToysHelperContract.machServiceName)
        listener.setConnectionCodeSigningRequirement(MacPowerToysHelperContract.mainAppRequirement)
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
        fatalError("Fan helper daemon stopped")
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MacPowerToysHelperXPCProtocol.self)
        connection.exportedObject = service
        idleExit.track(connection)
        service.fanLease.track(connection)
        connection.resume()
        return true
    }
}

nonisolated final class FanHelperXPCService: NSObject, MacPowerToysHelperXPCProtocol, @unchecked Sendable {
    let fanLease = FanManualLease()

    func neighborSnapshot(reply: @escaping (Data?, String) -> Void) {
        reply(nil, Bundle.main.object(forInfoDictionaryKey: "MPTSourceCommit") as? String ?? "")
    }

    func applyFanPreset(_ preset: String, reply: @escaping (String) -> Void) {
        guard let mode = FanPreset(rawValue: preset), let client = NSXPCConnection.current() else {
            reply("Unsupported fan preset.")
            return
        }
        do {
            try fanLease.apply(mode, client: ObjectIdentifier(client))
            reply("")
        } catch {
            reply(error.localizedDescription)
        }
    }

    func restartAudio(reply: @escaping (String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["coreaudiod"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            reply(error.localizedDescription)
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [weak process] in
            if process?.isRunning == true { process?.terminate() }
        }
        process.waitUntilExit()
        reply(process.terminationStatus == 0 ? "" : "Core Audio did not restart (killall exit \(process.terminationStatus)).")
    }
}

/// Ends the on-demand daemon after it served no connection for `delay` seconds. launchd starts it
/// again from the installed binary on the next request, so an app update never leaves an old daemon.
nonisolated final class FanHelperIdleExit: @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private var connections = 0
    private var generation = 0

    init(delay: TimeInterval = 30) {
        self.delay = delay
        schedule()
    }

    func track(_ connection: NSXPCConnection) {
        lock.withLock { connections += 1; generation += 1 }
        connection.invalidationHandler = { [weak self] in self?.connectionEnded() }
    }

    private func connectionEnded() {
        lock.withLock { connections -= 1; generation += 1 }
        schedule()
    }

    private func schedule() {
        let scheduled = lock.withLock { generation }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [self] in
            if lock.withLock({ connections == 0 && generation == scheduled }) { exit(0) }
        }
    }
}
