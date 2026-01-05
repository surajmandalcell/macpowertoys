//
//  BackgroundService.swift
//  powertoys
//

import Foundation

protocol BackgroundService: Actor {
    var id: String { get }
    var isRunning: Bool { get }

    func start() async
    func stop() async
}

@Observable
@MainActor
final class BackgroundServiceManager {
    static let shared = BackgroundServiceManager()

    private var services: [String: any BackgroundService] = [:]
    private(set) var runningServices: Set<String> = []

    private init() {}

    func register(_ service: any BackgroundService) async {
        let id = await service.id
        services[id] = service
        LogManager.shared.debug("Registered background service: \(id)", source: "BackgroundServiceManager")
    }

    func startAll() async {
        LogManager.shared.info("Starting all background services...", source: "BackgroundServiceManager")

        for (id, _) in services {
            await start(serviceId: id)
        }
    }

    func stopAll() async {
        LogManager.shared.info("Stopping all background services...", source: "BackgroundServiceManager")

        for id in runningServices {
            await stop(serviceId: id)
        }
    }

    func start(serviceId: String) async {
        guard let service = services[serviceId] else {
            LogManager.shared.warning("Service not found: \(serviceId)", source: "BackgroundServiceManager")
            return
        }

        guard !runningServices.contains(serviceId) else {
            LogManager.shared.debug("Service already running: \(serviceId)", source: "BackgroundServiceManager")
            return
        }

        await service.start()
        runningServices.insert(serviceId)
        LogManager.shared.info("Started service: \(serviceId)", source: "BackgroundServiceManager")
    }

    func stop(serviceId: String) async {
        guard let service = services[serviceId] else { return }
        guard runningServices.contains(serviceId) else { return }

        await service.stop()
        runningServices.remove(serviceId)
        LogManager.shared.info("Stopped service: \(serviceId)", source: "BackgroundServiceManager")
    }

    func service<T: BackgroundService>(for id: String) -> T? {
        services[id] as? T
    }

    func isRunning(_ serviceId: String) -> Bool {
        runningServices.contains(serviceId)
    }
}
