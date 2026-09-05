import CryptoKit
import Foundation

nonisolated enum DevEntryState: Equatable, Sendable {
    case absent
    case unchanged
    case changed
    case added
    case typeChanged
    case unreadable
    case unstable
}

nonisolated struct DevPlannerInput: Sendable {
    var pair: DevSyncPair
    var project: DevProject
    var baseline: DevBaseline?
    var internalSnapshot: DevSnapshot?
    var externalSnapshot: DevSnapshot?
    var tombstones: [DevTombstone]
    var unresolvedConflicts: [DevConflict]
    var capabilities: DevPairCapabilities
    var unstablePaths: Set<String>
    var now: Date
}

nonisolated struct DevPlannerOutput: Equatable, Sendable {
    var plan: DevSyncPlan
    var newConflicts: [DevConflict]
    var newTombstones: [DevTombstone]
    var driftPaths: [String]
    var externalOnlyPaths: [String]
    var needsHashes: Set<String>
    var projectState: DevProjectState
    var warnings: [DevProjectWarning]
}

nonisolated enum DevReconciliationPlanner {
    static func plan(_ input: DevPlannerInput) -> DevPlannerOutput {
        var planner = DevPlanningContext(input: input)
        return planner.build()
    }

    static func entryState(
        baseline: DevFileSignature?,
        current: DevFileSignature?,
        isUnreadable: Bool,
        isUnstable: Bool,
        toleranceNanoseconds: Int64,
        compareMode: Bool
    ) -> DevEntryState {
        if isUnreadable { return .unreadable }
        if isUnstable { return .unstable }
        guard let baseline else { return current == nil ? .absent : .added }
        guard let current else { return .absent }
        guard baseline.kind == current.kind else { return .typeChanged }
        return baseline.quickMatches(current, toleranceNanoseconds: toleranceNanoseconds, compareMode: compareMode)
            ? .unchanged
            : .changed
    }

    static func matchRenames(baseline: DevBaseline, snapshot: DevSnapshot) -> [(from: String, to: String)] {
        let baselinePaths = Set(baseline.entries.keys)
        let snapshotPaths = Set(snapshot.entries.keys)
        var missing = baseline.entries.filter { !snapshotPaths.contains($0.key) }
        var additions = snapshot.entries.filter { !baselinePaths.contains($0.key) }
        missing = missing.filter { plannablePath($0.key) }
        additions = additions.filter { plannablePath($0.key) }

        var usedFrom = Set<String>()
        var matches: [(from: String, to: String)] = []
        for addition in additions.sorted(by: { bytewisePrecedes($0.key, $1.key) }) {
            let resourceMatches = missing.filter { old in
                !usedFrom.contains(old.key)
                    && old.value.signature.resourceIdentifier != nil
                    && old.value.signature.resourceIdentifier == addition.value.resourceIdentifier
            }
            if resourceMatches.count == 1, let match = resourceMatches.first {
                usedFrom.insert(match.key)
                matches.append((match.key, addition.key))
                continue
            }

            let hashMatches = missing.filter { old in
                let oldSignature = old.value.signature
                return !usedFrom.contains(old.key)
                    && oldSignature.kind == addition.value.kind
                    && oldSignature.size == addition.value.size
                    && oldSignature.contentHash != nil
                    && oldSignature.contentHash == addition.value.contentHash
            }
            if hashMatches.count == 1, let match = hashMatches.first {
                usedFrom.insert(match.key)
                matches.append((match.key, addition.key))
            }
        }
        return matches
    }

    fileprivate static func plannablePath(_ path: String) -> Bool {
        DevRelativePath.isSafe(path) && !DevRelativePath.isCloudSyncSystemPath(path)
    }

    fileprivate static func bytewisePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}

