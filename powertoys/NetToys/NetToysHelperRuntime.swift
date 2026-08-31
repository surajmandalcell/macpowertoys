import Foundation

nonisolated enum SSHAnchorVerifiedUpdate {
    enum UpdateError: LocalizedError, Equatable {
        case candidateProbeFailed
        case postWriteProbeFailed
        case rollbackFailed

        var errorDescription: String? {
            switch self {
            case .candidateProbeFailed:
                "The recovered address did not pass its confirmation probe."
            case .postWriteProbeFailed:
                "The recovered address stopped responding, so SSH Anchor restored the original address."
            case .rollbackFailed:
                "The recovered address failed verification, and SSH Anchor could not restore the original address."
            }
        }
    }

    static func apply(
        original: SSHAnchorConfiguration,
        recovered: SSHAnchorConfiguration,
        configURL: URL,
        backupDirectory: URL,
        verify: @escaping @Sendable (String, UInt16) async -> Bool,
        commit: @escaping @Sendable () throws -> Void
    ) async throws {
        guard await verify(recovered.hostName, recovered.port) else {
            throw UpdateError.candidateProbeFailed
        }
        _ = try SSHConfigFileUpdater.update(
            configURL: configURL,
            backupDirectory: backupDirectory,
            hostAlias: original.hostAlias,
            expectedHostName: original.hostName,
            newHostName: recovered.hostName
        )
        do {
            guard await verify(recovered.hostName, recovered.port) else {
                throw UpdateError.postWriteProbeFailed
            }
            try commit()
        } catch {
            do {
                _ = try SSHConfigFileUpdater.update(
                    configURL: configURL,
                    backupDirectory: backupDirectory,
                    hostAlias: original.hostAlias,
                    expectedHostName: recovered.hostName,
                    newHostName: original.hostName
                )
            } catch {
                throw UpdateError.rollbackFailed
            }
            throw error
        }
    }
}

