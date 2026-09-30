import CoreFoundation
import XCTest
@testable import powertoys

final class MacTweaksCatalogTests: XCTestCase {
    func testCatalogueAndSearch() {
        XCTAssertEqual(TweakCatalog.items.count, 130)
        XCTAssertEqual(Set(TweakCatalog.items.map(\.id)).count, 130)
        XCTAssertEqual(TweakSearch.results(for: "microphone").first?.id, "mic-lock")
        XCTAssertEqual(TweakSearch.results(for: "screnshot format").first?.id, "screenshots.format")
        XCTAssertEqual(TweakSearch.results(for: "dotfiles").first?.id, "finder.hidden-files")
        XCTAssertEqual(TweakSearch.results(for: "dock gap").first?.id, "dock.spacers")
        XCTAssertTrue(TweakSearch.results(for: "quiteunlikelyquery").isEmpty)
        XCTAssertFalse(TweakPreferences.supportsWrites(for: "finder.hidden-files", on: .init(majorVersion: 28, minorVersion: 0, patchVersion: 0)))
        XCTAssertFalse(TweakPreferences.fields(for: "finder.hidden-files").isEmpty)
        XCTAssertFalse(TweakPreferences.supportsWrites(for: "finder.column-sizing", on: .init(majorVersion: 27, minorVersion: 0, patchVersion: 0)))
    }

    func testEveryCatalogueCategoryAppearsOnceInSidebar() {
        let grouped = TweakCatalog.sidebarGroups.flatMap(\.categories)
        XCTAssertEqual(grouped.count, Set(grouped).count)
        XCTAssertEqual(Set(grouped), Set(TweakCatalog.items.map(\.category)).union([TweakSearch.micLock.category]))
    }

    func testEveryWritablePreferenceHasCompletePresentationMetadata() {
        let fields = TweakCatalog.items.flatMap { TweakPreferences.fields(for: $0.id) }
        XCTAssertFalse(fields.isEmpty)
        XCTAssertEqual(fields.map(\.identity).count, Set(fields.map(\.identity)).count)
        XCTAssertTrue(fields.allSatisfy { !$0.label.isEmpty && !$0.choices.isEmpty })
        XCTAssertTrue(fields.flatMap(\.choices).allSatisfy { !$0.label.isEmpty })

        let repeatField = TweakPreferences.fields(for: "input.press-hold")[0]
        XCTAssertEqual(repeatField.choices[0].value as? Bool, false, "On must disable the accent popup")
        XCTAssertEqual(repeatField.choices[1].value as? Bool, true)

        let shadowField = TweakPreferences.fields(for: "screenshots.shadow")[0]
        XCTAssertEqual(shadowField.choices[0].value as? Bool, false, "On must include window shadows")
        XCTAssertEqual(shadowField.choices[1].value as? Bool, true)
    }

    func testDeclaredDefaultsDriveModifiedStateAndControlLabels() {
        let hiddenFiles = TweakPreferences.fields(for: "finder.hidden-files")[0]
        XCTAssertFalse(hiddenFiles.differsFromDefault(-1))
        XCTAssertFalse(hiddenFiles.differsFromDefault(1))
        XCTAssertTrue(hiddenFiles.differsFromDefault(0))

        let revealDelay = TweakPreferences.fields(for: "dock.reveal-delay")[0]
        XCTAssertEqual(revealDelay.defaultLabel, "0.40")
        XCTAssertEqual(revealDelay.defaultSelection, 8)
        XCTAssertFalse(revealDelay.differsFromDefault(8))
        XCTAssertTrue(revealDelay.differsFromDefault(0))

        let menuSpacing = TweakPreferences.fields(for: "menubar.spacing")[0]
        XCTAssertEqual(menuSpacing.defaultLabel, "Always")
        XCTAssertFalse(menuSpacing.differsFromDefault(-1))
        XCTAssertTrue(menuSpacing.differsFromDefault(0))
        XCTAssertTrue(hiddenFiles.needsReset(1, hasBackup: true), "An original custom value must remain restorable at the declared default")
        XCTAssertTrue(hiddenFiles.needsReset(-1, hasBackup: true), "Deleting a key must not hide its original value")
        XCTAssertFalse(hiddenFiles.needsReset(1, hasBackup: false))
    }

