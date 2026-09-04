import XCTest
@testable import powertoys

final class DevSyncPolicyTests: XCTestCase {
    func testScenario25IgnoredSensitiveFileUsesSensitiveOverride() {
        let decision = engine(gitIgnored: [".env.local"]).decide(
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

    func testExplicitExcludeAppliesBeforeSensitiveAndGitRules() {
        var policy = DevSyncConfiguration.Policy()
        policy.explicitExcludes = ["config/.env.local"]
        let decision = engine(
            policy: policy,
            gitTracked: ["config/.env.local"],
            gitIgnored: ["config/.env.local"]
        ).decide(
            DevPolicyInput(relativePath: "config/.env.local", kind: .file, size: 1, isInsideGitDirectory: false)
        )

        XCTAssertEqual(decision.reason, .explicitUserExclude)
        XCTAssertFalse(decision.included)
    }

    func testScenario25SensitiveSizeGuardExcludesOversizedMatch() {
        var policy = DevSyncConfiguration.Policy()
        policy.includeIgnoredSensitiveFiles = false
        policy.sensitiveSizeGuardBytes = 10
        let decision = engine(policy: policy).decide(
            DevPolicyInput(relativePath: "credentials.json", kind: .file, size: 11, isInsideGitDirectory: false)
        )
        XCTAssertEqual(decision.reason, .sensitiveSizeGuard)
        XCTAssertFalse(decision.included)

        let ignored = engine(policy: policy, gitIgnored: [".env.local"]).decide(
            DevPolicyInput(relativePath: ".env.local", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        XCTAssertEqual(ignored.reason, .gitIgnored)
    }

    func testScenario26GitLockIsExcludedButImportantLockIsIncluded() {
        var policy = DevSyncConfiguration.Policy()
        policy.explicitIncludes = [".git/index.lock"]
        let policyEngine = DevFilePolicyEngine(
            policy: policy,
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

    func testRequiredGitMetadataFollowsSensitiveAndMetadataRules() {
        let metadata = engine().decide(
            DevPolicyInput(relativePath: ".git/MERGE_HEAD", kind: .file, size: 1, isInsideGitDirectory: true)
        )
        XCTAssertEqual(metadata.reason, .requiredGitMetadata)

        let sensitive = engine().decide(
            DevPolicyInput(relativePath: ".git/private.key", kind: .file, size: 1, isInsideGitDirectory: true)
        )
        XCTAssertEqual(sensitive.reason, .sensitiveOverride)
        XCTAssertTrue(sensitive.sensitive)

        var policy = DevSyncConfiguration.Policy()
        policy.includeGitMetadata = false
        let disabled = engine(policy: policy).decide(
            DevPolicyInput(relativePath: ".git/MERGE_HEAD", kind: .file, size: 1, isInsideGitDirectory: true)
        )
        XCTAssertFalse(disabled.included)

        policy.includeGitMetadata = true
        policy.includeGitLFSObjects = false
        let lfs = engine(policy: policy).decide(
            DevPolicyInput(relativePath: ".git/lfs/objects/object", kind: .file, size: 1, isInsideGitDirectory: true)
        )
        XCTAssertFalse(lfs.included)
    }

    func testGitTrackedBeatsGitIgnoreAndCommonCache() {
        let path = "node_modules/local-package/index.js"
        let decision = engine(gitTracked: [path], gitIgnored: [path]).decide(
            DevPolicyInput(relativePath: path, kind: .file, size: 1, isInsideGitDirectory: false)
        )

        XCTAssertEqual(decision.reason, .gitTracked)
        XCTAssertTrue(decision.included)
    }

    func testGitIgnoreBeatsCommonExclusion() {
        let path = "node_modules/index.js"
        let decision = engine(gitIgnored: [path]).decide(
            DevPolicyInput(relativePath: path, kind: .file, size: 1, isInsideGitDirectory: false)
        )

        XCTAssertEqual(decision.reason, .gitIgnored)
        XCTAssertFalse(decision.included)
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
        var policy = DevSyncConfiguration.Policy()
        policy.explicitIncludes = ["*.icloud"]
        let decision = engine(policy: policy, gitTracked: ["notes.txt.icloud"]).decide(
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
        let includedByDefault = engine().decide(
            DevPolicyInput(relativePath: "dist/app.js", kind: .file, size: 1, isInsideGitDirectory: false)
        )
        XCTAssertEqual(includedByDefault.reason, .defaultInclusion)
        XCTAssertTrue(includedByDefault.included)
        XCTAssertTrue(DevFilePolicyEngine.isCommonCachePath("project/node_modules/a.js"))
        XCTAssertTrue(DevFilePolicyEngine.isBuildOutputPath("project/dist/a.js"))
    }

    func testSensitivePatternsDoNotSearchExcludedCaches() {
        let decision = engine().decide(
            DevPolicyInput(relativePath: "node_modules/package/.env", kind: .file, size: 1, isInsideGitDirectory: false)
        )

        XCTAssertEqual(decision.reason, .commonExclusion)
        XCTAssertFalse(decision.included)
    }

    func testImportantLockFilesRemainEligibleWithoutTracking() {
        for path in DevSyncDefaults.importantLockFiles {
            let decision = engine().decide(
                DevPolicyInput(relativePath: path, kind: .file, size: 1, isInsideGitDirectory: false)
            )
            XCTAssertTrue(decision.included, path)
            XCTAssertEqual(decision.reason, .defaultInclusion, path)
        }
    }

    func testExplicitRulesMatchFullPathAndLastComponent() {
        var policy = DevSyncConfiguration.Policy()
        policy.explicitIncludes = ["config/*.json", "*.local"]
        let policyEngine = engine(policy: policy, gitIgnored: ["config/settings.json", "nested/user.local"])

        XCTAssertEqual(
            policyEngine.decide(DevPolicyInput(relativePath: "config/settings.json", kind: .file, size: 1, isInsideGitDirectory: false)).reason,
            .explicitUserInclude
        )
        XCTAssertEqual(
            policyEngine.decide(DevPolicyInput(relativePath: "nested/user.local", kind: .file, size: 1, isInsideGitDirectory: false)).reason,
            .explicitUserInclude
        )
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

        let reorderedEngine = engine(gitTracked: ["b", "a"], gitIgnored: ["d", "c"])
        let sortedEngine = engine(gitTracked: ["a", "b"], gitIgnored: ["c", "d"])
        XCTAssertEqual(reorderedEngine.fingerprint(), sortedEngine.fingerprint())
    }

    private func engine(
        policy: DevSyncConfiguration.Policy = .init(),
        gitTracked: Set<String> = [],
        gitIgnored: Set<String> = []
    ) -> DevFilePolicyEngine {
        DevFilePolicyEngine(
            policy: policy,
            projectKind: .gitRepository,
            gitDirectoryRelativePath: ".git",
            gitTracked: gitTracked,
            gitIgnored: gitIgnored,
            gitAvailable: true,
            projectIgnoreRules: []
        )
    }
}
