//
//  DevSyncModels.swift
//  powertoys
//

import SwiftUI

// MARK: - Mode, side, residency

nonisolated enum DevSyncMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case devOneWay
    case devBidirectional

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .devOneWay: return "Dev One-Way"
        case .devBidirectional: return "Dev Bidirectional"
        }
    }

    var summary: String {
        switch self {
        case .devOneWay:
            return "Internal projects sync to external. External-only projects stay external and appear as links internally."
        case .devBidirectional:
            return "Changes sync in both directions. External-only projects stay external and appear as links internally."
        }
    }
}

nonisolated enum DevSyncSide: String, Codable, CaseIterable, Sendable {
    case `internal`
    case external

    var displayName: String {
        switch self {
        case .internal: return "Internal"
        case .external: return "External"
        }
    }

    var opposite: DevSyncSide {
        self == .internal ? .external : .internal
    }
}

nonisolated enum DevProjectResidency: String, Codable, CaseIterable, Sendable {
    case mirrored
    case externalResident
    case internalOnlyPendingMirror
    case externalOnlyPendingLink

    var displayName: String {
        switch self {
        case .mirrored: return "Mirrored"
        case .externalResident: return "External"
        case .internalOnlyPendingMirror: return "Pending mirror"
        case .externalOnlyPendingLink: return "Pending link"
        }
    }

    var icon: String {
        switch self {
        case .mirrored: return "arrow.left.arrow.right"
        case .externalResident: return "externaldrive"
        case .internalOnlyPendingMirror: return "internaldrive"
        case .externalOnlyPendingLink: return "link"
        }
    }
}

nonisolated enum DevProjectKind: String, Codable, Sendable {
    case gitRepository
    case gitLinkedWorktree
    case gitBareRepository
    case nonGit

    var displayName: String {
        switch self {
        case .gitRepository: return "Git repository"
        case .gitLinkedWorktree: return "Linked worktree"
        case .gitBareRepository: return "Bare repository"
        case .nonGit: return "Folder"
        }
    }
}

nonisolated enum DevEntryKind: String, Codable, Sendable {
    case file
    case directory
    case symlink
    case unsupported
}

// MARK: - States

nonisolated enum DevSyncPairState: String, Codable, Sendable {
    case disabled
    case initializing
    case idle
    case debouncing
    case planning
    case transferring
    case verifying
    case paused
    case volumeOffline
    case blocked
    case error

    var displayName: String {
        switch self {
        case .disabled: return "Off"
        case .initializing: return "Starting"
        case .idle: return "Idle"
        case .debouncing: return "Changes pending"
        case .planning: return "Planning"
        case .transferring: return "Syncing"
        case .verifying: return "Verifying"
        case .paused: return "Paused"
        case .volumeOffline: return "Drive offline"
        case .blocked: return "Blocked"
        case .error: return "Error"
        }
    }

    var icon: String {
        switch self {
        case .disabled: return "circle"
        case .initializing: return "hourglass"
        case .idle: return "checkmark.circle.fill"
        case .debouncing: return "clock"
        case .planning: return "list.bullet.clipboard"
        case .transferring: return "arrow.up.arrow.down.circle"
        case .verifying: return "checkmark.shield"
        case .paused: return "pause.circle.fill"
        case .volumeOffline: return "externaldrive.badge.xmark"
        case .blocked: return "hand.raised.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .green
        case .debouncing, .planning, .transferring, .verifying, .initializing: return .accentColor
        case .paused, .volumeOffline: return .orange
        case .blocked, .error: return .red
        case .disabled: return .secondary
        }
    }

    var isActive: Bool {
        switch self {
        case .initializing, .idle, .debouncing, .planning, .transferring, .verifying: return true
        default: return false
        }
    }
}

nonisolated enum DevProjectState: String, Codable, Sendable {
    case clean
    case dirtyInternal
    case dirtyExternal
    case dirtyBoth
    case waitingForQuiet
    case waitingForGit
    case syncing
    case conflict
    case destinationDrift
    case linkOffline
    case linkMissing
    case blockedByTopology
    case blockedByFileSystem
    case missing
    case paused
    case error

    var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .dirtyInternal, .dirtyExternal, .dirtyBoth: return "Changes pending"
        case .waitingForQuiet: return "Waiting"
        case .waitingForGit: return "Waiting for Git"
        case .syncing: return "Syncing"
        case .conflict: return "Conflict"
        case .destinationDrift: return "Drift"
        case .linkOffline: return "Offline"
        case .linkMissing: return "Link missing"
        case .blockedByTopology: return "Blocked"
        case .blockedByFileSystem: return "Blocked"
        case .missing: return "Missing"
        case .paused: return "Paused"
        case .error: return "Error"
        }
    }

    var tint: Color {
        switch self {
        case .clean: return .green
        case .dirtyInternal, .dirtyExternal, .dirtyBoth, .waitingForQuiet, .waitingForGit, .syncing: return .accentColor
        case .destinationDrift, .linkOffline, .linkMissing, .missing, .paused: return .orange
        case .conflict, .blockedByTopology, .blockedByFileSystem, .error: return .red
        }
    }

    var isBlocked: Bool {
        switch self {
        case .conflict, .blockedByTopology, .blockedByFileSystem, .error: return true
        default: return false
        }
    }
}

nonisolated enum DevOperationState: String, Codable, Sendable {
    case planned
    case safetyPrepared
    case transferRunning
    case transferComplete
    case verifying
    case committed
    case cancelled
    case failed
    case recoveryRequired

    var isTerminal: Bool {
        self == .committed || self == .cancelled || self == .failed
    }
}

nonisolated enum DevManagedLinkState: String, Codable, Sendable {
    case healthy
    case offline
    case missing
    case replaced
    case wrongTarget

    var displayName: String {
        switch self {
        case .healthy: return "Linked"
        case .offline: return "Offline"
        case .missing: return "Link missing"
        case .replaced: return "Path collision"
        case .wrongTarget: return "Wrong target"
        }
    }
}

// MARK: - Pair and configuration

