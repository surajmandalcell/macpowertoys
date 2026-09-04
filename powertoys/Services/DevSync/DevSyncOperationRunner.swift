import Darwin
import Foundation

nonisolated struct DevOperationContext: Sendable {
    var pair: DevSyncPair
    var project: DevProject?
    var internalRoot: URL
    var externalRoot: URL
    var capabilities: DevPairCapabilities
    var rsyncExecutable: URL
    var stateStore: DevSyncStateStore
    var safetyStore: DevSafetyStore
    var linkManager: DevManagedLinkManager
    var ledger: DevSelfEventLedger
    var policy: DevFilePolicyEngine?
    var gitDirectoryRelativePath: String?
}

nonisolated struct DevOperationOutcome: Equatable, Sendable {
    var operation: DevOperation
    var committedPaths: [String]
    var requeuedPaths: [String]
    var deferredPaths: [String]
    var baseline: DevBaseline?
    var tombstones: [DevTombstone]
    var conflicts: [DevConflict]
    var bytesWritten: Int64
    var projectState: DevProjectState
    var error: String?
}

nonisolated enum DevRecoveryDecision: Equatable, Sendable {
    case commitVerified([String])
    case rollbackSafety
    case replan
    case leaveForUser(String)
}

nonisolated enum DevOperationRunnerError: LocalizedError, Sendable {
    case rootUnavailable
    case identityMismatch
    case invalidAction
    case preconditionChanged(String)
    case notEnoughSpace(required: Int64, available: Int64)
    case readOnlyVolume
    case transferFailed(DevRsyncExitClass)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .rootUnavailable: "A Dev Sync root is unavailable."
        case .identityMismatch: "Wrong drive."
        case .invalidAction: "The plan contains an unsafe action."
        case .preconditionChanged: "A planned path changed before the operation started."
        case .notEnoughSpace(let required, let available):
            "Not enough space. \(max(0, required - available)) bytes more are required."
        case .readOnlyVolume: "The destination volume is read-only."
        case .transferFailed(let exitClass): "rsync ended with \(exitClass.rawValue)."
        case .verificationFailed: "Transferred paths did not verify."
        }
    }
}

