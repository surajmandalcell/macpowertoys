import Foundation
import XCTest
@testable import powertoys

final class DevSyncPlannerPropertyTests: XCTestCase {
    func testPropertyPlannerActionNeverEscapesEitherRoot() {
        var generator = PlannerGenerator(seed: 1)
        let invalidPaths = ["../escape", "/absolute", "a//b", "a/../../b", ".cloudsync-system/state"]
        for _ in 0..<200 {
            let path = invalidPaths[generator.index(in: invalidPaths)]
            let output = plan(path: path, baseline: nil, internalEntries: [path: generator.signature()], externalEntries: [:])
            XCTAssertTrue(output.plan.actions.isEmpty)
            XCTAssertTrue(output.plan.manifestToExternal.isEmpty)
            XCTAssertTrue(output.plan.manifestToInternal.isEmpty)
        }
    }

    func testPropertyDestructiveActionAlwaysHasSafetyActionFirst() {
        var generator = PlannerGenerator(seed: 2)
        for iteration in 0..<200 {
            let path = "files/\(iteration)-\(generator.next()).txt"
            let signature = generator.signature()
            let output = plan(path: path, baseline: signature, internalEntries: [:], externalEntries: [path: signature])
            for (index, action) in output.plan.actions.enumerated() where action.kind.isDestructive {
                XCTAssertGreaterThan(index, 0)
                XCTAssertEqual(output.plan.actions[index - 1].kind, .stageExistingVersion)
                XCTAssertEqual(output.plan.actions[index - 1].relativePath, action.relativePath)
            }
        }
    }

    func testPropertyIncompleteScanProducesNoDeletion() {
        var generator = PlannerGenerator(seed: 3)
        for iteration in 0..<200 {
            let path = "files/\(iteration).txt"
            let signature = generator.signature()
            let output = plan(path: path, baseline: signature, internalEntries: [:], externalEntries: [path: signature], internalComplete: false)
            XCTAssertFalse(output.plan.actions.contains { $0.kind == .deletePath })
            XCTAssertFalse(output.plan.deletionsAllowed)
        }
    }

    func testPropertyDifferentContentsNeverAutoOverwriteBidirectional() {
        var generator = PlannerGenerator(seed: 4)
        for iteration in 0..<200 {
            let path = "files/\(iteration).txt"
            let baseline = generator.signature()
            let internalSignature = generator.signature(differentFrom: baseline)
            let externalSignature = generator.signature(differentFrom: internalSignature)
            let output = plan(mode: .devBidirectional, path: path, baseline: baseline, internalEntries: [path: internalSignature], externalEntries: [path: externalSignature])
            XCTAssertFalse(output.plan.actions.contains { $0.kind == .copyPath })
            XCTAssertEqual(output.newConflicts.map(\.type), [.contentContent])
        }
    }

    func testPropertyUnavailableVolumeNeverProducesDeletion() {
        var generator = PlannerGenerator(seed: 5)
        for iteration in 0..<200 {
            let path = "files/\(iteration).txt"
            let signature = generator.signature()
            let output = plan(path: path, baseline: signature, internalEntries: [:], externalEntries: [path: signature], externalAvailable: false)
            XCTAssertFalse(output.plan.actions.contains { $0.kind == .deletePath })
            XCTAssertFalse(output.plan.deletionsAllowed)
        }
    }

    func testPropertyManagedLinkNeverEntersAnActionOrManifest() {
        var generator = PlannerGenerator(seed: 6)
        for iteration in 0..<200 {
            let path = "links/\(iteration)-\(generator.next())"
            let signature = generator.signature(kind: .symlink)
            let output = plan(
                path: path,
                baseline: signature,
                internalEntries: [:],
                externalEntries: [path: signature],
                internalExcluded: [path: .managedLink]
            )
            XCTAssertFalse(output.plan.actions.contains { $0.relativePath == path })
            XCTAssertFalse(output.plan.manifestToExternal.contains(path))
            XCTAssertFalse(output.plan.manifestToInternal.contains(path))
        }
    }

    func testPropertyFailedPreconditionReplanHasNoLaterDestructiveActionForPath() {
        var generator = PlannerGenerator(seed: 7)
        for iteration in 0..<200 {
            let path = "files/\(iteration).txt"
            let baseline = generator.signature()
            let initial = plan(path: path, baseline: baseline, internalEntries: [:], externalEntries: [path: baseline])
            XCTAssertTrue(initial.plan.actions.contains { $0.kind == .deletePath })
            let changedDestination = generator.signature(differentFrom: baseline)
            let replanned = plan(path: path, baseline: baseline, internalEntries: [:], externalEntries: [path: changedDestination])
            XCTAssertFalse(replanned.plan.actions.contains { $0.kind.isDestructive })
            XCTAssertEqual(replanned.newConflicts.map(\.type), [.deleteModify])
        }
    }