nonisolated struct DevSyncRoot: Codable, Equatable, Sendable {
    var bookmark: Data?
    var path: String
    var volumeIdentifier: String
    var volumeName: String
    var fileSystemType: String

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

nonisolated struct DevSyncPair: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var mode: DevSyncMode
    var internalRoot: DevSyncRoot
    var externalRoot: DevSyncRoot
    var configuration: DevSyncConfiguration
    var state: DevSyncPairState
    var createdAt: Date
    var updatedAt: Date
    var lastFullReconcileAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?
    var hasCompletedFirstRun: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        mode: DevSyncMode,
        internalRoot: DevSyncRoot,
        externalRoot: DevSyncRoot,
        configuration: DevSyncConfiguration = .default,
        state: DevSyncPairState = .disabled,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastFullReconcileAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastError: String? = nil,
        hasCompletedFirstRun: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.mode = mode
        self.internalRoot = internalRoot
        self.externalRoot = externalRoot
        self.configuration = configuration
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastFullReconcileAt = lastFullReconcileAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.hasCompletedFirstRun = hasCompletedFirstRun
    }

    func root(for side: DevSyncSide) -> DevSyncRoot {
        side == .internal ? internalRoot : externalRoot
    }
}

nonisolated enum DevActivityPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case responsive
    case balanced
    case lowDriveActivity
    case manualOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .responsive: return "Responsive"
        case .balanced: return "Balanced"
        case .lowDriveActivity: return "Low drive activity"
        case .manualOnly: return "Manual only"
        }
    }

    var timing: DevSyncConfiguration.Timing {
        switch self {
        case .responsive:
            return .init(fseventsLatencySeconds: 1, quietPeriodSeconds: 3, minimumProjectIntervalSeconds: 5, continuousCheckpointSeconds: 120, largeFileQuietSeconds: 30, fullReconcileSeconds: 21_600)
        case .balanced:
            return .default
        case .lowDriveActivity:
            return .init(fseventsLatencySeconds: 5, quietPeriodSeconds: 60, minimumProjectIntervalSeconds: 300, continuousCheckpointSeconds: 1_800, largeFileQuietSeconds: 300, fullReconcileSeconds: 43_200)
        case .manualOnly:
            return .init(fseventsLatencySeconds: 5, quietPeriodSeconds: 0, minimumProjectIntervalSeconds: 0, continuousCheckpointSeconds: 0, largeFileQuietSeconds: 60, fullReconcileSeconds: 0)
        }
    }
}

nonisolated enum DevMetadataOption: String, Codable, CaseIterable, Sendable {
    case auto
    case on
    case off
}

