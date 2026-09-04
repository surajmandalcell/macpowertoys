import XCTest
@testable import powertoys

final class DevSyncModelTests: XCTestCase {
    func testPairRoundTripsThroughJSON() throws {
        let pair = DevSyncPair(
            displayName: "DevSSD",
            mode: .devBidirectional,
            internalRoot: DevSyncRoot(bookmark: Data([1, 2]), path: "/Users/me/dev", volumeIdentifier: "uuid:A", volumeName: "Macintosh HD", fileSystemType: "apfs"),
            externalRoot: DevSyncRoot(bookmark: nil, path: "/Volumes/DevSSD/dev", volumeIdentifier: "uuid:B", volumeName: "DevSSD", fileSystemType: "apfs")
        )
        let data = try JSONEncoder().encode(pair)
        let restored = try JSONDecoder().decode(DevSyncPair.self, from: data)
        XCTAssertEqual(restored, pair)
        XCTAssertEqual(restored.configuration, .default)
        XCTAssertEqual(restored.root(for: .external).volumeName, "DevSSD")
    }

    func testLegacyConfigurationGainsNewFieldsWithDefaults() throws {
        let json = #"{"policy":{"followGitIgnore":false},"safety":{"retainDeletesDays":3}}"#
        let configuration = try JSONDecoder().decode(DevSyncConfiguration.self, from: Data(json.utf8))
        XCTAssertFalse(configuration.policy.followGitIgnore)
        XCTAssertTrue(configuration.policy.includeIgnoredSensitiveFiles)
        XCTAssertEqual(configuration.policy.sensitivePatterns, DevSyncDefaults.sensitivePatterns)
        XCTAssertEqual(configuration.safety.retainDeletesDays, 3)
        XCTAssertEqual(configuration.safety.retainOverwritesDays, 7)
        XCTAssertEqual(configuration.timing, .default)
        XCTAssertEqual(configuration.performance.eventStormThreshold, 1_000)
        XCTAssertEqual(configuration.policySchemaVersion, 0)
        XCTAssertTrue(configuration.needsPolicyReview)
        XCTAssertFalse(DevSyncConfiguration.default.needsPolicyReview)
    }

    func testQuickSignatureMatchUsesToleranceAndExecutableBit() {
        let base = DevFileSignature(kind: .file, size: 10, modificationTimeNanoseconds: 1_000_000_000, mode: 0o644)
        let withinTolerance = DevFileSignature(kind: .file, size: 10, modificationTimeNanoseconds: 2_500_000_000, mode: 0o644)
        let executable = DevFileSignature(kind: .file, size: 10, modificationTimeNanoseconds: 1_000_000_000, mode: 0o755)
        let directory = DevFileSignature(kind: .directory)

        XCTAssertTrue(base.quickMatches(withinTolerance, toleranceNanoseconds: 2_000_000_000, compareMode: true))
        XCTAssertFalse(base.quickMatches(withinTolerance, toleranceNanoseconds: 1_000_000_000, compareMode: true))
        XCTAssertFalse(base.quickMatches(executable, toleranceNanoseconds: 0, compareMode: true))
        XCTAssertTrue(base.quickMatches(executable, toleranceNanoseconds: 0, compareMode: false))
        XCTAssertFalse(base.quickMatches(directory, toleranceNanoseconds: 0, compareMode: true))
        XCTAssertTrue(directory.quickMatches(DevFileSignature(kind: .directory), toleranceNanoseconds: 0, compareMode: true))
    }

    func testExitCodesClassifyPerSpecTable() {
        XCTAssertEqual(DevRsyncExitClass.classify(exitCode: 0), .success)
        XCTAssertEqual(DevRsyncExitClass.classify(exitCode: 20), .cancelled)
        XCTAssertEqual(DevRsyncExitClass.classify(exitCode: 23), .partial)
        XCTAssertEqual(DevRsyncExitClass.classify(exitCode: 24), .vanished)
        XCTAssertEqual(DevRsyncExitClass.classify(exitCode: 25), .deleteLimit)
        XCTAssertEqual(DevRsyncExitClass.classify(exitCode: 1), .failure)
        XCTAssertEqual(DevRsyncExitClass.classify(exitCode: 255), .failure)
    }

    func testPrimaryActionTitleStatesTheRealOperation() {
        var summary = DevPlanSummary()
        XCTAssertEqual(summary.primaryActionTitle, "Nothing to change")
        summary.managedLinksToCreate = 1
        XCTAssertEqual(summary.primaryActionTitle, "Create 1 managed link")
        summary.copyToExternalCount = 3
        XCTAssertEqual(summary.primaryActionTitle, "Copy 3 files and 1 managed link")
        summary.deletionCount = 2
        XCTAssertEqual(summary.primaryActionTitle, "Copy 3 files and 1 managed link and 2 deletions")
    }

    func testRelativePathSafetyRejectsEscapesAndSystemPaths() {
        XCTAssertTrue(DevRelativePath.isSafe("src/main.swift"))
        XCTAssertTrue(DevRelativePath.isSafe("dir with space/ü.txt"))
        XCTAssertFalse(DevRelativePath.isSafe(""))
        XCTAssertFalse(DevRelativePath.isSafe("/abs"))
        XCTAssertFalse(DevRelativePath.isSafe("a/../b"))
        XCTAssertFalse(DevRelativePath.isSafe("a//b"))
        XCTAssertFalse(DevRelativePath.isSafe("a\0b"))
        XCTAssertTrue(DevRelativePath.isCloudSyncSystemPath("proj/.cloudsync-system/x"))
        XCTAssertFalse(DevRelativePath.isCloudSyncSystemPath("proj/system/x"))
        XCTAssertEqual(DevRelativePath.parent("a/b/c"), "a/b")
        XCTAssertNil(DevRelativePath.parent("a"))
        XCTAssertEqual(DevRelativePath.normalizedKey("Re\u{0301}sume\u{0301}.MD"), "résumé.md")
    }

    func testGlobMatchingCoversSensitiveAndCachePatterns() {
        XCTAssertTrue(DevRelativePath.matchesGlob("*.pem", name: "server.pem"))
        XCTAssertTrue(DevRelativePath.matchesGlob(".env.*", name: ".env.local"))
        XCTAssertFalse(DevRelativePath.matchesGlob(".env.*", name: ".env"))
        XCTAssertTrue(DevRelativePath.matchesGlob("cmake-build-*", name: "cmake-build-debug"))
        XCTAssertTrue(DevRelativePath.matchesGlob("credentials*.json", name: "credentials-prod.json"))
    }

    func testConflictTypesThatBlockWholeProject() {
        XCTAssertTrue(DevConflictType.caseCollision.blocksWholeProject)
        XCTAssertTrue(DevConflictType.projectIdentity.blocksWholeProject)
        XCTAssertFalse(DevConflictType.contentContent.blocksWholeProject)
        XCTAssertFalse(DevConflictType.destinationDrift.blocksWholeProject)
    }
}
