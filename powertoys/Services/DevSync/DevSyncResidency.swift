import Darwin
import Foundation

nonisolated struct DevResidencyContext: Sendable {
    var pair: DevSyncPair
    var project: DevProject
    var internalRoot: URL
    var externalRoot: URL
    var capabilities: DevPairCapabilities
    var policy: DevFilePolicyEngine
    var gitDirectoryRelativePath: String?
    var stateStore: DevSyncStateStore
    var safetyStore: DevSafetyStore
    var linkManager: DevManagedLinkManager
    var rsyncExecutable: URL
}

nonisolated enum DevResidencyError: Error, Equatable, Sendable {
    case unexpectedInternalPath(String)
    case stagingVerificationFailed([String])
    case notEnoughSpace(required: Int64, available: Int64)
    case transferFailed(DevRsyncExitClass)
    case linkUnusable(String)
    case wrongResidency
}

nonisolated extension DevFilePolicyEngine: DevPathPolicy {
    func decide(
        relativePath: String,
        kind: DevEntryKind,
        size: Int64,
        isInsideGitDirectory: Bool
    ) -> DevFilePolicyDecision {
        decide(DevPolicyInput(
            relativePath: relativePath,
            kind: kind,
            size: size,
            isInsideGitDirectory: isInsideGitDirectory
        ))
    }
}