nonisolated struct DevSyncConfiguration: Codable, Equatable, Sendable {
    static let currentPolicySchemaVersion = 1

    struct Discovery: Codable, Equatable, Sendable {
        var requireGitByDefault = true
        var showMarkerCandidates = true
        var allowNestedIndependentRepositories = false

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            requireGitByDefault = try c.decodeIfPresent(Bool.self, forKey: .requireGitByDefault) ?? true
            showMarkerCandidates = try c.decodeIfPresent(Bool.self, forKey: .showMarkerCandidates) ?? true
            allowNestedIndependentRepositories = try c.decodeIfPresent(Bool.self, forKey: .allowNestedIndependentRepositories) ?? false
        }
    }

    struct Policy: Codable, Equatable, Sendable {
        var followGitIgnore = false
        var includeIgnoredSensitiveFiles = true
        var sensitivePatterns: [String] = DevSyncDefaults.sensitivePatterns
        var sensitiveSizeGuardBytes: Int64 = 50 * 1_024 * 1_024
        var skipCommonCaches = true
        var skipUnignoredBuildOutputs = true
        var includeGitMetadata = true
        var includeGitLFSObjects = true
        var explicitIncludes: [String] = []
        var explicitExcludes: [String] = []

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            followGitIgnore = try c.decodeIfPresent(Bool.self, forKey: .followGitIgnore) ?? false
            includeIgnoredSensitiveFiles = try c.decodeIfPresent(Bool.self, forKey: .includeIgnoredSensitiveFiles) ?? true
            sensitivePatterns = try c.decodeIfPresent([String].self, forKey: .sensitivePatterns) ?? DevSyncDefaults.sensitivePatterns
            sensitiveSizeGuardBytes = try c.decodeIfPresent(Int64.self, forKey: .sensitiveSizeGuardBytes) ?? 50 * 1_024 * 1_024
            skipCommonCaches = try c.decodeIfPresent(Bool.self, forKey: .skipCommonCaches) ?? true
            skipUnignoredBuildOutputs = try c.decodeIfPresent(Bool.self, forKey: .skipUnignoredBuildOutputs) ?? true
            includeGitMetadata = try c.decodeIfPresent(Bool.self, forKey: .includeGitMetadata) ?? true
            includeGitLFSObjects = try c.decodeIfPresent(Bool.self, forKey: .includeGitLFSObjects) ?? true
            explicitIncludes = try c.decodeIfPresent([String].self, forKey: .explicitIncludes) ?? []
            explicitExcludes = try c.decodeIfPresent([String].self, forKey: .explicitExcludes) ?? []
        }
    }

    struct Timing: Codable, Equatable, Sendable {
        var fseventsLatencySeconds: Double
        var quietPeriodSeconds: Double
        var minimumProjectIntervalSeconds: Double
        var continuousCheckpointSeconds: Double
        var largeFileQuietSeconds: Double
        var fullReconcileSeconds: Double

        static let `default` = Timing(fseventsLatencySeconds: 2, quietPeriodSeconds: 10, minimumProjectIntervalSeconds: 20, continuousCheckpointSeconds: 300, largeFileQuietSeconds: 60, fullReconcileSeconds: 21_600)

        var isManualOnly: Bool { quietPeriodSeconds <= 0 }
    }

    struct Safety: Codable, Equatable, Sendable {
        var retainOverwritesDays = 7
        var retainDeletesDays = 30
        var retainResolvedConflictsDays = 30
        var protectDestinationDrift = true
        var wholeProjectDeleteRequiresConfirmation = true
        var maximumSafetyStoreBytes: Int64?
        var minimumFreeSpaceReserveBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
        var autoRepairMissingLinks = false

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            retainOverwritesDays = try c.decodeIfPresent(Int.self, forKey: .retainOverwritesDays) ?? 7
            retainDeletesDays = try c.decodeIfPresent(Int.self, forKey: .retainDeletesDays) ?? 30
            retainResolvedConflictsDays = try c.decodeIfPresent(Int.self, forKey: .retainResolvedConflictsDays) ?? 30
            protectDestinationDrift = try c.decodeIfPresent(Bool.self, forKey: .protectDestinationDrift) ?? true
            wholeProjectDeleteRequiresConfirmation = try c.decodeIfPresent(Bool.self, forKey: .wholeProjectDeleteRequiresConfirmation) ?? true
            maximumSafetyStoreBytes = try c.decodeIfPresent(Int64.self, forKey: .maximumSafetyStoreBytes)
            minimumFreeSpaceReserveBytes = try c.decodeIfPresent(Int64.self, forKey: .minimumFreeSpaceReserveBytes) ?? 2 * 1_024 * 1_024 * 1_024
            autoRepairMissingLinks = try c.decodeIfPresent(Bool.self, forKey: .autoRepairMissingLinks) ?? false
        }
    }

    struct Performance: Codable, Equatable, Sendable {
        var maxConcurrentTransfersPerVolume = 1
        var largeFileWarningBytes: Int64 = 1_073_741_824
        var eventStormThreshold = 1_000
        var eventStormWindowSeconds: Double = 10
        var pathCollapseThreshold = 10_000

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            maxConcurrentTransfersPerVolume = try c.decodeIfPresent(Int.self, forKey: .maxConcurrentTransfersPerVolume) ?? 1
            largeFileWarningBytes = try c.decodeIfPresent(Int64.self, forKey: .largeFileWarningBytes) ?? 1_073_741_824
            eventStormThreshold = try c.decodeIfPresent(Int.self, forKey: .eventStormThreshold) ?? 1_000
            eventStormWindowSeconds = try c.decodeIfPresent(Double.self, forKey: .eventStormWindowSeconds) ?? 10
            pathCollapseThreshold = try c.decodeIfPresent(Int.self, forKey: .pathCollapseThreshold) ?? 10_000
        }
    }

    struct Metadata: Codable, Equatable, Sendable {
        var permissions: DevMetadataOption = .auto
        var xattrs: DevMetadataOption = .auto
        var hardLinks: DevMetadataOption = .off

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            permissions = try c.decodeIfPresent(DevMetadataOption.self, forKey: .permissions) ?? .auto
            xattrs = try c.decodeIfPresent(DevMetadataOption.self, forKey: .xattrs) ?? .auto
            hardLinks = try c.decodeIfPresent(DevMetadataOption.self, forKey: .hardLinks) ?? .off
        }
    }

    struct Power: Codable, Equatable, Sendable {
        var pauseOnLowPowerMode = false
        var largeTransfersRequirePower = false

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pauseOnLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .pauseOnLowPowerMode) ?? false
            largeTransfersRequirePower = try c.decodeIfPresent(Bool.self, forKey: .largeTransfersRequirePower) ?? false
        }
    }

    var policySchemaVersion = DevSyncConfiguration.currentPolicySchemaVersion
    var activityPreset: DevActivityPreset = .balanced
    var discovery = Discovery()
    var policy = Policy()
    var timing = Timing.default
    var safety = Safety()
    var performance = Performance()
    var metadata = Metadata()
    var power = Power()

    static let `default` = DevSyncConfiguration()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        policySchemaVersion = try c.decodeIfPresent(Int.self, forKey: .policySchemaVersion) ?? 0
        activityPreset = try c.decodeIfPresent(DevActivityPreset.self, forKey: .activityPreset) ?? .balanced
        discovery = try c.decodeIfPresent(Discovery.self, forKey: .discovery) ?? Discovery()
        policy = try c.decodeIfPresent(Policy.self, forKey: .policy) ?? Policy()
        timing = try c.decodeIfPresent(Timing.self, forKey: .timing) ?? activityPreset.timing
        safety = try c.decodeIfPresent(Safety.self, forKey: .safety) ?? Safety()
        performance = try c.decodeIfPresent(Performance.self, forKey: .performance) ?? Performance()
        metadata = try c.decodeIfPresent(Metadata.self, forKey: .metadata) ?? Metadata()
        power = try c.decodeIfPresent(Power.self, forKey: .power) ?? Power()
    }

    var needsPolicyReview: Bool {
        policySchemaVersion != DevSyncConfiguration.currentPolicySchemaVersion
    }
}

// MARK: - Projects

nonisolated struct DevGitTopology: Codable, Equatable, Sendable {
    var kind: DevProjectKind
    var gitDirectory: String?
    var commonDirectory: String?
    var submodulePaths: [String] = []
    var hasAlternates = false
    var alternateOutsidePair = false
    var commonDirectoryOutsidePair = false
    var isShallow = false
    var hasLFS = false
}

nonisolated struct DevProjectIdentity: Codable, Equatable, Sendable {
    var remoteURLHints: [String] = []
    var headReference: String?
    var firstCommit: String?
    var topologyKind: DevProjectKind
    var fingerprint: String

    static func fingerprint(remoteURLHints: [String], firstCommit: String?, topologyKind: DevProjectKind) -> String {
        let parts = [topologyKind.rawValue, firstCommit ?? "-"] + remoteURLHints.sorted()
        return parts.joined(separator: "|")
    }
}

nonisolated enum DevProjectWarning: String, Codable, CaseIterable, Sendable {
    case unsupportedTopology
    case submoduleOutsidePair
    case alternatesOutsidePair
    case gitUnavailable
    case caseCollision
    case normalizationCollision
    case volatileFiles
    case largeFiles
    case unencryptedSensitiveTarget
    case portableFidelity
    case externalOnlyPaths
    case linkTargetOutsideProject
    case incompleteScan

    var displayName: String {
        switch self {
        case .unsupportedTopology: return "Destination copy is not usable as a worktree"
        case .submoduleOutsidePair: return "Submodule Git directory outside this pair"
        case .alternatesOutsidePair: return "Git alternates outside this pair"
        case .gitUnavailable: return "Git is not available"
        case .caseCollision: return "Case collision"
        case .normalizationCollision: return "Name collision"
        case .volatileFiles: return "Volatile files waiting"
        case .largeFiles: return "Large files"
        case .unencryptedSensitiveTarget: return "Secrets stored on an unencrypted drive"
        case .portableFidelity: return "Some metadata is not preserved"
        case .externalOnlyPaths: return "External-only files"
        case .linkTargetOutsideProject: return "Link target outside project"
        case .incompleteScan: return "Some folders could not be read"
        }
    }
}

