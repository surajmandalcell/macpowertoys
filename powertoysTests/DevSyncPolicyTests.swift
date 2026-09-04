import XCTest
@testable import powertoys

final class DevSyncPolicyTests: XCTestCase {
    func testScenario25IgnoredSensitiveFileUsesSensitiveOverride() {
        let decision = engine().decide(
            DevPolicyInput(relativePath: ".env.local", kind: .file, size: 12, isInsideGitDirectory: false)
        )
        XCTAssertEqual(decision.reason, .sensitiveOverride)
        XCTAssertTrue(decision.included)
        XCTAssertTrue(decision.sensitive)
    }

    func testScenario25ExplicitIncludeBeatsSensitiveSizeGuard() {
        var policy = DevSyncConfiguration.Policy()
        policy.sensitiveSizeGuardBytes = 10
        policy.explicitIncludes = ["secrets.bin"]
        let decision = engine(policy: policy).decide(
            DevPolicyInput(relativePath: "secrets.bin", kind: .file, size: 11, isInsideGitDirectory: false)
        )
        XCTAssertEqual(decision.reason, .explicitUserInclude)
        XCTAssertTrue(decision.included)
    }

    func testScenario25SensitiveSizeGuardExcludesOversizedMatch() {
        var policy = DevSyncConfiguration.Policy()
        policy.sensitiveSizeGuardBytes = 10
        let decision = engine(policy: policy).decide(
            DevPolicyInput(relativePath: "credentials.json", kind: .file, size: 11, isInsideGitDirectory: false)
        )
        XCTAssertEqual(decision.reason, .sensitiveSizeGuard)
        XCTAssertFalse(decision.included)
    }