    func testResetPreflightsManagedAndExternalChangesAndClearsUntrackedValues() throws {
        let domain = "com.macpowertoys.tweak-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ManagedTweakTestDefaults(suiteName: domain))
        let fields = ["First", "Second"].map { TweakPreferenceField.flag($0, domain, $0) }
        let store = TweakPreferenceStore(defaults: defaults)
        func set(_ value: CFPropertyList?, for field: TweakPreferenceField) {
            CFPreferencesSetValue(field.key as CFString, value, domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            XCTAssertTrue(CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
        }
        defer {
            for field in fields { set(nil, for: field) }
            defaults.removePersistentDomain(forName: domain)
        }

        try store.apply(fields, selections: Dictionary(uniqueKeysWithValues: fields.map { ($0.identity, 0) }))
        defaults.forcedKeys = [fields[1].key]
        XCTAssertThrowsError(try store.restore(fields, includingUntracked: true)) { error in
            guard case TweakPreferenceError.managed = error else { return XCTFail("Expected managed-preference protection") }
        }
        XCTAssertTrue(fields.allSatisfy { store.value(for: $0) as? Bool == true }, "Preflight must leave every key unchanged")
        XCTAssertTrue(store.hasBackup(for: fields))

        defaults.forcedKeys = []
        set("changed elsewhere" as CFString, for: fields[1])
        XCTAssertThrowsError(try store.restore(fields, includingUntracked: true)) { error in
            guard case TweakPreferenceError.changedElsewhere = error else { return XCTFail("Expected external-change protection") }
        }
        XCTAssertEqual(store.value(for: fields[0]) as? Bool, true)
        XCTAssertEqual(store.value(for: fields[1]) as? String, "changed elsewhere")
        set(true as CFPropertyList, for: fields[1])
        try store.restore(fields)
        XCTAssertTrue(fields.allSatisfy { store.value(for: $0) == nil })

        set("custom value" as CFString, for: fields[0])
        try store.restore(fields)
        XCTAssertEqual(store.value(for: fields[0]) as? String, "custom value", "Exact restore ignores untracked keys")
        try store.restore(fields, includingUntracked: true)
        XCTAssertNil(store.value(for: fields[0]))
        XCTAssertFalse(store.hasBackup(for: fields), "Reset to default must not create a reverse-reset backup")
    }

    func testExactPreferenceUndoRestoresAbsentAndExistingValues() throws {
        let domain = "com.macpowertoys.tweak-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let field = TweakPreferenceField.flag("Test", domain, "MacTweaksTestFlag")
        let store = TweakPreferenceStore(defaults: defaults)
        defer {
            CFPreferencesSetValue(field.key as CFString, nil, domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            defaults.removePersistentDomain(forName: domain)
        }

        XCTAssertNil(store.value(for: field))
        try store.apply([field], selections: [field.identity: -1])
        XCTAssertFalse(store.hasBackup(for: [field]), "A no-op must not create recovery state")

        try store.apply([field], selections: [field.identity: 0])
        XCTAssertEqual(store.value(for: field) as? Bool, true)
        XCTAssertTrue(store.hasBackup(for: [field]))
        XCTAssertEqual(store.storedOriginalChoices(for: [field])[field.identity], -1)
        XCTAssertEqual(TweakPreferenceStore.readSelectedChoice(for: field), 0)
        try store.apply([field], selections: [field.identity: -1])
        XCTAssertNil(store.value(for: field))
        XCTAssertFalse(store.hasBackup(for: [field]), "Returning to the original value must clear recovery state")

        try store.apply([field], selections: [field.identity: 0])
        CFPreferencesSetValue(field.key as CFString, nil, domain as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        XCTAssertTrue(CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
        try store.restore([field])
        XCTAssertFalse(store.hasBackup(for: [field]))

        CFPreferencesSetValue(field.key as CFString, false as CFPropertyList, domain as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        XCTAssertTrue(CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
        try store.apply([field], selections: [field.identity: 0])
        XCTAssertEqual(store.originalChoice(for: field), 1)
        try store.restore([field])
        XCTAssertEqual(store.value(for: field) as? Bool, false)

        try store.apply([field], selections: [field.identity: 0])
        try store.apply([field], selections: [field.identity: 1])
        XCTAssertEqual(store.value(for: field) as? Bool, false)
        XCTAssertFalse(store.hasBackup(for: [field]))
    }

    func testUnreadableBackupBlocksWritesAndRemainsIntact() throws {
        let domain = "com.macpowertoys.tweak-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let damaged = Data("unreadable backup".utf8)
        let field = TweakPreferenceField.flag("Test", domain, "Test")
        let damagedRecord = try PropertyListSerialization.data(
            fromPropertyList: [field.identity: ["original": damaged]], format: .binary, options: 0
        )
        for backup in [damaged, damagedRecord] {
            defaults.set(backup, forKey: "macTweaks.preferenceBackups.v1")
            let store = TweakPreferenceStore(defaults: defaults)
            XCTAssertThrowsError(try store.apply([field], selections: [field.identity: 0]))
            XCTAssertThrowsError(try store.restore([field], includingUntracked: true))
            XCTAssertNil(store.value(for: field))
            XCTAssertEqual(defaults.data(forKey: "macTweaks.preferenceBackups.v1"), backup)
        }
    }
}

private final class ManagedTweakTestDefaults: UserDefaults, @unchecked Sendable {
    var forcedKeys: Set<String> = []

    override func objectIsForced(forKey defaultName: String, inDomain domainName: String) -> Bool {
        forcedKeys.contains(defaultName)
    }
}
