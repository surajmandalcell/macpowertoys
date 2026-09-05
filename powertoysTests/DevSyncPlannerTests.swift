import Foundation
import XCTest
@testable import powertoys

final class DevSyncPlannerTests: XCTestCase {
    func testEntryStateUsesQuickSignatureToleranceAndFlags() {
        XCTAssertEqual(DevReconciliationPlanner.entryState(baseline: nil, current: nil, isUnreadable: false, isUnstable: false, toleranceNanoseconds: 0, compareMode: true), .absent)
        XCTAssertEqual(DevReconciliationPlanner.entryState(baseline: nil, current: signature(1), isUnreadable: false, isUnstable: false, toleranceNanoseconds: 0, compareMode: true), .added)
        XCTAssertEqual(DevReconciliationPlanner.entryState(baseline: signature(1), current: signature(1), isUnreadable: false, isUnstable: false, toleranceNanoseconds: 0, compareMode: true), .unchanged)
        XCTAssertEqual(DevReconciliationPlanner.entryState(baseline: signature(1), current: signature(2), isUnreadable: false, isUnstable: false, toleranceNanoseconds: 0, compareMode: true), .changed)
        XCTAssertEqual(DevReconciliationPlanner.entryState(baseline: signature(1), current: signature(1, kind: .directory), isUnreadable: false, isUnstable: false, toleranceNanoseconds: 0, compareMode: true), .typeChanged)
        XCTAssertEqual(DevReconciliationPlanner.entryState(baseline: signature(1), current: nil, isUnreadable: true, isUnstable: false, toleranceNanoseconds: 0, compareMode: true), .unreadable)
        XCTAssertEqual(DevReconciliationPlanner.entryState(baseline: signature(1), current: signature(1), isUnreadable: false, isUnstable: true, toleranceNanoseconds: 0, compareMode: true), .unstable)
    }

    func testOneWaySameAsBaselineSameAsBaselineDoesNothing() {
        XCTAssertTrue(plan(mode: .devOneWay, baseline: signature(1), internalEntry: signature(1), externalEntry: signature(1)).plan.actions.isEmpty)
    }

    func testOneWayChangedInternalUnchangedExternalCopiesOutward() {
        assertKinds(plan(mode: .devOneWay, baseline: signature(1), internalEntry: signature(2), externalEntry: signature(1)), [.stageExistingVersion, .copyPath])
    }

    func testOneWayAddedInternalAbsentExternalCopiesOutward() {
        let output = plan(mode: .devOneWay, baseline: nil, internalEntry: signature(2), externalEntry: nil)
        assertKinds(output, [.copyPath])
        XCTAssertEqual(output.plan.manifestToExternal, [path])
    }

    func testOneWayDeletedInternalUnchangedExternalQuarantinesAndTombstones() {
        let output = plan(mode: .devOneWay, baseline: signature(1), internalEntry: nil, externalEntry: signature(1))
        assertKinds(output, [.stageExistingVersion, .deletePath])
        XCTAssertEqual(output.newTombstones.count, 1)
        XCTAssertEqual(output.newTombstones[0].deletedFromSide, .internal)
        XCTAssertEqual(output.newTombstones[0].expiresAt, now.addingTimeInterval(30 * 86_400))
    }

    func testOneWayChangedBothDifferentlyConflicts() {
        assertConflict(plan(mode: .devOneWay, baseline: signature(1), internalEntry: signature(2), externalEntry: signature(3)), .contentContent)
    }

    func testOneWayDeletedInternalChangedExternalConflicts() {
        assertConflict(plan(mode: .devOneWay, baseline: signature(1), internalEntry: nil, externalEntry: signature(3)), .deleteModify)
    }

    func testOneWayUnchangedInternalChangedExternalRecordsDrift() {
        let output = plan(mode: .devOneWay, baseline: signature(1), internalEntry: signature(1), externalEntry: signature(3))
        XCTAssertEqual(output.driftPaths, [path])
        XCTAssertEqual(output.projectState, .destinationDrift)
    }

    func testOneWayUnchangedInternalDeletedExternalRecordsDrift() {
        let output = plan(mode: .devOneWay, baseline: signature(1), internalEntry: signature(1), externalEntry: nil)
        XCTAssertEqual(output.driftPaths, [path])
        XCTAssertTrue(output.plan.actions.isEmpty)
    }

    func testOneWayNoBaselineExternalAddedIsRetained() {
        let output = plan(mode: .devOneWay, baseline: nil, internalEntry: nil, externalEntry: signature(2))
        XCTAssertEqual(output.externalOnlyPaths, [path])
        XCTAssertTrue(output.plan.actions.isEmpty)
    }

    func testOneWayBothAddedDifferentlyConflicts() {
        assertConflict(plan(mode: .devOneWay, baseline: nil, internalEntry: signature(2), externalEntry: signature(3)), .contentContent)
    }