nonisolated struct DevProject: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var pairID: UUID
    var relativePath: String
    var residency: DevProjectResidency
    var kind: DevProjectKind
    var identity: DevProjectIdentity?
    var topology: DevGitTopology?
    var internalResourceIdentifier: Data?
    var externalResourceIdentifier: Data?
    var state: DevProjectState
    var explicitlyIncluded: Bool
    var explicitlyExcluded: Bool
    var lastSeenInternalAt: Date?
    var lastSeenExternalAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?
    var warnings: [DevProjectWarning]
    var includedBytes: Int64
    var excludedBytes: Int64
    var includedCount: Int
    var excludedCount: Int

    init(
        id: UUID = UUID(),
        pairID: UUID,
        relativePath: String,
        residency: DevProjectResidency,
        kind: DevProjectKind,
        identity: DevProjectIdentity? = nil,
        topology: DevGitTopology? = nil,
        internalResourceIdentifier: Data? = nil,
        externalResourceIdentifier: Data? = nil,
        state: DevProjectState = .clean,
        explicitlyIncluded: Bool = false,
        explicitlyExcluded: Bool = false,
        lastSeenInternalAt: Date? = nil,
        lastSeenExternalAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastError: String? = nil,
        warnings: [DevProjectWarning] = [],
        includedBytes: Int64 = 0,
        excludedBytes: Int64 = 0,
        includedCount: Int = 0,
        excludedCount: Int = 0
    ) {
        self.id = id
        self.pairID = pairID
        self.relativePath = relativePath
        self.residency = residency
        self.kind = kind
        self.identity = identity
        self.topology = topology
        self.internalResourceIdentifier = internalResourceIdentifier
        self.externalResourceIdentifier = externalResourceIdentifier
        self.state = state
        self.explicitlyIncluded = explicitlyIncluded
        self.explicitlyExcluded = explicitlyExcluded
        self.lastSeenInternalAt = lastSeenInternalAt
        self.lastSeenExternalAt = lastSeenExternalAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.warnings = warnings
        self.includedBytes = includedBytes
        self.excludedBytes = excludedBytes
        self.includedCount = includedCount
        self.excludedCount = excludedCount
    }

    var name: String { (relativePath as NSString).lastPathComponent }

    var isRootUnit: Bool { relativePath.isEmpty }

    var displayName: String { isRootUnit ? "Everything else" : name }

    var normalizedRelativePath: String {
        DevRelativePath.normalizedKey(relativePath)
    }
}

nonisolated enum DevCandidateKind: String, Codable, Sendable {
    case nestedRepository
    case bareRepository
    case marker

    var displayName: String {
        switch self {
        case .nestedRepository: return "Nested repository"
        case .bareRepository: return "Bare repository"
        case .marker: return "Project marker"
        }
    }
}

nonisolated struct DevProjectCandidate: Codable, Identifiable, Equatable, Sendable {
    var relativePath: String
    var side: DevSyncSide
    var kind: DevCandidateKind
    var markerName: String?

    var id: String { "\(side.rawValue):\(relativePath)" }
}

// MARK: - Signatures and baselines

nonisolated struct DevFileSignature: Codable, Equatable, Hashable, Sendable {
    var kind: DevEntryKind
    var size: UInt64?
    var modificationTimeNanoseconds: Int64?
    var mode: UInt16?
    var symlinkTarget: String?
    var resourceIdentifier: Data?
    var contentHash: Data?
    var xattrDigest: Data?

    init(
        kind: DevEntryKind,
        size: UInt64? = nil,
        modificationTimeNanoseconds: Int64? = nil,
        mode: UInt16? = nil,
        symlinkTarget: String? = nil,
        resourceIdentifier: Data? = nil,
        contentHash: Data? = nil,
        xattrDigest: Data? = nil
    ) {
        self.kind = kind
        self.size = size
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.mode = mode
        self.symlinkTarget = symlinkTarget
        self.resourceIdentifier = resourceIdentifier
        self.contentHash = contentHash
        self.xattrDigest = xattrDigest
    }

    var isExecutable: Bool {
        guard let mode else { return false }
        return mode & 0o111 != 0
    }

    func quickMatches(_ other: DevFileSignature, toleranceNanoseconds: Int64, compareMode: Bool) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .symlink:
            return symlinkTarget == other.symlinkTarget
        case .directory:
            return true
        case .unsupported:
            return true
        case .file:
            guard size == other.size else { return false }
            if compareMode, isExecutable != other.isExecutable { return false }
            guard let mine = modificationTimeNanoseconds, let theirs = other.modificationTimeNanoseconds else {
                return modificationTimeNanoseconds == other.modificationTimeNanoseconds
            }
            return abs(mine - theirs) <= toleranceNanoseconds
        }
    }
}

nonisolated struct DevBaselineEntry: Codable, Equatable, Sendable {
    var signature: DevFileSignature
    var lastVerifiedAt: Date
}

nonisolated struct DevBaseline: Codable, Equatable, Sendable {
    var projectID: UUID
    var policySchemaVersion: Int
    var timestampToleranceNanoseconds: Int64
    var entries: [String: DevBaselineEntry]
    var updatedAt: Date

    init(projectID: UUID, policySchemaVersion: Int = DevSyncConfiguration.currentPolicySchemaVersion, timestampToleranceNanoseconds: Int64 = 0, entries: [String: DevBaselineEntry] = [:], updatedAt: Date = Date()) {
        self.projectID = projectID
        self.policySchemaVersion = policySchemaVersion
        self.timestampToleranceNanoseconds = timestampToleranceNanoseconds
        self.entries = entries
        self.updatedAt = updatedAt
    }
}

nonisolated struct DevTombstone: Codable, Identifiable, Equatable, Sendable {
    var projectID: UUID
    var relativePath: String
    var deletedFromSide: DevSyncSide
    var baselineSignature: DevFileSignature
    var createdAt: Date
    var observedInternal: Bool
    var observedExternal: Bool
    var expiresAt: Date

    var id: String { "\(projectID.uuidString):\(relativePath)" }

    var observedOnBothSides: Bool { observedInternal && observedExternal }
}