private nonisolated struct DevPlanningContext {
    let input: DevPlannerInput
    let compareMode: Bool
    let scanComplete: Bool
    var deletionsAllowed: Bool
    var actions: [DevSyncAction] = []
    var manifests: [DevSyncSide: Set<String>] = [.internal: [], .external: []]
    var conflicts: [DevConflict] = []
    var tombstones: [DevTombstone] = []
    var driftPaths: Set<String> = []
    var externalOnlyPaths: Set<String> = []
    var needsHashes: Set<String> = []
    var warnings: [DevProjectWarning]
    var deferred = false
    var blockedState: DevProjectState?
    var consumedPaths: Set<String> = []

    init(input: DevPlannerInput) {
        self.input = input
        compareMode = input.capabilities.internalVolume?.supportsUnixPermissions == true
            && input.capabilities.externalVolume?.supportsUnixPermissions == true
        scanComplete = input.internalSnapshot?.complete == true && input.externalSnapshot?.complete == true
        let projectAllowsDeletion = !input.project.state.isBlocked
            && ![.paused, .missing, .error, .linkOffline, .linkMissing].contains(input.project.state)
        let noUnreadablePaths = input.internalSnapshot?.unreadablePaths.isEmpty == true
            && input.externalSnapshot?.unreadablePaths.isEmpty == true
        deletionsAllowed = scanComplete
            && input.internalSnapshot != nil
            && input.externalSnapshot != nil
            && projectAllowsDeletion
            && noUnreadablePaths
            && input.unstablePaths.isEmpty
        warnings = input.project.warnings
        if !scanComplete || !noUnreadablePaths { addWarning(.incompleteScan) }
        if input.capabilities.fidelity == .portable { addWarning(.portableFidelity) }
    }

    mutating func build() -> DevPlannerOutput {
        guard input.internalSnapshot != nil, input.externalSnapshot != nil else {
            deferred = true
            return output()
        }
        if blockForExistingConflicts() || blockForCollisions() { return output() }
        processPolicyExclusions()
        processRenames()

        var paths = Set<String>()
        if let baseline = input.baseline { paths.formUnion(baseline.entries.keys) }
        if let internalSnapshot = input.internalSnapshot { paths.formUnion(internalSnapshot.entries.keys) }
        if let externalSnapshot = input.externalSnapshot { paths.formUnion(externalSnapshot.entries.keys) }
        for path in paths.sorted(by: DevReconciliationPlanner.bytewisePrecedes)
        where DevReconciliationPlanner.plannablePath(path) && !consumedPaths.contains(path) && !isManagedOrSystemExcluded(path) {
            process(path: path)
        }
        return output()
    }

    private mutating func blockForExistingConflicts() -> Bool {
        let unresolved = input.unresolvedConflicts.filter { !$0.isResolved && $0.projectID == input.project.id }
        guard unresolved.contains(where: \.type.blocksWholeProject) else { return false }
        deletionsAllowed = false
        blockedState = unresolved.contains { conflict in
            [.caseCollision, .normalizationCollision, .projectPath, .managedLinkCollision].contains(conflict.type)
        } ? .blockedByFileSystem : .blockedByTopology
        return true
    }

    private mutating func blockForCollisions() -> Bool {
        var found = false
        inspectCollisions(input.internalSnapshot, side: .internal, destinationIsCaseSensitive: input.capabilities.externalVolume?.isCaseSensitive ?? true, found: &found)
        inspectCollisions(input.externalSnapshot, side: .external, destinationIsCaseSensitive: input.capabilities.internalVolume?.isCaseSensitive ?? true, found: &found)
        if found {
            actions.removeAll()
            manifests = [.internal: [], .external: []]
            deletionsAllowed = false
            blockedState = .blockedByFileSystem
        }
        return found
    }

    private mutating func inspectCollisions(
        _ snapshot: DevSnapshot?,
        side: DevSyncSide,
        destinationIsCaseSensitive: Bool,
        found: inout Bool
    ) {
        guard let snapshot else { return }
        for group in snapshot.collisions where group.count > 1 {
            let normalized = Set(group.map { $0.precomposedStringWithCanonicalMapping })
            let type: DevConflictType = normalized.count < group.count ? .normalizationCollision : .caseCollision
            let canCopyFromSide = input.pair.mode == .devBidirectional || side == .internal
            guard type == .normalizationCollision || (canCopyFromSide && !destinationIsCaseSensitive) else { continue }
            found = true
            addWarning(type == .caseCollision ? .caseCollision : .normalizationCollision)
            addConflict(
                path: group.sorted(by: DevReconciliationPlanner.bytewisePrecedes).first ?? "",
                type: type,
                baseline: nil,
                internalSignature: nil,
                externalSignature: nil,
                detail: group.sorted(by: DevReconciliationPlanner.bytewisePrecedes).joined(separator: "\n")
            )
        }
    }

    private mutating func processPolicyExclusions() {
        guard let baseline = input.baseline, let internalSnapshot = input.internalSnapshot else { return }
        let roots = internalSnapshot.excluded
            .filter { path, reason in
                baseline.entries[path] != nil
                    && reason != .managedLink
                    && reason != .cloudSyncInternalPath
                    && DevReconciliationPlanner.plannablePath(path)
            }
            .map(\.key)
            .sorted(by: DevReconciliationPlanner.bytewisePrecedes)
        for path in roots where !consumedPaths.contains(path) {
            let descendants = baseline.entries.keys.filter { $0 == path || $0.hasPrefix(path + "/") }
            consumedPaths.formUnion(descendants)
            guard deletionsAllowed, let baselineSignature = baseline.entries[path]?.signature else {
                deferred = true
                continue
            }
            let externalSignature = input.externalSnapshot?.entries[path] ?? baselineSignature
            appendDeletion(path: path, deletedFrom: .internal, destination: .external, signature: externalSignature, baseline: baselineSignature, reason: "Path excluded by current policy")
        }
    }

    private mutating func processRenames() {
        guard let baseline = input.baseline else { return }
        let internalRenames = input.internalSnapshot?.complete == true
            ? Dictionary(uniqueKeysWithValues: collapsedRenames(DevReconciliationPlanner.matchRenames(baseline: baseline, snapshot: input.internalSnapshot!), baseline: baseline).map { ($0.from, $0.to) })
            : [:]
        let externalRenames = input.externalSnapshot?.complete == true
            ? Dictionary(uniqueKeysWithValues: collapsedRenames(DevReconciliationPlanner.matchRenames(baseline: baseline, snapshot: input.externalSnapshot!), baseline: baseline).map { ($0.from, $0.to) })
            : [:]
        let oldPaths = Set(internalRenames.keys).union(externalRenames.keys)
        let tombstonePaths = Set(input.tombstones.filter { $0.projectID == input.project.id }.map(\.relativePath))

        for oldPath in oldPaths.sorted(by: DevReconciliationPlanner.bytewisePrecedes) where !tombstonePaths.contains(oldPath) {
            let internalNewPath = internalRenames[oldPath]
            let externalNewPath = externalRenames[oldPath]
            consumedPaths.insert(oldPath)
            if let internalNewPath { consumedPaths.insert(internalNewPath) }
            if let externalNewPath { consumedPaths.insert(externalNewPath) }
            let baselineSignature = baseline.entries[oldPath]?.signature

            if let internalNewPath, let externalNewPath {
                if internalNewPath == externalNewPath {
                    appendEstablishBaseline(path: internalNewPath, internalSignature: input.internalSnapshot?.entries[internalNewPath], externalSignature: input.externalSnapshot?.entries[externalNewPath], reason: "Rename found on both sides")
                } else {
                    addConflict(path: oldPath, type: .renameRename, baseline: baselineSignature, internalSignature: input.internalSnapshot?.entries[internalNewPath], externalSignature: input.externalSnapshot?.entries[externalNewPath])
                }
                continue
            }

            if let internalNewPath {
                guard counterpartMatchesBaseline(path: oldPath, side: .external, baseline: baselineSignature),
                      let externalSignature = input.externalSnapshot?.entries[oldPath]
                else {
                    addConflict(path: oldPath, type: .renameModify, baseline: baselineSignature, internalSignature: input.internalSnapshot?.entries[internalNewPath], externalSignature: input.externalSnapshot?.entries[oldPath])
                    continue
                }
                appendMove(from: oldPath, to: internalNewPath, side: .external, signature: externalSignature)
                if let baselineSignature, let renamedSignature = input.internalSnapshot?.entries[internalNewPath],
                   renamedSignature.kind == .directory {
                    processRenamedDirectory(from: oldPath, to: internalNewPath, renamedSide: .internal)
                } else if let baselineSignature, let renamedSignature = input.internalSnapshot?.entries[internalNewPath],
                          !signatureMatches(renamedSignature, baselineSignature) {
                    appendCopy(path: internalNewPath, sourceSide: .internal, source: renamedSignature, destination: externalSignature)
                }
                continue
            }

            guard let externalNewPath else { continue }
            if input.pair.mode == .devOneWay {
                driftPaths.insert(oldPath)
                continue
            }
            guard counterpartMatchesBaseline(path: oldPath, side: .internal, baseline: baselineSignature),
                  let internalSignature = input.internalSnapshot?.entries[oldPath]
            else {
                addConflict(path: oldPath, type: .renameModify, baseline: baselineSignature, internalSignature: input.internalSnapshot?.entries[oldPath], externalSignature: input.externalSnapshot?.entries[externalNewPath])
                continue
            }
            appendMove(from: oldPath, to: externalNewPath, side: .internal, signature: internalSignature)
            if let baselineSignature, let renamedSignature = input.externalSnapshot?.entries[externalNewPath],
               renamedSignature.kind == .directory {
                processRenamedDirectory(from: oldPath, to: externalNewPath, renamedSide: .external)
            } else if let baselineSignature, let renamedSignature = input.externalSnapshot?.entries[externalNewPath],
                      !signatureMatches(renamedSignature, baselineSignature) {
                appendCopy(path: externalNewPath, sourceSide: .external, source: renamedSignature, destination: internalSignature)
            }
        }
    }

    private mutating func processRenamedDirectory(from oldRoot: String, to newRoot: String, renamedSide: DevSyncSide) {
        guard let baseline = input.baseline else { return }
        let oldPrefix = oldRoot + "/"
        let newPrefix = newRoot + "/"
        var suffixes = Set(baseline.entries.keys.compactMap { path in
            path.hasPrefix(oldPrefix) ? String(path.dropFirst(oldPrefix.count)) : nil
        })
        if let internalEntries = input.internalSnapshot?.entries {
            let prefix = renamedSide == .internal ? newPrefix : oldPrefix
            suffixes.formUnion(internalEntries.keys.compactMap { path in
                path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
            })
        }
        if let externalEntries = input.externalSnapshot?.entries {
            let prefix = renamedSide == .external ? newPrefix : oldPrefix
            suffixes.formUnion(externalEntries.keys.compactMap { path in
                path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
            })
        }

        for suffix in suffixes.sorted(by: DevReconciliationPlanner.bytewisePrecedes) {
            let oldPath = oldPrefix + suffix
            let newPath = newPrefix + suffix
            consumedPaths.insert(oldPath)
            consumedPaths.insert(newPath)
            guard DevReconciliationPlanner.plannablePath(oldPath), DevReconciliationPlanner.plannablePath(newPath),
                  tombstoneFor(path: oldPath) == nil, tombstoneFor(path: newPath) == nil,
                  !isManagedOrSystemExcluded(oldPath), !isManagedOrSystemExcluded(newPath)
            else {
                deferred = true
                continue
            }

            let storedBaseline = baseline.entries[oldPath]?.signature
            let internalPath = renamedSide == .internal ? newPath : oldPath
            let externalPath = renamedSide == .external ? newPath : oldPath
            let internalSignature = input.internalSnapshot?.entries[internalPath]
            let externalSignature = input.externalSnapshot?.entries[externalPath]
            let internalState = state(baseline: storedBaseline, current: internalSignature, snapshot: input.internalSnapshot, path: internalPath)
            let externalState = state(baseline: storedBaseline, current: externalSignature, snapshot: input.externalSnapshot, path: externalPath)
            if [.unreadable, .unstable].contains(internalState) || [.unreadable, .unstable].contains(externalState) {
                deferred = true
                deletionsAllowed = false
            } else if let storedBaseline {
                processBaselinePath(
                    path: newPath,
                    baseline: storedBaseline,
                    internalSignature: internalSignature,
                    externalSignature: externalSignature,
                    internalState: internalState,
                    externalState: externalState
                )
            } else {
                processFirstRunPath(path: newPath, internalSignature: internalSignature, externalSignature: externalSignature)
            }
        }
    }

    private func collapsedRenames(_ matches: [(from: String, to: String)], baseline: DevBaseline) -> [(from: String, to: String)] {
        matches.filter { match in
            !matches.contains { parent in
                guard parent.from != match.from,
                      baseline.entries[parent.from]?.signature.kind == .directory,
                      match.from.hasPrefix(parent.from + "/")
                else { return false }
                return match.to == parent.to + match.from.dropFirst(parent.from.count)
            }
        }
    }

    private func counterpartMatchesBaseline(path: String, side: DevSyncSide, baseline: DevFileSignature?) -> Bool {
        guard let baseline else { return false }
        let current = side == .internal ? input.internalSnapshot?.entries[path] : input.externalSnapshot?.entries[path]
        return current?.quickMatches(baseline, toleranceNanoseconds: input.capabilities.timestampToleranceNanoseconds, compareMode: compareMode) == true
    }

    private mutating func process(path: String) {
        guard !hasUnresolvedConflict(path: path) else {
            deferred = true
            return
        }
        let storedBaseline = input.baseline?.entries[path]?.signature
        let internalSignature = input.internalSnapshot?.entries[path]
        let externalSignature = input.externalSnapshot?.entries[path]
        if processTombstone(path: path, internalSignature: internalSignature, externalSignature: externalSignature) { return }

        let effectiveBaseline = tombstoneFor(path: path) == nil ? storedBaseline : nil
        let internalState = state(baseline: effectiveBaseline, current: internalSignature, snapshot: input.internalSnapshot, path: path)
        let externalState = state(baseline: effectiveBaseline, current: externalSignature, snapshot: input.externalSnapshot, path: path)
        if [.unreadable, .unstable].contains(internalState) || [.unreadable, .unstable].contains(externalState) {
            deferred = true
            deletionsAllowed = false
            return
        }
        if effectiveBaseline == nil {
            processFirstRunPath(path: path, internalSignature: internalSignature, externalSignature: externalSignature)
        } else {
            processBaselinePath(
                path: path,
                baseline: effectiveBaseline!,
                internalSignature: internalSignature,
                externalSignature: externalSignature,
                internalState: internalState,
                externalState: externalState
            )
        }
    }

    private mutating func processFirstRunPath(path: String, internalSignature: DevFileSignature?, externalSignature: DevFileSignature?) {
        switch (internalSignature, externalSignature) {
        case (nil, nil):
            return
        case (let source?, nil):
            appendCopy(path: path, sourceSide: .internal, source: source, destination: nil)
        case (nil, let source?):
            if input.pair.mode == .devOneWay {
                externalOnlyPaths.insert(path)
                addWarning(.externalOnlyPaths)
            } else {
                appendCopy(path: path, sourceSide: .external, source: source, destination: nil)
            }
        case (let internalEntry?, let externalEntry?):
            guard internalEntry.kind == externalEntry.kind else {
                addConflict(path: path, type: .typeChange, baseline: nil, internalSignature: internalEntry, externalSignature: externalEntry)
                return
            }
            if contentEqual(internalEntry, externalEntry) {
                appendEstablishBaseline(path: path, internalSignature: internalEntry, externalSignature: externalEntry, reason: "First-run entries match")
            } else if hashesNeeded(internalEntry, externalEntry) {
                needsHashes.insert(path)
                deferred = true
            } else if internalEntry.kind != .file,
                      internalEntry.quickMatches(externalEntry, toleranceNanoseconds: input.capabilities.timestampToleranceNanoseconds, compareMode: compareMode) {
                appendEstablishBaseline(path: path, internalSignature: internalEntry, externalSignature: externalEntry, reason: "First-run entries match")
            } else {
                addConflict(path: path, type: .contentContent, baseline: nil, internalSignature: internalEntry, externalSignature: externalEntry)
            }
        }
    }

    private mutating func processBaselinePath(
        path: String,
        baseline: DevFileSignature,
        internalSignature: DevFileSignature?,
        externalSignature: DevFileSignature?,
        internalState: DevEntryState,
        externalState: DevEntryState
    ) {
        if internalState == .typeChanged || externalState == .typeChanged {
            if let internalEntry = internalSignature, let externalEntry = externalSignature,
               internalEntry.kind == externalEntry.kind, contentEqual(internalEntry, externalEntry) {
                appendEstablishBaseline(path: path, internalSignature: internalEntry, externalSignature: externalEntry, reason: "Matching type change")
            } else {
                addConflict(path: path, type: .typeChange, baseline: baseline, internalSignature: internalSignature, externalSignature: externalSignature)
            }
            return
        }
        if let internalEntry = internalSignature, let externalEntry = externalSignature,
           (internalState == .changed || externalState == .changed),
           contentEqual(internalEntry, externalEntry) {
            appendEstablishBaseline(path: path, internalSignature: internalEntry, externalSignature: externalEntry, reason: "Current contents match")
            return
        }
        if internalState == .changed, let internalEntry = internalSignature, contentEqual(internalEntry, baseline), externalState == .unchanged {
            appendEstablishBaseline(path: path, internalSignature: internalEntry, externalSignature: externalSignature, reason: "Internal metadata changed")
            return
        }
        if externalState == .changed, let externalEntry = externalSignature, contentEqual(externalEntry, baseline), internalState == .unchanged {
            appendEstablishBaseline(path: path, internalSignature: internalSignature, externalSignature: externalEntry, reason: "External metadata changed")
            return
        }

        switch (internalState, externalState) {
        case (.unchanged, .unchanged), (.absent, .absent):
            return
        case (.changed, .unchanged):
            appendCopy(path: path, sourceSide: .internal, source: internalSignature!, destination: externalSignature)
        case (.unchanged, .changed):
            if input.pair.mode == .devOneWay {
                driftPaths.insert(path)
            } else {
                appendCopy(path: path, sourceSide: .external, source: externalSignature!, destination: internalSignature)
            }
        case (.absent, .unchanged):
            appendDeletionIfAllowed(path: path, deletedFrom: .internal, destination: .external, signature: externalSignature!, baseline: baseline)
        case (.unchanged, .absent):
            if input.pair.mode == .devOneWay {
                driftPaths.insert(path)
            } else {
                appendDeletionIfAllowed(path: path, deletedFrom: .external, destination: .internal, signature: internalSignature!, baseline: baseline)
            }
        case (.changed, .changed):
            if let internalEntry = internalSignature, let externalEntry = externalSignature, hashesNeeded(internalEntry, externalEntry) {
                needsHashes.insert(path)
                deferred = true
            } else {
                addConflict(path: path, type: .contentContent, baseline: baseline, internalSignature: internalSignature, externalSignature: externalSignature)
            }
        case (.absent, .changed):
            addConflict(path: path, type: .deleteModify, baseline: baseline, internalSignature: nil, externalSignature: externalSignature)
        case (.changed, .absent):
            addConflict(path: path, type: .modifyDelete, baseline: baseline, internalSignature: internalSignature, externalSignature: nil)
        default:
            deferred = true
        }
    }

    private mutating func processTombstone(path: String, internalSignature: DevFileSignature?, externalSignature: DevFileSignature?) -> Bool {
        guard let tombstone = tombstoneFor(path: path) else { return false }
        if input.pair.mode == .devOneWay {
            guard internalSignature == nil, let externalEntry = externalSignature,
                  signatureMatches(externalEntry, tombstone.baselineSignature)
            else { return false }
            appendDeletionIfAllowed(path: path, deletedFrom: .internal, destination: .external, signature: externalEntry, baseline: tombstone.baselineSignature, createTombstone: false)
            return true
        }
        if externalSignature == nil, let internalEntry = internalSignature, signatureMatches(internalEntry, tombstone.baselineSignature) {
            appendDeletionIfAllowed(path: path, deletedFrom: .external, destination: .internal, signature: internalEntry, baseline: tombstone.baselineSignature, createTombstone: false)
            return true
        }
        if internalSignature == nil, let externalEntry = externalSignature, signatureMatches(externalEntry, tombstone.baselineSignature) {
            appendDeletionIfAllowed(path: path, deletedFrom: .internal, destination: .external, signature: externalEntry, baseline: tombstone.baselineSignature, createTombstone: false)
            return true
        }
        return false
    }

    private func tombstoneFor(path: String) -> DevTombstone? {
        input.tombstones.first { $0.projectID == input.project.id && $0.relativePath == path }
    }

    private func state(baseline: DevFileSignature?, current: DevFileSignature?, snapshot: DevSnapshot?, path: String) -> DevEntryState {
        DevReconciliationPlanner.entryState(
            baseline: baseline,
            current: current,
            isUnreadable: affected(path: path, by: snapshot?.unreadablePaths ?? []),
            isUnstable: affected(path: path, by: Array(input.unstablePaths)),
            toleranceNanoseconds: input.capabilities.timestampToleranceNanoseconds,
            compareMode: compareMode
        )
    }

    private func affected(path: String, by problemPaths: [String]) -> Bool {
        problemPaths.contains { problem in
            problem.isEmpty || path == problem || path.hasPrefix(problem + "/")
        }
    }

    private func hashesNeeded(_ lhs: DevFileSignature, _ rhs: DevFileSignature) -> Bool {
        lhs.kind == .file && rhs.kind == .file && (lhs.contentHash == nil || rhs.contentHash == nil)
    }

    private func contentEqual(_ lhs: DevFileSignature, _ rhs: DevFileSignature) -> Bool {
        guard lhs.kind == rhs.kind else { return false }
        switch lhs.kind {
        case .file:
            return lhs.contentHash != nil && lhs.contentHash == rhs.contentHash
        case .symlink:
            return lhs.symlinkTarget == rhs.symlinkTarget
        case .directory:
            return true
        case .unsupported:
            return lhs == rhs
        }
    }

    private func signatureMatches(_ lhs: DevFileSignature, _ rhs: DevFileSignature) -> Bool {
        contentEqual(lhs, rhs)
            || lhs.quickMatches(rhs, toleranceNanoseconds: input.capabilities.timestampToleranceNanoseconds, compareMode: compareMode)
    }

    private mutating func appendCopy(path: String, sourceSide: DevSyncSide, source: DevFileSignature, destination: DevFileSignature?) {
        guard source.kind != .unsupported else {
            deferred = true
            return
        }
        let destinationSide = sourceSide.opposite
        if source.kind == .directory {
            guard destination == nil else { return }
            appendAction(kind: .createDirectory, destinationSide: destinationSide, path: path, source: source, destination: nil, overwrites: false, bytes: 0, reason: "Create missing directory")
            return
        }
        if let destination {
            appendStage(path: path, side: destinationSide, signature: destination, reason: "Retain destination before overwrite")
        }
        let bytes = signedSize(source.size)
        appendAction(
            kind: .copyPath,
            destinationSide: destinationSide,
            path: path,
            source: source,
            destination: destination,
            overwrites: destination != nil,
            bytes: bytes,
            reason: "Copy \(sourceSide.displayName.lowercased()) change"
        )
        manifests[destinationSide, default: []].insert(path)
    }

    private mutating func appendDeletionIfAllowed(
        path: String,
        deletedFrom: DevSyncSide,
        destination: DevSyncSide,
        signature: DevFileSignature,
        baseline: DevFileSignature,
        createTombstone: Bool = true
    ) {
        guard deletionsAllowed else {
            deferred = true
            return
        }
        appendDeletion(path: path, deletedFrom: deletedFrom, destination: destination, signature: signature, baseline: baseline, reason: "Propagate verified deletion", createTombstone: createTombstone)
    }

    private mutating func appendDeletion(
        path: String,
        deletedFrom: DevSyncSide,
        destination: DevSyncSide,
        signature: DevFileSignature,
        baseline: DevFileSignature,
        reason: String,
        createTombstone: Bool = true
    ) {
        appendStage(path: path, side: destination, signature: signature, reason: "Retain path before deletion")
        appendAction(kind: .deletePath, destinationSide: destination, path: path, source: nil, destination: signature, overwrites: false, bytes: signedSize(signature.size), reason: reason)
        guard createTombstone else { return }
        tombstones.append(
            DevTombstone(
                projectID: input.project.id,
                relativePath: path,
                deletedFromSide: deletedFrom,
                baselineSignature: baseline,
                createdAt: input.now,
                observedInternal: deletedFrom == .internal,
                observedExternal: deletedFrom == .external,
                expiresAt: input.now.addingTimeInterval(TimeInterval(input.pair.configuration.safety.retainDeletesDays) * 86_400)
            )
        )
    }

    private mutating func appendMove(from: String, to: String, side: DevSyncSide, signature: DevFileSignature) {
        appendStage(path: from, side: side, signature: signature, reason: "Retain rename source")
        appendAction(kind: .movePath, destinationSide: side, path: from, destinationPath: to, source: signature, destination: nil, overwrites: false, bytes: signedSize(signature.size), reason: "Move confirmed rename")
    }

    private mutating func appendStage(path: String, side: DevSyncSide, signature: DevFileSignature, reason: String) {
        appendAction(kind: .stageExistingVersion, destinationSide: side, path: path, source: signature, destination: signature, overwrites: false, bytes: signedSize(signature.size), reason: reason)
    }

    private mutating func appendEstablishBaseline(path: String, internalSignature: DevFileSignature?, externalSignature: DevFileSignature?, reason: String) {
        appendAction(kind: .establishBaseline, destinationSide: .external, path: path, source: internalSignature, destination: externalSignature, overwrites: false, bytes: 0, reason: reason)
    }

    private mutating func addConflict(
        path: String,
        type: DevConflictType,
        baseline: DevFileSignature?,
        internalSignature: DevFileSignature?,
        externalSignature: DevFileSignature?,
        detail: String? = nil
    ) {
        guard !conflicts.contains(where: { $0.relativePath == path && $0.type == type }) else { return }
        let conflict = DevConflict(
            id: stableUUID(["conflict", input.project.id.uuidString, path, type.rawValue]),
            projectID: input.project.id,
            relativePath: path,
            type: type,
            baselineSignature: baseline,
            internalSignature: internalSignature,
            externalSignature: externalSignature,
            createdAt: input.now,
            detail: detail
        )
        conflicts.append(conflict)
        appendAction(kind: .createConflict, destinationSide: .external, path: path, source: internalSignature, destination: externalSignature, conflictType: type, overwrites: false, bytes: 0, reason: type.displayName)
    }

    private mutating func appendAction(
        kind: DevSyncActionKind,
        destinationSide: DevSyncSide,
        path: String,
        destinationPath: String? = nil,
        source: DevFileSignature?,
        destination: DevFileSignature?,
        conflictType: DevConflictType? = nil,
        overwrites: Bool,
        bytes: Int64,
        reason: String
    ) {
        let ordinal = actions.count
        actions.append(
            DevSyncAction(
                id: stableUUID(["action", input.project.id.uuidString, kind.rawValue, destinationSide.rawValue, path, destinationPath ?? "", String(ordinal)]),
                kind: kind,
                destinationSide: destinationSide,
                relativePath: path,
                destinationRelativePath: destinationPath,
                conflictType: conflictType,
                overwritesDestination: overwrites,
                bytes: bytes,
                preconditions: DevActionPreconditions(
                    expectedSourceSignature: source,
                    expectedDestinationSignature: destination,
                    expectDestinationAbsent: destination == nil,
                    expectedVolumeIdentifier: input.pair.root(for: destinationSide).volumeIdentifier,
                    expectedProjectFingerprint: input.project.identity?.fingerprint,
                    expectedParentKind: .directory,
                    requiredFreeBytes: kind == .copyPath || kind == .createDirectory ? bytes : 0,
                    policySchemaVersion: input.pair.configuration.policySchemaVersion
                ),
                reason: reason
            )
        )
    }

    private func hasUnresolvedConflict(path: String) -> Bool {
        input.unresolvedConflicts.contains { !$0.isResolved && $0.projectID == input.project.id && $0.relativePath == path }
    }

    private func isManagedOrSystemExcluded(_ path: String) -> Bool {
        [input.internalSnapshot, input.externalSnapshot].contains { snapshot in
            snapshot?.excluded.contains { excludedPath, reason in
                (reason == .managedLink || reason == .cloudSyncInternalPath)
                    && (path == excludedPath || path.hasPrefix(excludedPath + "/"))
            } == true
        }
    }

    private mutating func output() -> DevPlannerOutput {
        if !externalOnlyPaths.isEmpty { addWarning(.externalOnlyPaths) }
        let sortedActions = actions
        let summary = summary(for: sortedActions)
        let plan = DevSyncPlan(
            id: stableUUID(["plan", input.pair.id.uuidString, input.project.id.uuidString, String(input.now.timeIntervalSinceReferenceDate)]),
            pairID: input.pair.id,
            projectID: input.project.id,
            createdAt: input.now,
            actions: sortedActions,
            manifestToExternal: (manifests[.external] ?? []).sorted(by: DevReconciliationPlanner.bytewisePrecedes),
            manifestToInternal: (manifests[.internal] ?? []).sorted(by: DevReconciliationPlanner.bytewisePrecedes),
            summary: summary,
            scanComplete: scanComplete,
            deletionsAllowed: deletionsAllowed
        )
        return DevPlannerOutput(
            plan: plan,
            newConflicts: conflicts,
            newTombstones: tombstones,
            driftPaths: driftPaths.sorted(by: DevReconciliationPlanner.bytewisePrecedes),
            externalOnlyPaths: externalOnlyPaths.sorted(by: DevReconciliationPlanner.bytewisePrecedes),
            needsHashes: needsHashes,
            projectState: projectState,
            warnings: warnings
        )
    }

    private var projectState: DevProjectState {
        if let blockedState { return blockedState }
        if !conflicts.isEmpty || input.unresolvedConflicts.contains(where: { !$0.isResolved && $0.projectID == input.project.id }) { return .conflict }
        if !driftPaths.isEmpty { return .destinationDrift }
        if !actions.isEmpty { return .syncing }
        if deferred || !needsHashes.isEmpty {
            switch input.project.state {
            case .dirtyInternal, .dirtyExternal, .dirtyBoth, .waitingForQuiet, .waitingForGit:
                return input.project.state
            default:
                return .dirtyBoth
            }
        }
        return .clean
    }

    private func summary(for actions: [DevSyncAction]) -> DevPlanSummary {
        var summary = DevPlanSummary()
        for action in actions {
            switch action.kind {
            case .copyPath:
                if action.destinationSide == .external {
                    summary.copyToExternalCount += 1
                    summary.copyToExternalBytes += action.bytes
                } else {
                    summary.copyToInternalCount += 1
                    summary.copyToInternalBytes += action.bytes
                }
                summary.requiredFreeBytes += action.preconditions.requiredFreeBytes
            case .createManagedLink:
                summary.managedLinksToCreate += 1
            case .stageExistingVersion:
                summary.safetyMoveCount += 1
            case .deletePath:
                summary.deletionCount += 1
            case .createConflict:
                summary.conflictCount += 1
            default:
                break
            }
        }
        summary.retainedExternalOnlyCount = externalOnlyPaths.count
        summary.blockedPathCount = conflicts.count
        summary.ignoredBytes = (input.internalSnapshot?.excludedBytes ?? 0) + (input.externalSnapshot?.excludedBytes ?? 0)
        return summary
    }

    private mutating func addWarning(_ warning: DevProjectWarning) {
        if !warnings.contains(warning) { warnings.append(warning) }
    }

    private func signedSize(_ size: UInt64?) -> Int64 {
        guard let size else { return 0 }
        return size > UInt64(Int64.max) ? Int64.max : Int64(size)
    }
}

