//
//  DevSyncEngine.swift
//  powertoys
//

import Foundation

// MARK: - Live status

nonisolated struct DevPairStatus: Codable, Equatable, Sendable {
    var pairID: UUID
    var state: DevSyncPairState
    var volumeOnline: Bool
    var phaseDetail: String?
    var lastSuccessAt: Date?
    var nextCheckpointAt: Date?
    var pendingProjectCount: Int
    var pendingBytes: Int64
    var bytesWrittenToday: Int64
    var conflictCount: Int
    var driftCount: Int
    var blockedProjectCount: Int
    var safetyStoreBytes: Int64
    var rsyncSummary: String?
    var progressFraction: Double?
    var currentOperationKind: DevOperationKind?
    var currentProjectID: UUID?
    var lastError: String?

    init(
        pairID: UUID,
        state: DevSyncPairState = .disabled,
        volumeOnline: Bool = false,
        phaseDetail: String? = nil,
        lastSuccessAt: Date? = nil,
        nextCheckpointAt: Date? = nil,
        pendingProjectCount: Int = 0,
        pendingBytes: Int64 = 0,
        bytesWrittenToday: Int64 = 0,
        conflictCount: Int = 0,
        driftCount: Int = 0,
        blockedProjectCount: Int = 0,
        safetyStoreBytes: Int64 = 0,
        rsyncSummary: String? = nil,
        progressFraction: Double? = nil,
        currentOperationKind: DevOperationKind? = nil,
        currentProjectID: UUID? = nil,
        lastError: String? = nil
    ) {
        self.pairID = pairID
        self.state = state
        self.volumeOnline = volumeOnline
        self.phaseDetail = phaseDetail
        self.lastSuccessAt = lastSuccessAt
        self.nextCheckpointAt = nextCheckpointAt
        self.pendingProjectCount = pendingProjectCount
        self.pendingBytes = pendingBytes
        self.bytesWrittenToday = bytesWrittenToday
        self.conflictCount = conflictCount
        self.driftCount = driftCount
        self.blockedProjectCount = blockedProjectCount
        self.safetyStoreBytes = safetyStoreBytes
        self.rsyncSummary = rsyncSummary
        self.progressFraction = progressFraction
        self.currentOperationKind = currentOperationKind
        self.currentProjectID = currentProjectID
        self.lastError = lastError
    }

    var attentionCount: Int { conflictCount + blockedProjectCount }
}

nonisolated enum DevSyncNotificationKind: String, Codable, Sendable {
    case driveMissing
    case blockedByConflict
    case diskAlmostFull
    case sensitiveOnUnencryptedDrive
    case managedLinkBroken
    case operationFailed
    case firstRunComplete
}

nonisolated struct DevSyncNotification: Equatable, Sendable {
    var kind: DevSyncNotificationKind
    var pairID: UUID
    var title: String
    var body: String
}

nonisolated enum DevSyncUpdate: Sendable {
    case pairs([DevSyncPair])
    case status(DevPairStatus)
    case projects(pairID: UUID, [DevProject])
    case conflicts(pairID: UUID, [DevConflict])
    case links(pairID: UUID, [DevManagedLink])
    case capabilities(pairID: UUID, DevPairCapabilities)
    case notification(DevSyncNotification)
    case drift(pairID: UUID, projectID: UUID, [String])
}

// MARK: - Setup

nonisolated struct DevSetupDraft: Equatable, Sendable {
    var displayName: String
    var mode: DevSyncMode
    var internalURL: URL?
    var externalURL: URL?
    var configuration: DevSyncConfiguration
    var excludedProjectPaths: Set<String>
    var includedCandidatePaths: Set<String>
    var adoptedLinkPaths: Set<String>

    init(
        displayName: String = "",
        mode: DevSyncMode = .devOneWay,
        internalURL: URL? = nil,
        externalURL: URL? = nil,
        configuration: DevSyncConfiguration = .default,
        excludedProjectPaths: Set<String> = [],
        includedCandidatePaths: Set<String> = [],
        adoptedLinkPaths: Set<String> = []
    ) {
        self.displayName = displayName
        self.mode = mode
        self.internalURL = internalURL
        self.externalURL = externalURL
        self.configuration = configuration
        self.excludedProjectPaths = excludedProjectPaths
        self.includedCandidatePaths = includedCandidatePaths
        self.adoptedLinkPaths = adoptedLinkPaths
    }
}