nonisolated enum DevDirtyReason: String, Codable, Sendable {
    case fileEvent
    case rootChanged
    case droppedEvents
    case mount
    case policyChanged
    case userRequested
    case periodic
    case recovery
    case incompleteScan
    case unknownPath
}

nonisolated struct DevDirtyEntry: Codable, Equatable, Sendable {
    var projectID: UUID?
    var side: DevSyncSide
    var relativePath: String?
    var firstEventAt: Date
    var lastEventAt: Date
    var reason: DevDirtyReason
    var requiresFullScan: Bool
    var attemptCount: Int
}

nonisolated struct DevEventCursor: Codable, Equatable, Sendable {
    var pairID: UUID
    var side: DevSyncSide
    var volumeIdentifier: String
    var lastEventID: UInt64
    var updatedAt: Date
}

// MARK: - Managed links

nonisolated struct DevManagedLink: Codable, Identifiable, Equatable, Sendable {
    var projectID: UUID
    var linkRelativePath: String
    var targetVolumeIdentifier: String
    var targetRelativePath: String
    var lastWrittenTargetText: String
    var linkResourceIdentifier: Data?
    var state: DevManagedLinkState
    var createdAt: Date
    var lastValidatedAt: Date?
    var adoptedFromUserLink: Bool

    var id: UUID { projectID }
}

// MARK: - Conflicts

nonisolated enum DevConflictType: String, Codable, CaseIterable, Sendable {
    case contentContent
    case addAdd
    case deleteModify
    case modifyDelete
    case typeChange
    case caseCollision
    case normalizationCollision
    case projectIdentity
    case projectPath
    case renameRename
    case renameModify
    case unsupportedGitTopology
    case destinationDrift
    case metadataOnly
    case managedLinkCollision

    var displayName: String {
        switch self {
        case .contentContent: return "Content"
        case .addAdd: return "Added on both sides"
        case .deleteModify: return "Deleted internally, changed externally"
        case .modifyDelete: return "Changed internally, deleted externally"
        case .typeChange: return "Type change"
        case .caseCollision: return "Case collision"
        case .normalizationCollision: return "Name collision"
        case .projectIdentity: return "Project identity"
        case .projectPath: return "Path collision"
        case .renameRename: return "Renamed on both sides"
        case .renameModify: return "Renamed and changed"
        case .unsupportedGitTopology: return "Unsupported Git topology"
        case .destinationDrift: return "Destination drift"
        case .metadataOnly: return "Metadata only"
        case .managedLinkCollision: return "Path collision"
        }
    }

    var blocksWholeProject: Bool {
        switch self {
        case .caseCollision, .normalizationCollision, .projectIdentity, .projectPath, .unsupportedGitTopology, .managedLinkCollision:
            return true
        default:
            return false
        }
    }
}

nonisolated enum DevConflictResolution: String, Codable, CaseIterable, Sendable {
    case keepInternal
    case keepExternal
    case keepBoth
    case markSame
    case excludePath
    case deferred

    var displayName: String {
        switch self {
        case .keepInternal: return "Keep Internal"
        case .keepExternal: return "Keep External"
        case .keepBoth: return "Keep Both"
        case .markSame: return "Mark Resolved after Manual Merge"
        case .excludePath: return "Exclude"
        case .deferred: return "Defer"
        }
    }
}

nonisolated struct DevConflict: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var projectID: UUID
    var relativePath: String
    var type: DevConflictType
    var baselineSignature: DevFileSignature?
    var internalSignature: DevFileSignature?
    var externalSignature: DevFileSignature?
    var internalSafetyPath: String?
    var externalSafetyPath: String?
    var createdAt: Date
    var resolvedAt: Date?
    var resolution: DevConflictResolution?
    var detail: String?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        relativePath: String,
        type: DevConflictType,
        baselineSignature: DevFileSignature? = nil,
        internalSignature: DevFileSignature? = nil,
        externalSignature: DevFileSignature? = nil,
        internalSafetyPath: String? = nil,
        externalSafetyPath: String? = nil,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolution: DevConflictResolution? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.relativePath = relativePath
        self.type = type
        self.baselineSignature = baselineSignature
        self.internalSignature = internalSignature
        self.externalSignature = externalSignature
        self.internalSafetyPath = internalSafetyPath
        self.externalSafetyPath = externalSafetyPath
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolution = resolution
        self.detail = detail
    }

    var isResolved: Bool { resolvedAt != nil }
}

// MARK: - File policy

nonisolated enum DevFilePolicyReason: String, Codable, CaseIterable, Sendable {
    case unsupportedObjectType
    case cloudSyncInternalPath
    case managedLink
    case separateProject
    case explicitUserInclude
    case explicitUserExclude
    case sensitiveOverride
    case sensitiveSizeGuard
    case requiredGitMetadata
    case transientGitLock
    case gitTracked
    case gitIgnored
    case commonExclusion
    case buildOutputExclusion
    case datalessPlaceholder
    case defaultInclusion

    var displayName: String {
        switch self {
        case .unsupportedObjectType: return "Unsupported object type"
        case .cloudSyncInternalPath: return "Cloud Sync system path"
        case .managedLink: return "Managed link"
        case .separateProject: return "Separate project"
        case .explicitUserInclude: return "Included by rule"
        case .explicitUserExclude: return "Excluded by rule"
        case .sensitiveOverride: return "Sensitive override"
        case .sensitiveSizeGuard: return "Larger than the sensitive size guard"
        case .requiredGitMetadata: return "Git metadata"
        case .transientGitLock: return "Transient Git lock"
        case .gitTracked: return "Tracked by Git"
        case .gitIgnored: return "Ignored by Git"
        case .commonExclusion: return "Common cache or dependency"
        case .buildOutputExclusion: return "Build output"
        case .datalessPlaceholder: return "Not downloaded"
        case .defaultInclusion: return "Project file"
        }
    }
}

