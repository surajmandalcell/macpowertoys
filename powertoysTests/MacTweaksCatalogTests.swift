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

        CFPreferencesSetValue(field.key as CFString, false as CFPropertyList, domain as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        XCTAssertTrue(CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
        try store.apply([field], selections: [field.identity: 0])
        try store.restore([field])
        XCTAssertEqual(store.value(for: field) as? Bool, false)
    }
}
