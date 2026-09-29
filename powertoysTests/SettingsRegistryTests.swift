import XCTest
@testable import powertoys

@MainActor
final class SettingsRegistryTests: XCTestCase {
    func testFreshDefaultsHaveNoDifferencesAndRequiredDefaultsAreRegistered() {
        withDefaults { defaults in
            XCTAssertTrue(SettingsRegistry.modified(defaults: defaults).isEmpty)

            let keys = Set(SettingsRegistry.entries.map(\.key))
            XCTAssertTrue(keys.isSuperset(of: [
                "app.appearance",
                "app.closeMainWindowAfterOpeningTool",
                "app.showTray",
                "settingsSync.enabled",
                "main.favorites",
                "main.sort",
                "main.viewMode",
                "color-picker.format.v1",
            ]))
        }
    }

    func testNSNumberScalarsCompareByValue() {
        withDefaults { defaults in
            defaults.set(NSNumber(value: 1), forKey: "count")
            defaults.set(NSNumber(value: true), forKey: "enabled")

            let entries = [
                testEntry(id: "count", defaultValue: 1),
                testEntry(id: "enabled", defaultValue: true),
            ]
            XCTAssertTrue(SettingsRegistry.modified(entries: entries, defaults: defaults).isEmpty)
        }
    }

    func testRegisteredScalarDisplaysKeepNumbersAndBooleansDistinct() throws {
        try withDefaults { defaults in
            let transfers = try XCTUnwrap(SettingsRegistry.entries.first { $0.id == "rclone.transfers" })
            let showTray = try XCTUnwrap(SettingsRegistry.entries.first { $0.id == "app.showTray" })
            defaults.set(NSNumber(value: 1), forKey: transfers.key)
            defaults.set(NSNumber(value: true), forKey: showTray.key)

            XCTAssertEqual(transfers.currentDisplay(defaults: defaults), "1")
            XCTAssertEqual(showTray.currentDisplay(defaults: defaults), "Enabled")
        }
    }

    func testJSONStringComparisonIgnoresWhitespaceAndObjectOrder() {
        withDefaults { defaults in
            defaults.set(#"{ "items": [1, 2], "enabled": true }"#, forKey: "json")
            let entry = testEntry(
                id: "json",
                defaultValue: #"{"enabled":true,"items":[1,2]}"#
            )

            XCTAssertTrue(SettingsRegistry.modified(entries: [entry], defaults: defaults).isEmpty)
        }
    }

    func testResetTouchesOnlySelectedEntryAndSkipsLiveCallbackForCustomSuite() async {
        await withDefaults { defaults in
            defaults.set(2, forKey: "first")
            defaults.set(3, forKey: "second")
            var callbackCount = 0
            let first = testEntry(
                id: "first",
                defaultValue: 1,
                beforeReset: { callbackCount += 1 }
            )
            let second = testEntry(id: "second", defaultValue: 1)

            await SettingsRegistry.reset(first, defaults: defaults)

            XCTAssertNil(defaults.object(forKey: "first"))
            XCTAssertEqual(defaults.integer(forKey: "second"), 3)
            XCTAssertEqual(callbackCount, 0, "Custom suites must not call live runtime callbacks")
            XCTAssertEqual(
                SettingsRegistry.modified(entries: [first, second], defaults: defaults).map(\.id),
                ["second"]
            )
        }
    }

    func testPerToolEnablementResetPreservesDisabledSiblings() async throws {
        try await withDefaults { defaults in
            defaults.set(["awake", "rclone"], forKey: "powertoys.disabledTools")
            let entries = SettingsRegistry.entries(toolIDs: ["awake", "rclone"])
                .filter { $0.id.hasSuffix(".enabled") }

            XCTAssertEqual(Set(SettingsRegistry.modified(entries: entries, defaults: defaults).map(\.toolID)), ["awake", "rclone"])

            let awake = try XCTUnwrap(entries.first { $0.toolID == "awake" })
            await SettingsRegistry.reset(awake, defaults: defaults)

            XCTAssertEqual(defaults.stringArray(forKey: "powertoys.disabledTools"), ["rclone"])
            XCTAssertEqual(SettingsRegistry.modified(entries: entries, defaults: defaults).map(\.toolID), ["rclone"])
        }
    }

    func testCodableFieldResetPreservesSiblingSettings() async throws {
        try await withDefaults { defaults in
            let stored = TextExtractorSettings(
                speed: .accurate,
                languageCorrection: false,
                preferredLanguages: ["en-US"],
                detectCodes: false
            )
            defaults.set(try JSONEncoder().encode(stored), forKey: "text-extractor.settings.v1")
            let entries = SettingsRegistry.entries(toolIDs: ["text-extractor"])
            let quality = try XCTUnwrap(entries.first { $0.id == "text-extractor.recognitionQuality" })

            await SettingsRegistry.reset(quality, defaults: defaults)

            let data = try XCTUnwrap(defaults.data(forKey: "text-extractor.settings.v1"))
            let updated = try JSONDecoder().decode(TextExtractorSettings.self, from: data)
            XCTAssertEqual(updated.speed, .fast)
            XCTAssertFalse(updated.languageCorrection)
            XCTAssertEqual(updated.preferredLanguages, ["en-US"])
            XCTAssertFalse(updated.detectCodes)
        }
    }

    func testUnknownKeysAreIgnored() {
        withDefaults { defaults in
            defaults.set("keep me", forKey: "unknown.preference")

            XCTAssertTrue(SettingsRegistry.modified(defaults: defaults).isEmpty)
            XCTAssertEqual(defaults.string(forKey: "unknown.preference"), "keep me")
        }
    }

    private func testEntry(
        id: String,
        defaultValue: Any,
        beforeReset: (() async -> Void)? = nil
    ) -> SettingsRegistry.Entry {
        SettingsRegistry.Entry(
            id: id,
            key: id,
            label: id,
            defaultValue: defaultValue,
            readValue: { $0.object(forKey: id) ?? defaultValue },
            resetStoredValue: { $0.removeObject(forKey: id) },
            beforeReset: beforeReset
        )
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "SettingsRegistryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "SettingsRegistryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }
}