nonisolated struct DevFilePolicyDecision: Codable, Equatable, Sendable {
    var included: Bool
    var reason: DevFilePolicyReason
    var sensitive: Bool
    var volatile: Bool
    var requiresStableWindow: Bool

    static func include(_ reason: DevFilePolicyReason, sensitive: Bool = false, volatile: Bool = false, requiresStableWindow: Bool = false) -> DevFilePolicyDecision {
        DevFilePolicyDecision(included: true, reason: reason, sensitive: sensitive, volatile: volatile, requiresStableWindow: requiresStableWindow)
    }

    static func exclude(_ reason: DevFilePolicyReason) -> DevFilePolicyDecision {
        DevFilePolicyDecision(included: false, reason: reason, sensitive: false, volatile: false, requiresStableWindow: false)
    }
}

// MARK: - Plans and operations

nonisolated enum DevSyncActionKind: String, Codable, Sendable {
    case createDirectory
    case copyPath
    case movePath
    case stageExistingVersion
    case deletePath
    case createManagedLink
    case repairManagedLink
    case removeManagedLink
    case establishBaseline
    case createConflict
    case noOp

    var isDestructive: Bool {
        switch self {
        case .deletePath, .movePath, .removeManagedLink: return true
        case .copyPath: return false
        default: return false
        }
    }
}

nonisolated struct DevActionPreconditions: Codable, Equatable, Sendable {
    var expectedSourceSignature: DevFileSignature?
    var expectedDestinationSignature: DevFileSignature?
    var expectDestinationAbsent: Bool
    var expectedVolumeIdentifier: String
    var expectedProjectFingerprint: String?
    var expectedParentKind: DevEntryKind
    var requiredFreeBytes: Int64
    var policySchemaVersion: Int
}

nonisolated struct DevSyncAction: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: DevSyncActionKind
    var destinationSide: DevSyncSide
    var relativePath: String
    var destinationRelativePath: String?
    var conflictType: DevConflictType?
    var overwritesDestination: Bool
    var bytes: Int64
    var preconditions: DevActionPreconditions
    var reason: String

    init(
        id: UUID = UUID(),
        kind: DevSyncActionKind,
        destinationSide: DevSyncSide,
        relativePath: String,
        destinationRelativePath: String? = nil,
        conflictType: DevConflictType? = nil,
        overwritesDestination: Bool = false,
        bytes: Int64 = 0,
        preconditions: DevActionPreconditions,
        reason: String
    ) {
        self.id = id
        self.kind = kind
        self.destinationSide = destinationSide
        self.relativePath = relativePath
        self.destinationRelativePath = destinationRelativePath
        self.conflictType = conflictType
        self.overwritesDestination = overwritesDestination
        self.bytes = bytes
        self.preconditions = preconditions
        self.reason = reason
    }
}

nonisolated struct DevPlanSummary: Codable, Equatable, Sendable {
    var copyToExternalCount = 0
    var copyToExternalBytes: Int64 = 0
    var copyToInternalCount = 0
    var copyToInternalBytes: Int64 = 0
    var managedLinksToCreate = 0
    var retainedExternalOnlyCount = 0
    var safetyMoveCount = 0
    var deletionCount = 0
    var conflictCount = 0
    var blockedPathCount = 0
    var sensitiveIncludedCount = 0
    var ignoredBytes: Int64 = 0
    var requiredFreeBytes: Int64 = 0

    var primaryActionTitle: String {
        var parts: [String] = []
        if copyToExternalCount + copyToInternalCount > 0 {
            let count = copyToExternalCount + copyToInternalCount
            parts.append("Copy \(count) \(count == 1 ? "file" : "files")")
        }
        if managedLinksToCreate > 0 {
            parts.append("\(managedLinksToCreate) managed \(managedLinksToCreate == 1 ? "link" : "links")")
        }
        if deletionCount > 0 {
            parts.append("\(deletionCount) \(deletionCount == 1 ? "deletion" : "deletions")")
        }
        guard !parts.isEmpty else { return "Nothing to change" }
        if parts.count == 1 { return parts[0].hasPrefix("Copy") ? parts[0] : "Create " + parts[0] }
        let head = parts[0].hasPrefix("Copy") ? parts[0] : "Create " + parts[0]
        return head + " and " + parts.dropFirst().joined(separator: " and ")
    }
}

nonisolated struct DevSyncPlan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var pairID: UUID
    var projectID: UUID?
    var createdAt: Date
    var actions: [DevSyncAction]
    var manifestToExternal: [String]
    var manifestToInternal: [String]
    var summary: DevPlanSummary
    var scanComplete: Bool
    var deletionsAllowed: Bool

    init(
        id: UUID = UUID(),
        pairID: UUID,
        projectID: UUID? = nil,
        createdAt: Date = Date(),
        actions: [DevSyncAction] = [],
        manifestToExternal: [String] = [],
        manifestToInternal: [String] = [],
        summary: DevPlanSummary = DevPlanSummary(),
        scanComplete: Bool = true,
        deletionsAllowed: Bool = true
    ) {
        self.id = id
        self.pairID = pairID
        self.projectID = projectID
        self.createdAt = createdAt
        self.actions = actions
        self.manifestToExternal = manifestToExternal
        self.manifestToInternal = manifestToInternal
        self.summary = summary
        self.scanComplete = scanComplete
        self.deletionsAllowed = deletionsAllowed
    }

    var hasMutations: Bool {
        actions.contains { $0.kind != .noOp && $0.kind != .createConflict && $0.kind != .establishBaseline }
    }
}

nonisolated enum DevOperationKind: String, Codable, Sendable {
    case firstRun
    case reconcile
    case moveToExternal
    case bringInternal
    case linkRepair
    case conflictResolution
    case verify
    case retention
}

