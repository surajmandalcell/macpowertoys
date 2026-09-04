//
//  DevSyncInterfaceTests.swift
//  powertoysTests
//

import XCTest
@testable import powertoys

@MainActor
final class DevSyncInterfaceTests: XCTestCase {
    private var seed: DevSyncPreviewFixture.Seed!
    private var engine: DevSyncPreviewEngine!
    private var manager: DevSyncManager!

    override func setUp() async throws {
        seed = DevSyncPreviewFixture.seed()
        engine = DevSyncPreviewFixture.engine(seed)
        manager = DevSyncManager(engine: engine)
    }

    override func tearDown() async throws {
        manager = nil
        engine = nil
        seed = nil
    }

    // MARK: Loading

    func testLoadPopulatesPairsStatusProjectsConflictsAndLinks() async {
        await manager.load()

        XCTAssertEqual(manager.pairs.map(\.id), [seed.pair.id])
        XCTAssertEqual(manager.selectedPairID, seed.pair.id)
        XCTAssertEqual(manager.status(for: seed.pair.id).state, .idle)
        XCTAssertEqual(manager.projects(for: seed.pair.id).count, 4)
        XCTAssertEqual(manager.unresolvedConflicts(for: seed.pair.id).count, 2)
        XCTAssertEqual(manager.links[seed.pair.id]?.count, 1)
        XCTAssertNotNil(manager.capabilities[seed.pair.id])
    }

    func testAttentionCountSumsConflictsAndBlockedProjects() async {
        await manager.load()

        XCTAssertEqual(seed.status.conflictCount, 2)
        XCTAssertEqual(seed.status.blockedProjectCount, 1)
        XCTAssertEqual(manager.attentionCount, 3)
    }

    func testStreamedStatusUpdateChangesPublishedStatus() async throws {
        await manager.load()
        XCTAssertTrue(manager.status(for: seed.pair.id).volumeOnline)

        var offline = seed.status
        offline.volumeOnline = false
        offline.state = .volumeOffline
        engine.emit(.status(offline))

        try await waitUntil { self.manager.status(for: self.seed.pair.id).state == .volumeOffline }
        XCTAssertFalse(manager.status(for: seed.pair.id).volumeOnline)
    }

    func testStreamedProjectsUpdateReplacesProjects() async throws {
        await manager.load()

        engine.emit(.projects(pairID: seed.pair.id, [seed.projects[0]]))

        try await waitUntil { self.manager.projects(for: self.seed.pair.id).count == 1 }
    }

    // MARK: Intents

    func testPairIntentsForwardToEngine() async {
        await manager.load()
        let pairID = seed.pair.id

        await manager.syncNow(pairID: pairID)
        await manager.pause(pairID: pairID)
        await manager.resume(pairID: pairID)
        await manager.verifyNow(pairID: pairID)
        await manager.repairLinks(pairID: pairID)
        _ = await manager.previewPending(pairID: pairID)
        await manager.updateConfiguration(pairID: pairID, configuration: .default)

        XCTAssertEqual(
            engine.receivedIntents,
            ["syncNow", "pause", "resume", "verifyNow", "repairLinks", "previewPending", "updateConfiguration"]
        )
    }

    func testProjectIntentsForwardToEngine() async {
        await manager.load()
        let pairID = seed.pair.id
        let projectID = seed.projects[0].id

        await manager.syncProject(pairID: pairID, projectID: projectID)
        await manager.previewProject(pairID: pairID, projectID: projectID)
        await manager.moveToExternal(pairID: pairID, projectID: projectID)
        await manager.bringInternal(pairID: pairID, projectID: projectID)
        await manager.setProjectExcluded(pairID: pairID, projectID: projectID, excluded: true)
        await manager.includeCandidate(pairID: pairID, relativePath: "work/new")
        await manager.repairLink(pairID: pairID, projectID: projectID)
        await manager.decideMissingProject(pairID: pairID, projectID: projectID, decision: .keepExternalOnly)
        await manager.resolveDrift(pairID: pairID, projectID: projectID, relativePath: "build/output.bin", resolution: .overwriteExternal)
        await manager.resolveConflict(pairID: pairID, conflictID: seed.conflicts[0].id, resolution: .keepInternal)

        XCTAssertEqual(
            engine.receivedIntents,
            [
                "syncProject", "previewProject", "moveToExternal", "bringInternal",
                "setProjectExcluded:true", "includeCandidate", "repairLink",
                "decideMissingProject:keepExternalOnly", "resolveDrift:overwriteExternal",
                "resolveConflict:keepInternal"
            ]
        )
    }

    func testRemovePairForwardsAndClearsSelection() async {
        await manager.load()

        await manager.removePair(pairID: seed.pair.id, deleteSafetyStore: false)

        XCTAssertTrue(engine.receivedIntents.contains("removePair"))
        XCTAssertTrue(manager.pairs.isEmpty)
        XCTAssertNil(manager.selectedPairID)
        XCTAssertFalse(manager.isShowingPairSettings)
    }

    func testUnresolvedConflictsPutTheFocusedProjectFirst() async {
        await manager.load()
        manager.focusedConflictProjectID = seed.conflicts[1].projectID

        XCTAssertEqual(manager.unresolvedConflicts(for: seed.pair.id).first?.id, seed.conflicts[1].id)
    }