    func testScenario26GitLockIsExcludedButImportantLockIsIncluded() {
        let policyEngine = DevFilePolicyEngine(
            policy: .init(),
            projectKind: .gitRepository,
            gitDirectoryRelativePath: ".git",
            gitTracked: ["package-lock.json"],
            gitIgnored: [],
            gitAvailable: true,
            projectIgnoreRules: []
        )
        let lock = policyEngine.decide(
            DevPolicyInput(relativePath: ".git/index.lock", kind: .file, size: 1, isInsideGitDirectory: true)
        )
        let important = policyEngine.decide(
            DevPolicyInput(relativePath: "package-lock.json", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        XCTAssertEqual(lock.reason, .transientGitLock)
        XCTAssertFalse(lock.included)
        XCTAssertEqual(important.reason, .gitTracked)
        XCTAssertTrue(important.included)
    }

    func testScenario40UnsupportedObjectTypeAlwaysExcluded() {
        var policy = DevSyncConfiguration.Policy()
        policy.explicitIncludes = ["socket"]
        let decision = engine(policy: policy).decide(
            DevPolicyInput(relativePath: "socket", kind: .unsupported, size: 0, isInsideGitDirectory: false)
        )
        XCTAssertEqual(decision.reason, .unsupportedObjectType)
        XCTAssertFalse(decision.included)
    }

    func testScenario50DSStoreIsHardExcluded() {
        let decision = engine().decide(
            DevPolicyInput(relativePath: "folder/.DS_Store", kind: .file, size: 100, isInsideGitDirectory: false)
        )
        XCTAssertEqual(decision.reason, .commonExclusion)
        XCTAssertFalse(decision.included)
    }

    func testScenario51CloudSyncSystemPathIsHardExcluded() {
        let decision = engine().decide(
            DevPolicyInput(relativePath: ".cloudsync-system/index", kind: .file, size: 100, isInsideGitDirectory: false)
        )
        XCTAssertEqual(decision.reason, .cloudSyncInternalPath)
        XCTAssertFalse(decision.included)
    }

    func testScenario52ICloudPlaceholderIsDataless() {
        let decision = engine().decide(
            DevPolicyInput(relativePath: "notes.txt.icloud", kind: .file, size: 0, isInsideGitDirectory: false)
        )
        XCTAssertEqual(decision.reason, .datalessPlaceholder)
        XCTAssertFalse(decision.included)
    }

    func testScenario24CommonCachesAndOptionalBuildOutputs() {
        let cache = engine().decide(
            DevPolicyInput(relativePath: "node_modules/package.js", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        XCTAssertEqual(cache.reason, .commonExclusion)

        var policy = DevSyncConfiguration.Policy()
        policy.skipUnignoredBuildOutputs = true
        let build = engine(policy: policy).decide(
            DevPolicyInput(relativePath: "dist/app.js", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        XCTAssertEqual(build.reason, .buildOutputExclusion)
        XCTAssertFalse(build.included)
        XCTAssertTrue(DevFilePolicyEngine.isCommonCachePath("project/node_modules/a.js"))
        XCTAssertTrue(DevFilePolicyEngine.isBuildOutputPath("project/dist/a.js"))
    }

    func testScenario44VolatileAndLargeFilesNeedStableWindow() {
        let database = engine().decide(
            DevPolicyInput(relativePath: "app.sqlite", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        let large = engine().decide(
            DevPolicyInput(relativePath: "archive.bin", kind: .file, size: 1_073_741_825, isInsideGitDirectory: false)
        )
        let diskImage = engine().decide(
            DevPolicyInput(relativePath: "images/disk.vmdk", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        XCTAssertTrue(database.volatile)
        XCTAssertTrue(database.requiresStableWindow)
        XCTAssertTrue(diskImage.volatile)
        XCTAssertTrue(diskImage.requiresStableWindow)
        XCTAssertFalse(large.volatile)
        XCTAssertTrue(large.requiresStableWindow)
    }

    func testScenario74NonGitPolicyUsesCommonProfileWithoutGitSets() {
        let policyEngine = DevFilePolicyEngine(
            policy: .init(),
            projectKind: .nonGit,
            gitDirectoryRelativePath: nil,
            gitTracked: nil,
            gitIgnored: nil,
            gitAvailable: false,
            projectIgnoreRules: []
        )
        let visible = policyEngine.decide(
            DevPolicyInput(relativePath: "source.swift", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        let cache = policyEngine.decide(
            DevPolicyInput(relativePath: "node_modules/file.js", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        XCTAssertEqual(visible.reason, .defaultInclusion)
        XCTAssertEqual(cache.reason, .commonExclusion)
    }

    func testPolicyIgnoreRulesAreOrderedAndFingerprintChangesWithRules() {
        let rules = DevFilePolicyEngine.parseProjectIgnoreRules("# comment\n*.tmp\n!important.tmp\n")
        XCTAssertEqual(rules, ["*.tmp", "!important.tmp"])
        let policyEngine = DevFilePolicyEngine(
            policy: .init(),
            projectKind: .nonGit,
            gitDirectoryRelativePath: nil,
            gitTracked: nil,
            gitIgnored: nil,
            gitAvailable: false,
            projectIgnoreRules: rules
        )
        XCTAssertEqual(
            policyEngine.decide(DevPolicyInput(relativePath: "other.tmp", kind: .file, size: 1, isInsideGitDirectory: false)).reason,
            .gitIgnored
        )
        XCTAssertEqual(
            policyEngine.decide(DevPolicyInput(relativePath: "important.tmp", kind: .file, size: 1, isInsideGitDirectory: false)).reason,
            .defaultInclusion
        )
        let otherEngine = DevFilePolicyEngine(
            policy: .init(),
            projectKind: .gitRepository,
            gitDirectoryRelativePath: ".git",
            gitTracked: [],
            gitIgnored: [],
            gitAvailable: true,
            projectIgnoreRules: []
        )
        XCTAssertNotEqual(policyEngine.fingerprint(), otherEngine.fingerprint())
    }

    private func engine(policy: DevSyncConfiguration.Policy = .init()) -> DevFilePolicyEngine {
        DevFilePolicyEngine(
            policy: policy,
            projectKind: .gitRepository,
            gitDirectoryRelativePath: ".git",
            gitTracked: [],
            gitIgnored: [],
            gitAvailable: true,
            projectIgnoreRules: []
        )
    }
}
