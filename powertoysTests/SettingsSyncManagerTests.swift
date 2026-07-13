import XCTest
@testable import powertoys

@MainActor
final class SettingsSyncManagerTests: XCTestCase {
    private final class FakeCloudStore: KeyValueCloudStore {
        var storage: [String: Any] = [:]
        var synchronizeCount = 0

        func object(forKey defaultName: String) -> Any? { storage[defaultName] }
        func set(_ value: Any?, forKey defaultName: String) { storage[defaultName] = value }
        func removeObject(forKey defaultName: String) { storage[defaultName] = nil }
        var dictionaryRepresentation: [String: Any] { storage }
        func synchronize() -> Bool {
            synchronizeCount += 1
            return true
        }
    }

    private var cloud: FakeCloudStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var appliedSourceLists: [[String]] = []
    private var writtenToolPrefs: [(bundleID: String, key: String, value: Any)] = []
    private var toolPrefs: [String: Any] = [:]
    private var receipts: [MarketplaceReceipt] = []

    override func setUp() {
        super.setUp()
        cloud = FakeCloudStore()
        suiteName = "settings-sync-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        appliedSourceLists = []
        writtenToolPrefs = []
        toolPrefs = [:]
        receipts = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeManager(sourceURLs: [String] = []) -> SettingsSyncManager {
        SettingsSyncManager(
            cloud: cloud,
            defaults: defaults,
            currentSourceURLs: { sourceURLs },
            applySourceURLs: { [weak self] in self?.appliedSourceLists.append($0) },
            receiptsProvider: { [weak self] in self?.receipts ?? [] },
            readToolPreference: { [weak self] bundleID, key in self?.toolPrefs["\(bundleID)/\(key)"] },
            writeToolPreference: { [weak self] bundleID, key, value in
                self?.writtenToolPrefs.append((bundleID, key, value))
            }
        )
    }

    private func makeReceipt() throws -> MarketplaceReceipt {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("spec/marketplace/valid-catalog.json")
        let catalog = try MarketplaceCatalog.decode(Data(contentsOf: url), reservedToolIDs: [])
        return MarketplaceReceipt(
            manifest: catalog.tools[0],
            sourceID: "acme-tools",
            sourceURL: URL(string: "https://example.com/catalog.json")!,
            installedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    func testEnableWithEmptyCloudPushesAllowlistedStateAndMarker() {
        defaults.set("Dark", forKey: "appTheme")
        defaults.set("session-junk", forKey: "rclone.lastContent")
        let manager = makeManager(sourceURLs: ["https://example.com/catalog.json"])

        XCTAssertEqual(manager.enable(), .enabled)

        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(cloud.storage["defaults.appTheme"] as? String, "Dark")
        XCTAssertEqual(cloud.storage["marketplace.sourceURLs"] as? [String], ["https://example.com/catalog.json"])
        XCTAssertNotNil(cloud.storage["settingsSync.seededAt"])
        XCTAssertFalse(cloud.storage.keys.contains { $0.contains("rclone.lastContent") })
    }

    func testEnableWithExistingCloudDataReportsConflictAndChangesNothing() {
        cloud.storage["settingsSync.seededAt"] = 1_780_000_000.0
        cloud.storage["defaults.appTheme"] = "Light"
        let manager = makeManager()

        XCTAssertEqual(manager.enable(), .conflict)

        XCTAssertFalse(manager.isEnabled)
        XCTAssertNil(defaults.string(forKey: "appTheme"))
        XCTAssertEqual(cloud.storage.count, 2)
    }

    func testResolveConflictUseCloudAppliesCloudState() {
        cloud.storage["settingsSync.seededAt"] = 1_780_000_000.0
        cloud.storage["defaults.appTheme"] = "Light"
        cloud.storage["marketplace.sourceURLs"] = ["https://example.com/catalog.json"]
        defaults.set("Dark", forKey: "appTheme")
        let manager = makeManager()

        manager.resolveConflict(useCloud: true)

        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(defaults.string(forKey: "appTheme"), "Light")
        XCTAssertEqual(appliedSourceLists, [["https://example.com/catalog.json"]])
        XCTAssertEqual(cloud.storage["defaults.appTheme"] as? String, "Light")
    }

    func testResolveConflictReplaceCloudPushesLocalState() {
        cloud.storage["settingsSync.seededAt"] = 1_780_000_000.0
        cloud.storage["defaults.appTheme"] = "Light"
        defaults.set("Dark", forKey: "appTheme")
        let manager = makeManager()

        manager.resolveConflict(useCloud: false)

        XCTAssertEqual(defaults.string(forKey: "appTheme"), "Dark")
        XCTAssertEqual(cloud.storage["defaults.appTheme"] as? String, "Dark")
        XCTAssertTrue(appliedSourceLists.isEmpty)
    }

    func testExternalChangeAppliesOnlyAllowlistedKeys() {
        let manager = makeManager()
        XCTAssertEqual(manager.enable(), .enabled)

        cloud.storage["defaults.appTheme"] = "Light"
        cloud.storage["defaults.rclone.lastContent"] = "evil"
        cloud.storage["marketplace.sourceURLs"] = ["https://other.example/catalog.json"]
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [
                "defaults.appTheme", "defaults.rclone.lastContent", "marketplace.sourceURLs"
            ]]
        )

        XCTAssertEqual(defaults.string(forKey: "appTheme"), "Light")
        XCTAssertNil(defaults.string(forKey: "rclone.lastContent"))
        XCTAssertEqual(appliedSourceLists.last, ["https://other.example/catalog.json"])
        XCTAssertNotNil(manager.lastSyncDescription)
    }

    func testToolContractPushAndApplyRespectDeclaredKeys() throws {
        receipts = [try makeReceipt()]
        toolPrefs["com.acme.window-snapper/snapper.gridColumns"] = 4
        let manager = makeManager()
        XCTAssertEqual(manager.enable(), .enabled)

        XCTAssertEqual(cloud.storage["tool.com.acme.window-snapper/snapper.gridColumns"] as? Int, 4)

        cloud.storage["tool.com.acme.window-snapper/snapper.showOverlay"] = true
        cloud.storage["tool.com.acme.window-snapper/not.declared"] = "evil"
        cloud.storage["tool.com.other.app/anything"] = "evil"
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: [
                "tool.com.acme.window-snapper/snapper.showOverlay",
                "tool.com.acme.window-snapper/not.declared",
                "tool.com.other.app/anything"
            ]]
        )

        XCTAssertEqual(writtenToolPrefs.count, 1)
        XCTAssertEqual(writtenToolPrefs[0].key, "snapper.showOverlay")
        XCTAssertEqual(writtenToolPrefs[0].value as? Bool, true)
    }

    func testLocalDefaultsChangePushesWithoutEcho() {
        let manager = makeManager()
        XCTAssertEqual(manager.enable(), .enabled)

        defaults.set("Light", forKey: "appTheme")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        XCTAssertEqual(cloud.storage["defaults.appTheme"] as? String, "Light")

        let writesBefore = cloud.synchronizeCount
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: ["defaults.appTheme"]]
        )
        XCTAssertEqual(cloud.storage["defaults.appTheme"] as? String, "Light")
        XCTAssertEqual(cloud.synchronizeCount, writesBefore)
    }

    func testDisableStopsObserving() {
        let manager = makeManager()
        XCTAssertEqual(manager.enable(), .enabled)
        manager.disable()

        cloud.storage["defaults.appTheme"] = "Light"
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: ["defaults.appTheme"]]
        )

        XCTAssertFalse(manager.isEnabled)
        XCTAssertNil(defaults.string(forKey: "appTheme"))
    }
}