nonisolated struct DevOperation: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var pairID: UUID
    var projectID: UUID?
    var kind: DevOperationKind
    var state: DevOperationState
    var plan: DevSyncPlan
    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var rsyncPath: String?
    var rsyncVersion: String?
    var rsyncExitCode: Int32?
    var bytesPlanned: Int64
    var bytesTransferred: Int64
    var filesTransferred: Int
    var errorSummary: String?
    var safetyRecords: [DevSafetyRecord]

    init(
        id: UUID = UUID(),
        pairID: UUID,
        projectID: UUID?,
        kind: DevOperationKind,
        state: DevOperationState = .planned,
        plan: DevSyncPlan,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        rsyncPath: String? = nil,
        rsyncVersion: String? = nil,
        rsyncExitCode: Int32? = nil,
        bytesPlanned: Int64 = 0,
        bytesTransferred: Int64 = 0,
        filesTransferred: Int = 0,
        errorSummary: String? = nil,
        safetyRecords: [DevSafetyRecord] = []
    ) {
        self.id = id
        self.pairID = pairID
        self.projectID = projectID
        self.kind = kind
        self.state = state
        self.plan = plan
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.rsyncPath = rsyncPath
        self.rsyncVersion = rsyncVersion
        self.rsyncExitCode = rsyncExitCode
        self.bytesPlanned = bytesPlanned
        self.bytesTransferred = bytesTransferred
        self.filesTransferred = filesTransferred
        self.errorSummary = errorSummary
        self.safetyRecords = safetyRecords
    }
}

nonisolated enum DevSafetyRecordKind: String, Codable, Sendable {
    case overwritten
    case deleted
    case conflictCopy
    case projectRetired
    case staging
}

