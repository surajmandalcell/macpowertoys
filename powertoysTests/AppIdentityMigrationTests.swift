import XCTest
@testable import powertoys

final class AppIdentityMigrationTests: XCTestCase {
    func testApplicationSupportMigrationCopiesLegacyDataWithoutDeletingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
        let legacy = root.appendingPathComponent("PowerToys", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("jobs".utf8).write(to: legacy.appendingPathComponent("transfers.json"))
        try Data("store".utf8).write(to: legacy.appendingPathComponent("PowerToys.store"))
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = AppDataLocation.prepareDirectory(at: root, isTest: false)

        XCTAssertEqual(destination.lastPathComponent, "MacPowerToys")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("transfers.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("MacPowerToys.store").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("transfers.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("PowerToys.store").path))
    }

    func testDefaultsMigrationDoesNotOverwriteNewValues() {
        let suite = "MacPowerToysTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("new", forKey: "existing")

        let count = AppIdentity.migrateLegacyDefaults(
            ["existing": "old", "copied": 42],
            into: defaults
        )

        XCTAssertEqual(count, 1)
        XCTAssertEqual(defaults.string(forKey: "existing"), "new")
        XCTAssertEqual(defaults.integer(forKey: "copied"), 42)
    }

    func testDeepLinksAcceptNewAndLegacySchemes() {
        XCTAssertTrue(DeepLinkHandler.isSupportedScheme("macpowertoys"))
        XCTAssertTrue(DeepLinkHandler.isSupportedScheme("powertoys"))
        XCTAssertFalse(DeepLinkHandler.isSupportedScheme("https"))
    }
}