nonisolated struct DevSetupProbe: Equatable, Sendable {
    var issues: [DevRootIssue]
    var internalRoot: DevSyncRoot?
    var externalRoot: DevSyncRoot?
    var capabilities: DevPairCapabilities
    var gitAvailable: Bool
    var warnings: [String]

    var canContinue: Bool {
        issues.isEmpty && internalRoot != nil && externalRoot != nil && capabilities.fidelity != .blocked
    }
}

nonisolated enum DevSetupGroup: String, Codable, CaseIterable, Sendable {
    case internalOnly
    case externalOnly
    case bothSides
    case identityConflicts
    case unmanagedCandidates
    case unsupportedTopology

    var displayName: String {
        switch self {
        case .internalOnly: return "Internal only"
        case .externalOnly: return "External only"
        case .bothSides: return "On both sides"
        case .identityConflicts: return "Identity conflicts"
        case .unmanagedCandidates: return "Unmanaged candidates"
        case .unsupportedTopology: return "Unsupported topology"
        }
    }
}

nonisolated struct DevSetupProjectItem: Identifiable, Equatable, Sendable {
    var relativePath: String
    var kind: DevProjectKind
    var candidateKind: DevCandidateKind?
    var residency: DevProjectResidency?
    var includedBytes: Int64
    var excludedBytes: Int64
    var warnings: [DevProjectWarning]
    var adoptableLinkTarget: String?

    var id: String { relativePath }
    var name: String { (relativePath as NSString).lastPathComponent }
}

nonisolated struct DevSetupProjectGroup: Identifiable, Equatable, Sendable {
    var group: DevSetupGroup
    var items: [DevSetupProjectItem]

    var id: String { group.rawValue }
}

nonisolated struct DevSetupPreview: Equatable, Sendable {
    var plan: DevSyncPlan
    var groups: [DevSetupProjectGroup]
    var sensitiveIncludedPaths: [String]
    var warnings: [String]
    var availableExternalBytes: Int64
    var scanComplete: Bool

    var summary: DevPlanSummary { plan.summary }
}

// MARK: - Engine contract

nonisolated protocol DevSyncEngine: Sendable {
    var updates: AsyncStream<DevSyncUpdate> { get }

    func start() async
    func stop() async

    func pairs() async -> [DevSyncPair]
    func status(pairID: UUID) async -> DevPairStatus?
    func projects(pairID: UUID) async -> [DevProject]
    func conflicts(pairID: UUID) async -> [DevConflict]
    func links(pairID: UUID) async -> [DevManagedLink]
    func capabilities(pairID: UUID) async -> DevPairCapabilities
    func operations(pairID: UUID, limit: Int) async -> [DevOperation]
    func safetyRecords(pairID: UUID, limit: Int) async -> [DevSafetyRecord]

    func probeRoots(internal: URL, external: URL) async -> DevSetupProbe
    func discover(draft: DevSetupDraft) async -> [DevSetupProjectGroup]
    func preview(draft: DevSetupDraft) async -> DevSetupPreview
    func createPair(draft: DevSetupDraft, approvedPreview: DevSetupPreview) async throws -> DevSyncPair
    func removePair(pairID: UUID, deleteSafetyStore: Bool) async throws
    func updateConfiguration(pairID: UUID, configuration: DevSyncConfiguration) async throws

    func syncNow(pairID: UUID) async
    func pause(pairID: UUID) async
    func resume(pairID: UUID) async
    func verifyNow(pairID: UUID) async
    func repairLinks(pairID: UUID) async
    func previewPending(pairID: UUID) async -> DevSyncPlan?

    func syncProject(pairID: UUID, projectID: UUID) async
    func previewProject(pairID: UUID, projectID: UUID) async -> DevSyncPlan?
    func moveToExternal(pairID: UUID, projectID: UUID) async throws
    func bringInternal(pairID: UUID, projectID: UUID) async throws
    func setProjectExcluded(pairID: UUID, projectID: UUID, excluded: Bool) async
    func includeCandidate(pairID: UUID, relativePath: String) async
    func repairLink(pairID: UUID, projectID: UUID) async throws
    func adoptLink(pairID: UUID, relativePath: String) async throws
    func decideMissingProject(pairID: UUID, projectID: UUID, decision: DevMissingProjectDecision) async throws
    func resolveDrift(pairID: UUID, projectID: UUID, relativePath: String, resolution: DevDriftResolution) async throws
    func resolveConflict(pairID: UUID, conflictID: UUID, resolution: DevConflictResolution) async throws
    func explain(pairID: UUID, projectID: UUID, relativePath: String) async -> DevFilePolicyDecision?
}

