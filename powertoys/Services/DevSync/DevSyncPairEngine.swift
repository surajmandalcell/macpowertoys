import Foundation

nonisolated struct DevMutationActivity: Sendable {
    let perform: @Sendable (@escaping @Sendable () async -> DevOperationOutcome) async -> DevOperationOutcome

    func callAsFunction(
        _ operation: @escaping @Sendable () async -> DevOperationOutcome
    ) async -> DevOperationOutcome {
        await perform(operation)
    }

    static let live = DevMutationActivity { operation in
        let activity = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: "Dev Sync")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        return await operation()
    }
}

actor DevVolumeMutationGate {
    static let shared = DevVolumeMutationGate()

    private var active: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ volumeIdentifier: String) async {
        if active.insert(volumeIdentifier).inserted { return }
        await withCheckedContinuation { continuation in
            waiters[volumeIdentifier, default: []].append(continuation)
        }
    }

    func release(_ volumeIdentifier: String) {
        guard var queued = waiters[volumeIdentifier], !queued.isEmpty else {
            active.remove(volumeIdentifier)
            waiters[volumeIdentifier] = nil
            return
        }
        let next = queued.removeFirst()
        waiters[volumeIdentifier] = queued.isEmpty ? nil : queued
        next.resume()
    }
}

actor DevSyncPairEngine {
    private var pair: DevSyncPair
    private let stateStore: DevSyncStateStore
    private let rsyncExecutable: URL
    private let emit: @Sendable (DevSyncUpdate) -> Void
    private let now: @Sendable () -> Date
    private let lowPowerModeEnabled: @Sendable () -> Bool
    private let withMutationActivity: DevMutationActivity
    private var statusValue: DevPairStatus
    private var projectValues: [DevProject] = []
    private var conflictValues: [DevConflict] = []
    private var linkValues: [DevManagedLink] = []
    private var capabilityValue = DevPairCapabilities()
    private var internalRoot: URL?
    private var externalRoot: URL?
    private var scheduler: DevDirtyScheduler
    private var internalStream: DevEventStream?
    private var externalStream: DevEventStream?
    private var schedulerLoop: Task<Void, Never>?
    private var activeRunner: DevOperationRunner?
    private var activeGeneration: DevDirtyGeneration?
    private var running = false
    private var paused = false
    private var volumeOnline = false
    private var unmounting = false
    private var notifiedKinds: Set<String> = []
    private var lastRetentionAt: Date?
    private var bytesDay = Calendar.current.startOfDay(for: Date())
    private let ledger = DevSelfEventLedger()
    private var safetyStore: DevSafetyStore
    private var linkManager: DevManagedLinkManager

    init(
        pair: DevSyncPair,
        stateStore: DevSyncStateStore,
        rsyncExecutable: URL,
        emit: @escaping @Sendable (DevSyncUpdate) -> Void,
        now: @escaping @Sendable () -> Date = Date.init,
        lowPowerModeEnabled: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        withMutationActivity: DevMutationActivity = .live
    ) {
        self.pair = pair
        self.stateStore = stateStore
        self.rsyncExecutable = rsyncExecutable
        self.emit = emit
        self.now = now
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.withMutationActivity = withMutationActivity
        statusValue = DevPairStatus(pairID: pair.id, state: pair.state)
        scheduler = DevDirtyScheduler(timing: pair.configuration.timing, performance: pair.configuration.performance, now: now)
        safetyStore = DevSafetyStore(pair: pair, stateStore: stateStore)
        linkManager = DevManagedLinkManager(pair: pair, stateStore: stateStore)
    }

    func start() async {
        guard !running else { return }
        running = true
        paused = false
        let previousState = pair.state
        setPairState(.initializing, detail: "Resolving roots")
        projectValues = await stateStore.loadProjects(pairID: pair.id)
        conflictValues = await stateStore.loadConflicts(pairID: pair.id)
        linkValues = await stateStore.loadLinks(pairID: pair.id)
        await scheduler.importEntries(await stateStore.loadDirty(pairID: pair.id))
        guard await resolveRootsAndCapabilities(forceProbe: false) else { return }
        await recoverOpenOperations()
        await refreshLinks()
        await refreshCatalog()
        let requiresFull = pair.lastFullReconcileAt.map {
            now().timeIntervalSince($0) >= pair.configuration.timing.fullReconcileSeconds
        } ?? true
        if requiresFull || previousState != .idle {
            for project in projectValues where !project.explicitlyExcluded {
                await scheduler.requestNow(projectID: project.id, reason: .periodic)
            }
            await processNextDue()
        }
        startEventStreams()
        startSchedulerLoop()
        if statusValue.state == .initializing || statusValue.state == .planning {
            setPairState(.idle)
        }
    }

    func stop() async {
        running = false
        schedulerLoop?.cancel()
        schedulerLoop = nil
        internalStream?.stop()
        externalStream?.stop()
        internalStream = nil
        externalStream = nil
        await activeRunner?.cancel()
        try? await persistSchedulerState()
        setPairState(.disabled)
    }

    func pause() async {
        paused = true
        await activeRunner?.cancel()
        setPairState(.paused)
        try? await persistSchedulerState()
    }

    func resume() async {
        paused = false
        guard volumeOnline else {
            setPairState(.volumeOffline)
            return
        }
        setPairState(.idle)
        startSchedulerLoop()
        await processNextDue()
    }

    func volumeDidMount(_ url: URL) async {
        guard !volumeOnline || url.path == pair.externalRoot.url.path || pair.externalRoot.url.path.hasPrefix(url.path + "/") else { return }
        switch DevSyncRoots.resolve(pair.externalRoot) {
        case .identityMismatch:
            volumeOnline = false
            setPairState(.blocked, detail: "Wrong drive", error: "Wrong drive")
            return
        case .offline, .staleBookmark:
            return
        case .available:
            break
        }
        guard await resolveRootsAndCapabilities(forceProbe: true) else { return }
        await refreshLinks()
        await recoverOpenOperations()
        unmounting = false
        await refreshCatalog()
        for project in projectValues where !project.explicitlyExcluded {
            await scheduler.requestNow(projectID: project.id, reason: .mount)
        }
        startEventStreams()
        await processNextDue()
    }

    func volumeWillUnmount(_ url: URL) async {
        guard isExternalVolume(url) else { return }
        unmounting = true
        internalStream?.stop()
        externalStream?.stop()
        await activeRunner?.cancel()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while (activeRunner != nil || activeGeneration != nil), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        try? await persistSchedulerState()
    }

    func volumeDidUnmount(_ url: URL) async {
        guard isExternalVolume(url) else { return }
        volumeOnline = false
        if var operation = await stateStore.loadOpenOperations(pairID: pair.id).first {
            operation.state = .recoveryRequired
            operation.updatedAt = now()
            operation.errorSummary = "External volume was disconnected during an operation."
            try? await stateStore.saveOperation(operation)
        }
        setPairState(.volumeOffline, detail: "Drive disconnected")
        scheduleDriveMissingNotification()
    }

    func syncNow() async {
        for project in projectValues where !project.explicitlyExcluded {
            await scheduler.requestNow(projectID: project.id, reason: .userRequested)
        }
        try? await persistSchedulerState()
        Task { await self.processNextDue() }
    }

    func syncProject(_ projectID: UUID) async {
        await scheduler.requestNow(projectID: projectID, reason: .userRequested)
        try? await persistSchedulerState()
        Task { await self.processNextDue() }
    }

    func verifyNow() async {
        guard let internalRoot, let externalRoot else { return }
        setPairState(.verifying, detail: "Reading both copies")
        let verifier = DevDeepVerifier(
            pair: pair,
            projects: projectValues,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            capabilities: capabilityValue
        )
        for project in projectValues where !project.explicitlyExcluded && project.residency != .externalResident {
            do {
                let report = try await verifier.verify(pairID: pair.id, projectID: project.id)
                updateProject(project.id, state: report.differences.isEmpty && report.complete ? .clean : .destinationDrift, output: nil, error: nil)
            } catch is CancellationError {
                break
            } catch {
                updateProject(project.id, state: .error, output: nil, error: error.localizedDescription)
            }
        }
        setPairState(.idle)
    }

    func repairLinks() async {
        guard let internalRoot, let externalRoot else { return }
        for link in linkValues where link.state != .healthy {
            _ = try? await linkManager.repair(
                link,
                internalRoot: internalRoot,
                externalRoot: externalRoot,
                externalVolumeIdentifier: pair.externalRoot.volumeIdentifier,
                recreateMissing: pair.configuration.safety.autoRepairMissingLinks
            )
        }
        await refreshLinks()
    }

    func previewPending() async -> DevSyncPlan? {
        guard let generation = nextGeneration(await scheduler.due()) else { return nil }
        return await plan(for: generation.projectID, paths: generation.paths, fullScan: generation.requiresFullScan)?.plan
    }

    func previewProject(_ projectID: UUID) async -> DevSyncPlan? {
        await plan(for: projectID, paths: nil, fullScan: true)?.plan
    }

    func moveToExternal(_ projectID: UUID) async throws {
        guard let project = projectValues.first(where: { $0.id == projectID }) else { return }
        let result = try await withResidencyMutation(project: project) { context in
            try await DevResidencyConversion.moveToExternal(context, progress: { _ in })
        }
        replaceProject(result.project)
    }

    func bringInternal(_ projectID: UUID) async throws {
        guard let project = projectValues.first(where: { $0.id == projectID }) else { return }
        let result = try await withResidencyMutation(project: project) { context in
            try await DevResidencyConversion.bringInternal(context, progress: { _ in })
        }
        replaceProject(result.project)
    }

    func setProjectExcluded(_ projectID: UUID, excluded: Bool) async {
        guard let index = projectValues.firstIndex(where: { $0.id == projectID }) else { return }
        projectValues[index].explicitlyExcluded = excluded
        projectValues[index].state = excluded ? .paused : .dirtyBoth
        try? await stateStore.saveProjects(projectValues, pairID: pair.id)
        emitProjects()
        if !excluded { await syncProject(projectID) }
    }

    func includeCandidate(relativePath: String) async {
        guard DevRelativePath.isSafe(relativePath), !projectValues.contains(where: { $0.relativePath == relativePath }) else { return }
        let project = DevProject(pairID: pair.id, relativePath: relativePath, residency: .mirrored, kind: .nonGit, explicitlyIncluded: true)
        projectValues.append(project)
        try? await stateStore.saveProjects(projectValues, pairID: pair.id)
        emitProjects()
        await syncProject(project.id)
    }

    func repairLink(_ projectID: UUID) async throws {
        guard let internalRoot, let externalRoot,
              let link = linkValues.first(where: { $0.projectID == projectID }) else { return }
        _ = try await linkManager.repair(
            link,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: pair.externalRoot.volumeIdentifier,
            recreateMissing: true
        )
        await refreshLinks()
    }

    func adoptLink(relativePath: String) async throws {
        guard let internalRoot, let externalRoot,
              let project = projectValues.first(where: { $0.relativePath == relativePath }) else { return }
        _ = try await linkManager.adopt(
            userLinkRelativePath: relativePath,
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            externalVolumeIdentifier: pair.externalRoot.volumeIdentifier
        )
        await refreshLinks()
    }

    func decideMissingProject(_ projectID: UUID, decision: DevMissingProjectDecision) async throws {
        guard let project = projectValues.first(where: { $0.id == projectID }), let externalRoot else { return }
        switch decision {
        case .keepExternalOnly:
            let result = try await withResidencyMutation(project: project) { context in
                try await DevResidencyConversion.convertMissingInternalToExternalResident(context)
            }
            replaceProject(result.project)
        case .bringBackFromExternal:
            var externalResident = project
            externalResident.residency = .externalResident
            let result = try await withResidencyMutation(project: externalResident) { context in
                try await DevResidencyConversion.bringInternal(context, progress: { _ in })
            }
            replaceProject(result.project)
        case .deleteExternalToHistory:
            _ = try await safetyStore.retireProject(
                side: .external,
                projectURL: externalRoot.appendingPathComponent(project.relativePath),
                relativePath: project.relativePath,
                projectID: project.id,
                operationID: UUID(),
                retainDays: pair.configuration.safety.retainDeletesDays
            )
            projectValues.removeAll { $0.id == projectID }
            try await stateStore.saveProjects(projectValues, pairID: pair.id)
            emitProjects()
        }
    }

    func resolveDrift(projectID: UUID, relativePath: String, resolution: DevDriftResolution) async throws {
        guard DevRelativePath.isSafe(relativePath),
              let project = projectValues.first(where: { $0.id == projectID }),
              let internalRoot, let externalRoot else { return }
        let internalURL = internalRoot.appendingPathComponent(project.relativePath).appendingPathComponent(relativePath)
        let externalURL = externalRoot.appendingPathComponent(project.relativePath).appendingPathComponent(relativePath)
        switch resolution {
        case .adoptExternal:
            let signature = try DevSnapshotScanner.signature(of: externalURL, includeHash: true)
            let current = try? DevSnapshotScanner.signature(of: internalURL, includeHash: true)
            let preconditions = DevActionPreconditions(
                expectedSourceSignature: signature,
                expectedDestinationSignature: current,
                expectDestinationAbsent: current == nil,
                expectedVolumeIdentifier: pair.internalRoot.volumeIdentifier,
                expectedProjectFingerprint: project.identity?.fingerprint,
                expectedParentKind: .directory,
                requiredFreeBytes: Int64(signature.size ?? 0),
                policySchemaVersion: pair.configuration.policySchemaVersion
            )
            var actions: [DevSyncAction] = []
            if current != nil {
                actions.append(DevSyncAction(kind: .stageExistingVersion, destinationSide: .internal, relativePath: relativePath, preconditions: preconditions, reason: "Retain internal version"))
            }
            actions.append(DevSyncAction(kind: .copyPath, destinationSide: .internal, relativePath: relativePath, bytes: Int64(signature.size ?? 0), preconditions: preconditions, reason: "Adopt external version"))
            let syncPlan = DevSyncPlan(pairID: pair.id, projectID: project.id, actions: actions, manifestToInternal: [relativePath])
            _ = await run(plan: syncPlan, output: emptyOutput(plan: syncPlan), project: project, kind: .reconcile)
        case .overwriteExternal, .restoreToExternal:
            let signature = try DevSnapshotScanner.signature(of: internalURL, includeHash: true)
            let current = try? DevSnapshotScanner.signature(of: externalURL, includeHash: true)
            let preconditions = DevActionPreconditions(
                expectedSourceSignature: signature,
                expectedDestinationSignature: current,
                expectDestinationAbsent: current == nil,
                expectedVolumeIdentifier: pair.externalRoot.volumeIdentifier,
                expectedProjectFingerprint: project.identity?.fingerprint,
                expectedParentKind: .directory,
                requiredFreeBytes: Int64(signature.size ?? 0),
                policySchemaVersion: pair.configuration.policySchemaVersion
            )
            var actions: [DevSyncAction] = []
            if current != nil {
                actions.append(DevSyncAction(kind: .stageExistingVersion, destinationSide: .external, relativePath: relativePath, preconditions: preconditions, reason: "Retain external version"))
            }
            actions.append(DevSyncAction(
                kind: .copyPath,
                destinationSide: .external,
                relativePath: relativePath,
                bytes: Int64(signature.size ?? 0),
                preconditions: preconditions,
                reason: "Resolve external drift"
            ))
            let syncPlan = DevSyncPlan(pairID: pair.id, projectID: project.id, actions: actions, manifestToExternal: [relativePath])
            _ = await run(plan: syncPlan, output: emptyOutput(plan: syncPlan), project: project, kind: .reconcile)
        }
        await syncProject(projectID)
    }

    func resolveConflict(_ conflictID: UUID, resolution: DevConflictResolution) async throws {
        guard let index = conflictValues.firstIndex(where: { $0.id == conflictID }) else { return }
        conflictValues[index].resolution = resolution
        conflictValues[index].resolvedAt = resolution == .deferred ? nil : now()
        try await stateStore.saveConflicts(conflictValues, pairID: pair.id)
        emit(.conflicts(pairID: pair.id, conflictValues))
        if resolution != .deferred { await syncProject(conflictValues[index].projectID) }
    }

    func explain(projectID: UUID, relativePath: String) async -> DevFilePolicyDecision? {
        guard let project = projectValues.first(where: { $0.id == projectID }),
              let internalRoot else { return nil }
        let projectURL = internalRoot.appendingPathComponent(project.relativePath)
        let url = projectURL.appendingPathComponent(relativePath)
        guard let signature = try? DevSnapshotScanner.signature(of: url, includeHash: false) else { return nil }
        let policy = await makePolicy(project: project, projectURL: projectURL)
        return policy.decide(relativePath: relativePath, kind: signature.kind, size: Int64(signature.size ?? 0), isInsideGitDirectory: relativePath == ".git" || relativePath.hasPrefix(".git/"))
    }

    func updateConfiguration(_ configuration: DevSyncConfiguration) async {
        pair.configuration = configuration
        pair.updatedAt = now()
        let entries = await scheduler.exportEntries()
        scheduler = DevDirtyScheduler(timing: configuration.timing, performance: configuration.performance, now: now)
        await scheduler.importEntries(entries)
        safetyStore = DevSafetyStore(pair: pair, stateStore: stateStore)
        linkManager = DevManagedLinkManager(pair: pair, stateStore: stateStore)
        try? await savePair()
        for project in projectValues { await scheduler.requestNow(projectID: project.id, reason: .policyChanged) }
        Task { await self.processNextDue() }
    }

    func status() -> DevPairStatus { statusValue }
    func projects() -> [DevProject] { projectValues }
    func conflicts() -> [DevConflict] { conflictValues }
    func links() -> [DevManagedLink] { linkValues }
    func capabilities() -> DevPairCapabilities { capabilityValue }

    func noteEvents(side: DevSyncSide, relativePaths: [String], at date: Date? = nil) async {
        let projects = projectValues
        await scheduler.noteEvents(side: side, relativePaths: relativePaths, projectResolver: { path in
            projects
                .filter { path == $0.relativePath || path.hasPrefix($0.relativePath + "/") }
                .max { $0.relativePath.count < $1.relativePath.count }?.id
        }, at: date)
        try? await persistSchedulerState()
        startSchedulerLoop()
    }

    private func resolveRootsAndCapabilities(forceProbe: Bool) async -> Bool {
        switch (DevSyncRoots.resolve(pair.internalRoot), DevSyncRoots.resolve(pair.externalRoot)) {
        case (.available(let internalURL), .available(let externalURL)):
            internalRoot = internalURL
            externalRoot = externalURL
        case (_, .identityMismatch):
            volumeOnline = false
            setPairState(.blocked, detail: "Wrong drive", error: "Wrong drive")
            return false
        default:
            volumeOnline = false
            setPairState(.volumeOffline, detail: "Drive unavailable")
            scheduleDriveMissingNotification()
            return false
        }
        volumeOnline = true
        capabilityValue = await stateStore.loadCapabilities(pairID: pair.id)
        let stale = capabilityValue.probedAt.map { now().timeIntervalSince($0) > 86_400 } ?? true
        if forceProbe || stale, let internalRoot, let externalRoot {
            let internalVolume = await Task.detached(priority: .utility) { DevVolumeProbe.probe(rootURL: internalRoot, probeDirectory: internalRoot) }.value
            let externalVolume = await Task.detached(priority: .utility) { DevVolumeProbe.probe(rootURL: externalRoot, probeDirectory: externalRoot) }.value
            let rsync = try? await DevRsyncProbe.probe(executable: rsyncExecutable, selfTestDirectory: externalRoot)
            capabilityValue = DevPairCapabilities(internalVolume: internalVolume, externalVolume: externalVolume, rsync: rsync, probedAt: now())
            try? await stateStore.saveCapabilities(capabilityValue, pairID: pair.id)
            emit(.capabilities(pairID: pair.id, capabilityValue))
        }
        if capabilityValue.externalVolume?.isReadOnly == true {
            setPairState(.blocked, detail: "External drive is read-only", error: "External drive is read-only")
            return false
        }
        return true
    }

    private func recoverOpenOperations() async {
        guard let internalRoot, let externalRoot else { return }
        for var operation in await stateStore.loadOpenOperations(pairID: pair.id) {
            let project = projectValues.first { $0.id == operation.projectID }
            let context = operationContext(project: project, internalRoot: internalRoot, externalRoot: externalRoot)
            switch await DevRecovery.recover(operation: operation, context: context) {
            case .commitVerified(let paths):
                guard let project else { continue }
                var baseline = await stateStore.loadBaseline(projectID: project.id, pairID: pair.id)
                    ?? DevBaseline(projectID: project.id)
                for action in operation.plan.actions where paths.contains(action.relativePath) {
                    if let signature = action.preconditions.expectedSourceSignature {
                        baseline.entries[action.relativePath] = DevBaselineEntry(signature: signature, lastVerifiedAt: now())
                    }
                }
                try? await stateStore.saveBaseline(baseline, pairID: pair.id)
                operation.state = .committed
                operation.updatedAt = now()
                operation.completedAt = operation.updatedAt
                try? await stateStore.saveOperation(operation)
            case .rollbackSafety:
                operation.state = .failed
                operation.updatedAt = now()
                operation.completedAt = operation.updatedAt
                try? await stateStore.saveOperation(operation)
            case .replan:
                if let projectID = operation.projectID { await scheduler.requestNow(projectID: projectID, reason: .recovery) }
            case .leaveForUser(let reason):
                setPairState(.blocked, detail: reason, error: reason)
            }
        }
    }

    private func refreshCatalog() async {
        guard let internalRoot, let externalRoot else { return }
        setPairState(.planning, detail: "Discovering projects")
        let links = await linkManager.links()
        async let internalDiscovery = DevProjectDiscovery.discover(
            root: internalRoot,
            side: .internal,
            configuration: pair.configuration.discovery,
            managedLinkPaths: Set(links.map(\.linkRelativePath)),
            otherRoot: externalRoot
        )
        async let externalDiscovery = DevProjectDiscovery.discover(
            root: externalRoot,
            side: .external,
            configuration: pair.configuration.discovery,
            managedLinkPaths: [],
            otherRoot: internalRoot
        )
        let internalResult = await internalDiscovery
        let externalResult = await externalDiscovery
        var internalIdentities: [String: DevProjectIdentity] = [:]
        var externalIdentities: [String: DevProjectIdentity] = [:]
        for project in internalResult.projects where project.kind != .nonGit {
            internalIdentities[project.relativePath] = await DevGit.identity(projectURL: project.url)
        }
        for project in externalResult.projects where project.kind != .nonGit {
            externalIdentities[project.relativePath] = await DevGit.identity(projectURL: project.url)
        }
        let output = DevCatalogPlanner.plan(DevCatalogInput(
            pair: pair,
            knownProjects: projectValues,
            internalDiscovery: internalResult,
            externalDiscovery: externalResult,
            links: links,
            internalIdentities: internalIdentities,
            externalIdentities: externalIdentities,
            excludedProjectPaths: Set(projectValues.filter(\.explicitlyExcluded).map(\.relativePath)),
            includedCandidatePaths: Set(projectValues.filter(\.explicitlyIncluded).map(\.relativePath)),
            adoptedLinkPaths: Set(links.filter(\.adoptedFromUserLink).map(\.linkRelativePath))
        ))
        projectValues = output.projects
        conflictValues = mergeConflicts(conflictValues, output.conflicts)
        try? await stateStore.saveProjects(projectValues, pairID: pair.id)
        try? await stateStore.saveConflicts(conflictValues, pairID: pair.id)
        emitProjects()
        emit(.conflicts(pairID: pair.id, conflictValues))
        await createPendingLinks()
        if internalResult.complete && externalResult.complete {
            await handleMissingProjects(output.missingProjects)
        }
    }

    private func createPendingLinks() async {
        guard let internalRoot, let externalRoot, volumeOnline else { return }
        let knownProjectPaths = Set(projectValues.map(\.relativePath))
        var changed = false
        for index in projectValues.indices
        where projectValues[index].residency == .externalOnlyPendingLink && !projectValues[index].explicitlyExcluded {
            changed = true
            do {
                _ = try await linkManager.create(
                    project: projectValues[index],
                    internalRoot: internalRoot,
                    externalRoot: externalRoot,
                    externalVolumeIdentifier: pair.externalRoot.volumeIdentifier,
                    knownProjectPaths: knownProjectPaths
                )
                projectValues[index].residency = .externalResident
                projectValues[index].state = .clean
                projectValues[index].lastError = nil
                projectValues[index].lastSuccessAt = now()
            } catch DevManagedLinkError.internalPathExists(let kind) {
                projectValues[index].state = .linkMissing
                projectValues[index].lastError = "A \(kind.rawValue) already exists at the internal path. Dev Sync keeps it. Move it aside or exclude the project."
            } catch {
                projectValues[index].state = .linkMissing
                projectValues[index].lastError = "The managed link could not be created: \(error)"
            }
        }
        guard changed else { return }
        try? await stateStore.saveProjects(projectValues, pairID: pair.id)
        emitProjects()
        await refreshLinks()
    }

    private func handleMissingProjects(_ missing: [DevProject]) async {
        for project in missing where project.residency == .mirrored {
            if pair.mode == .devOneWay {
                if let result = try? await withResidencyMutation(project: project, operation: { context in
                    try await DevResidencyConversion.convertMissingInternalToExternalResident(context)
                }) {
                    replaceProject(result.project)
                }
            } else if let index = projectValues.firstIndex(where: { $0.id == project.id }) {
                projectValues[index].state = .missing
            }
        }
        try? await stateStore.saveProjects(projectValues, pairID: pair.id)
        emitProjects()
    }

    private func refreshLinks() async {
        guard let internalRoot else { return }
        let refreshed = try? await linkManager.refreshStates(
            internalRoot: internalRoot,
            externalRoot: volumeOnline ? externalRoot : nil,
            externalVolumeIdentifier: volumeOnline ? pair.externalRoot.volumeIdentifier : nil
        )
        if let refreshed {
            linkValues = refreshed
        } else {
            linkValues = await linkManager.links()
        }
        emit(.links(pairID: pair.id, linkValues))
        if linkValues.contains(where: { $0.state != .healthy && $0.state != .offline }) {
            notifyOnce(.managedLinkBroken, title: "A Dev Sync link needs repair", body: "Open Dev Sync to review the managed link.")
        }
    }

    private func startEventStreams() {
        guard running, volumeOnline, internalStream == nil, externalStream == nil,
              let internalRoot, let externalRoot else { return }
        let cursors = Task { await stateStore.loadCursors(pairID: pair.id) }
        Task {
            let stored = await cursors.value
            let internalCursor = stored.first { $0.side == .internal && $0.volumeIdentifier == pair.internalRoot.volumeIdentifier }
            let externalCursor = stored.first { $0.side == .external && $0.volumeIdentifier == pair.externalRoot.volumeIdentifier }
            let queue = DispatchQueue(label: "DevSync.Events.\(pair.id.uuidString)")
            internalStream = DevEventStream(rootURL: internalRoot, sinceEventID: internalCursor?.lastEventID, latencySeconds: pair.configuration.timing.fseventsLatencySeconds, queue: queue) { [weak self] batch in
                Task { await self?.handle(batch: batch, side: .internal, root: internalRoot) }
            }
            externalStream = DevEventStream(rootURL: externalRoot, sinceEventID: externalCursor?.lastEventID, latencySeconds: pair.configuration.timing.fseventsLatencySeconds, queue: queue) { [weak self] batch in
                Task { await self?.handle(batch: batch, side: .external, root: externalRoot) }
            }
            _ = internalStream?.start()
            _ = externalStream?.start()
        }
    }

    private func handle(batch: DevEventBatch, side: DevSyncSide, root: URL) async {
        guard running else { return }
        let cursor = DevEventCursor(pairID: pair.id, side: side, volumeIdentifier: pair.root(for: side).volumeIdentifier, lastEventID: batch.lastEventID, updatedAt: now())
        var cursors = await stateStore.loadCursors(pairID: pair.id).filter { $0.side != side }
        cursors.append(cursor)
        try? await stateStore.saveCursors(cursors, pairID: pair.id)
        if batch.mustRescanRoot {
            await scheduler.noteFullRescan(side: side, projectID: nil, reason: .droppedEvents)
        } else {
            let rootPath = root.standardizedFileURL.path
            let paths = batch.events.compactMap { event -> String? in
                let path = URL(fileURLWithPath: event.path).standardizedFileURL.path
                guard path.hasPrefix(rootPath + "/") else { return nil }
                return String(path.dropFirst(rootPath.count + 1))
            }
            await noteEvents(side: side, relativePaths: paths)
        }
    }

    private func startSchedulerLoop() {
        guard running, schedulerLoop == nil else { return }
        schedulerLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processNextDue()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func processNextDue() async {
        guard running, !paused, volumeOnline, activeRunner == nil else { return }
        guard let due = nextGeneration(await scheduler.due()) else {
            if statusValue.state == .debouncing { setPairState(.idle) }
            return
        }
        if pair.configuration.power.pauseOnLowPowerMode,
           lowPowerModeEnabled(),
           due.reason != .userRequested {
            setPairState(.paused, detail: "Low Power Mode")
            return
        }
        guard let generation = await scheduler.begin(projectID: due.projectID) else { return }
        if generation.projectID == DevDirtyScheduler.discoveryProjectID {
            await refreshCatalog()
            await scheduler.complete(projectID: generation.projectID)
            try? await persistSchedulerState()
            return
        }
        activeGeneration = generation
        guard let output = await plan(for: generation.projectID, paths: generation.paths, fullScan: generation.requiresFullScan),
              let project = projectValues.first(where: { $0.id == generation.projectID }) else {
            await scheduler.requeue(generation)
            activeGeneration = nil
            return
        }
        let hasExecutablePlan = output.plan.hasMutations || output.plan.actions.contains(where: { $0.kind == .establishBaseline })
        if [.waitingForGit, .waitingForQuiet].contains(output.projectState), !hasExecutablePlan {
            await scheduler.requeue(generation)
            activeGeneration = nil
            return
        }
        if hasExecutablePlan {
            let kind: DevOperationKind = pair.hasCompletedFirstRun ? .reconcile : .firstRun
            let outcome = await run(plan: output.plan, output: output, project: project, kind: kind)
            await finish(generation: generation, project: project, outcome: outcome, output: output)
            if [.waitingForGit, .waitingForQuiet].contains(output.projectState) {
                updateProject(project.id, state: output.projectState, output: output, error: nil)
                await scheduler.requeue(generation)
            }
        } else {
            updateProject(project.id, state: output.projectState, output: output, error: nil)
            if output.projectState == .conflict {
                notifyOnce(.blockedByConflict, title: "Dev Sync needs a decision", body: "A conflict is blocking automatic synchronization.")
            }
            await scheduler.complete(projectID: generation.projectID)
            pair.lastFullReconcileAt = generation.requiresFullScan ? now() : pair.lastFullReconcileAt
            try? await savePair()
            setPairState(.idle)
        }
        activeGeneration = nil
        try? await persistSchedulerState()
    }

    private func plan(for projectID: UUID, paths: Set<String>?, fullScan: Bool) async -> DevPlannerOutput? {
        guard let project = projectValues.first(where: { $0.id == projectID }),
              !project.explicitlyExcluded, project.residency != .externalResident,
              let internalRoot, let externalRoot else { return nil }
        let internalProject = internalRoot.appendingPathComponent(project.relativePath)
        let externalProject = externalRoot.appendingPathComponent(project.relativePath)
        let gitDirectoryRelativePath = project.topology?.gitDirectory ?? ".git"
        let hasGitLock = project.kind != .nonGit && !DevGit.activeLocks(
            projectURL: internalProject,
            gitDirectory: internalProject.appendingPathComponent(gitDirectoryRelativePath)
        ).isEmpty
        setPairState(.planning, detail: project.name)
        let baseline = await stateStore.loadBaseline(projectID: project.id, pairID: pair.id)
        let limited = fullScan ? nil : projectPaths(paths, project: project)
        let policy = await makePolicy(project: project, projectURL: internalProject)
        async let internalScan = scan(projectURL: internalProject, project: project, policy: policy, baseline: baseline, limit: limited, hashPaths: [])
        async let externalScan = scan(projectURL: externalProject, project: project, policy: policy, baseline: baseline, limit: limited, hashPaths: [])
        var internalSnapshot = await internalScan
        var externalSnapshot = await externalScan
        if hasGitLock {
            internalSnapshot = deferringGitMetadata(internalSnapshot, baseline: baseline, gitDirectory: gitDirectoryRelativePath)
            externalSnapshot = deferringGitMetadata(externalSnapshot, baseline: baseline, gitDirectory: gitDirectoryRelativePath)
        }
        async let unstableInternal = unstablePaths(projectURL: internalProject, project: project, snapshot: internalSnapshot, policy: policy)
        async let unstableExternal = unstablePaths(projectURL: externalProject, project: project, snapshot: externalSnapshot, policy: policy)
        let unstableSets = await (unstableInternal, unstableExternal)
        let unstablePaths = unstableSets.0.union(unstableSets.1)
        let tombstones = await stateStore.loadTombstones(pairID: pair.id).filter { $0.projectID == project.id }
        let conflicts = conflictValues.filter { $0.projectID == project.id && $0.resolvedAt == nil }
        var output = DevReconciliationPlanner.plan(DevPlannerInput(
            pair: pair,
            project: project,
            baseline: baseline,
            internalSnapshot: internalSnapshot,
            externalSnapshot: externalSnapshot,
            tombstones: tombstones,
            unresolvedConflicts: conflicts,
            capabilities: capabilityValue,
            unstablePaths: unstablePaths,
            now: now()
        ))
        if !output.needsHashes.isEmpty {
            async let hashedInternal = scan(projectURL: internalProject, project: project, policy: policy, baseline: baseline, limit: limited, hashPaths: output.needsHashes)
            async let hashedExternal = scan(projectURL: externalProject, project: project, policy: policy, baseline: baseline, limit: limited, hashPaths: output.needsHashes)
            internalSnapshot = await hashedInternal
            externalSnapshot = await hashedExternal
            if hasGitLock {
                internalSnapshot = deferringGitMetadata(internalSnapshot, baseline: baseline, gitDirectory: gitDirectoryRelativePath)
                externalSnapshot = deferringGitMetadata(externalSnapshot, baseline: baseline, gitDirectory: gitDirectoryRelativePath)
            }
            output = DevReconciliationPlanner.plan(DevPlannerInput(
                pair: pair,
                project: project,
                baseline: baseline,
                internalSnapshot: internalSnapshot,
                externalSnapshot: externalSnapshot,
                tombstones: tombstones,
                unresolvedConflicts: conflicts,
                capabilities: capabilityValue,
                unstablePaths: unstablePaths,
                now: now()
            ))
        }
        if hasGitLock { output.projectState = .waitingForGit }
        return output
    }

    private func deferringGitMetadata(
        _ snapshot: DevSnapshot?,
        baseline: DevBaseline?,
        gitDirectory: String
    ) -> DevSnapshot? {
        guard var snapshot else { return nil }
        let isGitPath: (String) -> Bool = { $0 == gitDirectory || $0.hasPrefix(gitDirectory + "/") }
        snapshot.entries = snapshot.entries.filter { !isGitPath($0.key) }
        snapshot.excluded = snapshot.excluded.filter { !isGitPath($0.key) }
        for (path, entry) in baseline?.entries ?? [:] where isGitPath(path) {
            snapshot.entries[path] = entry.signature
        }
        snapshot.collisions.removeAll { $0.contains(where: isGitPath) }
        return snapshot
    }

    private func unstablePaths(
        projectURL: URL,
        project: DevProject,
        snapshot: DevSnapshot?,
        policy: DevFilePolicyEngine
    ) async -> Set<String> {
        guard let snapshot else { return [] }
        let gitDirectory = project.topology?.gitDirectory
        let stableWindow = pair.configuration.timing.largeFileQuietSeconds
        return await withTaskGroup(of: String?.self, returning: Set<String>.self) { group in
            for (path, signature) in snapshot.entries where signature.kind == .file {
                let insideGit = gitDirectory.map { path == $0 || path.hasPrefix($0 + "/") } ?? false
                let size = signature.size.flatMap(Int64.init(exactly:)) ?? Int64.max
                let decision = policy.decide(relativePath: path, kind: .file, size: size, isInsideGitDirectory: insideGit)
                guard decision.requiresStableWindow else { continue }
                group.addTask {
                    await DevSnapshotScanner.isStable(
                        url: projectURL.appendingPathComponent(path),
                        previous: signature,
                        windowSeconds: stableWindow
                    ) ? nil : path
                }
            }
            var paths: Set<String> = []
            for await path in group {
                if let path { paths.insert(path) }
            }
            return paths
        }
    }

    private func scan(
        projectURL: URL,
        project: DevProject,
        policy: DevFilePolicyEngine,
        baseline: DevBaseline?,
        limit: Set<String>?,
        hashPaths: Set<String>
    ) async -> DevSnapshot? {
        guard FileManager.default.fileExists(atPath: projectURL.path) else { return nil }
        let partial = await DevSnapshotScanner.scan(
            projectURL: projectURL,
            policy: policy,
            gitDirectoryRelativePath: project.topology?.gitDirectory,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: capabilityValue.externalVolume?.isCaseSensitive == false,
            hashPaths: hashPaths,
            limitToPaths: limit
        )
        guard let limit, let baseline else { return partial }
        var entries = baseline.entries.mapValues(\.signature)
        for path in limit {
            entries = entries.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
        }
        entries.merge(partial.entries) { _, current in current }
        return DevSnapshot(
            entries: entries,
            excluded: partial.excluded,
            unreadablePaths: partial.unreadablePaths,
            complete: partial.complete,
            collisions: partial.collisions,
            includedBytes: partial.includedBytes,
            excludedBytes: partial.excludedBytes,
            scannedAt: partial.scannedAt
        )
    }

    private func makePolicy(project: DevProject, projectURL: URL) async -> DevFilePolicyEngine {
        let manifest = project.kind == .nonGit
            ? nil
            : try? await DevGit.workingTreeManifest(projectURL: projectURL).reduce(into: Set<String>()) { $0.insert($1) }
        return DevFilePolicyEngine(
            policy: pair.configuration.policy,
            projectKind: project.kind,
            gitDirectoryRelativePath: project.topology?.gitDirectory,
            gitTracked: manifest,
            gitManifest: manifest,
            gitIgnored: nil,
            gitAvailable: manifest != nil,
            projectIgnoreRules: []
        )
    }

    private func run(plan: DevSyncPlan, output: DevPlannerOutput, project: DevProject, kind: DevOperationKind) async -> DevOperationOutcome {
        guard let internalRoot, let externalRoot else {
            return DevOperationOutcome(operation: DevOperation(pairID: pair.id, projectID: project.id, kind: kind, state: .failed, plan: plan), committedPaths: [], requeuedPaths: plan.actions.map(\.relativePath), deferredPaths: [], baseline: nil, tombstones: [], conflicts: [], bytesWritten: 0, projectState: .error, error: "Roots unavailable")
        }
        let gateKey = pair.externalRoot.volumeIdentifier
        await DevVolumeMutationGate.shared.acquire(gateKey)
        defer {
            Task { await DevVolumeMutationGate.shared.release(gateKey) }
        }
        setPairState(.transferring, detail: project.name)
        let context = operationContext(project: project, internalRoot: internalRoot, externalRoot: externalRoot)
        let runner = DevOperationRunner(context: context)
        activeRunner = runner
        let baseline = await stateStore.loadBaseline(projectID: project.id, pairID: pair.id)
        let outcome = await withMutationActivity {
            await runner.run(plan: plan, kind: kind, baseline: baseline, plannerOutput: output) { [weak self] progress, detail in
                Task { await self?.setProgress(progress, detail: detail) }
            }
        }
        activeRunner = nil
        return outcome
    }

    private func finish(generation: DevDirtyGeneration, project: DevProject, outcome: DevOperationOutcome, output: DevPlannerOutput) async {
        if unmounting, outcome.operation.state == .cancelled {
            var operation = outcome.operation
            operation.state = .recoveryRequired
            operation.completedAt = nil
            operation.updatedAt = now()
            operation.errorSummary = "External volume was disconnected during the operation."
            try? await stateStore.saveOperation(operation)
        }
        conflictValues = mergeConflicts(conflictValues, outcome.conflicts)
        try? await stateStore.saveConflicts(conflictValues, pairID: pair.id)
        emit(.conflicts(pairID: pair.id, conflictValues))
        resetBytesIfNeeded()
        statusValue.bytesWrittenToday += outcome.bytesWritten
        statusValue.driftCount = output.driftPaths.count
        statusValue.conflictCount = conflictValues.filter { $0.resolvedAt == nil }.count
        if outcome.requeuedPaths.isEmpty {
            await scheduler.complete(projectID: project.id)
        } else {
            var requeued = generation
            requeued.paths = Set(outcome.requeuedPaths.map { project.relativePath.isEmpty ? $0 : "\(project.relativePath)/\($0)" })
            requeued.requiresFullScan = false
            await scheduler.requeue(requeued)
        }
        updateProject(project.id, state: outcome.projectState, output: output, error: outcome.error)
        if outcome.error == nil {
            if let index = projectValues.firstIndex(where: { $0.id == project.id }),
               projectValues[index].residency == .internalOnlyPendingMirror {
                projectValues[index].residency = .mirrored
                try? await stateStore.saveProjects(projectValues, pairID: pair.id)
                emitProjects()
            }
            pair.lastSuccessAt = now()
            pair.lastFullReconcileAt = generation.requiresFullScan ? now() : pair.lastFullReconcileAt
            if !pair.hasCompletedFirstRun {
                pair.hasCompletedFirstRun = true
                notifyOnce(.firstRunComplete, title: "Dev Sync is ready", body: "The first synchronization completed.")
            }
            await runRetentionIfDue()
            setPairState(.idle)
        } else if outcome.projectState == .blockedByFileSystem {
            setPairState(.blocked, detail: outcome.error, error: outcome.error)
            if outcome.error?.contains("Not enough space") == true {
                notifyOnce(.diskAlmostFull, title: "Dev Sync needs more space", body: outcome.error ?? "The destination is full.")
            }
        } else if outcome.operation.state == .cancelled && paused {
            setPairState(.paused)
        } else {
            setPairState(.error, detail: outcome.error, error: outcome.error)
            notifyOnce(.operationFailed, title: "Dev Sync operation failed", body: outcome.error ?? "The operation could not finish.")
        }
        try? await savePair()
    }

    private func runRetentionIfDue() async {
        guard activeRunner == nil, lastRetentionAt.map({ now().timeIntervalSince($0) >= 3_600 }) ?? true else { return }
        let open = Set(await stateStore.loadOpenOperations(pairID: pair.id).map(\.id))
        let unresolved = Set(conflictValues.filter { $0.resolvedAt == nil }.map(\.id))
        _ = try? await safetyStore.runRetention(now: now(), safety: pair.configuration.safety, unresolvedConflictIDs: unresolved, openOperationIDs: open)
        lastRetentionAt = now()
        statusValue.safetyStoreBytes = await safetyStore.usageBytes(side: .internal) + safetyStore.usageBytes(side: .external)
        emitStatus()
    }

    private func operationContext(project: DevProject?, internalRoot: URL, externalRoot: URL) -> DevOperationContext {
        DevOperationContext(
            pair: pair,
            project: project,
            internalRoot: internalRoot,
            externalRoot: externalRoot,
            capabilities: capabilityValue,
            rsyncExecutable: rsyncExecutable,
            stateStore: stateStore,
            safetyStore: safetyStore,
            linkManager: linkManager,
            ledger: ledger,
            policy: nil,
            gitDirectoryRelativePath: project?.topology?.gitDirectory
        )
    }

    private func withResidencyMutation<T: Sendable>(
        project: DevProject,
        operation: @Sendable (DevResidencyContext) async throws -> T
    ) async throws -> T {
        guard let internalRoot, let externalRoot else { throw DevOperationRunnerError.rootUnavailable }
        let policy = await makePolicy(project: project, projectURL: internalRoot.appendingPathComponent(project.relativePath))
        let context = DevResidencyContext(pair: pair, project: project, internalRoot: internalRoot, externalRoot: externalRoot, capabilities: capabilityValue, policy: policy, gitDirectoryRelativePath: project.topology?.gitDirectory, stateStore: stateStore, safetyStore: safetyStore, linkManager: linkManager, rsyncExecutable: rsyncExecutable)
        let key = pair.externalRoot.volumeIdentifier
        await DevVolumeMutationGate.shared.acquire(key)
        defer { Task { await DevVolumeMutationGate.shared.release(key) } }
        return try await operation(context)
    }

    private func projectPaths(_ paths: Set<String>?, project: DevProject) -> Set<String>? {
        guard let paths else { return nil }
        let prefix = project.relativePath.isEmpty ? "" : project.relativePath + "/"
        return Set(paths.compactMap { path in
            if path == project.relativePath { return "" }
            guard path.hasPrefix(prefix) else { return nil }
            let relative = String(path.dropFirst(prefix.count))
            return DevRelativePath.isSafe(relative) ? relative : nil
        })
    }

    private func replaceProject(_ project: DevProject) {
        if let index = projectValues.firstIndex(where: { $0.id == project.id }) { projectValues[index] = project }
        else { projectValues.append(project) }
        Task { try? await stateStore.saveProjects(projectValues, pairID: pair.id) }
        emitProjects()
    }

    private func updateProject(_ id: UUID, state: DevProjectState, output: DevPlannerOutput?, error: String?) {
        guard let index = projectValues.firstIndex(where: { $0.id == id }) else { return }
        projectValues[index].state = state
        projectValues[index].lastError = error
        projectValues[index].warnings = output?.warnings ?? projectValues[index].warnings
        if error == nil { projectValues[index].lastSuccessAt = now() }
        Task { try? await stateStore.saveProjects(projectValues, pairID: pair.id) }
        emitProjects()
    }

    private func mergeConflicts(_ stored: [DevConflict], _ added: [DevConflict]) -> [DevConflict] {
        var result = stored
        for conflict in added where !result.contains(where: { $0.id == conflict.id || ($0.projectID == conflict.projectID && $0.relativePath == conflict.relativePath && $0.resolvedAt == nil) }) {
            result.append(conflict)
        }
        return result
    }

    private func nextGeneration(_ generations: [DevDirtyGeneration]) -> DevDirtyGeneration? {
        generations.min { left, right in
            let leftPriority = generationPriority(left.reason)
            let rightPriority = generationPriority(right.reason)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if left.firstEventAt != right.firstEventAt { return left.firstEventAt < right.firstEventAt }
            return left.projectID.uuidString < right.projectID.uuidString
        }
    }

    private func generationPriority(_ reason: DevDirtyReason) -> Int {
        switch reason {
        case .userRequested: 0
        case .recovery, .mount: 1
        default: 2
        }
    }

    private func emptyOutput(plan: DevSyncPlan, state: DevProjectState = .clean) -> DevPlannerOutput {
        DevPlannerOutput(plan: plan, newConflicts: [], newTombstones: [], driftPaths: [], externalOnlyPaths: [], needsHashes: [], projectState: state, warnings: [])
    }

    private func persistSchedulerState() async throws {
        let entries = await scheduler.exportEntries()
        try await stateStore.saveDirty(entries, pairID: pair.id)
        statusValue.pendingProjectCount = Set(entries.compactMap(\.projectID)).count
        statusValue.nextCheckpointAt = await scheduler.nextDueDate()
        emitStatus()
    }

    private func savePair() async throws {
        var pairs = await stateStore.loadPairs()
        if let index = pairs.firstIndex(where: { $0.id == pair.id }) { pairs[index] = pair }
        else { pairs.append(pair) }
        try await stateStore.savePairs(pairs)
    }

    private func setPairState(_ state: DevSyncPairState, detail: String? = nil, error: String? = nil) {
        pair.state = state
        pair.lastError = error
        pair.updatedAt = now()
        statusValue.state = state
        statusValue.volumeOnline = volumeOnline
        statusValue.phaseDetail = detail
        statusValue.lastError = error
        statusValue.currentProjectID = activeGeneration?.projectID
        statusValue.currentOperationKind = activeRunner == nil ? nil : .reconcile
        emitStatus()
    }

    private func setProgress(_ progress: Double, detail: String?) {
        statusValue.progressFraction = progress
        if let detail { statusValue.phaseDetail = detail }
        emitStatus()
    }

    private func emitStatus() {
        emit(.status(statusValue))
    }

    private func emitProjects() {
        emit(.projects(pairID: pair.id, projectValues))
    }

    private func resetBytesIfNeeded() {
        let day = Calendar.current.startOfDay(for: now())
        if day != bytesDay {
            bytesDay = day
            statusValue.bytesWrittenToday = 0
        }
    }

    private func isExternalVolume(_ url: URL) -> Bool {
        DevSyncRoots.volumeIdentifier(for: url) == pair.externalRoot.volumeIdentifier
            || pair.externalRoot.url.path == url.path
            || pair.externalRoot.url.path.hasPrefix(url.path + "/")
    }

    private func scheduleDriveMissingNotification() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard let self, await !self.volumeOnline else { return }
            await self.emitDriveMissing()
        }
    }

    private func emitDriveMissing() {
        notifyOnce(.driveMissing, title: "Dev Sync drive is missing", body: "Reconnect the configured external drive to continue.")
    }

    private func notifyOnce(_ kind: DevSyncNotificationKind, title: String, body: String) {
        guard notifiedKinds.insert(kind.rawValue).inserted else { return }
        emit(.notification(DevSyncNotification(kind: kind, pairID: pair.id, title: title, body: body)))
    }
}
