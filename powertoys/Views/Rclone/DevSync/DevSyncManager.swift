//
//  DevSyncManager.swift
//  powertoys
//

import AppKit
import SwiftUI

@MainActor
@Observable
final class DevSyncManager {
    static let shared = DevSyncManager(engine: DevSyncPreviewEngine())

    var engine: DevSyncEngine {
        didSet { restartUpdates() }
    }

    private(set) var pairs: [DevSyncPair] = []
    private(set) var status: [UUID: DevPairStatus] = [:]
    private(set) var projects: [UUID: [DevProject]] = [:]
    private(set) var conflicts: [UUID: [DevConflict]] = [:]
    private(set) var links: [UUID: [DevManagedLink]] = [:]
    private(set) var capabilities: [UUID: DevPairCapabilities] = [:]
    var driftPaths: [UUID: [String]] = [:]

    var selectedPairID: UUID?
    var isPresentingSetup = false
    var isShowingPairSettings = false
    var lastNotification: DevSyncNotification?
    var focusedConflictProjectID: UUID?
    var errorBanner: String?

    private var updatesTask: Task<Void, Never>?

    init(engine: DevSyncEngine) {
        self.engine = engine
    }

    isolated deinit {
        updatesTask?.cancel()
    }

    var attentionCount: Int {
        status.values.reduce(0) { $0 + $1.attentionCount }
    }

    var selectedPair: DevSyncPair? {
        guard let selectedPairID else { return pairs.first }
        return pairs.first { $0.id == selectedPairID } ?? pairs.first
    }

    func status(for pairID: UUID) -> DevPairStatus {
        status[pairID] ?? DevPairStatus(pairID: pairID)
    }

    func projects(for pairID: UUID) -> [DevProject] { projects[pairID] ?? [] }

    func unresolvedConflicts(for pairID: UUID) -> [DevConflict] {
        (conflicts[pairID] ?? [])
            .filter { !$0.isResolved }
            .sorted { left, right in
                let leftFocused = left.projectID == focusedConflictProjectID
                let rightFocused = right.projectID == focusedConflictProjectID
                if leftFocused != rightFocused { return leftFocused }
                return left.createdAt < right.createdAt
            }
    }

    func link(for project: DevProject) -> DevManagedLink? {
        (links[project.pairID] ?? []).first { $0.projectID == project.id }
    }

    // MARK: Loading

    func load() async {
        await engine.start()
        pairs = await engine.pairs()
        for pair in pairs {
            await loadPair(pair.id)
        }
        if selectedPairID == nil || !pairs.contains(where: { $0.id == selectedPairID }) {
            selectedPairID = pairs.first?.id
        }
        restartUpdates()
    }

    private func loadPair(_ pairID: UUID) async {
        status[pairID] = await engine.status(pairID: pairID)
        projects[pairID] = await engine.projects(pairID: pairID)
        conflicts[pairID] = await engine.conflicts(pairID: pairID)
        links[pairID] = await engine.links(pairID: pairID)
        capabilities[pairID] = await engine.capabilities(pairID: pairID)
    }

    private func restartUpdates() {
        updatesTask?.cancel()
        let stream = engine.updates
        updatesTask = Task { [weak self] in
            for await update in stream {
                guard !Task.isCancelled else { return }
                await self?.apply(update)
            }
        }
    }

    func apply(_ update: DevSyncUpdate) {
        switch update {
        case .pairs(let value):
            pairs = value
            if selectedPairID == nil || !value.contains(where: { $0.id == selectedPairID }) {
                selectedPairID = value.first?.id
            }
        case .status(let value):
            status[value.pairID] = value
        case .projects(let pairID, let value):
            projects[pairID] = value
        case .conflicts(let pairID, let value):
            conflicts[pairID] = value
        case .links(let pairID, let value):
            links[pairID] = value
        case .capabilities(let pairID, let value):
            capabilities[pairID] = value
        case .notification(let value):
            lastNotification = value
            LogManager.shared.info("Dev Sync notification: \(value.kind.rawValue)", source: "DevSync")
        }
    }

    // MARK: Pair intents

    func syncNow(pairID: UUID) async { await engine.syncNow(pairID: pairID) }
    func pause(pairID: UUID) async { await engine.pause(pairID: pairID) }
    func resume(pairID: UUID) async { await engine.resume(pairID: pairID) }
    func verifyNow(pairID: UUID) async { await engine.verifyNow(pairID: pairID) }
    func repairLinks(pairID: UUID) async { await engine.repairLinks(pairID: pairID) }