    func testSafetyStorePathUsesTheSystemDirectoryAndPairIdentifier() async {
        let url = manager.safetyStoreURL(for: seed.pair)

        XCTAssertEqual(
            url.path,
            "/Volumes/DevSSD/Code/\(DevSyncDefaults.systemDirectoryName)/\(seed.pair.id.uuidString)"
        )
    }

    // MARK: Setup model

    func testSetupContinueStaysDisabledWhileTheProbeHasIssues() {
        let model = DevSyncSetupModel(engine: engine)
        model.draft.internalURL = URL(fileURLWithPath: "/Users/dev/Code")
        model.draft.externalURL = URL(fileURLWithPath: "/Users/dev/Code")
        model.probe = DevSetupProbe(
            issues: [.sameDirectory],
            internalRoot: seed.pair.internalRoot,
            externalRoot: seed.pair.externalRoot,
            capabilities: DevPairCapabilities(),
            gitAvailable: true,
            warnings: []
        )

        XCTAssertFalse(model.canContinue)
        XCTAssertEqual(model.rootIssues, [DevRootIssue.sameDirectory.message])

        model.probe = DevSetupProbe(
            issues: [],
            internalRoot: seed.pair.internalRoot,
            externalRoot: seed.pair.externalRoot,
            capabilities: DevPairCapabilities(),
            gitAvailable: true,
            warnings: []
        )

        XCTAssertTrue(model.canContinue)
    }

    func testSetupStepLabelsCoverSixSteps() {
        XCTAssertEqual(DevSetupStep.allCases.count, 6)
        XCTAssertEqual(DevSetupStep.roots.label, "Step 1 of 6 · Roots")
        XCTAssertEqual(DevSetupStep.preview.label, "Step 6 of 6 · Preview")
    }

    func testSetupPrimaryActionTitleMatchesThePreviewSummaryOnTheLastStep() {
        let model = DevSyncSetupModel(engine: engine)
        XCTAssertEqual(model.primaryActionTitle, "Continue")

        var summary = DevPlanSummary()
        summary.copyToExternalCount = 3
        summary.managedLinksToCreate = 1
        let preview = DevSetupPreview(
            plan: DevSyncPlan(pairID: seed.pair.id, summary: summary),
            groups: [],
            sensitiveIncludedPaths: [],
            warnings: [],
            availableExternalBytes: 0,
            scanComplete: true
        )
        model.step = .preview
        model.preview = preview

        XCTAssertEqual(model.primaryActionTitle, preview.summary.primaryActionTitle)
        XCTAssertEqual(model.primaryActionTitle, "Copy 3 files and 1 managed link")
        XCTAssertTrue(model.canContinue)
    }

    func testSetupProjectInclusionTracksExcludedAndCandidatePaths() {
        let model = DevSyncSetupModel(engine: engine)
        let item = DevSetupProjectItem(
            relativePath: "work/scanner",
            kind: .gitRepository,
            candidateKind: nil,
            residency: .mirrored,
            includedBytes: 10,
            excludedBytes: 0,
            warnings: [],
            adoptableLinkTarget: nil
        )

        XCTAssertTrue(model.isIncluded(item, in: .internalOnly))
        model.setIncluded(false, for: item, in: .internalOnly)
        XCTAssertFalse(model.isIncluded(item, in: .internalOnly))
        XCTAssertTrue(model.draft.excludedProjectPaths.contains(item.relativePath))

        XCTAssertFalse(model.isIncluded(item, in: .unmanagedCandidates))
        model.setIncluded(true, for: item, in: .unmanagedCandidates)
        XCTAssertTrue(model.draft.includedCandidatePaths.contains(item.relativePath))
    }

    func testSetupActivityPresetReplacesTiming() {
        let model = DevSyncSetupModel(engine: engine)
        model.applyActivityPreset(.lowDriveActivity)

        XCTAssertEqual(model.draft.configuration.activityPreset, .lowDriveActivity)
        XCTAssertEqual(model.draft.configuration.timing, DevActivityPreset.lowDriveActivity.timing)
    }

    // MARK: Sidebar badge

    func testSidebarBadgeHidesAtZeroAndShowsTheCount() {
        XCTAssertNil(DevSyncSidebarBadge.text(0))
        XCTAssertEqual(DevSyncSidebarBadge.text(3), "3")
    }

    // MARK: Conflict diff

    func testConflictDiffMarksAddedAndRemovedLines() {
        let lines = DevConflictDiff.lines(newText: "one\ntwo\nthree", oldText: "one\ntwo")

        XCTAssertEqual(lines.map(\.kind), [.context, .context, .added])
        XCTAssertEqual(lines.last?.text, "three")
        XCTAssertEqual(lines.last?.prefix, "+")

        let removed = DevConflictDiff.lines(newText: "one", oldText: "one\ntwo")
        XCTAssertEqual(removed.map(\.kind), [.context, .removed])
        XCTAssertEqual(removed.last?.prefix, "-")
    }

    func testConflictDiffSkipsSymbolicLinksAndOversizedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevSyncInterfaceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let real = directory.appendingPathComponent("real.txt")
        try "hello".write(to: real, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let big = directory.appendingPathComponent("big.txt")
        try String(repeating: "a", count: DevConflictDiff.maximumFileBytes + 1)
            .write(to: big, atomically: true, encoding: .utf8)

        XCTAssertEqual(DevConflictDiff.readText(at: real.path), "hello")
        XCTAssertNil(DevConflictDiff.readText(at: link.path))
        XCTAssertNil(DevConflictDiff.readText(at: big.path))
    }

    // MARK: Helpers

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not met within \(timeout) seconds")
    }
}