nonisolated enum DevResidencyConversion {
    static func moveToExternal(
        _ context: DevResidencyContext,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (project: DevProject, operation: DevOperation) {
        guard DevRelativePath.isSafe(context.project.relativePath),
              context.project.residency == .mirrored || context.project.residency == .internalOnlyPendingMirror,
              context.capabilities.externalVolume?.volumeIdentifier == nil
                || context.capabilities.externalVolume?.volumeIdentifier == context.pair.externalRoot.volumeIdentifier else {
            throw DevResidencyError.wrongResidency
        }

        let originalProject = context.project
        var project = originalProject
        var operation = makeOperation(context: context, kind: .moveToExternal)
        var retirement: DevSafetyRecord?
        var createdLink: DevManagedLink?
        var linkVerified = false

        do {
            try await persist(&operation, state: .planned, store: context.stateStore)
            project.state = .paused
            try await saveProject(project, context: context)
            progress(1.0 / 11.0)

            try await persist(&operation, state: .planned, store: context.stateStore)
            let internalProject = context.internalRoot.appendingPathComponent(project.relativePath).standardizedFileURL
            let externalProject = context.externalRoot.appendingPathComponent(project.relativePath).standardizedFileURL
            try await verifyProjectIdentity(context: context, source: internalProject, existingTarget: externalProject)
            progress(2.0 / 11.0)

            try await persist(&operation, state: .planned, store: context.stateStore)
            let transferInput = try await transferInput(
                context: context,
                projectURL: internalProject,
                destinationVolume: context.capabilities.externalVolume
            )
            operation.plan.manifestToExternal = transferInput.manifest
            operation.bytesPlanned = transferInput.snapshot.includedBytes
            operation.plan.summary.copyToExternalCount = transferInput.manifest.count
            operation.plan.summary.copyToExternalBytes = transferInput.snapshot.includedBytes
            operation.plan.summary.requiredFreeBytes = transferInput.snapshot.includedBytes
            progress(3.0 / 11.0)

            try await persist(&operation, state: .transferRunning, store: context.stateStore)
            let stagingRoot = try await context.safetyStore.directory(.staging, side: .external)
            let stagingProject = stagingRoot.appendingPathComponent(project.id.uuidString, isDirectory: true)
            try prepareStaging(stagingProject, below: stagingRoot)
            let capabilities = try await rsyncCapabilities(context, selfTestDirectory: stagingRoot)
            let partial = try await context.safetyStore.partialDirectory(side: .external)
            let stagingResult = try await runTransfer(
                executable: context.rsyncExecutable,
                capabilities: capabilities,
                pairCapabilities: context.capabilities,
                metadata: context.pair.configuration.metadata,
                source: internalProject,
                destination: stagingProject,
                manifest: transferInput.manifest,
                partialDirectory: partial,
                backupDirectory: nil,
                progressRange: (3.0 / 11.0)...(4.0 / 11.0),
                progress: progress
            )
            try requireSuccess(stagingResult)
            operation.rsyncPath = context.rsyncExecutable.path
            operation.rsyncVersion = capabilities.versionText
            operation.rsyncExitCode = stagingResult.exitCode
            operation.filesTransferred += stagingResult.itemizedPaths.count
            progress(4.0 / 11.0)

            try await persist(&operation, state: .verifying, store: context.stateStore)
            try verify(
                snapshot: transferInput.snapshot,
                manifest: transferInput.manifest,
                destination: stagingProject,
                toleranceNanoseconds: context.capabilities.timestampToleranceNanoseconds,
                compareMode: shouldCompareMode(capabilities: capabilities, context: context)
            )
            operation.bytesTransferred = transferInput.snapshot.includedBytes
            progress(5.0 / 11.0)

            try await persist(&operation, state: .transferComplete, store: context.stateStore)
            if entryKind(at: externalProject) == nil {
                try createParents(for: project.relativePath, under: context.externalRoot)
                try FileManager.default.moveItem(at: stagingProject, to: externalProject)
            } else {
                guard entryKind(at: externalProject) == .directory else { throw DevResidencyError.wrongResidency }
                let backup = try await context.safetyStore.backupDirectory(side: .external, operationID: operation.id)
                let mergeResult = try await runTransfer(
                    executable: context.rsyncExecutable,
                    capabilities: capabilities,
                    pairCapabilities: context.capabilities,
                    metadata: context.pair.configuration.metadata,
                    source: stagingProject,
                    destination: externalProject,
                    manifest: transferInput.manifest,
                    partialDirectory: partial,
                    backupDirectory: backup,
                    progressRange: (5.0 / 11.0)...(6.0 / 11.0),
                    progress: progress
                )
                try requireSuccess(mergeResult)
                operation.rsyncExitCode = mergeResult.exitCode
                operation.filesTransferred += mergeResult.itemizedPaths.count
                try removeStaging(stagingProject, below: stagingRoot)
                try verify(
                    snapshot: transferInput.snapshot,
                    manifest: transferInput.manifest,
                    destination: externalProject,
                    toleranceNanoseconds: context.capabilities.timestampToleranceNanoseconds,
                    compareMode: shouldCompareMode(capabilities: capabilities, context: context)
                )
            }
            progress(6.0 / 11.0)

            try await persist(&operation, state: .safetyPrepared, store: context.stateStore)
            retirement = try await context.safetyStore.retireProject(
                side: .internal,
                projectURL: internalProject,
                relativePath: project.relativePath,
                projectID: project.id,
                operationID: operation.id,
                retainDays: context.pair.configuration.safety.retainDeletesDays
            )
            if let retirement { operation.safetyRecords.append(retirement) }
            progress(7.0 / 11.0)

            try await persist(&operation, state: .safetyPrepared, store: context.stateStore)
            let knownProjectPaths = Set(await context.stateStore.loadProjects(pairID: context.pair.id).map(\.relativePath))
            createdLink = try await context.linkManager.create(
                project: project,
                internalRoot: context.internalRoot,
                externalRoot: context.externalRoot,
                externalVolumeIdentifier: context.pair.externalRoot.volumeIdentifier,
                knownProjectPaths: knownProjectPaths
            )
            progress(8.0 / 11.0)

            try await persist(&operation, state: .verifying, store: context.stateStore)
            guard let createdLink else { throw DevResidencyError.linkUnusable(project.relativePath) }
            try await verifyLink(createdLink, context: context)
            linkVerified = true
            progress(9.0 / 11.0)

            try await persist(&operation, state: .verifying, store: context.stateStore)
            project.residency = .externalResident
            project.state = .clean
            project.lastSuccessAt = Date()
            project.lastError = nil
            try await saveProject(project, context: context)
            operation.state = .committed
            operation.updatedAt = Date()
            operation.completedAt = operation.updatedAt
            try await context.stateStore.saveOperation(operation)
            progress(10.0 / 11.0)

            try await context.stateStore.saveOperation(operation)
            progress(1)
            return (project, operation)
        } catch {
            var rollbackSucceeded = true
            if !linkVerified {
                rollbackSucceeded = await rollbackMoveToExternal(
                    context: context,
                    link: createdLink,
                    retirement: retirement,
                    operationID: operation.id,
                    relativePath: project.relativePath
                )
            }
            var failedProject = originalProject
            failedProject.state = .error
            failedProject.lastError = String(describing: error)
            try? await saveProject(failedProject, context: context)
            operation.state = linkVerified || !rollbackSucceeded ? .recoveryRequired : .failed
            operation.updatedAt = Date()
            operation.completedAt = operation.state == .failed ? operation.updatedAt : nil
            operation.errorSummary = String(describing: error)
            try? await context.stateStore.saveOperation(operation)
            logFailure("Move to External failed", project: project.relativePath)
            throw error
        }
    }

    static func bringInternal(
        _ context: DevResidencyContext,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (project: DevProject, operation: DevOperation) {
        guard DevRelativePath.isSafe(context.project.relativePath),
              context.project.residency == .externalResident,
              context.capabilities.externalVolume?.volumeIdentifier == nil
                || context.capabilities.externalVolume?.volumeIdentifier == context.pair.externalRoot.volumeIdentifier else {
            throw DevResidencyError.wrongResidency
        }

        let originalProject = context.project
        var project = originalProject
        var operation = makeOperation(context: context, kind: .bringInternal)
        var managedLink: DevManagedLink?
        var linkRemoved = false
        var installed = false

        do {
            try await persist(&operation, state: .planned, store: context.stateStore)
            project.state = .paused
            try await saveProject(project, context: context)
            progress(1.0 / 9.0)

            try await persist(&operation, state: .planned, store: context.stateStore)
            let internalProject = context.internalRoot.appendingPathComponent(project.relativePath).standardizedFileURL
            let externalProject = context.externalRoot.appendingPathComponent(project.relativePath).standardizedFileURL
            guard let link = await context.linkManager.links().first(where: { $0.projectID == project.id }) else {
                throw DevResidencyError.unexpectedInternalPath(internalProject.path)
            }
            guard entryKind(at: internalProject) == .symlink else {
                throw DevResidencyError.unexpectedInternalPath(internalProject.path)
            }
            guard await context.linkManager.validate(
                link,
                internalRoot: context.internalRoot,
                externalRoot: context.externalRoot,
                externalVolumeIdentifier: context.pair.externalRoot.volumeIdentifier
            ) == .healthy else {
                throw DevResidencyError.linkUnusable(project.relativePath)
            }
            managedLink = link
            progress(2.0 / 9.0)

            try await persist(&operation, state: .planned, store: context.stateStore)
            guard entryKind(at: externalProject) == .directory else {
                throw DevResidencyError.linkUnusable(project.relativePath)
            }
            let transferInput = try await transferInput(
                context: context,
                projectURL: externalProject,
                destinationVolume: context.capabilities.internalVolume
            )
            operation.plan.manifestToInternal = transferInput.manifest
            operation.bytesPlanned = transferInput.snapshot.includedBytes
            operation.plan.summary.copyToInternalCount = transferInput.manifest.count
            operation.plan.summary.copyToInternalBytes = transferInput.snapshot.includedBytes
            operation.plan.summary.requiredFreeBytes = transferInput.snapshot.includedBytes
            let capacity = await importantCapacity(context.internalRoot)
                ?? context.capabilities.internalVolume?.availableCapacity
                ?? 0
            let reserve = max(0, context.pair.configuration.safety.minimumFreeSpaceReserveBytes)
            let available = capacity > reserve ? capacity - reserve : 0
            guard transferInput.snapshot.includedBytes <= available else {
                throw DevResidencyError.notEnoughSpace(required: transferInput.snapshot.includedBytes, available: available)
            }
            progress(3.0 / 9.0)

            try await persist(&operation, state: .transferRunning, store: context.stateStore)
            let stagingRoot = context.stateStore.pairDirectory(context.pair.id)
                .appendingPathComponent("staging", isDirectory: true)
            try createDirectory(stagingRoot, below: context.stateStore.pairDirectory(context.pair.id))
            let stagingProject = stagingRoot.appendingPathComponent(project.id.uuidString, isDirectory: true)
            try prepareStaging(stagingProject, below: stagingRoot)
            let capabilities = try await rsyncCapabilities(context, selfTestDirectory: stagingRoot)
            let partial = try await context.safetyStore.partialDirectory(side: .internal)
            let result = try await runTransfer(
                executable: context.rsyncExecutable,
                capabilities: capabilities,
                pairCapabilities: context.capabilities,
                metadata: context.pair.configuration.metadata,
                source: externalProject,
                destination: stagingProject,
                manifest: transferInput.manifest,
                partialDirectory: partial,
                backupDirectory: nil,
                progressRange: (3.0 / 9.0)...(4.0 / 9.0),
                progress: progress
            )
            try requireSuccess(result)
            operation.rsyncPath = context.rsyncExecutable.path
            operation.rsyncVersion = capabilities.versionText
            operation.rsyncExitCode = result.exitCode
            operation.filesTransferred = result.itemizedPaths.count
            progress(4.0 / 9.0)

            try await persist(&operation, state: .verifying, store: context.stateStore)
            try verify(
                snapshot: transferInput.snapshot,
                manifest: transferInput.manifest,
                destination: stagingProject,
                toleranceNanoseconds: context.capabilities.timestampToleranceNanoseconds,
                compareMode: shouldCompareMode(capabilities: capabilities, context: context)
            )
            operation.bytesTransferred = transferInput.snapshot.includedBytes
            progress(5.0 / 9.0)

            try await persist(&operation, state: .transferComplete, store: context.stateStore)
            guard let managedLink else { throw DevResidencyError.linkUnusable(project.relativePath) }
            do {
                try await context.linkManager.remove(managedLink, internalRoot: context.internalRoot, operationID: UUID())
                linkRemoved = true
            } catch {
                linkRemoved = entryKind(at: internalProject) == nil
                throw error
            }
            progress(6.0 / 9.0)

            try await persist(&operation, state: .transferComplete, store: context.stateStore)
            guard entryKind(at: internalProject) == nil else {
                throw DevResidencyError.unexpectedInternalPath(internalProject.path)
            }
            try FileManager.default.moveItem(at: stagingProject, to: internalProject)
            installed = true
            progress(7.0 / 9.0)

            try await persist(&operation, state: .verifying, store: context.stateStore)
            guard entryKind(at: externalProject) == .directory else {
                throw DevResidencyError.linkUnusable(project.relativePath)
            }
            progress(8.0 / 9.0)

            try await persist(&operation, state: .verifying, store: context.stateStore)
            project.residency = .mirrored
            project.state = .clean
            project.lastSuccessAt = Date()
            project.lastError = nil
            try await saveProject(project, context: context)
            operation.state = .committed
            operation.updatedAt = Date()
            operation.completedAt = operation.updatedAt
            try await context.stateStore.saveOperation(operation)
            progress(1)
            return (project, operation)
        } catch {
            var rollbackSucceeded = true
            if linkRemoved, !installed, let managedLink {
                do {
                    _ = try await context.linkManager.repair(
                        managedLink,
                        internalRoot: context.internalRoot,
                        externalRoot: context.externalRoot,
                        externalVolumeIdentifier: context.pair.externalRoot.volumeIdentifier,
                        recreateMissing: true
                    )
                } catch {
                    rollbackSucceeded = false
                }
            }
            var failedProject = originalProject
            failedProject.state = .error
            failedProject.lastError = String(describing: error)
            try? await saveProject(failedProject, context: context)
            operation.state = installed || !rollbackSucceeded ? .recoveryRequired : .failed
            operation.updatedAt = Date()
            operation.completedAt = operation.state == .failed ? operation.updatedAt : nil
            operation.errorSummary = String(describing: error)
            try? await context.stateStore.saveOperation(operation)
            logFailure("Bring Internal failed", project: project.relativePath)
            throw error
        }
    }

    static func convertMissingInternalToExternalResident(
        _ context: DevResidencyContext
    ) async throws -> (project: DevProject, operation: DevOperation) {
        guard DevRelativePath.isSafe(context.project.relativePath),
              context.capabilities.externalVolume?.volumeIdentifier == nil
                || context.capabilities.externalVolume?.volumeIdentifier == context.pair.externalRoot.volumeIdentifier else {
            throw DevResidencyError.wrongResidency
        }
        let originalProject = context.project
        var project = originalProject
        var operation = makeOperation(context: context, kind: .moveToExternal)
        var createdLink: DevManagedLink?

        do {
            try await persist(&operation, state: .planned, store: context.stateStore)
            let internalProject = context.internalRoot.appendingPathComponent(project.relativePath).standardizedFileURL
            let externalProject = context.externalRoot.appendingPathComponent(project.relativePath).standardizedFileURL
            guard entryKind(at: internalProject) == nil, entryKind(at: externalProject) == .directory else {
                throw DevResidencyError.wrongResidency
            }
            guard let baseline = await context.stateStore.loadBaseline(projectID: project.id, pairID: context.pair.id) else {
                throw DevResidencyError.stagingVerificationFailed(["baseline"])
            }

            try await persist(&operation, state: .verifying, store: context.stateStore)
            var failedPaths: [String] = []
            for path in baseline.entries.keys.sorted(by: bytewisePrecedes) {
                guard DevRelativePath.isSafe(path),
                      let entry = baseline.entries[path],
                      (try? DevSnapshotScanner.verify(
                        plannedSource: entry.signature,
                        destinationURL: externalProject.appendingPathComponent(path),
                        toleranceNanoseconds: baseline.timestampToleranceNanoseconds,
                        compareMode: true,
                        requireHash: false
                      )) == true else {
                    failedPaths.append(path)
                    continue
                }
            }
            guard failedPaths.isEmpty else { throw DevResidencyError.stagingVerificationFailed(failedPaths) }

            let knownProjectPaths = Set(await context.stateStore.loadProjects(pairID: context.pair.id).map(\.relativePath))
            createdLink = try await context.linkManager.create(
                project: project,
                internalRoot: context.internalRoot,
                externalRoot: context.externalRoot,
                externalVolumeIdentifier: context.pair.externalRoot.volumeIdentifier,
                knownProjectPaths: knownProjectPaths
            )
            guard let createdLink else { throw DevResidencyError.linkUnusable(project.relativePath) }
            try await verifyLink(createdLink, context: context)

            project.residency = .externalResident
            project.state = .clean
            project.lastError = nil
            project.lastSuccessAt = Date()
            try await saveProject(project, context: context)
            operation.state = .committed
            operation.updatedAt = Date()
            operation.completedAt = operation.updatedAt
            try await context.stateStore.saveOperation(operation)
            return (project, operation)
        } catch {
            if let createdLink {
                try? await context.linkManager.remove(createdLink, internalRoot: context.internalRoot, operationID: UUID())
            }
            project = originalProject
            project.state = .missing
            project.lastError = String(describing: error)
            try? await saveProject(project, context: context)
            operation.state = .failed
            operation.updatedAt = Date()
            operation.completedAt = operation.updatedAt
            operation.errorSummary = String(describing: error)
            try? await context.stateStore.saveOperation(operation)
            logFailure("Missing-project conversion failed", project: project.relativePath)
            throw error
        }
    }

    private nonisolated struct TransferInput: Sendable {
        var snapshot: DevSnapshot
        var manifest: [String]
    }

    private static func transferInput(
        context: DevResidencyContext,
        projectURL: URL,
        destinationVolume: DevVolumeCapabilities?
    ) async throws -> TransferInput {
        let first = await DevSnapshotScanner.scan(
            projectURL: projectURL,
            policy: context.policy,
            gitDirectoryRelativePath: context.gitDirectoryRelativePath,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: !(destinationVolume?.isCaseSensitive ?? true),
            hashPaths: []
        )
        guard first.complete, first.collisions.isEmpty else {
            throw DevResidencyError.stagingVerificationFailed(first.unreadablePaths + first.collisions.flatMap { $0 })
        }
        let filePaths = Set(first.entries.compactMap { $0.value.kind == .file ? $0.key : nil })
        let snapshot = await DevSnapshotScanner.scan(
            projectURL: projectURL,
            policy: context.policy,
            gitDirectoryRelativePath: context.gitDirectoryRelativePath,
            managedLinkPaths: [],
            collisionKeyCaseInsensitive: !(destinationVolume?.isCaseSensitive ?? true),
            hashPaths: filePaths
        )
        guard snapshot.complete, snapshot.collisions.isEmpty else {
            throw DevResidencyError.stagingVerificationFailed(snapshot.unreadablePaths + snapshot.collisions.flatMap { $0 })
        }
        let manifest = DevSnapshotScanner.manifest(paths: Set(snapshot.entries.keys))
        guard !manifest.isEmpty else { throw DevResidencyError.stagingVerificationFailed([projectURL.path]) }
        return TransferInput(snapshot: snapshot, manifest: manifest)
    }

    private static func verify(
        snapshot: DevSnapshot,
        manifest: [String],
        destination: URL,
        toleranceNanoseconds: Int64,
        compareMode: Bool
    ) throws {
        var failedPaths: [String] = []
        for path in manifest {
            guard let signature = snapshot.entries[path] else { continue }
            do {
                let verified = try DevSnapshotScanner.verify(
                    plannedSource: signature,
                    destinationURL: destination.appendingPathComponent(path),
                    toleranceNanoseconds: toleranceNanoseconds,
                    compareMode: compareMode,
                    requireHash: signature.kind == .file
                )
                if !verified { failedPaths.append(path) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedPaths.append(path)
            }
        }
        guard failedPaths.isEmpty else { throw DevResidencyError.stagingVerificationFailed(failedPaths) }
    }

    private static func runTransfer(
        executable: URL,
        capabilities: DevRsyncCapabilities,
        pairCapabilities: DevPairCapabilities,
        metadata: DevSyncConfiguration.Metadata,
        source: URL,
        destination: URL,
        manifest: [String],
        partialDirectory: URL,
        backupDirectory: URL?,
        progressRange: ClosedRange<Double>,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> DevRsyncResult {
        let options = DevRsyncOptions.resolve(
            capabilities: capabilities,
            pairCapabilities: pairCapabilities,
            metadata: metadata,
            partialDirectory: partialDirectory,
            backupDirectory: backupDirectory
        )
        let arguments = DevRsyncCommand.arguments(
            capabilities: capabilities,
            options: options,
            sourceRoot: source,
            destinationRoot: destination
        )
        let transfer = DevRsyncTransfer(
            executable: executable,
            arguments: arguments,
            manifest: manifest,
            capabilities: capabilities
        )
        return try await transfer.run { update in
            let fraction = min(1, Double(update.itemizedLines) / Double(max(1, manifest.count)))
            progress(progressRange.lowerBound + fraction * (progressRange.upperBound - progressRange.lowerBound))
        }
    }

    private static func requireSuccess(_ result: DevRsyncResult) throws {
        guard result.exitClass == .success else { throw DevResidencyError.transferFailed(result.exitClass) }
    }

    private static func rsyncCapabilities(
        _ context: DevResidencyContext,
        selfTestDirectory: URL
    ) async throws -> DevRsyncCapabilities {
        if let capabilities = context.capabilities.rsync { return capabilities }
        return try await DevRsyncProbe.probe(executable: context.rsyncExecutable, selfTestDirectory: selfTestDirectory)
    }

    private static func shouldCompareMode(
        capabilities: DevRsyncCapabilities,
        context: DevResidencyContext
    ) -> Bool {
        (capabilities.supportsExecutability || capabilities.supportsPerms)
            && context.capabilities.internalVolume?.supportsUnixPermissions == true
            && context.capabilities.externalVolume?.supportsUnixPermissions == true
    }

    private static func verifyProjectIdentity(
        context: DevResidencyContext,
        source: URL,
        existingTarget: URL
    ) async throws {
        guard entryKind(at: source) == .directory else { throw DevResidencyError.wrongResidency }
        let sourceIdentity = await DevGit.identity(projectURL: source)
        if let expected = context.project.identity, sourceIdentity?.fingerprint != expected.fingerprint {
            throw DevResidencyError.wrongResidency
        }
        guard let targetKind = entryKind(at: existingTarget) else { return }
        guard targetKind == .directory else { throw DevResidencyError.wrongResidency }
        let targetIdentity = await DevGit.identity(projectURL: existingTarget)
        if sourceIdentity?.fingerprint != targetIdentity?.fingerprint {
            throw DevResidencyError.wrongResidency
        }
    }

    private static func verifyLink(_ link: DevManagedLink, context: DevResidencyContext) async throws {
        let state = await context.linkManager.validate(
            link,
            internalRoot: context.internalRoot,
            externalRoot: context.externalRoot,
            externalVolumeIdentifier: context.pair.externalRoot.volumeIdentifier
        )
        guard state == .healthy else { throw DevResidencyError.linkUnusable(link.linkRelativePath) }
        let linkURL = context.internalRoot.appendingPathComponent(link.linkRelativePath)
        let targetText = try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
        guard targetText == link.lastWrittenTargetText else {
            throw DevResidencyError.linkUnusable(link.linkRelativePath)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: linkURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DevResidencyError.linkUnusable(link.linkRelativePath)
        }
    }

    private static func rollbackMoveToExternal(
        context: DevResidencyContext,
        link: DevManagedLink?,
        retirement: DevSafetyRecord?,
        operationID: UUID,
        relativePath: String
    ) async -> Bool {
        let internalProject = context.internalRoot.appendingPathComponent(relativePath)
        if let link {
            try? await context.linkManager.remove(link, internalRoot: context.internalRoot, operationID: UUID())
        }
        if entryKind(at: internalProject) == .symlink {
            _ = unlink(internalProject.path)
            var links = await context.stateStore.loadLinks(pairID: context.pair.id)
            links.removeAll { $0.projectID == context.project.id }
            try? await context.stateStore.saveLinks(links, pairID: context.pair.id)
        }
        let retainedURL = retirement.map { URL(fileURLWithPath: $0.safetyPath) }
            ?? context.stateStore.internalSafetyHistoryDirectory(context.pair.id)
                .appendingPathComponent(operationID.uuidString, isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: true)
        guard entryKind(at: retainedURL) == .directory, entryKind(at: internalProject) == nil else {
            return entryKind(at: internalProject) == .directory
        }
        do {
            try createParents(for: relativePath, under: context.internalRoot)
            try FileManager.default.moveItem(at: retainedURL, to: internalProject)
            let retiredRecordIDs = Set(
                await context.stateStore.loadSafetyRecords(pairID: context.pair.id)
                    .filter { $0.operationID == operationID && $0.kind == .projectRetired }
                    .map(\.id)
            )
            try await context.stateStore.applySafetyRecordChanges(pairID: context.pair.id, removing: retiredRecordIDs, expirations: [:])
            return true
        } catch {
            logFailure("Internal project restore failed", project: relativePath)
            return false
        }
    }

    private static func makeOperation(context: DevResidencyContext, kind: DevOperationKind) -> DevOperation {
        let destination: DevSyncSide = kind == .bringInternal ? .internal : .external
        let action = DevSyncAction(
            kind: .copyPath,
            destinationSide: destination,
            relativePath: context.project.relativePath,
            preconditions: DevActionPreconditions(
                expectedSourceSignature: nil,
                expectedDestinationSignature: nil,
                expectDestinationAbsent: false,
                expectedVolumeIdentifier: context.pair.root(for: destination).volumeIdentifier,
                expectedProjectFingerprint: context.project.identity?.fingerprint,
                expectedParentKind: .directory,
                requiredFreeBytes: context.project.includedBytes,
                policySchemaVersion: context.pair.configuration.policySchemaVersion
            ),
            reason: kind == .bringInternal ? "Bring project internal" : "Move project external"
        )
        let plan = DevSyncPlan(
            pairID: context.pair.id,
            projectID: context.project.id,
            actions: [action]
        )
        return DevOperation(
            pairID: context.pair.id,
            projectID: context.project.id,
            kind: kind,
            plan: plan
        )
    }

    private static func persist(
        _ operation: inout DevOperation,
        state: DevOperationState,
        store: DevSyncStateStore
    ) async throws {
        operation.state = state
        operation.updatedAt = Date()
        try await store.saveOperation(operation)
    }

    private static func saveProject(_ project: DevProject, context: DevResidencyContext) async throws {
        var projects = await context.stateStore.loadProjects(pairID: context.pair.id)
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        try await context.stateStore.saveProjects(projects, pairID: context.pair.id)
    }

    private static func importantCapacity(_ url: URL) async -> Int64? {
        await Task.detached(priority: .utility) {
            guard entryKind(at: url) == .directory else { return nil }
            return DevSyncRoots.availableCapacity(at: url)
        }.value
    }

    private static func prepareStaging(_ staging: URL, below root: URL) throws {
        if entryKind(at: staging) != nil {
            try removeStaging(staging, below: root)
        }
        try createDirectory(staging, below: root)
    }

    private static func removeStaging(_ staging: URL, below root: URL) throws {
        guard isBelow(staging, root: root), entryKind(at: staging) == .directory else {
            throw DevResidencyError.stagingVerificationFailed([staging.path])
        }
        try FileManager.default.removeItem(at: staging)
    }

    private static func createParents(for relativePath: String, under root: URL) throws {
        guard entryKind(at: root) == .directory else { throw DevResidencyError.wrongResidency }
        var current = root
        for component in DevRelativePath.components(relativePath).dropLast() {
            current.appendPathComponent(component, isDirectory: true)
            if let kind = entryKind(at: current) {
                guard kind == .directory else { throw DevResidencyError.wrongResidency }
            } else {
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
    }

    private static func createDirectory(_ directory: URL, below root: URL) throws {
        guard isBelow(directory, root: root), entryKind(at: root) == .directory else {
            throw DevResidencyError.stagingVerificationFailed([directory.path])
        }
        var current = root
        let relative = String(directory.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            if let kind = entryKind(at: current) {
                guard kind == .directory else { throw DevResidencyError.stagingVerificationFailed([current.path]) }
            } else {
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
    }

    private static func isBelow(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return rootPath == "/" ? candidatePath != "/" && candidatePath.hasPrefix("/") : candidatePath.hasPrefix(rootPath + "/")
    }

    private static func entryKind(at url: URL) -> DevEntryKind? {
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return lstat(path, &info) == 0
        }) else { return nil }
        switch info.st_mode & S_IFMT {
        case S_IFREG: return .file
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .unsupported
        }
    }

    private static func bytewisePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private static func logFailure(_ message: String, project: String) {
        Task { @MainActor in
            LogManager.shared.warning("\(message): \(project)", source: "DevSync")
        }
    }
}