nonisolated struct DevSafetyRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var operationID: UUID
    var projectID: UUID?
    var kind: DevSafetyRecordKind
    var side: DevSyncSide
    var originalRelativePath: String
    var safetyPath: String
    var bytes: Int64
    var createdAt: Date
    var expiresAt: Date?

    init(
        id: UUID = UUID(),
        operationID: UUID,
        projectID: UUID?,
        kind: DevSafetyRecordKind,
        side: DevSyncSide,
        originalRelativePath: String,
        safetyPath: String,
        bytes: Int64 = 0,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.operationID = operationID
        self.projectID = projectID
        self.kind = kind
        self.side = side
        self.originalRelativePath = originalRelativePath
        self.safetyPath = safetyPath
        self.bytes = bytes
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

// MARK: - Capabilities

nonisolated enum DevFileSystemFidelity: String, Codable, Sendable {
    case full
    case portable
    case blocked

    var displayName: String {
        switch self {
        case .full: return "Full fidelity"
        case .portable: return "Portable"
        case .blocked: return "Blocked"
        }
    }
}

nonisolated struct DevVolumeCapabilities: Codable, Equatable, Sendable {
    var volumeIdentifier: String
    var volumeName: String
    var mountPath: String
    var fileSystemType: String
    var isReadOnly: Bool
    var isRemovable: Bool
    var isLocal: Bool
    var isEncrypted: Bool?
    var availableCapacity: Int64
    var totalCapacity: Int64
    var isCaseSensitive: Bool
    var isCasePreserving: Bool
    var supportsSymbolicLinks: Bool
    var supportsHardLinks: Bool
    var supportsUnixPermissions: Bool
    var supportsExtendedAttributes: Bool
    var supportsCreationTimes: Bool
    var supportsPersistentIdentifiers: Bool
    var timestampResolutionNanoseconds: Int64
    var maximumPathComponentLength: Int
    var probedAt: Date
    var fidelity: DevFileSystemFidelity
    var fidelityNotes: [String]

    var modifyWindowSeconds: Int {
        Int((Double(timestampResolutionNanoseconds) / 1_000_000_000).rounded(.up))
    }
}

nonisolated struct DevRsyncCapabilities: Codable, Equatable, Sendable {
    var executablePath: String
    var versionText: String
    var protocolVersion: Int?
    var isOpenrsync: Bool
    var supportedLongOptions: Set<String>
    var supportsFilesFrom: Bool
    var supportsFrom0: Bool
    var supportsPartialDir: Bool
    var supportsBackupDir: Bool
    var supportsItemizeChanges: Bool
    var supportsExecutability: Bool
    var supportsPerms: Bool
    var supportsXattrs: Bool
    var supportsACLs: Bool
    var supportsHardLinks: Bool
    var supportsCrtimes: Bool
    var supportsOmitDirTimes: Bool
    var supportsModifyWindow: Bool
    var supportsDoubleDash: Bool
    var selfTestPassed: Bool
    var selfTestNotes: [String]
    var fingerprint: String
    var probedAt: Date

    var unsupportedFeatureNotes: [String] {
        var notes: [String] = []
        if !supportsFrom0 { notes.append("Names with newlines are deferred") }
        if !supportsACLs { notes.append("ACLs not preserved") }
        if !supportsCrtimes { notes.append("Creation times not preserved") }
        if !supportsXattrs { notes.append("Extended attributes not preserved") }
        if !supportsHardLinks { notes.append("Hard links copied as separate files") }
        return notes
    }
}

nonisolated enum DevRootIssue: Equatable, Sendable {
    case sameDirectory
    case nested(outer: String, inner: String)
    case notADirectory(String)
    case unreadable(String)
    case overlapsExistingPair(pairName: String, path: String)
    case isManagedLink(String)

    var message: String {
        switch self {
        case .sameDirectory: return "Roots must not be the same folder"
        case .nested: return "Roots must not overlap"
        case .notADirectory(let path): return "\(path) is not a folder"
        case .unreadable(let path): return "\(path) cannot be read"
        case .overlapsExistingPair(let pairName, let path): return "\(path) is already owned by pair \(pairName)"
        case .isManagedLink(let path): return "\(path) is a managed link"
        }
    }
}

nonisolated struct DevPairCapabilities: Codable, Equatable, Sendable {
    var internalVolume: DevVolumeCapabilities?
    var externalVolume: DevVolumeCapabilities?
    var rsync: DevRsyncCapabilities?
    var probedAt: Date?

    init(internalVolume: DevVolumeCapabilities? = nil, externalVolume: DevVolumeCapabilities? = nil, rsync: DevRsyncCapabilities? = nil, probedAt: Date? = nil) {
        self.internalVolume = internalVolume
        self.externalVolume = externalVolume
        self.rsync = rsync
        self.probedAt = probedAt
    }

    var timestampToleranceNanoseconds: Int64 {
        let volumes = max(internalVolume?.timestampResolutionNanoseconds ?? 0, externalVolume?.timestampResolutionNanoseconds ?? 0)
        let transferKeepsWholeSecondsOnly = rsync?.protocolVersion.map { $0 < 30 } == true
        return transferKeepsWholeSecondsOnly ? max(1_000_000_000, volumes) : volumes
    }

    var fidelity: DevFileSystemFidelity {
        switch (internalVolume?.fidelity, externalVolume?.fidelity) {
        case (.blocked, _), (_, .blocked): return .blocked
        case (.portable, _), (_, .portable): return .portable
        default: return .full
        }
    }
}

nonisolated enum DevRsyncExitClass: String, Codable, Sendable {
    case success
    case cancelled
    case partial
    case vanished
    case deleteLimit
    case failure

    static func classify(exitCode: Int32) -> DevRsyncExitClass {
        switch exitCode {
        case 0: return .success
        case 20: return .cancelled
        case 23: return .partial
        case 24: return .vanished
        case 25: return .deleteLimit
        default: return .failure
        }
    }
}

// MARK: - Shared constants and path helpers

nonisolated enum DevSyncDefaults {
    static let systemDirectoryName = ".cloudsync-system"
    static let partialDirectoryName = ".cloudsync-partial"
    static let stagingDirectoryName = ".cloudsync-staging"
    static let historyDirectoryName = ".cloudsync-history"
    static let conflictsDirectoryName = ".cloudsync-conflicts"
    static let managedLinkAttributeName = "com.surajmandal.macpowertoys.devsync-link"
    static let projectIgnoreFileName = ".cloudsyncignore"

    static let systemDirectoryNames: Set<String> = [
        systemDirectoryName, partialDirectoryName, stagingDirectoryName,
        historyDirectoryName, conflictsDirectoryName
    ]

    static let sensitivePatterns: [String] = [
        ".env", ".env.*", ".envrc", ".direnvrc", "local.properties", "gradle.properties",
        "secrets.properties", "key.properties", "*.tfvars", "*.tfvars.json", "*.auto.tfvars",
        ".npmrc", ".pypirc", ".netrc", "auth.json", "credentials*.json", "service-account*.json",
        "google-services.json", "GoogleService-Info.plist", "*.pem", "*.key", "*.pub", "*.crt",
        "*.cer", "*.der", "*.p12", "*.pfx", "*.jks", "*.keystore", "*.mobileprovision"
    ]

    static let hardExclusions: [String] = [
        ".DS_Store", "._*", ".Spotlight-V100", ".Trashes", ".fseventsd", ".TemporaryItems"
    ]

    /// Regenerable caches, dependency checkouts, and temporary folders. Git-tracked
    /// content inside any of these still syncs; only untracked junk is skipped.
    static let commonCacheDirectories: [String] = [
        "node_modules", ".npm", ".pnpm-store", ".yarn/cache", ".yarn/unplugged", ".pnp.cjs",
        ".parcel-cache", ".turbo", ".next", ".nuxt", ".output", ".svelte-kit", ".vite", ".astro",
        ".docusaurus", ".angular", ".cache", ".eslintcache", ".stylelintcache", ".webpack",
        ".serverless", ".vercel", ".netlify", ".wrangler", ".nyc_output", "storybook-static",
        "*.tsbuildinfo", ".expo", ".expo-shared", ".eas",
        "__pycache__", "*.pyc", "*.pyo", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox",
        ".nox", ".hypothesis", ".venv", "venv", ".eggs", "*.egg-info", "htmlcov", ".coverage",
        ".pdm-build", ".pytype", ".ipynb_checkpoints",
        ".gradle", ".kotlin", ".cxx", ".externalNativeBuild", "captures", ".bloop", ".metals", ".bsp",
        "Pods", "Carthage", "DerivedData", ".build", ".swiftpm", "xcuserdata", ".symbolcache",
        "*.xcarchive", ".dart_tool", ".pub-cache", ".fvm", "_build", "dist-newstyle", ".stack-work",
        "elm-stuff", ".cpcache", "zig-cache", ".zig-cache", "zig-out", "bazel-*", ".terraform",
        "CMakeFiles", "cmake-build-*", ".vs", "vendor",
        "test-results", "playwright-report", ".playwright", "cypress/videos", "cypress/screenshots",
        "tmp", "temp", ".tmp", ".temp"
    ]

    /// Build outputs that are skipped unless Git tracks content inside them.
    static let buildOutputDirectories: [String] = [
        "build", "out", "target", "coverage", "bin", "obj", "DerivedData"
    ]

    static let importantLockFiles: Set<String> = [
        "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "Cargo.lock", "go.sum",
        "Podfile.lock", "Gemfile.lock", "composer.lock", "Package.resolved",
        "gradle.lockfile", ".terraform.lock.hcl"
    ]

    static let transientGitLockPatterns: [String] = [
        "index.lock", "HEAD.lock", "config.lock", "packed-refs.lock", "shallow.lock", "*.lock", "tmp_*"
    ]

    static let volatileFilePatterns: [String] = [
        "*.sqlite", "*.sqlite3", "*.db", "*-wal", "*-shm", "*.mdb", "*.realm"
    ]

    static let diskImagePatterns: [String] = [
        "*.vmdk", "*.qcow2", "*.vdi", "*.sparsebundle", "*.sparseimage"
    ]

    static let projectMarkers: [String] = [
        "Package.swift", ".xcodeproj", ".xcworkspace", "package.json", "pyproject.toml",
        "Cargo.toml", "go.mod", "pom.xml", "build.gradle", "settings.gradle",
        "CMakeLists.txt", ".sln", ".csproj", "pubspec.yaml", "Gemfile", "composer.json",
        "terraform.tf"
    ]
}

extension URL {
    /// Joins a project-relative path; the root unit's empty path returns the root itself.
    nonisolated func devProjectURL(_ relativePath: String, isDirectory: Bool = true) -> URL {
        relativePath.isEmpty ? self : appendingPathComponent(relativePath, isDirectory: isDirectory)
    }
}

nonisolated enum DevRelativePath {
    static func normalizedKey(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0 == ".." || $0.isEmpty }
    }

    static func components(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    static func isCloudSyncSystemPath(_ path: String) -> Bool {
        components(path).contains { DevSyncDefaults.systemDirectoryNames.contains($0) }
    }

    static func parent(_ path: String) -> String? {
        let parts = components(path)
        guard parts.count > 1 else { return nil }
        return parts.dropLast().joined(separator: "/")
    }

    static func matchesGlob(_ pattern: String, name: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }
}
