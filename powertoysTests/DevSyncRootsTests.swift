import Darwin
import Foundation
import XCTest
@testable import powertoys

final class DevSyncRootsTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-roots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testScenario20RejectsSameNestedAndSymlinkRoots() throws {
        let internalURL = temporaryRoot.appendingPathComponent("internal", isDirectory: true)
        let externalURL = temporaryRoot.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: internalURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalURL, withIntermediateDirectories: true)

        let sameIssues = DevSyncRoots.validatePair(internal: internalURL, external: internalURL, existingPairs: [])
        XCTAssertTrue(sameIssues.contains(.sameDirectory), "same: \(sameIssues)")

        let nestedURL = internalURL.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        let nestedIssues = DevSyncRoots.validatePair(internal: internalURL, external: nestedURL, existingPairs: [])
        XCTAssertTrue(nestedIssues.contains { if case .nested = $0 { return true }; return false }, "nested: \(nestedIssues)")

        let symlinkURL = temporaryRoot.appendingPathComponent("internal-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: internalURL)
        let symlinkIssues = DevSyncRoots.validatePair(internal: symlinkURL, external: internalURL, existingPairs: [])
        XCTAssertTrue(symlinkIssues.contains(.sameDirectory), "symlink: \(symlinkIssues)")
    }

    func testScenario21RejectsExistingPairOverlapInBothDirections() throws {
        let existingInternal = temporaryRoot.appendingPathComponent("existing-internal", isDirectory: true)
        let existingExternal = temporaryRoot.appendingPathComponent("existing-external", isDirectory: true)
        let candidateExternal = temporaryRoot.appendingPathComponent("candidate-external", isDirectory: true)
        try FileManager.default.createDirectory(at: existingInternal, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingExternal, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: candidateExternal, withIntermediateDirectories: true)
        let existingPair = DevSyncPair(
            displayName: "DevSSD",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: existingInternal.path, volumeIdentifier: "uuid:internal", volumeName: "Internal", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: existingExternal.path, volumeIdentifier: "uuid:external", volumeName: "External", fileSystemType: "apfs")
        )

        let nestedCandidate = existingInternal.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedCandidate, withIntermediateDirectories: true)
        let nestedCandidatePath = try DevSyncRoots.canonicalURL(nestedCandidate).path
        XCTAssertTrue(
            DevSyncRoots.validatePair(internal: nestedCandidate, external: candidateExternal, existingPairs: [existingPair])
                .contains { if case .overlapsExistingPair(pairName: "DevSSD", path: nestedCandidatePath) = $0 { return true }; return false }
        )

        let outerCandidate = temporaryRoot.appendingPathComponent("outer", isDirectory: true)
        try FileManager.default.createDirectory(at: outerCandidate, withIntermediateDirectories: true)
        let nestedExisting = outerCandidate.appendingPathComponent("inside", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedExisting, withIntermediateDirectories: true)
        let nestedExistingPath = try DevSyncRoots.canonicalURL(nestedExisting).path
        let pairWithNestedRoot = DevSyncPair(
            displayName: "NestedPair",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: nestedExisting.path, volumeIdentifier: "uuid:nested", volumeName: "Nested", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: existingExternal.path, volumeIdentifier: "uuid:external", volumeName: "External", fileSystemType: "apfs")
        )
        XCTAssertTrue(
            DevSyncRoots.validatePair(internal: outerCandidate, external: candidateExternal, existingPairs: [pairWithNestedRoot])
                .contains { if case .overlapsExistingPair(pairName: "NestedPair", path: nestedExistingPath) = $0 { return true }; return false }
        )

        let offlineNestedPath = try DevSyncRoots.canonicalURL(outerCandidate).appendingPathComponent("offline-root").path
        let pairWithOfflineRoot = DevSyncPair(
            displayName: "OfflinePair",
            mode: .devOneWay,
            internalRoot: DevSyncRoot(bookmark: nil, path: offlineNestedPath, volumeIdentifier: "uuid:offline", volumeName: "Offline", fileSystemType: "apfs"),
            externalRoot: existingPair.externalRoot
        )
        let offlineIssues = DevSyncRoots.validatePair(internal: outerCandidate, external: candidateExternal, existingPairs: [pairWithOfflineRoot])
        XCTAssertTrue(
            offlineIssues.contains { if case .overlapsExistingPair(pairName: "OfflinePair", path: offlineNestedPath) = $0 { return true }; return false },
            "\(offlineIssues)"
        )
    }

    func testMakeRootCanonicalizesPathAndStoresVolumeUUID() throws {
        let realURL = temporaryRoot.appendingPathComponent("real", isDirectory: true)
        let aliasURL = temporaryRoot.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: realURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: realURL)

        let root = try DevSyncRoots.makeRoot(url: aliasURL)

        XCTAssertEqual(root.path, try DevSyncRoots.canonicalURL(realURL).path)
        XCTAssertTrue(root.bookmark?.isEmpty == false)
        XCTAssertTrue(root.volumeIdentifier.hasPrefix("uuid:"))
    }

    func testScenario54ResolveReturnsIdentityMismatchForWrongStoredVolume() throws {
        let rootURL = temporaryRoot.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var root = try DevSyncRoots.makeRoot(url: rootURL)
        root.volumeIdentifier = "uuid:not-the-current-volume"

        guard case .identityMismatch(let foundIdentifier, let foundName) = DevSyncRoots.resolve(root) else {
            return XCTFail("Expected a volume identity mismatch")
        }
        XCTAssertTrue(foundIdentifier.hasPrefix("uuid:"))
        XCTAssertFalse(foundName.isEmpty)
    }

    func testScenario55ResolveTracksMovedRootOnSameVolume() throws {
        let originalURL = temporaryRoot.appendingPathComponent("original", isDirectory: true)
        let movedURL = temporaryRoot.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: true)
        var root = try DevSyncRoots.makeRoot(url: originalURL)
        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        root.path = movedURL.path

        guard case .available(let resolvedURL) = DevSyncRoots.resolve(root) else {
            return XCTFail("Expected bookmark resolution after a same-volume move")
        }
        XCTAssertEqual(resolvedURL.path, try DevSyncRoots.canonicalURL(movedURL).path)
    }

    func testScenario43Scenario57ProbeReportsFullAPFSFidelityAndCapacity() throws {
        let capabilities = DevVolumeProbe.probe(rootURL: temporaryRoot, probeDirectory: temporaryRoot)

        XCTAssertEqual(capabilities.fidelity, .full)
        XCTAssertEqual(capabilities.timestampResolutionNanoseconds, 1)
        XCTAssertTrue(capabilities.supportsSymbolicLinks)
        XCTAssertTrue(capabilities.supportsExtendedAttributes)
        XCTAssertGreaterThan(capabilities.availableCapacity, 0)
    }

    func testScenario56ProbeBlocksAnUnwritableRoot() {
        chmod(temporaryRoot.path, mode_t(0o500))
        defer { chmod(temporaryRoot.path, mode_t(0o700)) }

        let capabilities = DevVolumeProbe.probe(rootURL: temporaryRoot, probeDirectory: temporaryRoot)

        XCTAssertEqual(capabilities.fidelity, .blocked)
        XCTAssertTrue(capabilities.fidelityNotes.contains("Volume is not writable"))
    }

    func testScenario56ProbeNeverEscapesThroughTheSystemDirectoryLink() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("devsync-probe-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: temporaryRoot.appendingPathComponent(".cloudsync-system"),
            withDestinationURL: outside
        )

        let capabilities = DevVolumeProbe.probe(rootURL: temporaryRoot)

        XCTAssertEqual(capabilities.fidelity, .blocked)
        XCTAssertTrue(capabilities.fidelityNotes.contains("Temporary volume probe is outside the root"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testScenario59SyntheticCoarseVolumeUsesTwoSecondWindow() {
        let capabilities = DevVolumeCapabilities(
            volumeIdentifier: "vol:DevSSD:1",
            volumeName: "DevSSD",
            mountPath: "/Volumes/DevSSD",
            fileSystemType: "exfat",
            isReadOnly: false,
            isRemovable: true,
            isLocal: true,
            isEncrypted: false,
            availableCapacity: 2_000_000_000,
            totalCapacity: 8_000_000_000,
            isCaseSensitive: false,
            isCasePreserving: true,
            supportsSymbolicLinks: false,
            supportsHardLinks: false,
            supportsUnixPermissions: false,
            supportsExtendedAttributes: false,
            supportsCreationTimes: false,
            supportsPersistentIdentifiers: false,
            timestampResolutionNanoseconds: 2_000_000_000,
            maximumPathComponentLength: 255,
            probedAt: Date(),
            fidelity: .portable,
            fidelityNotes: [
                "Symbolic links are not preserved",
                "Executable bits are not preserved",
                "Timestamps use a 2 s modify window"
            ]
        )

        XCTAssertEqual(capabilities.fidelity, .portable)
        XCTAssertEqual(capabilities.modifyWindowSeconds, 2)
        XCTAssertEqual(capabilities.fidelityNotes.count, 3)
    }

    func testScenario60ProbeReportsTheVolumeEncryptionState() throws {
        let expected = try temporaryRoot.resourceValues(forKeys: [.volumeIsEncryptedKey]).volumeIsEncrypted
        let capabilities = DevVolumeProbe.probe(rootURL: temporaryRoot, probeDirectory: temporaryRoot)

        XCTAssertEqual(capabilities.isEncrypted, expected)
        if expected == true {
            XCTAssertEqual(capabilities.fidelity, .full)
        }
    }
}