actor DevOperationRunner {
    private let context: DevOperationContext
    private var activeTransfer: DevRsyncTransfer?
    private var cancellationRequested = false

    init(context: DevOperationContext) {
        self.context = context
    }

    func run(
        plan: DevSyncPlan,
        kind: DevOperationKind,
        baseline: DevBaseline?,
        plannerOutput: DevPlannerOutput,
        progress: @escaping @Sendable (Double, String?) -> Void
    ) async -> DevOperationOutcome {
        var operation = DevOperation(
            pairID: context.pair.id,
            projectID: context.project?.id ?? plan.projectID,
            kind: kind,
            plan: plan,
            bytesPlanned: plan.actions.reduce(0) { $0 + max(0, $1.bytes) }
        )
        var currentBaseline = baseline
        var conflicts = plannerOutput.newConflicts
        var safetyRecords: [DevSafetyRecord] = []
        var verified: [String: DevFileSignature] = [:]
        var deletedPaths: [String] = []
        var deferredPaths: [String] = []
        var requeuedPaths: [String] = []
        var bytesWritten: Int64 = 0
        var mutationStarted = false

        do {
            try await validateRoots()
            try await validate(plan: plan)
            try await preflight(plan: plan)
            try await persist(&operation, state: .planned)
            progress(0.05, "Preparing safety copies")

            mutationStarted = plan.hasMutations
            try await prepareSafety(
                plan: plan,
                operation: &operation,
                records: &safetyRecords,
                conflicts: &conflicts
            )
            try await persist(&operation, state: .safetyPrepared)

            let transferResults = try await runTransfers(
                plan: plan,
                operation: &operation,
                deferredPaths: &deferredPaths,
                progress: progress
            )
            try await persist(&operation, state: .transferComplete)
            let exitClasses = transferResults.map(\.exitClass)

            if cancellationRequested || exitClasses.contains(.cancelled) {
                requeuedPaths = mutationPaths(in: plan)
                return await finishFailure(
                    operation: &operation,
                    state: .cancelled,
                    baseline: currentBaseline,
                    conflicts: conflicts,
                    requeuedPaths: requeuedPaths,
                    deferredPaths: deferredPaths,
                    projectState: .paused,
                    error: DevOperationRunnerError.transferFailed(.cancelled).localizedDescription
                )
            }

            if exitClasses.contains(.vanished) {
                requeuedPaths = mutationPaths(in: plan)
                return await finishFailure(
                    operation: &operation,
                    state: .failed,
                    baseline: currentBaseline,
                    conflicts: conflicts,
                    requeuedPaths: requeuedPaths,
                    deferredPaths: deferredPaths,
                    projectState: .dirtyBoth,
                    error: DevOperationRunnerError.transferFailed(.vanished).localizedDescription
                )
            }

            let hasPartial = exitClasses.contains(.partial)
            if exitClasses.contains(where: { ![.success, .partial].contains($0) }) {
                throw DevOperationRunnerError.transferFailed(exitClasses.first { ![.success, .partial].contains($0) } ?? .failure)
            }

            try await persist(&operation, state: .verifying)
            progress(0.8, "Verifying")
            let verification = await verifyCopiedPaths(plan: plan)
            verified = verification.verified
            requeuedPaths.append(contentsOf: verification.requeued)

            if hasPartial {
                let committedPaths = sortedPaths(verified.keys)
                currentBaseline = try await commit(
                    baseline: currentBaseline,
                    verified: verified,
                    deletedPaths: [],
                    tombstones: [],
                    conflicts: conflicts
                )
                requeuedPaths.append(contentsOf: mutationPaths(in: plan).filter { !verified.keys.contains($0) })
                operation.bytesTransferred = bytes(for: committedPaths, plan: plan)
                operation.filesTransferred = committedPaths.count
                operation.safetyRecords = safetyRecords
                let error = DevOperationRunnerError.transferFailed(.partial).localizedDescription
                return await finishFailure(
                    operation: &operation,
                    state: .failed,
                    baseline: currentBaseline,
                    conflicts: conflicts,
                    committedPaths: committedPaths,
                    requeuedPaths: sortedPaths(requeuedPaths),
                    deferredPaths: deferredPaths,
                    bytesWritten: operation.bytesTransferred,
                    projectState: .dirtyBoth,
                    error: error
                )
            }

            let nonTransfer = try await applyNonTransferActions(
                plan: plan,
                safetyRecords: safetyRecords,
                verified: verified
            )
            verified.merge(nonTransfer.verified) { _, new in new }
            deletedPaths = nonTransfer.deleted
            requeuedPaths.append(contentsOf: nonTransfer.requeued)

            let committedTombstones = plannerOutput.newTombstones.filter { deletedPaths.contains($0.relativePath) }
            currentBaseline = try await commit(
                baseline: currentBaseline,
                verified: verified,
                deletedPaths: deletedPaths,
                tombstones: committedTombstones,
                conflicts: conflicts
            )
            let committedPaths = sortedPaths(Array(verified.keys) + deletedPaths)
            bytesWritten = bytes(for: Array(verified.keys), plan: plan)
            operation.bytesTransferred = bytesWritten
            operation.filesTransferred = verified.count
            operation.safetyRecords = safetyRecords
            try await persist(&operation, state: .committed, terminal: true)
            progress(1, nil)
            return DevOperationOutcome(
                operation: operation,
                committedPaths: committedPaths,
                requeuedPaths: sortedPaths(requeuedPaths),
                deferredPaths: sortedPaths(deferredPaths),
                baseline: currentBaseline,
                tombstones: committedTombstones,
                conflicts: conflicts,
                bytesWritten: bytesWritten,
                projectState: requeuedPaths.isEmpty ? plannerOutput.projectStateAfterCommit : .dirtyBoth,
                error: nil
            )
        } catch is CancellationError {
            requeuedPaths = mutationPaths(in: plan)
            return await finishFailure(
                operation: &operation,
                state: .cancelled,
                baseline: currentBaseline,
                conflicts: conflicts,
                requeuedPaths: requeuedPaths,
                deferredPaths: deferredPaths,
                projectState: .paused,
                error: DevOperationRunnerError.transferFailed(.cancelled).localizedDescription
            )
        } catch {
            let state: DevOperationState = mutationStarted ? .recoveryRequired : .failed
            let projectState: DevProjectState = error is DevOperationRunnerError ? .blockedByFileSystem : .error
            return await finishFailure(
                operation: &operation,
                state: state,
                baseline: currentBaseline,
                conflicts: conflicts,
                requeuedPaths: mutationPaths(in: plan),
                deferredPaths: deferredPaths,
                projectState: projectState,
                error: (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            )
        }
    }

    func cancel() {
        cancellationRequested = true
        activeTransfer?.cancel()
    }

    private func validateRoots() async throws {
        let pair = context.pair
        let roots = [(context.internalRoot, pair.internalRoot), (context.externalRoot, pair.externalRoot)]
        try await Task.detached(priority: .utility) {
            for (url, expected) in roots {
                guard let identifier = DevSyncRoots.volumeIdentifier(for: url) else {
                    throw DevOperationRunnerError.rootUnavailable
                }
                guard identifier == expected.volumeIdentifier else {
                    throw DevOperationRunnerError.identityMismatch
                }
            }
        }.value
    }

    private func validate(plan: DevSyncPlan) async throws {
        try await Task.detached(priority: .utility) { [context] in
            for action in plan.actions {
                try Task.checkCancellation()
                guard DevRelativePath.isSafe(action.relativePath),
                      action.preconditions.policySchemaVersion == context.pair.configuration.policySchemaVersion,
                      action.preconditions.expectedVolumeIdentifier == context.pair.root(for: action.destinationSide).volumeIdentifier
                else { throw DevOperationRunnerError.invalidAction }

                let destinationRoot = Self.projectRoot(context: context, side: action.destinationSide)
                let sourceRoot = Self.projectRoot(context: context, side: action.destinationSide.opposite)
                let destination = destinationRoot.appendingPathComponent(action.relativePath)
                let source = sourceRoot.appendingPathComponent(action.relativePath)
                try Self.validateParents(of: destination, below: destinationRoot)

                switch action.kind {
                case .copyPath:
                    try Self.requireSignature(action.preconditions.expectedSourceSignature, at: source, label: action.relativePath)
                    try Self.requireDestination(action.preconditions, at: destination, label: action.relativePath)
                case .stageExistingVersion, .deletePath, .movePath:
                    try Self.requireSignature(
                        action.preconditions.expectedDestinationSignature ?? action.preconditions.expectedSourceSignature,
                        at: destination,
                        label: action.relativePath,
                        allowMissingForDeleteAfterStage: action.kind == .deletePath
                    )
                case .createDirectory, .createManagedLink:
                    if action.preconditions.expectDestinationAbsent, Self.entryKind(at: destination) != nil {
                        throw DevOperationRunnerError.preconditionChanged(action.relativePath)
                    }
                default:
                    break
                }
            }
        }.value
    }

    private func preflight(plan: DevSyncPlan) async throws {
        if context.capabilities.externalVolume?.isReadOnly == true,
           plan.actions.contains(where: { $0.destinationSide == .external && $0.kind != .noOp }) {
            throw DevOperationRunnerError.readOnlyVolume
        }
        let requiredBySide = Dictionary(grouping: plan.actions, by: \.destinationSide).mapValues {
            $0.reduce(Int64(0)) { total, action in
                let (sum, overflow) = total.addingReportingOverflow(max(0, action.preconditions.requiredFreeBytes))
                return overflow ? Int64.max : sum
            }
        }
        for (side, required) in requiredBySide where required > 0 {
            let root = side == .internal ? context.internalRoot : context.externalRoot
            let measured = await Task.detached(priority: .utility) {
                (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage
            }.value
            let probed = context.capabilitiesVolume(side)?.availableCapacity
            let available = [measured, probed].compactMap { $0 }.min() ?? 0
            let reserve = max(0, context.pair.configuration.safety.minimumFreeSpaceReserveBytes)
            let usable = max(0, available - reserve)
            guard required <= usable else {
                throw DevOperationRunnerError.notEnoughSpace(required: required, available: usable)
            }
        }
    }

    private func prepareSafety(
        plan: DevSyncPlan,
        operation: inout DevOperation,
        records: inout [DevSafetyRecord],
        conflicts: inout [DevConflict]
    ) async throws {
        for action in plan.actions where action.kind == .stageExistingVersion {
            try Task.checkCancellation()
            try await persist(&operation, state: .planned)
            let root = projectRoot(for: action.destinationSide)
            let safetyPath = safetyRelativePath(action.relativePath)
            let record = try await context.safetyStore.retainBeforeDelete(
                side: action.destinationSide,
                fileURL: root.appendingPathComponent(action.relativePath),
                relativePath: safetyPath,
                projectID: context.project?.id,
                operationID: operation.id,
                retainDays: context.pair.configuration.safety.retainDeletesDays
            )
            records.append(record)
            operation.safetyRecords = records
            try await context.stateStore.saveOperation(operation)
        }

        for action in plan.actions where action.kind == .createConflict {
            guard let project = context.project,
                  let conflictIndex = conflicts.firstIndex(where: {
                      $0.relativePath == action.relativePath && $0.type == action.conflictType
                  }) else { continue }
            for side in DevSyncSide.allCases {
                let file = projectRoot(for: side).appendingPathComponent(action.relativePath)
                guard Self.entryKind(at: file) != nil else { continue }
                let record = try await context.safetyStore.retainConflictCopy(
                    side: side,
                    fileURL: file,
                    relativePath: safetyRelativePath(action.relativePath),
                    projectID: project.id,
                    conflictID: conflicts[conflictIndex].id
                )
                records.append(record)
                if side == .internal { conflicts[conflictIndex].internalSafetyPath = record.safetyPath }
                else { conflicts[conflictIndex].externalSafetyPath = record.safetyPath }
            }
        }
    }

    private func runTransfers(
        plan: DevSyncPlan,
        operation: inout DevOperation,
        deferredPaths: inout [String],
        progress: @escaping @Sendable (Double, String?) -> Void
    ) async throws -> [DevRsyncResult] {
        var results: [DevRsyncResult] = []
        let transfers: [(DevSyncSide, [String])] = [(.external, plan.manifestToExternal), (.internal, plan.manifestToInternal)]
        for (destinationSide, manifest) in transfers where !manifest.isEmpty {
            try Task.checkCancellation()
            guard !cancellationRequested else { throw CancellationError() }
            guard let rsyncCapabilities = context.capabilities.rsync else {
                throw DevOperationRunnerError.transferFailed(.failure)
            }
            let sourceRoot = projectRoot(for: destinationSide.opposite)
            let destinationRoot = projectRoot(for: destinationSide)
            try await persist(&operation, state: .transferRunning)
            try await ensureProjectDirectory(destinationRoot, below: destinationSide == .internal ? context.internalRoot : context.externalRoot)
            let backup = try await context.safetyStore.backupDirectory(side: destinationSide, operationID: operation.id)
            let partial = try await context.safetyStore.partialDirectory(side: destinationSide)
            let options = DevRsyncOptions.resolve(
                capabilities: rsyncCapabilities,
                pairCapabilities: context.capabilities,
                metadata: context.pair.configuration.metadata,
                partialDirectory: partial,
                backupDirectory: backup
            )
            let arguments = DevRsyncCommand.arguments(
                capabilities: rsyncCapabilities,
                options: options,
                sourceRoot: sourceRoot,
                destinationRoot: destinationRoot
            )
            for action in plan.actions where action.kind == .copyPath && action.destinationSide == destinationSide {
                if let signature = action.preconditions.expectedSourceSignature {
                    await context.ledger.expect(
                        side: destinationSide,
                        relativePath: action.relativePath,
                        signature: signature,
                        operationID: operation.id,
                        until: Date().addingTimeInterval(120)
                    )
                }
            }
            let transfer = DevRsyncTransfer(
                executable: context.rsyncExecutable,
                arguments: arguments,
                manifest: manifest,
                capabilities: rsyncCapabilities
            )
            activeTransfer = transfer
            let result = try await transfer.run { update in
                let fraction = Double(update.itemizedLines) / Double(max(1, manifest.count))
                progress(0.15 + min(0.6, fraction * 0.6), update.lastRelativePath.map(Self.redactedPath))
            }
            activeTransfer = nil
            results.append(result)
            deferredPaths.append(contentsOf: result.deferredPaths)
            operation.rsyncPath = context.rsyncExecutable.path
            operation.rsyncVersion = rsyncCapabilities.versionText
            operation.rsyncExitCode = result.exitCode
            operation.filesTransferred += result.itemizedPaths.count
            try await context.stateStore.saveOperation(operation)
        }
        return results
    }

    private func verifyCopiedPaths(plan: DevSyncPlan) async -> (verified: [String: DevFileSignature], requeued: [String]) {
        var verified: [String: DevFileSignature] = [:]
        var requeued: [String] = []
        for action in plan.actions where action.kind == .copyPath {
            guard let plannedSource = action.preconditions.expectedSourceSignature else {
                requeued.append(action.relativePath)
                continue
            }
            let sourceURL = projectRoot(for: action.destinationSide.opposite).appendingPathComponent(action.relativePath)
            let destinationURL = projectRoot(for: action.destinationSide).appendingPathComponent(action.relativePath)
            let requireHash = plannedSource.kind == .file && plannedSource.contentHash != nil
            do {
                guard try DevSnapshotScanner.verify(
                    plannedSource: plannedSource,
                    destinationURL: destinationURL,
                    toleranceNanoseconds: timestampToleranceNanoseconds,
                    compareMode: compareMode,
                    requireHash: requireHash
                ) else {
                    requeued.append(action.relativePath)
                    continue
                }
                let sourceNow = try DevSnapshotScanner.signature(of: sourceURL, includeHash: requireHash)
                guard Self.signaturesMatch(plannedSource, sourceNow, tolerance: timestampToleranceNanoseconds, compareMode: compareMode) else {
                    requeued.append(action.relativePath)
                    continue
                }
                verified[action.relativePath] = sourceNow
            } catch {
                requeued.append(action.relativePath)
            }
        }
        return (verified, sortedPaths(requeued))
    }

    private func applyNonTransferActions(
        plan: DevSyncPlan,
        safetyRecords: [DevSafetyRecord],
        verified initialVerified: [String: DevFileSignature]
    ) async throws -> (verified: [String: DevFileSignature], deleted: [String], requeued: [String]) {
        var verified = initialVerified
        var deleted: [String] = []
        var requeued: [String] = []
        let staged = Dictionary(grouping: safetyRecords, by: { "\($0.side.rawValue)\0\($0.originalRelativePath)" })

        for action in plan.actions {
            try Task.checkCancellation()
            let destinationRoot = projectRoot(for: action.destinationSide)
            let destination = destinationRoot.appendingPathComponent(action.destinationRelativePath ?? action.relativePath)
            switch action.kind {
            case .createDirectory:
                try await ensureProjectDirectory(destination, below: destinationRoot)
                if let signature = try? DevSnapshotScanner.signature(of: destination, includeHash: false) {
                    verified[action.relativePath] = signature
                }
            case .deletePath:
                let key = "\(action.destinationSide.rawValue)\0\(safetyRelativePath(action.relativePath))"
                guard staged[key]?.isEmpty == false, Self.entryKind(at: destinationRoot.appendingPathComponent(action.relativePath)) == nil else {
                    requeued.append(action.relativePath)
                    continue
                }
                deleted.append(action.relativePath)
            case .movePath:
                let key = "\(action.destinationSide.rawValue)\0\(safetyRelativePath(action.relativePath))"
                guard let record = staged[key]?.last else {
                    requeued.append(action.relativePath)
                    continue
                }
                try await copyRetainedRecord(record, to: destination, below: destinationRoot)
                if let signature = try? DevSnapshotScanner.signature(of: destination, includeHash: false) {
                    deleted.append(action.relativePath)
                    verified[action.destinationRelativePath ?? action.relativePath] = signature
                }
            case .createManagedLink:
                guard let project = context.project else { throw DevOperationRunnerError.invalidAction }
                _ = try await context.linkManager.create(
                    project: project,
                    internalRoot: context.internalRoot,
                    externalRoot: context.externalRoot,
                    externalVolumeIdentifier: context.pair.externalRoot.volumeIdentifier,
                    knownProjectPaths: Set(await context.stateStore.loadProjects(pairID: context.pair.id).map(\.relativePath))
                )
            case .repairManagedLink:
                guard let link = await context.linkManager.links().first(where: { $0.projectID == context.project?.id }) else {
                    throw DevOperationRunnerError.invalidAction
                }
                _ = try await context.linkManager.repair(
                    link,
                    internalRoot: context.internalRoot,
                    externalRoot: context.externalRoot,
                    externalVolumeIdentifier: context.pair.externalRoot.volumeIdentifier,
                    recreateMissing: false
                )
            case .removeManagedLink:
                guard let link = await context.linkManager.links().first(where: { $0.projectID == context.project?.id }) else {
                    throw DevOperationRunnerError.invalidAction
                }
                try await context.linkManager.remove(link, internalRoot: context.internalRoot, operationID: UUID())
            case .establishBaseline:
                if let signature = try? baselineSignature(for: action) {
                    verified[action.relativePath] = signature
                } else {
                    requeued.append(action.relativePath)
                }
            default:
                break
            }
        }
        return (verified, sortedPaths(deleted), sortedPaths(requeued))
    }

    private func baselineSignature(for action: DevSyncAction) throws -> DevFileSignature {
        let internalURL = projectRoot(for: .internal).appendingPathComponent(action.relativePath)
        let externalURL = projectRoot(for: .external).appendingPathComponent(action.relativePath)
        let requireHash = action.preconditions.expectedSourceSignature?.contentHash != nil
            || action.preconditions.expectedDestinationSignature?.contentHash != nil
        let internalSignature = try DevSnapshotScanner.signature(of: internalURL, includeHash: requireHash)
        let externalSignature = try DevSnapshotScanner.signature(of: externalURL, includeHash: requireHash)
        guard Self.signaturesMatch(
            internalSignature,
            externalSignature,
            tolerance: timestampToleranceNanoseconds,
            compareMode: compareMode
        ) else { throw DevOperationRunnerError.verificationFailed }
        return internalSignature
    }

    private func commit(
        baseline: DevBaseline?,
        verified: [String: DevFileSignature],
        deletedPaths: [String],
        tombstones: [DevTombstone],
        conflicts: [DevConflict]
    ) async throws -> DevBaseline? {
        guard let projectID = context.project?.id ?? baseline?.projectID else {
            if !conflicts.isEmpty {
                try await context.stateStore.saveConflicts(conflicts, pairID: context.pair.id)
            }
            return baseline
        }
        var updated = baseline ?? DevBaseline(
            projectID: projectID,
            policySchemaVersion: context.pair.configuration.policySchemaVersion,
            timestampToleranceNanoseconds: context.capabilities.timestampToleranceNanoseconds
        )
        let now = Date()
        for path in deletedPaths {
            updated.entries = updated.entries.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
        }
        for (path, signature) in verified {
            updated.entries[path] = DevBaselineEntry(signature: signature, lastVerifiedAt: now)
        }
        updated.updatedAt = now
        if !verified.isEmpty || !deletedPaths.isEmpty || baseline != nil {
            try await context.stateStore.saveBaseline(updated, pairID: context.pair.id)
        }
        if !tombstones.isEmpty {
            var stored = await context.stateStore.loadTombstones(pairID: context.pair.id)
            let ids = Set(tombstones.map(\.id))
            stored.removeAll { ids.contains($0.id) }
            stored.append(contentsOf: tombstones)
            try await context.stateStore.saveTombstones(stored, pairID: context.pair.id)
        }
        if !conflicts.isEmpty {
            var stored = await context.stateStore.loadConflicts(pairID: context.pair.id)
            let ids = Set(conflicts.map(\.id))
            stored.removeAll { ids.contains($0.id) }
            stored.append(contentsOf: conflicts)
            try await context.stateStore.saveConflicts(stored, pairID: context.pair.id)
        }
        return updated
    }

    private func finishFailure(
        operation: inout DevOperation,
        state: DevOperationState,
        baseline: DevBaseline?,
        conflicts: [DevConflict],
        committedPaths: [String] = [],
        requeuedPaths: [String],
        deferredPaths: [String],
        bytesWritten: Int64 = 0,
        projectState: DevProjectState,
        error: String
    ) async -> DevOperationOutcome {
        operation.errorSummary = error
        try? await persist(&operation, state: state, terminal: state == .failed || state == .cancelled)
        return DevOperationOutcome(
            operation: operation,
            committedPaths: sortedPaths(committedPaths),
            requeuedPaths: sortedPaths(requeuedPaths),
            deferredPaths: sortedPaths(deferredPaths),
            baseline: baseline,
            tombstones: [],
            conflicts: conflicts,
            bytesWritten: bytesWritten,
            projectState: projectState,
            error: error
        )
    }

    private func persist(_ operation: inout DevOperation, state: DevOperationState, terminal: Bool = false) async throws {
        operation.state = state
        operation.updatedAt = Date()
        if terminal { operation.completedAt = operation.updatedAt }
        try await context.stateStore.saveOperation(operation)
    }

    private func ensureProjectDirectory(_ directory: URL, below root: URL) async throws {
        try await Task.detached(priority: .utility) {
            try Self.createDirectory(directory, below: root)
        }.value
    }

    private func copyRetainedRecord(_ record: DevSafetyRecord, to destination: URL, below root: URL) async throws {
        try await Task.detached(priority: .utility) {
            try Self.createDirectory(destination.deletingLastPathComponent(), below: root)
            guard Self.entryKind(at: destination) == nil else { throw DevOperationRunnerError.preconditionChanged(record.originalRelativePath) }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: record.safetyPath), to: destination)
        }.value
    }

    private func projectRoot(for side: DevSyncSide) -> URL {
        Self.projectRoot(context: context, side: side)
    }

    private func safetyRelativePath(_ path: String) -> String {
        guard let project = context.project else { return path }
        return project.relativePath.isEmpty ? path : "\(project.relativePath)/\(path)"
    }

    private var compareMode: Bool {
        context.capabilities.internalVolume?.supportsUnixPermissions == true
            && context.capabilities.externalVolume?.supportsUnixPermissions == true
    }

    private var timestampToleranceNanoseconds: Int64 {
        context.capabilities.rsync?.protocolVersion.map { $0 < 30 } == true
            ? max(1_000_000_000, context.capabilities.timestampToleranceNanoseconds)
            : context.capabilities.timestampToleranceNanoseconds
    }

    private func mutationPaths(in plan: DevSyncPlan) -> [String] {
        sortedPaths(plan.actions.filter { $0.kind != .noOp && $0.kind != .createConflict }.map(\.relativePath))
    }

    private func bytes(for paths: [String], plan: DevSyncPlan) -> Int64 {
        let pathSet = Set(paths)
        return plan.actions.filter { $0.kind == .copyPath && pathSet.contains($0.relativePath) }
            .reduce(0) { $0 + max(0, $1.bytes) }
    }

    private func sortedPaths<S: Sequence>(_ paths: S) -> [String] where S.Element == String {
        Array(Set(paths)).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    fileprivate nonisolated static func projectRoot(context: DevOperationContext, side: DevSyncSide) -> URL {
        let root = side == .internal ? context.internalRoot : context.externalRoot
        guard let project = context.project else { return root }
        return root.appendingPathComponent(project.relativePath, isDirectory: true)
    }

    private nonisolated static func requireDestination(
        _ preconditions: DevActionPreconditions,
        at url: URL,
        label: String
    ) throws {
        if preconditions.expectDestinationAbsent {
            guard entryKind(at: url) == nil else { throw DevOperationRunnerError.preconditionChanged(label) }
        } else {
            try requireSignature(preconditions.expectedDestinationSignature, at: url, label: label)
        }
    }

    private nonisolated static func requireSignature(
        _ expected: DevFileSignature?,
        at url: URL,
        label: String,
        allowMissingForDeleteAfterStage: Bool = false
    ) throws {
        guard let expected else { return }
        guard let actual = try? DevSnapshotScanner.signature(of: url, includeHash: expected.contentHash != nil) else {
            if allowMissingForDeleteAfterStage { return }
            throw DevOperationRunnerError.preconditionChanged(label)
        }
        guard signaturesMatch(expected, actual, tolerance: 0, compareMode: true) else {
            throw DevOperationRunnerError.preconditionChanged(label)
        }
    }

    fileprivate nonisolated static func signaturesMatch(
        _ expected: DevFileSignature,
        _ actual: DevFileSignature,
        tolerance: Int64,
        compareMode: Bool
    ) -> Bool {
        guard expected.quickMatches(actual, toleranceNanoseconds: tolerance, compareMode: compareMode) else { return false }
        return expected.contentHash == nil || expected.contentHash == actual.contentHash
    }

    private nonisolated static func validateParents(of url: URL, below root: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let parentPath = parent.path
        guard parentPath == rootPath || parentPath.hasPrefix(rootPath + "/") else {
            throw DevOperationRunnerError.invalidAction
        }
        var current = root
        let relative = String(parentPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if entryKind(at: root) == .symlink { throw DevOperationRunnerError.invalidAction }
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            if entryKind(at: current) == .symlink { throw DevOperationRunnerError.invalidAction }
        }
    }

    fileprivate nonisolated static func createDirectory(_ directory: URL, below root: URL) throws {
        let root = root.standardizedFileURL
        let directory = directory.standardizedFileURL
        guard directory.path == root.path || directory.path.hasPrefix(root.path + "/"), entryKind(at: root) == .directory else {
            throw DevOperationRunnerError.invalidAction
        }
        var current = root
        let relative = String(directory.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            if let kind = entryKind(at: current) {
                guard kind == .directory else { throw DevOperationRunnerError.invalidAction }
            } else {
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
    }

    fileprivate nonisolated static func entryKind(at url: URL) -> DevEntryKind? {
        var value = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return lstat(path, &value) == 0
        }) else { return nil }
        switch value.st_mode & S_IFMT {
        case S_IFREG: return DevEntryKind.file
        case S_IFDIR: return DevEntryKind.directory
        case S_IFLNK: return DevEntryKind.symlink
        default: return DevEntryKind.unsupported
        }
    }

    private nonisolated static func redactedPath(_ path: String) -> String {
        let components = DevRelativePath.components(path)
        guard !components.contains(where: { component in
            DevSyncDefaults.sensitivePatterns.contains { DevRelativePath.matchesGlob($0, name: component) }
        }) else {
            return "<sensitive>"
        }
        return components.suffix(2).joined(separator: "/")
    }
}

nonisolated enum DevRecovery {
    static func recover(operation: DevOperation, context: DevOperationContext) async -> DevRecoveryDecision {
        guard !operation.state.isTerminal else { return .replan }
        let rootsValid = await Task.detached(priority: .utility) {
            DevSyncRoots.volumeIdentifier(for: context.internalRoot) == context.pair.internalRoot.volumeIdentifier
                && DevSyncRoots.volumeIdentifier(for: context.externalRoot) == context.pair.externalRoot.volumeIdentifier
        }.value
        guard rootsValid else { return .leaveForUser("A Dev Sync root or drive identity does not match.") }

        let copyActions = operation.plan.actions.filter { $0.kind == .copyPath }
        if operation.state == .transferComplete || operation.state == .verifying || operation.state == .recoveryRequired {
            var verified: [String] = []
            for action in copyActions {
                guard let signature = action.preconditions.expectedSourceSignature else { continue }
                let sourceRoot = DevOperationRunner.projectRoot(context: context, side: action.destinationSide.opposite)
                let destinationRoot = DevOperationRunner.projectRoot(context: context, side: action.destinationSide)
                let requireHash = signature.contentHash != nil
                guard (try? DevSnapshotScanner.verify(
                    plannedSource: signature,
                    destinationURL: destinationRoot.appendingPathComponent(action.relativePath),
                    toleranceNanoseconds: timestampTolerance(context),
                    compareMode: true,
                    requireHash: requireHash
                )) == true,
                let currentSource = try? DevSnapshotScanner.signature(
                    of: sourceRoot.appendingPathComponent(action.relativePath),
                    includeHash: requireHash
                ),
                DevOperationRunner.signaturesMatch(
                    signature,
                    currentSource,
                    tolerance: timestampTolerance(context),
                    compareMode: true
                ) else { continue }
                verified.append(action.relativePath)
            }
            if !verified.isEmpty, verified.count == copyActions.count {
                return .commitVerified(verified.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
            }
        }

        let safetyRecords = operation.safetyRecords.isEmpty
            ? await context.stateStore.loadSafetyRecords(pairID: context.pair.id).filter { $0.operationID == operation.id }
            : operation.safetyRecords
        guard !safetyRecords.isEmpty else { return .replan }
        let canRollback = safetyRecords.allSatisfy { record in
            let root = record.side == .internal ? context.internalRoot : context.externalRoot
            let destination = root.appendingPathComponent(record.originalRelativePath)
            return DevOperationRunner.entryKind(at: URL(fileURLWithPath: record.safetyPath)) != nil
                && DevOperationRunner.entryKind(at: destination) == nil
        }
        guard canRollback else {
            return .leaveForUser("Recovery data and the active destination both exist.")
        }
        do {
            try await Task.detached(priority: .utility) {
                for record in safetyRecords {
                    let root = record.side == .internal ? context.internalRoot : context.externalRoot
                    let destination = root.appendingPathComponent(record.originalRelativePath)
                    try DevOperationRunner.createDirectory(destination.deletingLastPathComponent(), below: root)
                    try FileManager.default.moveItem(at: URL(fileURLWithPath: record.safetyPath), to: destination)
                }
            }.value
            return .rollbackSafety
        } catch {
            return .leaveForUser("Safety data could not be restored automatically.")
        }
    }

    private static func timestampTolerance(_ context: DevOperationContext) -> Int64 {
        context.capabilities.rsync?.protocolVersion.map { $0 < 30 } == true
            ? max(1_000_000_000, context.capabilities.timestampToleranceNanoseconds)
            : context.capabilities.timestampToleranceNanoseconds
    }
}

private extension DevOperationContext {
    nonisolated func capabilitiesVolume(_ side: DevSyncSide) -> DevVolumeCapabilities? {
        side == .internal ? capabilities.internalVolume : capabilities.externalVolume
    }
}

private extension DevPlannerOutput {
    nonisolated var projectStateAfterCommit: DevProjectState {
        switch projectState {
        case .syncing, .dirtyInternal, .dirtyExternal, .dirtyBoth, .waitingForQuiet, .waitingForGit: .clean
        default: projectState
        }
    }
}
