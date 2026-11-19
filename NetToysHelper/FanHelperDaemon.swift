import Foundation

nonisolated final class FanHelperDaemon: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service = FanHelperXPCService()
    private let idleExit: FanHelperIdleExit

    override init() {
        idleExit = FanHelperIdleExit { [service] in service.fanLease.hasOwner }
        super.init()
    }

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
    private let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))

    override init() {
        super.init()
        watchdog.schedule(deadline: .now() + 5, repeating: 5)
        watchdog.setEventHandler { [fanLease] in fanLease.expireIfIdle() }
        watchdog.resume()
    }

    func neighborSnapshot(reply: @escaping (Data?, String) -> Void) {
        reply(nil, Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
    }

    func writeFanKey(_ key: String, value: Double, reply: @escaping (String) -> Void) {
        guard let client = NSXPCConnection.current() else {
            reply("The fan helper could not identify the caller.")
            return
        }
        reply(fanLease.write(key, value: value, client: ObjectIdentifier(client)))
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
/// It stays while `keepAlive` is true, so a pending fan restore keeps its watchdog.
nonisolated final class FanHelperIdleExit: @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private let keepAlive: @Sendable () -> Bool
    private var connections = 0
    private var generation = 0

    init(delay: TimeInterval = 30, keepAlive: @escaping @Sendable () -> Bool = { false }) {
        self.delay = delay
        self.keepAlive = keepAlive
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
            guard lock.withLock({ connections == 0 && generation == scheduled }) else { return }
            if keepAlive() { schedule() } else { exit(0) }
        }
    }
}
