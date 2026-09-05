import Darwin
import Foundation

nonisolated final class DevSyncService: DevSyncEngine, @unchecked Sendable {
    static let shared = DevSyncService(stateStore: .shared)

    private actor Engines {
        var values: [UUID: DevSyncPairEngine] = [:]

        func engine(_ id: UUID) -> DevSyncPairEngine? { values[id] }
        func all() -> [DevSyncPairEngine] { Array(values.values) }
        func set(_ engine: DevSyncPairEngine, id: UUID) { values[id] = engine }
        func remove(_ id: UUID) -> DevSyncPairEngine? { values.removeValue(forKey: id) }
        func removeAll() { values.removeAll() }
    }

    private let stateStore: DevSyncStateStore
    private let rsyncPreferredPath: String?
    private let engines = Engines()
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<DevSyncUpdate>.Continuation] = [:]
    private var activePairCount = 0
    @MainActor private var volumeMonitor: DevVolumeMonitor?

    var updates: AsyncStream<DevSyncUpdate> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
            }
        }
    }

    var hasActivePairs: Bool { lock.withLock { activePairCount > 0 } }

    init(stateStore: DevSyncStateStore, rsyncPreferredPath: String? = nil) {
        self.stateStore = stateStore
        self.rsyncPreferredPath = rsyncPreferredPath
    }

    func start() async {
        guard let executable = DevRsyncLocator.locate(preferredPath: rsyncPreferredPath) else { return }
        let pairs = await stateStore.loadPairs()
        lock.withLock { activePairCount = pairs.filter { $0.state != .disabled }.count }
        for pair in pairs where pair.state != .disabled {
            if await engines.engine(pair.id) == nil {
                let engine = makeEngine(pair: pair, executable: executable)
                await engines.set(engine, id: pair.id)
                await engine.start()
            }
        }
        await MainActor.run {
            if volumeMonitor == nil {
                volumeMonitor = DevVolumeMonitor { [weak self] event in
                    guard let self else { return }
                    Task { await self.forward(event) }
                }
                volumeMonitor?.start()
            }
        }
        yield(.pairs(pairs))
    }

    func stop() async {
        for engine in await engines.all() { await engine.stop() }
        await engines.removeAll()
        await MainActor.run {
            volumeMonitor?.stop()
            volumeMonitor = nil
        }
    }

    func pairs() async -> [DevSyncPair] { await stateStore.loadPairs() }
    func status(pairID: UUID) async -> DevPairStatus? { await engines.engine(pairID)?.status() }
    func projects(pairID: UUID) async -> [DevProject] {
        if let engine = await engines.engine(pairID) { return await engine.projects() }
        return await stateStore.loadProjects(pairID: pairID)
    }

    func conflicts(pairID: UUID) async -> [DevConflict] {
        if let engine = await engines.engine(pairID) { return await engine.conflicts() }
        return await stateStore.loadConflicts(pairID: pairID)
    }

    func links(pairID: UUID) async -> [DevManagedLink] {
        if let engine = await engines.engine(pairID) { return await engine.links() }
        return await stateStore.loadLinks(pairID: pairID)
    }

    func capabilities(pairID: UUID) async -> DevPairCapabilities {
        if let engine = await engines.engine(pairID) { return await engine.capabilities() }
        return await stateStore.loadCapabilities(pairID: pairID)
    }
    func operations(pairID: UUID, limit: Int) async -> [DevOperation] { await stateStore.loadOperations(pairID: pairID, limit: limit) }
    func safetyRecords(pairID: UUID, limit: Int) async -> [DevSafetyRecord] { Array(await stateStore.loadSafetyRecords(pairID: pairID).sorted { $0.createdAt > $1.createdAt }.prefix(max(0, limit))) }

    func probeRoots(internal internalURL: URL, external externalURL: URL) async -> DevSetupProbe {
        let existing = await stateStore.loadPairs()
        let issues = DevSyncRoots.validatePair(internal: internalURL, external: externalURL, existingPairs: existing)
        let internalRoot = try? DevSyncRoots.makeRoot(url: internalURL)
        let externalRoot = try? DevSyncRoots.makeRoot(url: externalURL)
        guard let internalRoot, let externalRoot else {
            return DevSetupProbe(issues: issues, internalRoot: internalRoot, externalRoot: externalRoot, capabilities: DevPairCapabilities(), gitAvailable: DevGit.isAvailable, warnings: [])
        }
        async let internalVolume = Task.detached(priority: .utility) { DevVolumeProbe.probe(rootURL: internalURL, probeDirectory: internalURL) }.value
        async let externalVolume = Task.detached(priority: .utility) { DevVolumeProbe.probe(rootURL: externalURL, probeDirectory: externalURL) }.value
        let executable = DevRsyncLocator.locate(preferredPath: rsyncPreferredPath)
        let rsync: DevRsyncCapabilities?
        if let executable {
            rsync = try? await DevRsyncProbe.probe(executable: executable, selfTestDirectory: externalURL)
        } else {
            rsync = nil
        }
        let capabilities = await DevPairCapabilities(internalVolume: internalVolume, externalVolume: externalVolume, rsync: rsync, probedAt: Date())
        var warnings: [String] = []
        if capabilities.externalVolume?.isEncrypted == false,
           DevSyncConfiguration.default.policy.includeIgnoredSensitiveFiles {
            warnings.append("\(externalRoot.volumeName) is not encrypted. Secrets and history are stored in clear.")
        }
        if capabilities.internalVolume?.isLocal == false {
            warnings.append("Network volumes sync on a schedule only")
        }
        return DevSetupProbe(issues: issues, internalRoot: internalRoot, externalRoot: externalRoot, capabilities: capabilities, gitAvailable: DevGit.isAvailable, warnings: warnings)
    }

    func discover(draft: DevSetupDraft) async -> [DevSetupProjectGroup] {
        guard let catalog = await catalog(draft: draft) else { return [] }
        return groups(output: catalog.output)
    }

    func preview(draft: DevSetupDraft) async -> DevSetupPreview {
        guard let catalog = await catalog(draft: draft) else {
            return DevSetupPreview(plan: DevSyncPlan(pairID: UUID(), scanComplete: false, deletionsAllowed: false), groups: [], sensitiveIncludedPaths: [], warnings: ["Choose two valid roots."], availableExternalBytes: 0, scanComplete: false)
        }
        var actions: [DevSyncAction] = []
        var toExternal: [String] = []
        var toInternal: [String] = []
        var summary = DevPlanSummary()
        var complete = catalog.internalDiscovery.complete && catalog.externalDiscovery.complete
        var sensitive: [String] = []
        var projectBytes: [String: (included: Int64, excluded: Int64)] = [:]
        for project in catalog.output.projects where !project.explicitlyExcluded && project.residency != .externalResident && project.residency != .externalOnlyPendingLink {
            let internalURL = catalog.internalURL.devProjectURL(project.relativePath, isDirectory: false)
            let externalURL = catalog.externalURL.devProjectURL(project.relativePath, isDirectory: false)
            let policy = await previewPolicy(pair: catalog.pair, project: project, projectURL: internalURL)
            let nested = nestedProjectPaths(of: project, in: catalog.output.projects)
            async let internalSnapshot = snapshotIfPresent(url: internalURL, project: project, policy: policy, capabilities: catalog.capabilities, nestedProjectPaths: nested)
            async let externalSnapshot = snapshotIfPresent(url: externalURL, project: project, policy: policy, capabilities: catalog.capabilities, nestedProjectPaths: nested)
            let internalScan = await internalSnapshot
            let externalScan = await externalSnapshot ?? (project.residency == .internalOnlyPendingMirror ? DevSnapshot.emptyDestination : nil)
            if let internalScan { projectBytes[project.relativePath] = (internalScan.includedBytes, internalScan.excludedBytes) }
            complete = complete && internalScan?.complete == true && externalScan?.complete == true
            let output = DevReconciliationPlanner.plan(DevPlannerInput(pair: catalog.pair, project: project, baseline: nil, internalSnapshot: internalScan, externalSnapshot: externalScan, tombstones: [], unresolvedConflicts: [], capabilities: catalog.capabilities, unstablePaths: [], now: Date()))
            let prefix = project.relativePath.isEmpty ? "" : project.relativePath + "/"
            let gitPrefix = (project.topology?.gitDirectory ?? ".git") + "/"
            actions.append(contentsOf: output.plan.actions.map { action in
                var action = action
                action.relativePath = prefix + action.relativePath
                return action
            })
            toExternal.append(contentsOf: output.plan.manifestToExternal.map { prefix + $0 })
            toInternal.append(contentsOf: output.plan.manifestToInternal.map { prefix + $0 })
            var projectSummary = output.plan.summary
            for action in output.plan.actions where action.kind == .copyPath {
                let signature = action.preconditions.expectedSourceSignature
                let decision = policy.decide(relativePath: action.relativePath, kind: signature?.kind ?? .file, size: Int64(signature?.size ?? 0), isInsideGitDirectory: action.relativePath.hasPrefix(gitPrefix))
                guard decision.sensitive else { continue }
                sensitive.append(prefix + action.relativePath)
                projectSummary.sensitiveIncludedCount += 1
            }
            add(projectSummary, to: &summary)
        }
        summary.managedLinksToCreate += catalog.output.projectsToLink.count
        var warnings = catalog.probe.warnings
        let available = catalog.capabilities.externalVolume?.availableCapacity ?? 0
        let reserve = max(0, draft.configuration.safety.minimumFreeSpaceReserveBytes)
        if summary.requiredFreeBytes > available - reserve {
            let volumeName = catalog.capabilities.externalVolume?.volumeName ?? catalog.externalURL.lastPathComponent
            warnings.append("Not enough space on \(volumeName). Dev Sync keeps \(ByteCountFormatter.string(fromByteCount: reserve, countStyle: .file)) free.")
        }
        let plan = DevSyncPlan(pairID: catalog.pair.id, actions: actions, manifestToExternal: toExternal, manifestToInternal: toInternal, summary: summary, scanComplete: complete, deletionsAllowed: complete)
        return DevSetupPreview(
            plan: plan,
            groups: groups(output: catalog.output, bytes: projectBytes),
            sensitiveIncludedPaths: sensitive.sorted(),
            warnings: warnings,
            availableExternalBytes: available,
            scanComplete: complete
        )
    }

    func createPair(draft: DevSetupDraft, approvedPreview: DevSetupPreview) async throws -> DevSyncPair {
        guard approvedPreview.scanComplete,
              let internalURL = draft.internalURL,
              let externalURL = draft.externalURL else { throw DevOperationRunnerError.invalidAction("DevSyncService.swift") }
        let probe = await probeRoots(internal: internalURL, external: externalURL)
        guard probe.canContinue, let internalRoot = probe.internalRoot, let externalRoot = probe.externalRoot,
              let executable = DevRsyncLocator.locate(preferredPath: rsyncPreferredPath) else {
            throw DevOperationRunnerError.rootUnavailable
        }
        var pair = DevSyncPair(displayName: draft.displayName, mode: draft.mode, internalRoot: internalRoot, externalRoot: externalRoot, configuration: draft.configuration, state: .initializing)
        var stored = await stateStore.loadPairs()
        stored.append(pair)
        try await stateStore.savePairs(stored)
        if let catalog = await catalog(draft: draft, pairID: pair.id) {
            try await stateStore.saveProjects(catalog.output.projects, pairID: pair.id)
            try await stateStore.saveConflicts(catalog.output.conflicts, pairID: pair.id)
            try await prepareMirrorDirectories(catalog.output.projectsToMirror, externalRoot: externalURL, pair: pair)
        }
        try await stateStore.saveCapabilities(probe.capabilities, pairID: pair.id)
        let engine = makeEngine(pair: pair, executable: executable)
        await engines.set(engine, id: pair.id)
        lock.withLock { activePairCount += 1 }
        if draft.configuration.policy.includeIgnoredSensitiveFiles,
           probe.capabilities.externalVolume?.isEncrypted == false {
            yield(.notification(DevSyncNotification(
                kind: .sensitiveOnUnencryptedDrive,
                pairID: pair.id,
                title: "Dev Sync drive is not encrypted",
                body: "Secrets and history are stored in clear."
            )))
        }
        await engine.start()
        if let current = await stateStore.loadPairs().first(where: { $0.id == pair.id }) { pair = current }
        yield(.pairs(await stateStore.loadPairs()))
        return pair
    }

    func removePair(pairID: UUID, deleteSafetyStore: Bool) async throws {
        if let engine = await engines.remove(pairID) { await engine.stop() }
        let pairs = await stateStore.loadPairs()
        guard let pair = pairs.first(where: { $0.id == pairID }) else { return }
        if deleteSafetyStore {
            try await removeSafetyStore(pair: pair)
        }
        try await stateStore.removePair(pairID)
        let remaining = pairs.filter { $0.id != pairID }
        try await stateStore.savePairs(remaining)
        lock.withLock { activePairCount = remaining.filter { $0.state != .disabled }.count }
        yield(.pairs(remaining))
    }

    func updateConfiguration(pairID: UUID, configuration: DevSyncConfiguration) async throws {
        guard let engine = await engines.engine(pairID) else { return }
        await engine.updateConfiguration(configuration)
        yield(.pairs(await stateStore.loadPairs()))
    }

    func syncNow(pairID: UUID) async { await engines.engine(pairID)?.syncNow() }
    func pause(pairID: UUID) async { await engines.engine(pairID)?.pause() }
    func resume(pairID: UUID) async { await engines.engine(pairID)?.resume() }
    func verifyNow(pairID: UUID) async { await engines.engine(pairID)?.verifyNow() }
    func repairLinks(pairID: UUID) async { await engines.engine(pairID)?.repairLinks() }
    func previewPending(pairID: UUID) async -> DevSyncPlan? { await engines.engine(pairID)?.previewPending() }
    func syncProject(pairID: UUID, projectID: UUID) async { await engines.engine(pairID)?.syncProject(projectID) }
    func previewProject(pairID: UUID, projectID: UUID) async -> DevSyncPlan? { await engines.engine(pairID)?.previewProject(projectID) }
    func moveToExternal(pairID: UUID, projectID: UUID) async throws { try await engines.engine(pairID)?.moveToExternal(projectID) }
    func bringInternal(pairID: UUID, projectID: UUID) async throws { try await engines.engine(pairID)?.bringInternal(projectID) }
    func setProjectExcluded(pairID: UUID, projectID: UUID, excluded: Bool) async { await engines.engine(pairID)?.setProjectExcluded(projectID, excluded: excluded) }
    func includeCandidate(pairID: UUID, relativePath: String) async { await engines.engine(pairID)?.includeCandidate(relativePath: relativePath) }
    func repairLink(pairID: UUID, projectID: UUID) async throws { try await engines.engine(pairID)?.repairLink(projectID) }
    func adoptLink(pairID: UUID, relativePath: String) async throws { try await engines.engine(pairID)?.adoptLink(relativePath: relativePath) }
    func decideMissingProject(pairID: UUID, projectID: UUID, decision: DevMissingProjectDecision) async throws { try await engines.engine(pairID)?.decideMissingProject(projectID, decision: decision) }
    func resolveDrift(pairID: UUID, projectID: UUID, relativePath: String, resolution: DevDriftResolution) async throws { try await engines.engine(pairID)?.resolveDrift(projectID: projectID, relativePath: relativePath, resolution: resolution) }
    func resolveConflict(pairID: UUID, conflictID: UUID, resolution: DevConflictResolution) async throws { try await engines.engine(pairID)?.resolveConflict(conflictID, resolution: resolution) }
    func explain(pairID: UUID, projectID: UUID, relativePath: String) async -> DevFilePolicyDecision? { await engines.engine(pairID)?.explain(projectID: projectID, relativePath: relativePath) }

    private func makeEngine(pair: DevSyncPair, executable: URL) -> DevSyncPairEngine {
        DevSyncPairEngine(pair: pair, stateStore: stateStore, rsyncExecutable: executable) { [weak self] update in
            self?.yield(update)
        }
    }

    private func yield(_ update: DevSyncUpdate) {
        for continuation in lock.withLock({ Array(continuations.values) }) { continuation.yield(update) }
    }

    private func forward(_ event: DevVolumeEvent) async {
        for engine in await engines.all() {
            switch event {
            case .willUnmount(let url): await engine.volumeWillUnmount(url)
            case .didUnmount(let url): await engine.volumeDidUnmount(url)
            case .didMount(let url): await engine.volumeDidMount(url)
            }
        }
    }

    private struct Catalog {
        var pair: DevSyncPair
        var probe: DevSetupProbe
        var capabilities: DevPairCapabilities
        var internalURL: URL
        var externalURL: URL
        var internalDiscovery: DevDiscoveryResult
        var externalDiscovery: DevDiscoveryResult
        var output: DevCatalogOutput
    }

    private func catalog(draft: DevSetupDraft, pairID: UUID = UUID()) async -> Catalog? {
        guard let internalURL = draft.internalURL, let externalURL = draft.externalURL else { return nil }
        let probe = await probeRoots(internal: internalURL, external: externalURL)
        guard let internalRoot = probe.internalRoot, let externalRoot = probe.externalRoot else { return nil }
        let pair = DevSyncPair(id: pairID, displayName: draft.displayName, mode: draft.mode, internalRoot: internalRoot, externalRoot: externalRoot, configuration: draft.configuration, state: .initializing)
        async let internalDiscovery = DevProjectDiscovery.discover(root: internalURL, side: .internal, configuration: draft.configuration.discovery, managedLinkPaths: draft.adoptedLinkPaths, otherRoot: externalURL)
        async let externalDiscovery = DevProjectDiscovery.discover(root: externalURL, side: .external, configuration: draft.configuration.discovery, managedLinkPaths: [], otherRoot: internalURL)
        let internalResult = await internalDiscovery
        let externalResult = await externalDiscovery
        var internalIdentities: [String: DevProjectIdentity] = [:]
        var externalIdentities: [String: DevProjectIdentity] = [:]
        for project in internalResult.projects where project.kind != .nonGit { internalIdentities[project.relativePath] = await DevGit.identity(projectURL: project.url) }
        for project in externalResult.projects where project.kind != .nonGit { externalIdentities[project.relativePath] = await DevGit.identity(projectURL: project.url) }
        let output = DevCatalogPlanner.plan(DevCatalogInput(pair: pair, knownProjects: [], internalDiscovery: internalResult, externalDiscovery: externalResult, links: [], internalIdentities: internalIdentities, externalIdentities: externalIdentities, excludedProjectPaths: draft.excludedProjectPaths, includedCandidatePaths: draft.includedCandidatePaths, adoptedLinkPaths: draft.adoptedLinkPaths, linkableExternalDirectories: Set(externalResult.externalOnlyDirectories)))
        return Catalog(pair: pair, probe: probe, capabilities: probe.capabilities, internalURL: internalURL, externalURL: externalURL, internalDiscovery: internalResult, externalDiscovery: externalResult, output: output)
    }

    private func groups(output: DevCatalogOutput, bytes: [String: (included: Int64, excluded: Int64)] = [:]) -> [DevSetupProjectGroup] {
        var values: [DevSetupGroup: [DevSetupProjectItem]] = [:]
        for project in output.projects {
            let group: DevSetupGroup
            switch project.residency {
            case .mirrored: group = .bothSides
            case .internalOnlyPendingMirror: group = .internalOnly
            case .externalOnlyPendingLink, .externalResident: group = .externalOnly
            }
            values[group, default: []].append(item(project: project, bytes: bytes[project.relativePath]))
        }
        for candidate in output.candidates {
            values[.unmanagedCandidates, default: []].append(DevSetupProjectItem(relativePath: candidate.relativePath, kind: .nonGit, candidateKind: candidate.kind, residency: nil, includedBytes: 0, excludedBytes: 0, warnings: [], adoptableLinkTarget: output.adoptableLinks[candidate.relativePath]))
        }
        for conflict in output.conflicts where conflict.type == .projectIdentity || conflict.type == .projectPath {
            values[.identityConflicts, default: []].append(DevSetupProjectItem(relativePath: conflict.relativePath, kind: .nonGit, candidateKind: nil, residency: nil, includedBytes: 0, excludedBytes: 0, warnings: [], adoptableLinkTarget: nil))
        }
        return DevSetupGroup.allCases.compactMap { group in
            guard let items = values[group], !items.isEmpty else { return nil }
            return DevSetupProjectGroup(group: group, items: items.sorted { $0.relativePath < $1.relativePath })
        }
    }

    private func item(project: DevProject, bytes: (included: Int64, excluded: Int64)? = nil) -> DevSetupProjectItem {
        DevSetupProjectItem(relativePath: project.relativePath, kind: project.kind, candidateKind: nil, residency: project.residency, includedBytes: bytes?.included ?? project.includedBytes, excludedBytes: bytes?.excluded ?? project.excludedBytes, warnings: project.warnings, adoptableLinkTarget: nil)
    }

    private func previewPolicy(pair: DevSyncPair, project: DevProject, projectURL: URL) async -> DevFilePolicyEngine {
        let manifest = project.kind == .nonGit
            ? nil
            : try? await DevGit.workingTreeManifest(projectURL: projectURL).reduce(into: Set<String>()) { $0.insert($1) }
        return DevFilePolicyEngine(policy: pair.configuration.policy, projectKind: project.kind, gitDirectoryRelativePath: project.topology?.gitDirectory, gitTracked: manifest, gitManifest: manifest, gitIgnored: nil, gitAvailable: manifest != nil, projectIgnoreRules: [])
    }

    private func snapshotIfPresent(url: URL, project: DevProject, policy: DevFilePolicyEngine, capabilities: DevPairCapabilities, nestedProjectPaths: Set<String>) async -> DevSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return await DevSnapshotScanner.scan(projectURL: url, policy: policy, gitDirectoryRelativePath: project.topology?.gitDirectory, managedLinkPaths: [], nestedProjectPaths: nestedProjectPaths, collisionKeyCaseInsensitive: capabilities.externalVolume?.isCaseSensitive == false, hashPaths: [])
    }

    private func nestedProjectPaths(of project: DevProject, in projects: [DevProject]) -> Set<String> {
        let prefix = project.relativePath.isEmpty ? "" : project.relativePath + "/"
        return Set(projects.compactMap { other in
            guard other.id != project.id, !other.relativePath.isEmpty, other.relativePath.hasPrefix(prefix) else { return nil }
            return String(other.relativePath.dropFirst(prefix.count))
        })
    }

    private func add(_ source: DevPlanSummary, to target: inout DevPlanSummary) {
        target.copyToExternalCount += source.copyToExternalCount
        target.copyToExternalBytes += source.copyToExternalBytes
        target.copyToInternalCount += source.copyToInternalCount
        target.copyToInternalBytes += source.copyToInternalBytes
        target.managedLinksToCreate += source.managedLinksToCreate
        target.retainedExternalOnlyCount += source.retainedExternalOnlyCount
        target.safetyMoveCount += source.safetyMoveCount
        target.deletionCount += source.deletionCount
        target.conflictCount += source.conflictCount
        target.blockedPathCount += source.blockedPathCount
        target.sensitiveIncludedCount += source.sensitiveIncludedCount
        target.ignoredBytes += source.ignoredBytes
        target.requiredFreeBytes += source.requiredFreeBytes
    }

    private func removeSafetyStore(pair: DevSyncPair) async throws {
        let root = pair.externalRoot.url.appendingPathComponent(DevSyncDefaults.systemDirectoryName, isDirectory: true)
        let target = root.appendingPathComponent(pair.id.uuidString, isDirectory: true)
        try await Task.detached(priority: .utility) {
            guard Self.entryKind(target) != .symlink,
                  target.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
                throw CocoaError(.fileWriteNoPermission)
            }
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        }.value
    }

    private func prepareMirrorDirectories(_ projects: [DevProject], externalRoot: URL, pair: DevSyncPair) async throws {
        for project in projects where !project.isRootUnit {
            guard DevRelativePath.isSafe(project.relativePath) else { throw DevOperationRunnerError.invalidAction("DevSyncService.swift") }
            var operation = DevOperation(
                pairID: pair.id,
                projectID: project.id,
                kind: .firstRun,
                state: .planned,
                plan: DevSyncPlan(pairID: pair.id, projectID: project.id)
            )
            try await stateStore.saveOperation(operation)
            let destination = externalRoot.devProjectURL(project.relativePath)
            try await Task.detached(priority: .utility) {
                try Self.createDirectory(destination, below: externalRoot)
            }.value
            operation.state = .committed
            operation.updatedAt = Date()
            operation.completedAt = operation.updatedAt
            try await stateStore.saveOperation(operation)
        }
    }

    private nonisolated static func entryKind(_ url: URL) -> DevEntryKind? {
        var value = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in path.map { lstat($0, &value) == 0 } ?? false }) else { return nil }
        switch value.st_mode & S_IFMT {
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        case S_IFREG: return .file
        default: return .unsupported
        }
    }

    private nonisolated static func createDirectory(_ directory: URL, below root: URL) throws {
        guard entryKind(root) == .directory else { throw DevOperationRunnerError.rootUnavailable }
        var current = root
        for component in directory.pathComponents.dropFirst(root.pathComponents.count) {
            guard component != "..", component != ".", component != "/" else { throw DevOperationRunnerError.invalidAction("DevSyncService.swift") }
            current.appendPathComponent(component, isDirectory: true)
            if let kind = entryKind(current) {
                guard kind == .directory else { throw DevOperationRunnerError.invalidAction("DevSyncService.swift") }
            } else {
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
    }
}