    func testOneWaySameContentDifferentMetadataEstablishesBaseline() {
        let sharedHash = Data([9])
        let output = plan(mode: .devOneWay, baseline: signature(1, contentHash: sharedHash), internalEntry: signature(2, contentHash: sharedHash), externalEntry: signature(1, contentHash: sharedHash))
        assertKinds(output, [.establishBaseline])
    }

    func testOneWayUnreadableOrUnstableDefersAndDisablesDeletion() {
        let output = plan(mode: .devOneWay, baseline: signature(1), internalEntry: nil, externalEntry: signature(1), unreadableInternal: [path])
        XCTAssertTrue(output.plan.actions.isEmpty)
        XCTAssertFalse(output.plan.deletionsAllowed)
        XCTAssertEqual(output.projectState, .dirtyBoth)
    }

    func testBidirectionalSameAsBaselineSameAsBaselineDoesNothing() {
        XCTAssertTrue(plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(1), externalEntry: signature(1)).plan.actions.isEmpty)
    }

    func testBidirectionalChangedInternalUnchangedExternalCopiesOutward() {
        assertKinds(plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(2), externalEntry: signature(1)), [.stageExistingVersion, .copyPath])
    }

    func testBidirectionalUnchangedInternalChangedExternalCopiesInward() {
        let output = plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(1), externalEntry: signature(2))
        assertKinds(output, [.stageExistingVersion, .copyPath])
        XCTAssertEqual(output.plan.manifestToInternal, [path])
    }

    func testBidirectionalAddedInternalAbsentExternalCopiesOutward() {
        assertKinds(plan(mode: .devBidirectional, baseline: nil, internalEntry: signature(2), externalEntry: nil), [.copyPath])
    }

    func testBidirectionalAbsentInternalAddedExternalCopiesInward() {
        assertKinds(plan(mode: .devBidirectional, baseline: nil, internalEntry: nil, externalEntry: signature(2)), [.copyPath])
    }

    func testBidirectionalDeletedInternalUnchangedExternalDeletesExternal() {
        let output = plan(mode: .devBidirectional, baseline: signature(1), internalEntry: nil, externalEntry: signature(1))
        assertKinds(output, [.stageExistingVersion, .deletePath])
        XCTAssertEqual(output.newTombstones.first?.deletedFromSide, .internal)
    }

    func testBidirectionalUnchangedInternalDeletedExternalDeletesInternal() {
        let output = plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(1), externalEntry: nil)
        assertKinds(output, [.stageExistingVersion, .deletePath])
        XCTAssertEqual(output.newTombstones.first?.deletedFromSide, .external)
    }

    func testBidirectionalChangedBothSameHashEstablishesBaseline() {
        let hash = Data([8])
        assertKinds(plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(2, contentHash: hash), externalEntry: signature(3, contentHash: hash)), [.establishBaseline])
    }

    func testBidirectionalChangedBothWithoutHashesRequestsHashes() {
        let output = plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(2, contentHash: nil), externalEntry: signature(3, contentHash: nil))
        XCTAssertEqual(output.needsHashes, [path])
        XCTAssertTrue(output.plan.actions.isEmpty)
    }

    func testBidirectionalChangedBothDifferentlyConflicts() {
        assertConflict(plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(2), externalEntry: signature(3)), .contentContent)
    }

    func testBidirectionalDeletedInternalChangedExternalConflicts() {
        assertConflict(plan(mode: .devBidirectional, baseline: signature(1), internalEntry: nil, externalEntry: signature(3)), .deleteModify)
    }

    func testBidirectionalChangedInternalDeletedExternalConflicts() {
        assertConflict(plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(3), externalEntry: nil), .modifyDelete)
    }

    func testBidirectionalTypeChangedAgainstNonidenticalStateConflicts() {
        assertConflict(plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(2, kind: .directory), externalEntry: signature(1)), .typeChange)
    }

    func testBidirectionalBothAddedSameContentEstablishesBaseline() {
        let hash = Data([7])
        assertKinds(plan(mode: .devBidirectional, baseline: nil, internalEntry: signature(2, contentHash: hash), externalEntry: signature(3, contentHash: hash)), [.establishBaseline])
    }

    func testBidirectionalBothAddedDifferentlyConflicts() {
        assertConflict(plan(mode: .devBidirectional, baseline: nil, internalEntry: signature(2), externalEntry: signature(3)), .contentContent)
    }

    func testBidirectionalUnreadableOrUnstableDefersDestructiveAction() {
        let output = plan(mode: .devBidirectional, baseline: signature(1), internalEntry: nil, externalEntry: signature(1), unstablePaths: [path])
        XCTAssertTrue(output.plan.actions.isEmpty)
        XCTAssertFalse(output.plan.deletionsAllowed)
    }

    func testFirstRunPresentIdenticalEstablishesBaseline() {
        assertKinds(plan(mode: .devOneWay, baseline: nil, internalEntry: signature(1), externalEntry: signature(1)), [.establishBaseline])
    }

    func testFirstRunPresentInternalMissingExternalCopiesPermittedDirection() {
        assertKinds(plan(mode: .devOneWay, baseline: nil, internalEntry: signature(1), externalEntry: nil), [.copyPath])
    }

    func testFirstRunMissingInternalPresentExternalKeepsOneWayAndCopiesBidirectional() {
        XCTAssertTrue(plan(mode: .devOneWay, baseline: nil, internalEntry: nil, externalEntry: signature(1)).plan.actions.isEmpty)
        assertKinds(plan(mode: .devBidirectional, baseline: nil, internalEntry: nil, externalEntry: signature(1)), [.copyPath])
    }

    func testFirstRunPresentDifferentConflictsAfterHashes() {
        assertConflict(plan(mode: .devOneWay, baseline: nil, internalEntry: signature(2), externalEntry: signature(3)), .contentContent)
    }

    func testFirstRunFilesWithoutHashesRequestHashesEvenWhenQuickMetadataMatches() {
        let entry = signature(2, contentHash: nil)
        let output = plan(mode: .devBidirectional, baseline: nil, internalEntry: entry, externalEntry: entry)
        XCTAssertEqual(output.needsHashes, [path])
        XCTAssertTrue(output.plan.actions.isEmpty)
    }

    func testFirstRunFileDirectoryConflict() {
        assertConflict(plan(mode: .devOneWay, baseline: nil, internalEntry: signature(1), externalEntry: signature(1, kind: .directory)), .typeChange)
    }

    func testFirstRunCollisionBlocksProject() {
        let output = plan(mode: .devOneWay, baselineEntries: [:], baselineExists: false, internalEntries: ["Foo.swift": signature(1), "foo.swift": signature(2)], externalEntries: [:], internalCollisions: [["Foo.swift", "foo.swift"]], externalCaseSensitive: false)
        XCTAssertEqual(output.projectState, .blockedByFileSystem)
        XCTAssertTrue(output.plan.manifestToExternal.isEmpty)
        XCTAssertEqual(output.newConflicts.map(\.type), [.caseCollision])
    }

    func testConfirmedInternalRenameMovesExternalCounterpart() {
        let old = signature(1, resourceIdentifier: Data([4]))
        let renamed = signature(1, resourceIdentifier: Data([4]))
        let output = plan(mode: .devBidirectional, baselineEntries: ["old.txt": old], internalEntries: ["new.txt": renamed], externalEntries: ["old.txt": old])
        assertKinds(output, [.stageExistingVersion, .movePath])
        XCTAssertEqual(output.plan.actions.last?.destinationRelativePath, "new.txt")
        XCTAssertTrue(output.plan.manifestToExternal.isEmpty)
    }

    func testConfirmedInternalDirectoryRenameMovesCounterpartWithoutRecopyingDescendants() {
        let directory = signature(1, kind: .directory, resourceIdentifier: Data([4]))
        let file = signature(2, resourceIdentifier: Data([5]))
        let output = plan(
            mode: .devBidirectional,
            baselineEntries: ["old": directory, "old/file.txt": file],
            internalEntries: ["new": directory, "new/file.txt": file],
            externalEntries: ["old": directory, "old/file.txt": file]
        )
        assertKinds(output, [.stageExistingVersion, .movePath])
        XCTAssertEqual(output.plan.actions.last?.destinationRelativePath, "new")
        XCTAssertTrue(output.plan.manifestToExternal.isEmpty)
    }

    func testMatchRenamesUsesResourceIdentifierThenStrongHash() {
        let baseline = makeBaseline(entries: [
            "old-a": signature(1, resourceIdentifier: Data([1])),
            "old-b": signature(2, contentHash: Data([8]), resourceIdentifier: nil)
        ])
        let snapshot = makeSnapshot(entries: [
            "new-a": signature(1, resourceIdentifier: Data([1])),
            "new-b": signature(2, contentHash: Data([8]), resourceIdentifier: nil)
        ])
        let matches = DevReconciliationPlanner.matchRenames(baseline: baseline, snapshot: snapshot)
        XCTAssertEqual(matches.map { "\($0.from)>\($0.to)" }, ["old-a>new-a", "old-b>new-b"])
    }

    func testTombstoneStaleExternalCopyIsDeletedAgain() {
        let baseline = signature(1)
        let tombstone = makeTombstone(signature: baseline)
        let output = plan(mode: .devOneWay, baseline: baseline, internalEntry: nil, externalEntry: baseline, tombstones: [tombstone])
        assertKinds(output, [.stageExistingVersion, .deletePath])
        XCTAssertTrue(output.newTombstones.isEmpty)
    }

    func testTombstoneStaleCopyMatchesQuickSignatureWithoutHash() {
        let baseline = signature(1, contentHash: nil)
        let output = plan(mode: .devOneWay, baseline: baseline, internalEntry: nil, externalEntry: baseline, tombstones: [makeTombstone(signature: baseline)])
        assertKinds(output, [.stageExistingVersion, .deletePath])
    }

    func testAddedDirectoryUsesCreateDirectoryAndNeverEntersManifest() {
        let output = plan(mode: .devBidirectional, baseline: nil, internalEntry: signature(1, kind: .directory), externalEntry: nil)
        assertKinds(output, [.createDirectory])
        XCTAssertTrue(output.plan.manifestToExternal.isEmpty)
    }

    func testTombstoneDifferentContentIsANewAdd() {
        let baseline = signature(1)
        let output = plan(mode: .devBidirectional, baseline: baseline, internalEntry: signature(2), externalEntry: nil, tombstones: [makeTombstone(signature: baseline)])
        assertKinds(output, [.copyPath])
    }

    func testEveryMutatingActionCarriesFullPreconditionsAndOverwriteFlag() {
        let output = plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(2), externalEntry: signature(1))
        for action in output.plan.actions {
            XCTAssertFalse(action.preconditions.expectedVolumeIdentifier.isEmpty)
            XCTAssertEqual(action.preconditions.expectedProjectFingerprint, identity.fingerprint)
            XCTAssertEqual(action.preconditions.expectedParentKind, .directory)
            XCTAssertEqual(action.preconditions.policySchemaVersion, DevSyncConfiguration.currentPolicySchemaVersion)
        }
        XCTAssertEqual(output.plan.actions.last?.overwritesDestination, true)
    }

    func testPlanSummaryCountsActionsAndTitlesThreeCopiesWithOneManagedLink() {
        let output = plan(
            mode: .devOneWay,
            baselineEntries: [:],
            baselineExists: false,
            internalEntries: ["a": signature(1), "b": signature(2), "c": signature(3)],
            externalEntries: [:]
        )
        XCTAssertEqual(output.plan.summary.copyToExternalCount, 3)
        var summary = output.plan.summary
        summary.managedLinksToCreate = 1
        XCTAssertEqual(summary.primaryActionTitle, "Copy 3 files and 1 managed link")
    }

    func testScenario1IdenticalMirroredProjectEstablishesBaseline() {
        testFirstRunPresentIdenticalEstablishesBaseline()
    }

    func testScenario2ExternalOnlyProjectIsLinked() {
        let output = catalog(internal: [], external: [discovered(path, side: .external)])
        XCTAssertEqual(output.projectsToLink.map(\.relativePath), [path])
        XCTAssertEqual(output.projects.first?.residency, .externalOnlyPendingLink)
    }

    func testScenario3InternalOnlyProjectIsMirrored() {
        let output = catalog(internal: [discovered(path, side: .internal)], external: [])
        XCTAssertEqual(output.projectsToMirror.map(\.relativePath), [path])
        XCTAssertEqual(output.projects.first?.residency, .internalOnlyPendingMirror)
    }

    func testScenario4RealFolderAtManagedLinkPathConflicts() {
        let known = project(residency: .externalResident)
        let output = catalog(known: [known], internal: [discovered(path, side: .internal)], external: [discovered(path, side: .external)], links: [link(state: .replaced)])
        XCTAssertEqual(output.conflicts.map(\.type), [.managedLinkCollision])
        XCTAssertEqual(output.projects.first?.state, .blockedByFileSystem)
    }

    func testScenario5DifferentProjectIdentitiesBlockProject() {
        let output = catalog(
            internal: [discovered(path, side: .internal)],
            external: [discovered(path, side: .external)],
            internalIdentities: [path: projectIdentity(firstCommit: "a")],
            externalIdentities: [path: projectIdentity(firstCommit: "b")]
        )
        XCTAssertEqual(output.conflicts.map(\.type), [.projectIdentity])
        XCTAssertEqual(output.projects.first?.state, .blockedByTopology)
    }

    func testScenario6ExistingUserLinkIsAdoptable() {
        let target = "/external/\(path)"
        let output = catalog(internal: [], external: [discovered(path, side: .external)], symlinks: [path: target])
        XCTAssertEqual(output.adoptableLinks, [path: target])
        XCTAssertTrue(output.projectsToLink.isEmpty)
    }

    func testScenario7MissingInternalOneWayConvertsToPendingExternalLink() {
        let known = project(mode: .devOneWay, residency: .mirrored)
        let output = catalog(mode: .devOneWay, known: [known], internal: [], external: [discovered(path, side: .external)])
        XCTAssertEqual(output.projectsToLink.map(\.relativePath), [path])
    }

    func testScenario8MissingInternalBidirectionalPausesProject() {
        let known = project(residency: .mirrored)
        let output = catalog(known: [known], internal: [], external: [discovered(path, side: .external)])
        XCTAssertEqual(output.missingProjects.first?.state, .paused)
        XCTAssertTrue(output.projectsToLink.isEmpty)
    }

    func testScenario9MissingExternalResidentProjectIsMissing() {
        let known = project(residency: .externalResident)
        let output = catalog(known: [known], internal: [], external: [], links: [link(state: .healthy)])
        XCTAssertEqual(output.missingProjects.first?.state, .missing)
    }

    func testScenario10InternalProjectRenameMatchesResourceIdentifier() {
        let known = project(residency: .mirrored, internalResourceIdentifier: Data([9]), externalResourceIdentifier: Data([8]))
        let output = catalog(known: [known], internal: [discovered("personal/app-a2", side: .internal, resourceIdentifier: Data([9]))], external: [discovered(path, side: .external, resourceIdentifier: Data([8]))])
        XCTAssertEqual(output.renameCandidates.first?.confidence, 1)
        XCTAssertEqual(output.projects.first?.relativePath, "personal/app-a2")
    }

    func testScenario11InternalProjectMoveMatchesIdentity() {
        let knownIdentity = projectIdentity(firstCommit: "root")
        var known = project(residency: .mirrored, internalResourceIdentifier: nil, externalResourceIdentifier: Data([8]))
        known.identity = knownIdentity
        let newPath = "work/tool"
        let output = catalog(
            known: [known],
            internal: [discovered(newPath, side: .internal)],
            external: [discovered(path, side: .external, resourceIdentifier: Data([8]))],
            internalIdentities: [newPath: knownIdentity]
        )
        XCTAssertEqual(output.renameCandidates.first { $0.current.relativePath == newPath }?.evidence, "Matching project identity")
        XCTAssertEqual(output.projects.first?.relativePath, newPath)
    }

    func testScenario27DifferentConcurrentEditsConflict() {
        testBidirectionalChangedBothDifferentlyConflicts()
    }

    func testScenario28InternalEditCopiesToUnchangedExternal() {
        testBidirectionalChangedInternalUnchangedExternalCopiesOutward()
    }

    func testScenario29ExternalEditInOneWayRecordsDrift() {
        testOneWayUnchangedInternalChangedExternalRecordsDrift()
    }

    func testScenario30ExternalDeleteInOneWayRecordsDrift() {
        testOneWayUnchangedInternalDeletedExternalRecordsDrift()
    }

    func testScenario31InternalDeleteStagesExternalAndTombstones() {
        testOneWayDeletedInternalUnchangedExternalQuarantinesAndTombstones()
    }

    func testScenario32ExternalOnlyPathIsRetained() {
        testOneWayNoBaselineExternalAddedIsRetained()
    }

    func testScenario33BothChangedToSameBytesEstablishesBaseline() {
        testBidirectionalChangedBothSameHashEstablishesBaseline()
    }

    func testScenario34MetadataOnlyChangeEstablishesBaseline() {
        testOneWaySameContentDifferentMetadataEstablishesBaseline()
    }

    func testScenario35CaseCollisionBlocksAllActions() {
        testFirstRunCollisionBlocksProject()
    }

    func testScenario36NormalizationCollisionBlocksAllActions() {
        let composed = "caf\u{00e9}.txt"
        let decomposed = "cafe\u{0301}.txt"
        let output = plan(mode: .devBidirectional, baselineEntries: [:], baselineExists: false, internalEntries: [composed: signature(1)], externalEntries: [:], internalCollisions: [[composed, decomposed]])
        XCTAssertEqual(output.newConflicts.map(\.type), [.normalizationCollision])
        XCTAssertTrue(output.plan.actions.isEmpty)
    }

    func testScenario47UnstableSourceDefersAndKeepsProjectDirty() {
        let output = plan(mode: .devBidirectional, baseline: signature(1), internalEntry: signature(2), externalEntry: signature(1), unstablePaths: [path])
        XCTAssertTrue(output.plan.actions.isEmpty)
        XCTAssertEqual(output.projectState, .dirtyBoth)
    }

    func testScenario49NewIgnoreRuleStagesAndDeletesMirroredPath() {
        let baseline = signature(1, kind: .directory)
        let output = plan(
            mode: .devOneWay,
            baselineEntries: ["build": baseline, "build/output": signature(2)],
            internalEntries: [:],
            externalEntries: [:],
            internalExcluded: ["build": .gitIgnored],
            externalExcluded: ["build": .gitIgnored]
        )
        assertKinds(output, [.stageExistingVersion, .deletePath])
        XCTAssertEqual(output.plan.actions.last?.relativePath, "build")
    }

    func testCatalogRealInternalMissingExternalPlansMirror() {
        testScenario3InternalOnlyProjectIsMirrored()
    }

    func testCatalogMissingInternalRealExternalPlansLink() {
        testScenario2ExternalOnlyProjectIsLinked()
    }

    func testCatalogRealBothSameIdentityMerges() {
        let same = projectIdentity(firstCommit: "same")
        let output = catalog(internal: [discovered(path, side: .internal)], external: [discovered(path, side: .external)], internalIdentities: [path: same], externalIdentities: [path: same])
        XCTAssertEqual(output.projects.first?.residency, .mirrored)
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    func testCatalogRealBothDifferentIdentityConflicts() {
        testScenario5DifferentProjectIdentitiesBlockProject()
    }

    func testCatalogUserSymlinkToExternalProjectOffersAdoption() {
        testScenario6ExistingUserLinkIsAdoptable()
    }

    func testCatalogNonProjectInternalRealExternalConflicts() {
        let candidate = DevProjectCandidate(relativePath: path, side: .internal, kind: .marker, markerName: "package.json")
        let output = catalog(internal: [], external: [discovered(path, side: .external)], internalCandidates: [candidate])
        XCTAssertEqual(output.conflicts.map(\.type), [.projectPath])
    }

    func testCatalogRealInternalNonProjectExternalConflicts() {
        let candidate = DevProjectCandidate(relativePath: path, side: .external, kind: .marker, markerName: "package.json")
        let output = catalog(internal: [discovered(path, side: .internal)], external: [], externalCandidates: [candidate])
        XCTAssertEqual(output.conflicts.map(\.type), [.projectPath])
    }

    func testIncompleteCatalogDiscoveryDoesNotReportMissingProject() {
        let output = catalog(known: [project(residency: .mirrored)], internal: [], external: [], internalComplete: false, externalComplete: true)
        XCTAssertTrue(output.missingProjects.isEmpty)
    }

    func testIncompleteCatalogDiscoveryDoesNotInferRenameOrMissingProject() {
        let known = project(residency: .mirrored, internalResourceIdentifier: Data([4]))
        let output = catalog(known: [known], internal: [discovered("moved", side: .internal, resourceIdentifier: Data([4]))], external: [], internalComplete: false)
        XCTAssertTrue(output.renameCandidates.isEmpty)
        XCTAssertTrue(output.missingProjects.isEmpty)
    }

    func testUserLinkToDifferentExternalProjectIsAPathConflict() {
        let output = catalog(internal: [], external: [discovered(path, side: .external)], symlinks: [path: "/external/other-project"])
        XCTAssertEqual(output.conflicts.map(\.type), [.projectPath])
        XCTAssertTrue(output.adoptableLinks.isEmpty)
    }

    func testMatchingRemoteURLAloneDoesNotCreateRename() {
        let remoteOnly = projectIdentity(firstCommit: nil)
        var known = project(residency: .mirrored)
        known.identity = remoteOnly
        let output = catalog(known: [known], internal: [discovered("moved", side: .internal)], external: [], internalIdentities: ["moved": remoteOnly])
        XCTAssertFalse(output.renameCandidates.contains { $0.evidence == "Matching Git project identity" })
    }

    private let path = "Sources/App.swift"
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var identity: DevProjectIdentity { projectIdentity(firstCommit: "root") }

    private func signature(
        _ value: Int,
        kind: DevEntryKind = .file,
        contentHash: Data? = Data([0]),
        resourceIdentifier: Data? = nil
    ) -> DevFileSignature {
        DevFileSignature(
            kind: kind,
            size: kind == .directory ? nil : UInt64(value),
            modificationTimeNanoseconds: Int64(value),
            mode: 0o644,
            symlinkTarget: kind == .symlink ? "target-\(value)" : nil,
            resourceIdentifier: resourceIdentifier,
            contentHash: kind == .file ? (contentHash == Data([0]) ? Data([UInt8(truncatingIfNeeded: value)]) : contentHash) : nil
        )
    }

    private func plan(
        mode: DevSyncMode,
        baseline: DevFileSignature?,
        internalEntry: DevFileSignature?,
        externalEntry: DevFileSignature?,
        tombstones: [DevTombstone] = [],
        unreadableInternal: [String] = [],
        unstablePaths: Set<String> = []
    ) -> DevPlannerOutput {
        plan(
            mode: mode,
            baselineEntries: baseline.map { [path: $0] } ?? [:],
            baselineExists: baseline != nil,
            internalEntries: internalEntry.map { [path: $0] } ?? [:],
            externalEntries: externalEntry.map { [path: $0] } ?? [:],
            tombstones: tombstones,
            unreadableInternal: unreadableInternal,
            unstablePaths: unstablePaths
        )
    }

    private func plan(
        mode: DevSyncMode,
        baselineEntries: [String: DevFileSignature],
        baselineExists: Bool = true,
        internalEntries: [String: DevFileSignature],
        externalEntries: [String: DevFileSignature],
        tombstones: [DevTombstone] = [],
        unreadableInternal: [String] = [],
        unstablePaths: Set<String> = [],
        internalCollisions: [[String]] = [],
        externalCollisions: [[String]] = [],
        internalExcluded: [String: DevFilePolicyReason] = [:],
        externalExcluded: [String: DevFilePolicyReason] = [:],
        internalComplete: Bool = true,
        externalComplete: Bool = true,
        internalCaseSensitive: Bool = true,
        externalCaseSensitive: Bool = true
    ) -> DevPlannerOutput {
        let pair = makePair(mode: mode)
        let project = project(pairID: pair.id, mode: mode, residency: .mirrored)
        return DevReconciliationPlanner.plan(
            DevPlannerInput(
                pair: pair,
                project: project,
                baseline: baselineExists ? makeBaseline(projectID: project.id, entries: baselineEntries) : nil,
                internalSnapshot: makeSnapshot(entries: internalEntries, excluded: internalExcluded, unreadable: unreadableInternal, complete: internalComplete, collisions: internalCollisions),
                externalSnapshot: makeSnapshot(entries: externalEntries, excluded: externalExcluded, complete: externalComplete, collisions: externalCollisions),
                tombstones: tombstones.map { tombstone in
                    var tombstone = tombstone
                    tombstone.projectID = project.id
                    return tombstone
                },
                unresolvedConflicts: [],
                capabilities: DevPairCapabilities(
                    internalVolume: volume(identifier: "internal", caseSensitive: internalCaseSensitive),
                    externalVolume: volume(identifier: "external", caseSensitive: externalCaseSensitive)
                ),
                unstablePaths: unstablePaths,
                now: now
            )
        )
    }

    private func makePair(mode: DevSyncMode) -> DevSyncPair {
        DevSyncPair(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Test",
            mode: mode,
            internalRoot: DevSyncRoot(bookmark: nil, path: "/internal", volumeIdentifier: "internal", volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: "/external", volumeIdentifier: "external", volumeName: "External", fileSystemType: "apfs"),
            updatedAt: now
        )
    }

    private func project(
        pairID: UUID? = nil,
        mode: DevSyncMode = .devBidirectional,
        residency: DevProjectResidency,
        internalResourceIdentifier: Data? = nil,
        externalResourceIdentifier: Data? = nil
    ) -> DevProject {
        let pair = makePair(mode: mode)
        return DevProject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            pairID: pairID ?? pair.id,
            relativePath: path,
            residency: residency,
            kind: .gitRepository,
            identity: identity,
            internalResourceIdentifier: internalResourceIdentifier,
            externalResourceIdentifier: externalResourceIdentifier,
            state: .clean
        )
    }

    private func makeBaseline(projectID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, entries: [String: DevFileSignature]) -> DevBaseline {
        DevBaseline(projectID: projectID, entries: entries.mapValues { DevBaselineEntry(signature: $0, lastVerifiedAt: now) }, updatedAt: now)
    }

    private func makeSnapshot(
        entries: [String: DevFileSignature],
        excluded: [String: DevFilePolicyReason] = [:],
        unreadable: [String] = [],
        complete: Bool = true,
        collisions: [[String]] = []
    ) -> DevSnapshot {
        DevSnapshot(entries: entries, excluded: excluded, unreadablePaths: unreadable, complete: complete, collisions: collisions, includedBytes: 0, excludedBytes: 0, scannedAt: now)
    }

    private func makeTombstone(signature: DevFileSignature) -> DevTombstone {
        DevTombstone(projectID: UUID(), relativePath: path, deletedFromSide: .internal, baselineSignature: signature, createdAt: now, observedInternal: true, observedExternal: false, expiresAt: now.addingTimeInterval(30 * 86_400))
    }

    private func volume(identifier: String, caseSensitive: Bool) -> DevVolumeCapabilities {
        DevVolumeCapabilities(
            volumeIdentifier: identifier,
            volumeName: identifier,
            mountPath: "/\(identifier)",
            fileSystemType: "apfs",
            isReadOnly: false,
            isRemovable: identifier == "external",
            isLocal: true,
            isEncrypted: true,
            availableCapacity: 1_000_000,
            totalCapacity: 2_000_000,
            isCaseSensitive: caseSensitive,
            isCasePreserving: true,
            supportsSymbolicLinks: true,
            supportsHardLinks: true,
            supportsUnixPermissions: true,
            supportsExtendedAttributes: true,
            supportsCreationTimes: true,
            supportsPersistentIdentifiers: true,
            timestampResolutionNanoseconds: 0,
            maximumPathComponentLength: 255,
            probedAt: now,
            fidelity: .full,
            fidelityNotes: []
        )
    }

    private func projectIdentity(firstCommit: String?) -> DevProjectIdentity {
        let remotes = ["https://example.com/repo.git"]
        return DevProjectIdentity(remoteURLHints: remotes, headReference: "refs/heads/main", firstCommit: firstCommit, topologyKind: .gitRepository, fingerprint: DevProjectIdentity.fingerprint(remoteURLHints: remotes, firstCommit: firstCommit, topologyKind: .gitRepository))
    }

    private func discovered(_ relativePath: String, side: DevSyncSide, resourceIdentifier: Data? = nil) -> DevDiscoveredProject {
        DevDiscoveredProject(relativePath: relativePath, side: side, kind: .gitRepository, url: URL(fileURLWithPath: "/\(side.rawValue)/\(relativePath)"), resourceIdentifier: resourceIdentifier)
    }

    private func link(state: DevManagedLinkState) -> DevManagedLink {
        DevManagedLink(projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, linkRelativePath: path, targetVolumeIdentifier: "external", targetRelativePath: path, lastWrittenTargetText: "/external/\(path)", linkResourceIdentifier: nil, state: state, createdAt: now, lastValidatedAt: now, adoptedFromUserLink: false)
    }

    func testCatalogAlwaysEndsWithRootUnitAndLinksDriveOnlyDirectories() {
        let output = DevCatalogPlanner.plan(
            DevCatalogInput(
                pair: makePair(mode: .devOneWay),
                knownProjects: [],
                internalDiscovery: DevDiscoveryResult(projects: [], candidates: [], unreadablePaths: [], complete: true, symlinksToExternal: [:]),
                externalDiscovery: DevDiscoveryResult(projects: [], candidates: [], unreadablePaths: [], complete: true, symlinksToExternal: [:], externalOnlyDirectories: ["organization/lambton/meallens-data"]),
                links: [],
                internalIdentities: [:],
                externalIdentities: [:],
                excludedProjectPaths: [],
                includedCandidatePaths: [],
                adoptedLinkPaths: [],
                linkableExternalDirectories: ["organization/lambton/meallens-data"]
            )
        )
        XCTAssertEqual(output.projects.map(\.relativePath), ["organization/lambton/meallens-data", ""])
        XCTAssertEqual(output.projects.last?.residency, .mirrored)
        XCTAssertEqual(output.projects.last?.explicitlyIncluded, true)
        XCTAssertEqual(output.projects.first?.residency, .externalOnlyPendingLink)
        XCTAssertEqual(output.projects.first?.kind, .nonGit)
        XCTAssertEqual(output.projectsToLink.map(\.relativePath), ["organization/lambton/meallens-data"])
    }

    private func catalog(
        mode: DevSyncMode = .devBidirectional,
        known: [DevProject] = [],
        internal internalProjects: [DevDiscoveredProject],
        external externalProjects: [DevDiscoveredProject],
        links: [DevManagedLink] = [],
        internalCandidates: [DevProjectCandidate] = [],
        externalCandidates: [DevProjectCandidate] = [],
        symlinks: [String: String] = [:],
        internalIdentities: [String: DevProjectIdentity] = [:],
        externalIdentities: [String: DevProjectIdentity] = [:],
        internalComplete: Bool = true,
        externalComplete: Bool = true
    ) -> DevCatalogOutput {
        DevCatalogPlanner.plan(
            DevCatalogInput(
                pair: makePair(mode: mode),
                knownProjects: known,
                internalDiscovery: DevDiscoveryResult(projects: internalProjects, candidates: internalCandidates, unreadablePaths: [], complete: internalComplete, symlinksToExternal: symlinks),
                externalDiscovery: DevDiscoveryResult(projects: externalProjects, candidates: externalCandidates, unreadablePaths: [], complete: externalComplete, symlinksToExternal: [:]),
                links: links,
                internalIdentities: internalIdentities,
                externalIdentities: externalIdentities,
                excludedProjectPaths: [],
                includedCandidatePaths: [],
                adoptedLinkPaths: []
            )
        )
    }

    private func assertKinds(_ output: DevPlannerOutput, _ expected: [DevSyncActionKind], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(output.plan.actions.map(\.kind), expected, file: file, line: line)
    }

    private func assertConflict(_ output: DevPlannerOutput, _ type: DevConflictType, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(output.newConflicts.map(\.type), [type], file: file, line: line)
        XCTAssertEqual(output.plan.actions.map(\.kind), [.createConflict], file: file, line: line)
        XCTAssertEqual(output.projectState, .conflict, file: file, line: line)
    }
}