    @discardableResult
    func previewPending(pairID: UUID) async -> DevSyncPlan? {
        await engine.previewPending(pairID: pairID)
    }

    func removePair(pairID: UUID, deleteSafetyStore: Bool) async {
        await capture { try await self.engine.removePair(pairID: pairID, deleteSafetyStore: deleteSafetyStore) }
        pairs = await engine.pairs()
        if !pairs.contains(where: { $0.id == selectedPairID }) {
            selectedPairID = pairs.first?.id
        }
        isShowingPairSettings = false
    }

    func updateConfiguration(pairID: UUID, configuration: DevSyncConfiguration) async {
        await capture { try await self.engine.updateConfiguration(pairID: pairID, configuration: configuration) }
        if let index = pairs.firstIndex(where: { $0.id == pairID }) {
            pairs[index].configuration = configuration
        }
    }

    func createPair(draft: DevSetupDraft, approvedPreview: DevSetupPreview) async {
        await capture {
            let pair = try await self.engine.createPair(draft: draft, approvedPreview: approvedPreview)
            self.selectedPairID = pair.id
            await self.loadPair(pair.id)
        }
        pairs = await engine.pairs()
    }

    // MARK: Project intents

    func syncProject(pairID: UUID, projectID: UUID) async {
        await engine.syncProject(pairID: pairID, projectID: projectID)
    }

    func previewProject(pairID: UUID, projectID: UUID) async {
        let plan = await engine.previewProject(pairID: pairID, projectID: projectID)
        guard let plan else { return }
        driftPaths[projectID] = plan.actions
            .filter { $0.conflictType == .destinationDrift }
            .map(\.relativePath)
    }

    func moveToExternal(pairID: UUID, projectID: UUID) async {
        await capture { try await self.engine.moveToExternal(pairID: pairID, projectID: projectID) }
    }

    func bringInternal(pairID: UUID, projectID: UUID) async {
        await capture { try await self.engine.bringInternal(pairID: pairID, projectID: projectID) }
    }

    func setProjectExcluded(pairID: UUID, projectID: UUID, excluded: Bool) async {
        await engine.setProjectExcluded(pairID: pairID, projectID: projectID, excluded: excluded)
    }

    func includeCandidate(pairID: UUID, relativePath: String) async {
        await engine.includeCandidate(pairID: pairID, relativePath: relativePath)
    }

    func repairLink(pairID: UUID, projectID: UUID) async {
        await capture { try await self.engine.repairLink(pairID: pairID, projectID: projectID) }
    }

    func decideMissingProject(pairID: UUID, projectID: UUID, decision: DevMissingProjectDecision) async {
        await capture { try await self.engine.decideMissingProject(pairID: pairID, projectID: projectID, decision: decision) }
    }

    func resolveDrift(pairID: UUID, projectID: UUID, relativePath: String, resolution: DevDriftResolution) async {
        await capture { try await self.engine.resolveDrift(pairID: pairID, projectID: projectID, relativePath: relativePath, resolution: resolution) }
        driftPaths[projectID]?.removeAll { $0 == relativePath }
    }

    func resolveConflict(pairID: UUID, conflictID: UUID, resolution: DevConflictResolution) async {
        await capture { try await self.engine.resolveConflict(pairID: pairID, conflictID: conflictID, resolution: resolution) }
        conflicts[pairID] = await engine.conflicts(pairID: pairID)
    }

    // MARK: Locations

    func externalRootURL(for pair: DevSyncPair) -> URL { pair.externalRoot.url }

    func safetyStoreURL(for pair: DevSyncPair) -> URL {
        pair.externalRoot.url
            .appendingPathComponent(DevSyncDefaults.systemDirectoryName, isDirectory: true)
            .appendingPathComponent(pair.id.uuidString, isDirectory: true)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: Errors

    private func capture(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            errorBanner = error.localizedDescription
            LogManager.shared.error("Dev Sync action failed: \(error)", source: "DevSync")
        }
    }
}

// MARK: - Preview fixture

@MainActor
enum DevSyncPreviewFixture {
    struct Seed {
        var pair: DevSyncPair
        var status: DevPairStatus
        var projects: [DevProject]
        var conflicts: [DevConflict]
        var links: [DevManagedLink]
        var driftProjectID: UUID
    }