nonisolated struct DevCatalogInput: Sendable {
    var pair: DevSyncPair
    var knownProjects: [DevProject]
    var internalDiscovery: DevDiscoveryResult?
    var externalDiscovery: DevDiscoveryResult?
    var links: [DevManagedLink]
    var internalIdentities: [String: DevProjectIdentity]
    var externalIdentities: [String: DevProjectIdentity]
    var excludedProjectPaths: Set<String>
    var includedCandidatePaths: Set<String>
    var adoptedLinkPaths: Set<String>
    /// Drive-only directories outside every project that should become linked projects.
    var linkableExternalDirectories: Set<String> = []
}

nonisolated struct DevCatalogOutput: Equatable, Sendable {
    var projects: [DevProject]
    var projectsToMirror: [DevProject]
    var projectsToLink: [DevProject]
    var adoptableLinks: [String: String]
    var conflicts: [DevConflict]
    var missingProjects: [DevProject]
    var renameCandidates: [DevRenameCandidate]
    var candidates: [DevProjectCandidate]
}

nonisolated enum DevCatalogPlanner {
    static func plan(_ input: DevCatalogInput) -> DevCatalogOutput {
        var planner = DevCatalogPlanningContext(input: input)
        return planner.build()
    }
}

private nonisolated struct DevCatalogPlanningContext {
    let input: DevCatalogInput
    var internalProjects: [String: DevDiscoveredProject]
    var externalProjects: [String: DevDiscoveredProject]
    var projects: [DevProject] = []
    var projectsToMirror: [DevProject] = []
    var projectsToLink: [DevProject] = []
    var adoptableLinks: [String: String] = [:]
    var conflicts: [DevConflict] = []
    var missingProjects: [DevProject] = []
    var renameCandidates: [DevRenameCandidate] = []
    var consumedKnownIDs: Set<UUID> = []
    var consumedPaths: Set<String> = []

    init(input: DevCatalogInput) {
        self.input = input
        internalProjects = Dictionary(uniqueKeysWithValues: (input.internalDiscovery?.projects ?? []).map { ($0.relativePath, $0) })
        externalProjects = Dictionary(uniqueKeysWithValues: (input.externalDiscovery?.projects ?? []).map { ($0.relativePath, $0) })
        for candidate in (input.internalDiscovery?.candidates ?? []) + (input.externalDiscovery?.candidates ?? [])
        where input.includedCandidatePaths.contains(candidate.relativePath) {
            let discovered = DevDiscoveredProject(
                relativePath: candidate.relativePath,
                side: candidate.side,
                kind: .nonGit,
                url: input.pair.root(for: candidate.side).url.appendingPathComponent(candidate.relativePath),
                resourceIdentifier: nil
            )
            if candidate.side == .internal { internalProjects[candidate.relativePath] = discovered }
            else { externalProjects[candidate.relativePath] = discovered }
        }
        for path in input.linkableExternalDirectories
        where DevRelativePath.isSafe(path) && internalProjects[path] == nil && externalProjects[path] == nil {
            externalProjects[path] = DevDiscoveredProject(
                relativePath: path,
                side: .external,
                kind: .nonGit,
                url: input.pair.externalRoot.url.appendingPathComponent(path),
                resourceIdentifier: nil
            )
        }
        // A linked plain folder is not a repository, so neither walk reports it once the
        // internal link exists. Its healthy link is the evidence that it is still there.
        for project in input.knownProjects
        where project.kind == .nonGit
            && (project.residency == .externalResident || project.residency == .externalOnlyPendingLink)
            && externalProjects[project.relativePath] == nil
            && input.links.contains(where: { $0.linkRelativePath == project.relativePath && $0.state == .healthy }) {
            externalProjects[project.relativePath] = DevDiscoveredProject(
                relativePath: project.relativePath,
                side: .external,
                kind: .nonGit,
                url: input.pair.externalRoot.url.appendingPathComponent(project.relativePath),
                resourceIdentifier: project.externalResourceIdentifier
            )
        }
    }

    mutating func build() -> DevCatalogOutput {
        findRenames()
        applySafeRenames()
        let knownByPath = Dictionary(uniqueKeysWithValues: input.knownProjects.filter { !consumedKnownIDs.contains($0.id) }.map { ($0.relativePath, $0) })
        var paths = Set(knownByPath.keys)
        paths.formUnion(internalProjects.keys)
        paths.formUnion(externalProjects.keys)
        paths.formUnion(input.links.map(\.linkRelativePath))
        if let symlinks = input.internalDiscovery?.symlinksToExternal { paths.formUnion(symlinks.keys) }

        for path in paths.sorted(by: DevReconciliationPlanner.bytewisePrecedes) where !consumedPaths.contains(path) && !path.isEmpty {
            reconcile(path: path, known: knownByPath[path])
        }
        var rootUnit = knownByPath[""] ?? makeProject(path: "", kind: .nonGit, residency: .mirrored)
        rootUnit.residency = .mirrored
        rootUnit.explicitlyIncluded = true
        rootUnit.explicitlyExcluded = false
        if knownByPath[""] == nil { rootUnit.state = .clean }
        return DevCatalogOutput(
            projects: projects.sorted { DevReconciliationPlanner.bytewisePrecedes($0.relativePath, $1.relativePath) } + [rootUnit],
            projectsToMirror: projectsToMirror.sorted { DevReconciliationPlanner.bytewisePrecedes($0.relativePath, $1.relativePath) },
            projectsToLink: projectsToLink.sorted { DevReconciliationPlanner.bytewisePrecedes($0.relativePath, $1.relativePath) },
            adoptableLinks: adoptableLinks,
            conflicts: conflicts,
            missingProjects: missingProjects.sorted { DevReconciliationPlanner.bytewisePrecedes($0.relativePath, $1.relativePath) },
            renameCandidates: renameCandidates.sorted { DevReconciliationPlanner.bytewisePrecedes($0.current.relativePath, $1.current.relativePath) },
            candidates: remainingCandidates()
        )
    }

    private mutating func findRenames() {
        renameCandidates = []
        if input.internalDiscovery?.complete == true {
            renameCandidates += DevProjectDiscovery.matchRenames(
                previous: input.knownProjects,
                current: Array(internalProjects.values),
                side: .internal,
                identitiesByRelativePath: input.internalIdentities.filter { $0.value.firstCommit != nil }
            )
        }
        if input.externalDiscovery?.complete == true {
            renameCandidates += DevProjectDiscovery.matchRenames(
                previous: input.knownProjects,
                current: Array(externalProjects.values),
                side: .external,
                identitiesByRelativePath: input.externalIdentities.filter { $0.value.firstCommit != nil }
            )
        }
        var unique: [String: DevRenameCandidate] = [:]
        for candidate in renameCandidates {
            let key = "\(candidate.previous.id.uuidString):\(candidate.current.side.rawValue):\(candidate.current.relativePath)"
            if candidate.confidence > (unique[key]?.confidence ?? -1) { unique[key] = candidate }
        }
        renameCandidates = Array(unique.values)
    }

    private mutating func applySafeRenames() {
        let grouped = Dictionary(grouping: renameCandidates.filter { $0.confidence >= 0.9 }, by: { $0.previous.id })
        for (projectID, candidates) in grouped {
            let destinations = Set(candidates.map(\.current.relativePath))
            guard destinations.count == 1, let destination = destinations.first,
                  var project = input.knownProjects.first(where: { $0.id == projectID })
            else { continue }
            project.relativePath = destination
            if let internalCandidate = candidates.first(where: { $0.current.side == .internal }) {
                project.internalResourceIdentifier = internalCandidate.current.resourceIdentifier
            }
            if let externalCandidate = candidates.first(where: { $0.current.side == .external }) {
                project.externalResourceIdentifier = externalCandidate.current.resourceIdentifier
            }
            project.state = .syncing
            projects.append(project)
            consumedKnownIDs.insert(projectID)
            consumedPaths.insert(project.relativePath)
            consumedPaths.insert(candidates[0].previous.relativePath)
        }
        let pending = renameCandidates.filter { $0.confidence < 0.9 }
        for candidate in pending {
            consumedPaths.insert(candidate.current.relativePath)
        }
    }

    private mutating func reconcile(path: String, known: DevProject?) {
        guard DevReconciliationPlanner.plannablePath(path) else { return }
        let internalProject = internalProjects[path]
        let externalProject = externalProjects[path]
        let link = input.links.first { $0.linkRelativePath == path }
        let userLinkTarget = input.internalDiscovery?.symlinksToExternal[path]
        let excluded = input.excludedProjectPaths.contains(path)

        if let link, link.state == .replaced || (link != nil && internalProject != nil) {
            var project = known ?? makeProject(path: path, kind: externalProject?.kind ?? internalProject?.kind ?? .nonGit, residency: .externalResident)
            project.state = .blockedByFileSystem
            project.explicitlyExcluded = excluded
            projects.append(project)
            addCatalogConflict(project: project, type: .managedLinkCollision)
            return
        }
        if internalProject == nil, let externalProject, let userLinkTarget,
           !input.adoptedLinkPaths.contains(path), userLinkTarget != expectedExternalTarget(path: path) {
            var project = known ?? makeProject(path: path, kind: externalProject.kind, residency: .externalOnlyPendingLink)
            project.state = .blockedByFileSystem
            project.explicitlyExcluded = excluded
            projects.append(project)
            addCatalogConflict(project: project, type: .projectPath)
            return
        }
        if internalProject != nil, externalProject != nil, identitiesDiffer(path: path) {
            var project = update(known ?? makeProject(path: path, kind: internalProject!.kind, residency: .mirrored), internalProject: internalProject, externalProject: externalProject)
            project.state = .blockedByTopology
            project.explicitlyExcluded = excluded
            projects.append(project)
            addCatalogConflict(project: project, type: .projectIdentity)
            return
        }
        if hasNonProjectCollision(path: path, internalProject: internalProject, externalProject: externalProject) {
            var project = known ?? makeProject(path: path, kind: internalProject?.kind ?? externalProject?.kind ?? .nonGit, residency: .mirrored)
            project.state = .blockedByFileSystem
            project.explicitlyExcluded = excluded
            projects.append(project)
            addCatalogConflict(project: project, type: .projectPath)
            return
        }

        switch (internalProject, externalProject) {
        case (let internalProject?, let externalProject?):
            var project = update(known ?? makeProject(path: path, kind: internalProject.kind, residency: .mirrored), internalProject: internalProject, externalProject: externalProject)
            project.residency = .mirrored
            project.state = .clean
            project.explicitlyExcluded = excluded
            projects.append(project)
        case (let internalProject?, nil):
            reconcileInternalOnly(path: path, known: known, discovered: internalProject, excluded: excluded)
        case (nil, let externalProject?):
            reconcileExternalOnly(path: path, known: known, discovered: externalProject, link: link, userLinkTarget: userLinkTarget, excluded: excluded)
        case (nil, nil):
            reconcileMissing(path: path, known: known, link: link, excluded: excluded)
        }
    }

    private mutating func reconcileInternalOnly(path: String, known: DevProject?, discovered: DevDiscoveredProject, excluded: Bool) {
        var project = update(known ?? makeProject(path: path, kind: discovered.kind, residency: .internalOnlyPendingMirror), internalProject: discovered, externalProject: nil)
        project.explicitlyExcluded = excluded
        if let known, input.externalDiscovery?.complete != true {
            project.residency = known.residency
            project.state = known.state
            projects.append(project)
            return
        }
        if let known, known.residency == .mirrored, input.externalDiscovery?.complete == true, input.pair.mode == .devBidirectional {
            project.residency = .mirrored
            project.state = .paused
            missingProjects.append(project)
        } else {
            project.residency = .internalOnlyPendingMirror
            project.state = .dirtyInternal
            if !excluded, input.externalDiscovery?.complete == true { projectsToMirror.append(project) }
        }
        projects.append(project)
    }

    private mutating func reconcileExternalOnly(
        path: String,
        known: DevProject?,
        discovered: DevDiscoveredProject,
        link: DevManagedLink?,
        userLinkTarget: String?,
        excluded: Bool
    ) {
        var project = update(known ?? makeProject(path: path, kind: discovered.kind, residency: .externalOnlyPendingLink), internalProject: nil, externalProject: discovered)
        project.explicitlyExcluded = excluded
        if let known, input.internalDiscovery?.complete != true {
            project.residency = known.residency
            project.state = known.state
            projects.append(project)
            return
        }
        if let known, known.residency == .mirrored, input.internalDiscovery?.complete == true, input.pair.mode == .devBidirectional {
            project.residency = .mirrored
            project.state = .paused
            missingProjects.append(project)
        } else if link?.state == .healthy || input.adoptedLinkPaths.contains(path) {
            project.residency = .externalResident
            project.state = .clean
        } else if let userLinkTarget {
            project.residency = .externalOnlyPendingLink
            project.state = .dirtyExternal
            adoptableLinks[path] = userLinkTarget
        } else {
            project.residency = .externalOnlyPendingLink
            project.state = .dirtyExternal
            if !excluded, input.internalDiscovery?.complete == true { projectsToLink.append(project) }
        }
        projects.append(project)
    }

    private mutating func reconcileMissing(path: String, known: DevProject?, link: DevManagedLink?, excluded: Bool) {
        guard var project = known else { return }
        project.explicitlyExcluded = excluded
        let internalComplete = input.internalDiscovery?.complete == true
        let externalComplete = input.externalDiscovery?.complete == true
        guard internalComplete || externalComplete else {
            projects.append(project)
            return
        }
        if project.residency == .externalResident || link != nil {
            guard externalComplete else {
                projects.append(project)
                return
            }
            project.state = .missing
        } else if internalComplete && externalComplete {
            project.state = .missing
        } else {
            projects.append(project)
            return
        }
        missingProjects.append(project)
        projects.append(project)
    }

    private func hasNonProjectCollision(
        path: String,
        internalProject: DevDiscoveredProject?,
        externalProject: DevDiscoveredProject?
    ) -> Bool {
        let internalCandidate = input.internalDiscovery?.candidates.contains { $0.relativePath == path && !input.includedCandidatePaths.contains(path) } == true
        let externalCandidate = input.externalDiscovery?.candidates.contains { $0.relativePath == path && !input.includedCandidatePaths.contains(path) } == true
        return (internalCandidate && externalProject != nil) || (externalCandidate && internalProject != nil)
    }

    private func identitiesDiffer(path: String) -> Bool {
        guard let internalIdentity = input.internalIdentities[path], let externalIdentity = input.externalIdentities[path] else { return false }
        return internalIdentity.fingerprint != externalIdentity.fingerprint
    }

    private func expectedExternalTarget(path: String) -> String {
        input.pair.externalRoot.url.appendingPathComponent(path).standardizedFileURL.path
    }

    private func update(_ project: DevProject, internalProject: DevDiscoveredProject?, externalProject: DevDiscoveredProject?) -> DevProject {
        var project = project
        if let internalProject {
            project.kind = internalProject.kind
            project.internalResourceIdentifier = internalProject.resourceIdentifier
            project.identity = input.internalIdentities[internalProject.relativePath] ?? project.identity
        }
        if let externalProject {
            project.externalResourceIdentifier = externalProject.resourceIdentifier
            project.identity = project.identity ?? input.externalIdentities[externalProject.relativePath]
        }
        return project
    }

    private func makeProject(path: String, kind: DevProjectKind, residency: DevProjectResidency) -> DevProject {
        DevProject(
            id: stableUUID(["project", input.pair.id.uuidString, path]),
            pairID: input.pair.id,
            relativePath: path,
            residency: residency,
            kind: kind
        )
    }

    private mutating func addCatalogConflict(project: DevProject, type: DevConflictType) {
        conflicts.append(
            DevConflict(
                id: stableUUID(["catalog-conflict", project.id.uuidString, type.rawValue]),
                projectID: project.id,
                relativePath: project.relativePath,
                type: type,
                createdAt: input.pair.updatedAt
            )
        )
    }

    private func remainingCandidates() -> [DevProjectCandidate] {
        ((input.internalDiscovery?.candidates ?? []) + (input.externalDiscovery?.candidates ?? []))
            .filter { !input.includedCandidatePaths.contains($0.relativePath) && !input.excludedProjectPaths.contains($0.relativePath) }
            .sorted { $0.id < $1.id }
    }

}

private nonisolated func stableUUID(_ parts: [String]) -> UUID {
    var bytes = Array(SHA256.hash(data: Data(parts.joined(separator: "\u{0}").utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}
