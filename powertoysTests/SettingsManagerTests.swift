import XCTest
@testable import powertoys

@MainActor
final class SettingsManagerTests: XCTestCase {
    private var names: [String] = []

    override func tearDown() {
        for name in names {
            UserDefaults.standard.removeObject(forKey: "powertoys.\(name)")
            UserDefaults.standard.removeObject(forKey: "powertoys.test-tool.\(name)")
        }
        super.tearDown()
    }

    func testGenericGetSetRemoveAndToolNamespace() {
        let name = uniqueName()
        let manager = SettingsManager.shared
        XCTAssertEqual(manager.get(name, default: "fallback"), "fallback")

        manager.set(name, value: "global")
        manager.setToolSetting(name, for: "test-tool", value: "scoped")
        XCTAssertEqual(manager.get(name, default: "fallback"), "global")
        XCTAssertEqual(manager.toolSetting(name, for: "test-tool", default: "fallback"), "scoped")

        manager.remove(name)
        XCTAssertEqual(manager.get(name, default: "fallback"), "fallback")
        XCTAssertEqual(manager.toolSetting(name, for: "test-tool", default: "fallback"), "scoped")
    }

    func testTypedDefaultsDistinguishMissingFromStoredZeroValues() {
        let name = uniqueName()
        let manager = SettingsManager.shared
        XCTAssertTrue(manager.getBool(name, default: true))
        XCTAssertEqual(manager.getInt(name, default: 42), 42)
        XCTAssertEqual(manager.getDouble(name, default: 2.5), 2.5)
        XCTAssertEqual(manager.getString(name, default: "fallback"), "fallback")

        manager.set(name, value: false)
        XCTAssertFalse(manager.getBool(name, default: true))
        manager.set(name, value: 0)
        XCTAssertEqual(manager.getInt(name, default: 42), 0)
        manager.set(name, value: 0.0)
        XCTAssertEqual(manager.getDouble(name, default: 2.5), 0)
        manager.set(name, value: "")
        XCTAssertEqual(manager.getString(name, default: "fallback"), "")
    }

    func testDataAndCodableRoundTripAndMalformedDataFailsSafely() {
        struct Payload: Codable, Equatable { let value: Int }
        let name = uniqueName()
        let manager = SettingsManager.shared

        XCTAssertNil(manager.getData(name))
        manager.setCodable(name, value: Payload(value: 7))
        XCTAssertEqual(manager.getCodable(name, type: Payload.self), Payload(value: 7))

        manager.setData(name, value: Data("invalid".utf8))
        XCTAssertNil(manager.getCodable(name, type: Payload.self))
    }

    func testThemeAndToolEnablementRoundTrip() {
        let defaults = UserDefaults.standard
        let themeKey = "powertoys.theme"
        let toolsKey = "powertoys.disabledTools"
        let savedTheme = defaults.object(forKey: themeKey)
        let savedTools = defaults.object(forKey: toolsKey)
        defer {
            restore(savedTheme, key: themeKey)
            restore(savedTools, key: toolsKey)
        }

        defaults.removeObject(forKey: themeKey)
        defaults.removeObject(forKey: toolsKey)
        XCTAssertEqual(SettingsManager.shared.theme, "system")
        SettingsManager.shared.setToolEnabled(true, for: "test-toggle")
        XCTAssertTrue(SettingsManager.shared.isToolEnabled("test-toggle"))

        SettingsManager.shared.theme = "dark"
        SettingsManager.shared.setToolEnabled(false, for: "test-toggle")
        XCTAssertEqual(SettingsManager.shared.theme, "dark")
        XCTAssertFalse(SettingsManager.shared.isToolEnabled("test-toggle"))
        XCTAssertTrue((defaults.stringArray(forKey: toolsKey) ?? []).contains("test-toggle"))
        SettingsManager.shared.setToolEnabled(true, for: "test-toggle")
    }

    func testLegacyMonitorIDMigratesToCurrentID() {
        XCTAssertEqual(SettingsManager.migratedDisabledToolID("power-stats"), "system-monitor")
        XCTAssertEqual(SettingsManager.migratedDisabledToolID("system-care"), "system-care")
    }

    private func uniqueName() -> String {
        let name = "test.\(UUID().uuidString)"
        names.append(name)
        return name
    }

    private func restore(_ value: Any?, key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}
