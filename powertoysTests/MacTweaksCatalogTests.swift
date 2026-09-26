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

    func testEveryWorkingCardHasAnExample() {
        let workingIDs = TweakCatalog.items
            .filter { !TweakPreferences.fields(for: $0.id).isEmpty }
            .map(\.id) + ["mic-lock", "helper.keep-awake"]
        XCTAssertTrue(workingIDs.filter { TweakExample.forID($0) == nil }.isEmpty)
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
        try store.apply([field], selections: [field.identity: 0])
        XCTAssertEqual(store.value(for: field) as? Bool, true)
        try store.restore([field])
        XCTAssertNil(store.value(for: field))

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
        try store.restore([field])
        XCTAssertEqual(store.value(for: field) as? Bool, false)
    }
}