    static func seed() -> Seed {
        let pairID = UUID()
        let pair = DevSyncPair(
            id: pairID,
            displayName: "Dev",
            mode: .devBidirectional,
            internalRoot: DevSyncRoot(bookmark: nil, path: "/Users/dev/Code", volumeIdentifier: "internal", volumeName: "Macintosh HD", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: "/Volumes/DevSSD/Code", volumeIdentifier: "external", volumeName: "DevSSD", fileSystemType: "apfs"),
            state: .idle,
            hasCompletedFirstRun: true
        )

        let mirrored = DevProject(
            pairID: pairID,
            relativePath: "personal/powertoys",
            residency: .mirrored,
            kind: .gitRepository,
            state: .conflict,
            lastSuccessAt: Date().addingTimeInterval(-120),
            includedBytes: 1_200_000_000,
            excludedBytes: 4_800_000_000
        )
        let external = DevProject(
            pairID: pairID,
            relativePath: "archive/legacy-app",
            residency: .externalResident,
            kind: .gitRepository,
            state: .destinationDrift,
            lastSuccessAt: Date().addingTimeInterval(-7_200),
            warnings: [.externalOnlyPaths],
            includedBytes: 340_000_000,
            excludedBytes: 20_000_000
        )
        let pending = DevProject(
            pairID: pairID,
            relativePath: "work/scanner",
            residency: .internalOnlyPendingMirror,
            kind: .nonGit,
            state: .dirtyInternal,
            includedBytes: 88_000_000,
            excludedBytes: 2_000_000
        )
        let missing = DevProject(
            pairID: pairID,
            relativePath: "work/retired-tool",
            residency: .externalOnlyPendingLink,
            kind: .gitRepository,
            state: .missing,
            lastSuccessAt: Date().addingTimeInterval(-86_400),
            includedBytes: 12_000_000,
            excludedBytes: 0
        )

        let conflicts = [
            DevConflict(
                projectID: mirrored.id,
                relativePath: "Sources/App/Settings.swift",
                type: .contentContent,
                baselineSignature: DevFileSignature(kind: .file, size: 4_096, modificationTimeNanoseconds: 1_756_000_000_000_000_000),
                internalSignature: DevFileSignature(kind: .file, size: 4_310, modificationTimeNanoseconds: 1_757_000_000_000_000_000),
                externalSignature: DevFileSignature(kind: .file, size: 4_180, modificationTimeNanoseconds: 1_756_500_000_000_000_000)
            ),
            DevConflict(
                projectID: external.id,
                relativePath: "config/app.yml",
                type: .modifyDelete,
                internalSignature: DevFileSignature(kind: .file, size: 620, modificationTimeNanoseconds: 1_757_100_000_000_000_000)
            )
        ]

        let status = DevPairStatus(
            pairID: pairID,
            state: .idle,
            volumeOnline: true,
            lastSuccessAt: Date().addingTimeInterval(-120),
            nextCheckpointAt: Date().addingTimeInterval(180),
            pendingProjectCount: 1,
            pendingBytes: 88_000_000,
            bytesWrittenToday: 2_400_000_000,
            conflictCount: conflicts.count,
            driftCount: 1,
            blockedProjectCount: 1,
            safetyStoreBytes: 640_000_000,
            rsyncSummary: "rsync 3.4.1"
        )

        let link = DevManagedLink(
            projectID: missing.id,
            linkRelativePath: missing.relativePath,
            targetVolumeIdentifier: "external",
            targetRelativePath: missing.relativePath,
            lastWrittenTargetText: "/Volumes/DevSSD/Code/" + missing.relativePath,
            state: .missing,
            createdAt: Date().addingTimeInterval(-172_800),
            adoptedFromUserLink: false
        )

        return Seed(
            pair: pair,
            status: status,
            projects: [mirrored, external, pending, missing],
            conflicts: conflicts,
            links: [link],
            driftProjectID: external.id
        )
    }

    static func engine(_ seed: Seed) -> DevSyncPreviewEngine {
        DevSyncPreviewEngine(
            pairs: [seed.pair],
            status: [seed.pair.id: seed.status],
            projects: [seed.pair.id: seed.projects],
            conflicts: [seed.pair.id: seed.conflicts],
            links: [seed.pair.id: seed.links],
            capabilities: [seed.pair.id: DevPairCapabilities()]
        )
    }

    static func manager() -> DevSyncManager {
        let seed = seed()
        let manager = DevSyncManager(engine: engine(seed))
        manager.apply(.pairs([seed.pair]))
        manager.apply(.status(seed.status))
        manager.apply(.projects(pairID: seed.pair.id, seed.projects))
        manager.apply(.conflicts(pairID: seed.pair.id, seed.conflicts))
        manager.apply(.links(pairID: seed.pair.id, seed.links))
        manager.apply(.capabilities(pairID: seed.pair.id, DevPairCapabilities()))
        manager.driftPaths[seed.driftProjectID] = ["build/output.bin"]
        return manager
    }
}