nonisolated enum DevMissingProjectDecision: String, Codable, CaseIterable, Sendable {
    case keepExternalOnly
    case bringBackFromExternal
    case deleteExternalToHistory

    var displayName: String {
        switch self {
        case .keepExternalOnly: return "Keep external only"
        case .bringBackFromExternal: return "Bring back from external"
        case .deleteExternalToHistory: return "Delete external too"
        }
    }
}

nonisolated enum DevDriftResolution: String, Codable, CaseIterable, Sendable {
    case overwriteExternal
    case adoptExternal
    case restoreToExternal

    var displayName: String {
        switch self {
        case .overwriteExternal: return "Overwrite"
        case .adoptExternal: return "Adopt external copy"
        case .restoreToExternal: return "Restore to external"
        }
    }
}

// MARK: - In-memory engine for previews and interface tests

final class DevSyncPreviewEngine: DevSyncEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPairs: [DevSyncPair]
    private var storedStatus: [UUID: DevPairStatus]
    private var storedProjects: [UUID: [DevProject]]
    private var storedConflicts: [UUID: [DevConflict]]
    private var storedLinks: [UUID: [DevManagedLink]]
    private var storedCapabilities: [UUID: DevPairCapabilities]
    private var continuations: [UUID: AsyncStream<DevSyncUpdate>.Continuation] = [:]
    private(set) var receivedIntents: [String] = []

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

    init(
        pairs: [DevSyncPair] = [],
        status: [UUID: DevPairStatus] = [:],
        projects: [UUID: [DevProject]] = [:],
        conflicts: [UUID: [DevConflict]] = [:],
        links: [UUID: [DevManagedLink]] = [:],
        capabilities: [UUID: DevPairCapabilities] = [:]
    ) {
        storedPairs = pairs
        storedStatus = status
        storedProjects = projects
        storedConflicts = conflicts
        storedLinks = links
        storedCapabilities = capabilities
    }

    func emit(_ update: DevSyncUpdate) {
        lock.lock()
        switch update {
        case .pairs(let pairs): storedPairs = pairs
        case .status(let status): storedStatus[status.pairID] = status
        case .projects(let pairID, let projects): storedProjects[pairID] = projects
        case .conflicts(let pairID, let conflicts): storedConflicts[pairID] = conflicts
        case .links(let pairID, let links): storedLinks[pairID] = links
        case .capabilities(let pairID, let capabilities): storedCapabilities[pairID] = capabilities
        case .notification, .drift: break
        }
        lock.unlock()
        for continuation in lock.withLock({ Array(continuations.values) }) { continuation.yield(update) }
    }

    private func record(_ intent: String) {
        lock.lock()
        receivedIntents.append(intent)
        lock.unlock()
    }

    func start() async {}
    func stop() async {}
    func pairs() async -> [DevSyncPair] { lock.withLock { storedPairs } }
    func status(pairID: UUID) async -> DevPairStatus? { lock.withLock { storedStatus[pairID] } }
    func projects(pairID: UUID) async -> [DevProject] { lock.withLock { storedProjects[pairID] ?? [] } }
    func conflicts(pairID: UUID) async -> [DevConflict] { lock.withLock { storedConflicts[pairID] ?? [] } }
    func links(pairID: UUID) async -> [DevManagedLink] { lock.withLock { storedLinks[pairID] ?? [] } }
    func capabilities(pairID: UUID) async -> DevPairCapabilities { lock.withLock { storedCapabilities[pairID] ?? DevPairCapabilities() } }
    func operations(pairID: UUID, limit: Int) async -> [DevOperation] { [] }
    func safetyRecords(pairID: UUID, limit: Int) async -> [DevSafetyRecord] { [] }

    func probeRoots(internal: URL, external: URL) async -> DevSetupProbe {
        record("probeRoots")
        return DevSetupProbe(issues: [], internalRoot: nil, externalRoot: nil, capabilities: DevPairCapabilities(), gitAvailable: true, warnings: [])
    }

    func discover(draft: DevSetupDraft) async -> [DevSetupProjectGroup] {
        record("discover")
        return []
    }

    func preview(draft: DevSetupDraft) async -> DevSetupPreview {
        record("preview")
        return DevSetupPreview(plan: DevSyncPlan(pairID: UUID()), groups: [], sensitiveIncludedPaths: [], warnings: [], availableExternalBytes: 0, scanComplete: true)
    }

    func createPair(draft: DevSetupDraft, approvedPreview: DevSetupPreview) async throws -> DevSyncPair {
        record("createPair")
        let pair = DevSyncPair(
            displayName: draft.displayName,
            mode: draft.mode,
            internalRoot: DevSyncRoot(bookmark: nil, path: draft.internalURL?.path ?? "", volumeIdentifier: "", volumeName: "", fileSystemType: ""),
            externalRoot: DevSyncRoot(bookmark: nil, path: draft.externalURL?.path ?? "", volumeIdentifier: "", volumeName: "", fileSystemType: ""),
            configuration: draft.configuration,
            state: .idle
        )
        emit(.pairs(lock.withLock { storedPairs } + [pair]))
        return pair
    }

    func removePair(pairID: UUID, deleteSafetyStore: Bool) async throws {
        record("removePair")
        emit(.pairs(lock.withLock { storedPairs.filter { $0.id != pairID } }))
    }

    func updateConfiguration(pairID: UUID, configuration: DevSyncConfiguration) async throws { record("updateConfiguration") }
    func syncNow(pairID: UUID) async { record("syncNow") }
    func pause(pairID: UUID) async { record("pause") }
    func resume(pairID: UUID) async { record("resume") }
    func verifyNow(pairID: UUID) async { record("verifyNow") }
    func repairLinks(pairID: UUID) async { record("repairLinks") }
    func previewPending(pairID: UUID) async -> DevSyncPlan? { record("previewPending"); return nil }
    func syncProject(pairID: UUID, projectID: UUID) async { record("syncProject") }
    func previewProject(pairID: UUID, projectID: UUID) async -> DevSyncPlan? { record("previewProject"); return nil }
    func moveToExternal(pairID: UUID, projectID: UUID) async throws { record("moveToExternal") }
    func bringInternal(pairID: UUID, projectID: UUID) async throws { record("bringInternal") }
    func setProjectExcluded(pairID: UUID, projectID: UUID, excluded: Bool) async { record("setProjectExcluded:\(excluded)") }
    func includeCandidate(pairID: UUID, relativePath: String) async { record("includeCandidate") }
    func repairLink(pairID: UUID, projectID: UUID) async throws { record("repairLink") }
    func adoptLink(pairID: UUID, relativePath: String) async throws { record("adoptLink") }
    func decideMissingProject(pairID: UUID, projectID: UUID, decision: DevMissingProjectDecision) async throws { record("decideMissingProject:\(decision.rawValue)") }
    func resolveDrift(pairID: UUID, projectID: UUID, relativePath: String, resolution: DevDriftResolution) async throws { record("resolveDrift:\(resolution.rawValue)") }
    func resolveConflict(pairID: UUID, conflictID: UUID, resolution: DevConflictResolution) async throws { record("resolveConflict:\(resolution.rawValue)") }
    func explain(pairID: UUID, projectID: UUID, relativePath: String) async -> DevFilePolicyDecision? { record("explain"); return nil }
}