actor NetToysHelperRuntime {
    private let scanner = NetToysScanner()
    private var recoveryFailures: [UUID: Int] = [:]
    private var nextRecovery: [UUID: Date] = [:]
    private var routeMonitors: [UUID: SSHAnchorRouteMonitor] = [:]
    private var nextTailscaleAttempt: [UUID: Date] = [:]
    private var preparedAnchorPolicies = Set<UUID>()
    private var historyRecorder = NetworkTransitionRecorder()
    private var lastHistoryCheck = Date.distantPast
    private var networkSnapshot: NetworkRuntimeSnapshot?
    private var currentStatuses: [SSHAnchorStatus] = []
    private var ssidAccess: NetToysSSIDAccessState?
    private var wifiFailoverMonitor = WiFiFailoverMonitor()
    private var wifiFailoverStatus: WiFiFailoverStatus?

    func setSSIDAccess(_ state: NetToysSSIDAccessState) async {
        ssidAccess = state
        if state == .allowed { await checkNetwork(NetToysConfigurationStore.load()) }
        writeStatus()
    }

    func run() async {
        let heartbeat = Task { await heartbeatLoop() }
        defer { heartbeat.cancel() }
        saveStatus([])
        while !Task.isCancelled {
            let configuration = NetToysConfigurationStore.load()
            await tick(configuration)
            try? await Task.sleep(for: .seconds(configuration.probeInterval))
        }
    }

    private func tick(_ configuration: NetToysConfiguration) async {
        var statuses: [SSHAnchorStatus] = []
        for anchor in configuration.anchors {
            statuses.append(await check(anchor))
        }
        if configuration.wifiPriority.isEnabled
            || (configuration.recordsNetworkHistory
                && Date().timeIntervalSince(lastHistoryCheck) >= 30) {
            lastHistoryCheck = Date()
            await checkNetwork(configuration)
        } else if !configuration.wifiPriority.isEnabled {
            wifiFailoverMonitor = WiFiFailoverMonitor()
            wifiFailoverStatus = nil
        }
        saveStatus(statuses)
    }

    private func check(_ configuredAnchor: SSHAnchorConfiguration) async -> SSHAnchorStatus {
        guard configuredAnchor.isEnabled else { return status(configuredAnchor, .idle) }
        do {
            try prepareHostKeyPolicy(configuredAnchor)
        } catch {
            return status(configuredAnchor, .error, error.localizedDescription)
        }
        let anchor = synchronizedAnchor(configuredAnchor)
        if anchor.route == .tailscale { return await checkTailscale(anchor) }
        let probe = await TCPPortProbe.check(host: anchor.hostName, port: anchor.port, timeoutMilliseconds: 900)
        var routeMonitor = routeMonitors[anchor.id] ?? SSHAnchorRouteMonitor()
        let routeAction = routeMonitor.observe(
            route: .local,
            localIsOpen: probe.state == .open,
            at: Date()
        )
        routeMonitors[anchor.id] = routeMonitor
        if probe.state == .open {
            recoveryFailures[anchor.id] = nil
            nextRecovery[anchor.id] = nil
            nextTailscaleAttempt[anchor.id] = nil
            return status(anchor, .healthy)
        }
        if anchor.tailscaleFallback?.isEnabled == true,
           routeAction == .useTailscale,
           nextTailscaleAttempt[anchor.id].map({ $0 <= Date() }) ?? true {
            return await switchToTailscale(anchor)
        }
        if let next = nextRecovery[anchor.id], next > Date() {
            return status(anchor, .unavailable, "The port is unavailable. The next local scan is scheduled.")
        }
        return await recover(anchor)
    }

    private func checkTailscale(_ anchor: SSHAnchorConfiguration) async -> SSHAnchorStatus {
        let tailscaleProbe = await TCPPortProbe.check(
            host: anchor.hostName,
            port: anchor.port,
            timeoutMilliseconds: 900
        )
        let date = Date()
        var routeMonitor = routeMonitors[anchor.id] ?? SSHAnchorRouteMonitor()
        var recovered: SSHAnchorConfiguration?
        var localIsOpen = false

        if let localHostName = anchor.localHostName,
           let network = LocalIPv4Network.active(),
           network.contains(localHostName) {
            localIsOpen = await TCPPortProbe.check(
                host: localHostName,
                port: anchor.port,
                timeoutMilliseconds: 900
            ).state == .open
        }

        var action = routeMonitor.observe(
            route: .tailscale,
            localIsOpen: localIsOpen,
            at: date
        )
        if localIsOpen,
           action == .useLocal,
           let localHostName = anchor.localHostName {
            recovered = await verifiedLocalCandidate(anchor, hostName: localHostName)
            if recovered == nil {
                _ = routeMonitor.observe(route: .tailscale, localIsOpen: false, at: date)
            }
        }

        if recovered == nil,
           !localIsOpen,
           nextRecovery[anchor.id].map({ $0 <= date }) ?? true {
            recovered = await discoverLocalCandidate(anchor)
            if var discovered = recovered {
                var metadata = anchor
                metadata.localHostName = discovered.hostName
                saveAnchorMetadata(metadata, expectedHostName: anchor.hostName)
                discovered.localHostName = discovered.hostName
                recovered = discovered
                action = routeMonitor.observe(route: .tailscale, localIsOpen: true, at: date)
                if action != .useLocal,
                   tailscaleProbe.state == .open,
                   anchor.tailscaleFallback?.isEnabled == true {
                    recovered = nil
                }
            }
        }
        routeMonitors[anchor.id] = routeMonitor

        if let recovered {
            return await switchToLocal(anchor, recovered: recovered)
        }
        if tailscaleProbe.state == .open {
            let message = anchor.tailscaleFallback?.isEnabled == true
                ? "Using Tailscale while the helper confirms the local connection."
                : "Tailscale fallback is off. Waiting for the local connection."
            return status(anchor, .fallback, message)
        }
        if nextTailscaleAttempt[anchor.id].map({ $0 <= date }) ?? true {
            return await switchToTailscale(anchor)
        }
        return status(anchor, .unavailable, "Neither the local nor Tailscale endpoint is reachable.")
    }

    private func switchToTailscale(_ anchor: SSHAnchorConfiguration) async -> SSHAnchorStatus {
        guard let fallback = anchor.tailscaleFallback else {
            return status(anchor, .unavailable)
        }
        do {
            let peers = try await TailscalePeerCatalog.load()
            guard let endpoint = TailscalePeerCatalog.endpoint(
                nodeID: fallback.nodeID,
                peers: peers,
                isEnabled: fallback.isEnabled
            ) else {
                throw TailscalePeerCatalog.CatalogError.peerNotFound
            }
            var recovered = anchor
            recovered.localHostName = anchor.route == .local ? anchor.hostName : anchor.localHostName
            recovered.hostName = endpoint.ipAddress
            recovered.tailscaleFallback = endpoint
            try await applyVerifiedChange(original: anchor, recovered: recovered)
            var routeMonitor = routeMonitors[anchor.id] ?? SSHAnchorRouteMonitor()
            routeMonitor.didSwitch(to: .tailscale, at: Date())
            routeMonitors[anchor.id] = routeMonitor
            recoveryFailures[anchor.id] = nil
            nextRecovery[anchor.id] = nil
            nextTailscaleAttempt[anchor.id] = nil
            return status(recovered, .fallback, "The local endpoint is unavailable. Using Tailscale.")
        } catch {
            nextTailscaleAttempt[anchor.id] = Date().addingTimeInterval(30)
            return status(anchor, .fallbackUnavailable, error.localizedDescription)
        }
    }

    private func switchToLocal(
        _ anchor: SSHAnchorConfiguration,
        recovered: SSHAnchorConfiguration
    ) async -> SSHAnchorStatus {
        var local = recovered
        local.localHostName = local.hostName
        local.tailscaleFallback = anchor.tailscaleFallback
        do {
            try await applyVerifiedChange(original: anchor, recovered: local)
            var routeMonitor = routeMonitors[anchor.id] ?? SSHAnchorRouteMonitor()
            routeMonitor.didSwitch(to: .local, at: Date())
            routeMonitors[anchor.id] = routeMonitor
            recoveryFailures[anchor.id] = nil
            nextRecovery[anchor.id] = nil
            nextTailscaleAttempt[anchor.id] = nil
            return status(local, .recovered, "The local connection is back. Tailscale is on standby.")
        } catch {
            scheduleRetry(for: anchor.id)
            return status(anchor, .error, error.localizedDescription)
        }
    }

    private func recover(_ anchor: SSHAnchorConfiguration) async -> SSHAnchorStatus {
        let route = await DefaultRoute.load()
        guard let network = LocalIPv4Network.active(preferredInterfaceName: route?.interfaceName) else {
            scheduleRetry(for: anchor.id)
            return status(anchor, .unavailable, "No active local IPv4 network was found.")
        }
        let targets: [IPv4Address]
        do {
            targets = try network.targets(limit: 1_024)
        } catch {
            scheduleRetry(for: anchor.id)
            return status(anchor, .error, error.localizedDescription)
        }
        saveStatus([status(anchor, .scanning, "Searching \(network.cidr) on port \(anchor.port).")])
        let results = await scanner.scan(
            targets: targets,
            ports: [anchor.port],
            timeoutMilliseconds: 600,
            concurrency: 64
        )
        guard var recovered = SSHAnchorRecovery.resolve(anchor: anchor, scanResults: results) else {
            scheduleRetry(for: anchor.id)
            return status(anchor, .notFound, "No unique device matched this anchor.")
        }
        recovered.localHostName = recovered.hostName
        if recovered.hostName == anchor.hostName {
            recoveryFailures[anchor.id] = nil
            nextRecovery[anchor.id] = nil
            return status(recovered, .healthy)
        }
        do {
            try await applyVerifiedChange(original: anchor, recovered: recovered)
            recoveryFailures[anchor.id] = nil
            nextRecovery[anchor.id] = nil
            return status(recovered, .recovered, "Updated only HostName in ~/.ssh/config.")
        } catch {
            scheduleRetry(for: anchor.id)
            return status(anchor, .error, error.localizedDescription)
        }
    }

    private func verifiedLocalCandidate(
        _ anchor: SSHAnchorConfiguration,
        hostName: String
    ) async -> SSHAnchorConfiguration? {
        guard let address = IPv4Address(hostName) else { return nil }
        let results = await scanner.scan(
            targets: [address],
            ports: [anchor.port],
            timeoutMilliseconds: 600,
            concurrency: 1
        )
        return SSHAnchorRecovery.resolve(anchor: anchor, scanResults: results)
    }

    private func discoverLocalCandidate(_ anchor: SSHAnchorConfiguration) async -> SSHAnchorConfiguration? {
        let route = await DefaultRoute.load()
        guard let network = LocalIPv4Network.active(preferredInterfaceName: route?.interfaceName),
              let targets = try? network.targets(limit: 1_024)
        else {
            scheduleRetry(for: anchor.id)
            return nil
        }
        let results = await scanner.scan(
            targets: targets,
            ports: [anchor.port],
            timeoutMilliseconds: 600,
            concurrency: 64
        )
        guard let recovered = SSHAnchorRecovery.resolve(anchor: anchor, scanResults: results) else {
            scheduleRetry(for: anchor.id)
            return nil
        }
        recoveryFailures[anchor.id] = nil
        nextRecovery[anchor.id] = nil
        return recovered
    }

    private func applyVerifiedChange(
        original: SSHAnchorConfiguration,
        recovered: SSHAnchorConfiguration
    ) async throws {
        let latest = NetToysConfigurationStore.load()
        guard let current = latest.anchors.first(where: { $0.id == original.id }),
              current.hostName == original.hostName
        else { throw NetToysConfiguration.ConfigurationError.anchorNotFound }
        let updated = try latest.replacingAnchor(recovered)
        try await SSHAnchorVerifiedUpdate.apply(
            original: original,
            recovered: recovered,
            configURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config"),
            backupDirectory: NetToysPaths.backups,
            verify: { host, port in
                await TCPPortProbe.check(host: host, port: port, timeoutMilliseconds: 900).state == .open
            },
            commit: { try NetToysConfigurationStore.save(updated) }
        )
    }

    private func saveAnchorMetadata(
        _ anchor: SSHAnchorConfiguration,
        expectedHostName: String
    ) {
        let latest = NetToysConfigurationStore.load()
        guard let current = latest.anchors.first(where: { $0.id == anchor.id }),
              current.hostName == expectedHostName,
              let updated = try? latest.replacingAnchor(anchor)
        else { return }
        try? NetToysConfigurationStore.save(updated)
    }

    private func synchronizedAnchor(_ anchor: SSHAnchorConfiguration) -> SSHAnchorConfiguration {
        let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        guard let data = try? Data(contentsOf: configURL),
              let entry = SSHConfigEditor.entries(in: data).first(where: {
                  $0.aliases.contains { $0.caseInsensitiveCompare(anchor.hostAlias) == .orderedSame }
              }), entry.hostName != anchor.hostName
        else { return anchor }
        var copy = anchor
        copy.hostName = entry.hostName
        if copy.route == .local { copy.localHostName = entry.hostName }
        let configuration = NetToysConfigurationStore.load()
        if let updated = try? configuration.replacingAnchor(copy) {
            try? NetToysConfigurationStore.save(updated)
        }
        return copy
    }

    private func prepareHostKeyPolicy(_ anchor: SSHAnchorConfiguration) throws {
        guard !preparedAnchorPolicies.contains(anchor.id) else { return }
        _ = try SSHConfigFileUpdater.prepareAnchor(
            configURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config"),
            backupDirectory: NetToysPaths.backups,
            hostAlias: anchor.hostAlias,
            knownHostsAlias: anchor.knownHostsAlias
        )
        preparedAnchorPolicies.insert(anchor.id)
    }

    private func scheduleRetry(for id: UUID) {
        let failures = min((recoveryFailures[id] ?? 0) + 1, 5)
        recoveryFailures[id] = failures
        let seconds = min(30 * (1 << (failures - 1)), 300)
        nextRecovery[id] = Date().addingTimeInterval(TimeInterval(seconds))
    }

    private func checkNetwork(_ configuration: NetToysConfiguration) async {
        guard let route = await DefaultRoute.load() else {
            recordNetwork(
                networkID: "disconnected",
                ssid: nil,
                gateway: .unknown,
                internet: .unknown,
                shouldRecordHistory: configuration.recordsNetworkHistory
            )
            await updateWiFiFailover(
                configuration.wifiPriority,
                currentSSID: nil,
                isFailure: true,
                hasActiveRoute: false
            )
            return
        }
        async let gateway = NetworkProbe.gateway(route.gateway)
        async let internet = NetworkProbe.internet()
        let ssid = NetworkSSID.current(interfaceName: route.interfaceName)
        let internetState = await internet
        recordNetwork(
            networkID: route.networkID,
            ssid: ssid,
            usesSSIDIdentity: NetworkSSID.isWiFi(interfaceName: route.interfaceName),
            gateway: await gateway,
            internet: internetState,
            shouldRecordHistory: configuration.recordsNetworkHistory
        )
        await updateWiFiFailover(
            configuration.wifiPriority,
            currentSSID: ssid,
            isFailure: internetState == .unreachable,
            hasActiveRoute: true
        )
    }

    private func updateWiFiFailover(
        _ configuration: WiFiPriorityConfiguration,
        currentSSID: String?,
        isFailure: Bool,
        hasActiveRoute: Bool
    ) async {
        guard configuration.isEnabled else { return }
        let date = Date()
        guard !(hasActiveRoute && currentSSID == nil) else {
            wifiFailoverStatus = WiFiFailoverStatus(
                state: .failed,
                message: "The helper needs the Wi-Fi network name before it can switch networks.",
                updatedAt: date
            )
            return
        }
        guard wifiFailoverMonitor.shouldAttempt(
            isFailure: isFailure,
            threshold: configuration.outageThreshold,
            at: date
        ) else {
            wifiFailoverStatus = WiFiFailoverStatus(
                state: isFailure ? .waiting : .monitoring,
                message: isFailure
                    ? "Internet is unavailable. Waiting before failover."
                    : "Internet is reachable.",
                updatedAt: date
            )
            return
        }
        wifiFailoverMonitor.didAttempt(at: date)
        wifiFailoverStatus = WiFiFailoverStatus(
            state: .switching,
            message: "Looking for the next saved Wi-Fi network.",
            updatedAt: date
        )
        writeStatus()
        let availableSSIDs = await WiFiNetworkController.availableSSIDs()
        guard let target = WiFiFailoverMonitor.nextSSID(
            after: currentSSID,
            priorities: configuration.ssids,
            availableSSIDs: availableSSIDs
        ) else {
            wifiFailoverStatus = WiFiFailoverStatus(
                state: .failed,
                message: "No configured backup Wi-Fi network is nearby. macOS can try Instant Hotspot next.",
                updatedAt: Date()
            )
            return
        }
        do {
            try await WiFiNetworkController.join(target)
            wifiFailoverStatus = WiFiFailoverStatus(
                state: .switching,
                message: "Joined \(target). Checking Internet access.",
                updatedAt: Date()
            )
        } catch {
            wifiFailoverStatus = WiFiFailoverStatus(
                state: .failed,
                message: error.localizedDescription,
                updatedAt: Date()
            )
        }
    }

    private func recordNetwork(
        networkID: String,
        ssid: String?,
        usesSSIDIdentity: Bool = false,
        gateway: NetworkReachability,
        internet: NetworkReachability,
        shouldRecordHistory: Bool = true
    ) {
        let date = Date()
        networkSnapshot = NetworkRuntimeSnapshot(
            networkID: networkID,
            ssid: ssid,
            gateway: gateway,
            internet: internet,
            checkedAt: date
        )
        guard shouldRecordHistory,
              let event = historyRecorder.observe(
            networkID: networkID,
            ssid: ssid,
            usesSSIDIdentity: usesSSIDIdentity,
            gateway: gateway,
            internet: internet,
            at: date
        ) else { return }
        var history = NetToysConfigurationStore.history()
        history.append(event)
        try? NetToysConfigurationStore.saveHistory(history)
    }

    private func status(
        _ anchor: SSHAnchorConfiguration,
        _ state: SSHAnchorRuntimeState,
        _ message: String? = nil
    ) -> SSHAnchorStatus {
        SSHAnchorStatus(
            anchorID: anchor.id,
            state: state,
            currentHostName: anchor.hostName,
            lastCheck: Date(),
            message: message
        )
    }

    private func saveStatus(_ anchors: [SSHAnchorStatus]) {
        currentStatuses = anchors
        writeStatus()
    }

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            writeStatus()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func writeStatus() {
        try? NetToysConfigurationStore.saveStatus(
            NetToysHelperStatus(
                version: 1,
                heartbeat: Date(),
                anchors: currentStatuses,
                network: networkSnapshot,
                sourceCommit: Bundle.main.object(forInfoDictionaryKey: "MPTSourceCommit") as? String,
                ssidAccess: ssidAccess,
                wifiFailover: wifiFailoverStatus
            )
        )
    }
}

nonisolated enum NetworkProbe {
    static func gateway(_ host: String) async -> NetworkReachability {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-n", "-c", "1", "-W", "1000", host]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0 ? .reachable : .unreachable
            } catch {
                return .unknown
            }
        }.value
    }

    static func internet() async -> NetworkReachability {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return .unknown }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .unknown }
            return (200..<400).contains(response.statusCode) ? .reachable : .unreachable
        } catch {
            return .unreachable
        }
    }
}