    func testPropertyRerunningSuccessfulPlanTransfersNothing() {
        var generator = PlannerGenerator(seed: 8)
        for iteration in 0..<200 {
            let path = "files/\(iteration).txt"
            let baseline = generator.signature()
            let changed = generator.signature(differentFrom: baseline)
            let first = plan(mode: .devBidirectional, path: path, baseline: baseline, internalEntries: [path: changed], externalEntries: [path: baseline])
            XCTAssertTrue(first.plan.actions.contains { $0.kind == .copyPath })
            let rerun = plan(mode: .devBidirectional, path: path, baseline: changed, internalEntries: [path: changed], externalEntries: [path: changed])
            XCTAssertFalse(rerun.plan.actions.contains { $0.kind == .copyPath || $0.kind == .deletePath || $0.kind == .movePath })
        }
    }

    func testPropertyTombstonePreventsResurrection() {
        var generator = PlannerGenerator(seed: 9)
        for iteration in 0..<200 {
            let path = "files/\(iteration).txt"
            let signature = generator.signature()
            let tombstone = DevTombstone(
                projectID: projectID,
                relativePath: path,
                deletedFromSide: .internal,
                baselineSignature: signature,
                createdAt: now,
                observedInternal: true,
                observedExternal: false,
                expiresAt: now.addingTimeInterval(30 * 86_400)
            )
            let output = plan(path: path, baseline: signature, internalEntries: [:], externalEntries: [path: signature], tombstones: [tombstone])
            XCTAssertFalse(output.plan.actions.contains { $0.kind == .copyPath })
            XCTAssertEqual(output.plan.actions.map(\.kind), [.stageExistingVersion, .deletePath])
        }
    }

    func testPropertyCollidingNamesNeverEnterManifest() {
        var generator = PlannerGenerator(seed: 10)
        for iteration in 0..<200 {
            let composed = "names/caf\u{00e9}-\(iteration)-\(generator.next()).txt"
            let decomposed = composed.decomposedStringWithCanonicalMapping
            let output = plan(
                path: composed,
                baseline: nil,
                internalEntries: [composed: generator.signature()],
                externalEntries: [:],
                collisions: [[composed, decomposed]]
            )
            XCTAssertTrue(output.plan.manifestToExternal.isEmpty)
            XCTAssertTrue(output.plan.manifestToInternal.isEmpty)
            XCTAssertEqual(output.projectState, .blockedByFileSystem)
        }
    }

    private let pairID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func plan(
        mode: DevSyncMode = .devOneWay,
        path: String,
        baseline: DevFileSignature?,
        internalEntries: [String: DevFileSignature],
        externalEntries: [String: DevFileSignature],
        tombstones: [DevTombstone] = [],
        internalExcluded: [String: DevFilePolicyReason] = [:],
        collisions: [[String]] = [],
        internalComplete: Bool = true,
        externalAvailable: Bool = true
    ) -> DevPlannerOutput {
        let pair = DevSyncPair(
            id: pairID,
            displayName: "Properties",
            mode: mode,
            internalRoot: DevSyncRoot(bookmark: nil, path: "/internal", volumeIdentifier: "internal", volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: "/external", volumeIdentifier: "external", volumeName: "External", fileSystemType: "apfs"),
            updatedAt: now
        )
        let identity = DevProjectIdentity(remoteURLHints: [], headReference: nil, firstCommit: "root", topologyKind: .gitRepository, fingerprint: "root")
        let project = DevProject(id: projectID, pairID: pairID, relativePath: "project", residency: .mirrored, kind: .gitRepository, identity: identity, state: .clean)
        let baselineDocument = baseline.map {
            DevBaseline(projectID: projectID, entries: [path: DevBaselineEntry(signature: $0, lastVerifiedAt: now)], updatedAt: now)
        }
        let internalSnapshot = DevSnapshot(entries: internalEntries, excluded: internalExcluded, unreadablePaths: [], complete: internalComplete, collisions: collisions, includedBytes: 0, excludedBytes: 0, scannedAt: now)
        let externalSnapshot = externalAvailable
            ? DevSnapshot(entries: externalEntries, excluded: [:], unreadablePaths: [], complete: true, collisions: [], includedBytes: 0, excludedBytes: 0, scannedAt: now)
            : nil
        return DevReconciliationPlanner.plan(
            DevPlannerInput(
                pair: pair,
                project: project,
                baseline: baselineDocument,
                internalSnapshot: internalSnapshot,
                externalSnapshot: externalSnapshot,
                tombstones: tombstones,
                unresolvedConflicts: [],
                capabilities: DevPairCapabilities(),
                unstablePaths: [],
                now: now
            )
        )
    }
}

private nonisolated struct PlannerGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    mutating func index<T>(in values: [T]) -> Int {
        Int(next() % UInt64(values.count))
    }

    mutating func signature(kind: DevEntryKind = .file, differentFrom other: DevFileSignature? = nil) -> DevFileSignature {
        var value = next()
        if let other {
            while other.contentHash == data(value) { value = next() }
        }
        return DevFileSignature(
            kind: kind,
            size: kind == .directory ? nil : value % 1_000 + 1,
            modificationTimeNanoseconds: Int64(bitPattern: value),
            mode: 0o644,
            symlinkTarget: kind == .symlink ? "target-\(value)" : nil,
            contentHash: kind == .file ? data(value) : nil
        )
    }

    private func data(_ value: UInt64) -> Data {
        var value = value.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }
}
