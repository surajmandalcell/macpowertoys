import XCTest
@testable import powertoys

@MainActor
final class MainCatalogTests: XCTestCase {
    func testMainNavigationKeepsModifiedStateAndToolPagesStable() throws {
        let home = try sourceFile("powertoys/Views/HomeView.swift")
        let selectionStart = try XCTUnwrap(home.range(of: ".onChange(of: selectedTool)"))
        let selectionEnd = try XCTUnwrap(home.range(of: ".onReceive(NotificationCenter.default.publisher(for: .marketplaceReceiptsChanged)"))
        let defaultsStart = try XCTUnwrap(home.range(of: "private func observePreferences()"))
        XCTAssertFalse(home[selectionStart.lowerBound..<selectionEnd.lowerBound].contains("modifiedRevision += 1"))
        XCTAssertTrue(home[defaultsStart.lowerBound...].contains("modifiedRevision += 1"))
        XCTAssertTrue(home.contains("ToolSettingsPreferenceObserver(keys: Set(SettingsRegistry.entries.map(\\.key)))"))
        XCTAssertFalse(home.contains("publisher(for: UserDefaults.didChangeNotification)"))
        XCTAssertFalse(home.contains(".id(toolID)"))

        let tool = try sourceFile("powertoys/Views/ToolAboutView.swift")
        XCTAssertFalse(tool.contains(".id(tool.id)"))
        XCTAssertTrue(tool.contains("MainToolTab(rawValue: storedTab) ?? .settings"))
        XCTAssertTrue(tool.contains("if startsWithGuide { storedTab = MainToolTab.guide.rawValue }"))

        let sidebar = try sourceFile("powertoys/Views/ToolSidebarView.swift")
        XCTAssertTrue(sidebar.contains("@State private var hasChanges = false"))
        XCTAssertFalse(sidebar.contains("private var hasChanges: Bool"))
        XCTAssertTrue(sidebar.contains("Task.detached(priority: .utility) { SMAppService.mainApp.status }"))
        XCTAssertFalse(sidebar.contains("SettingsRegistry.hasChanges()"))
    }

    func testLauncherPreferencesIgnoreWindowStateButKeepActualSettingChanges() throws {
        let suite = "MainCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var changes = 0
        let observer = ToolSettingsPreferenceObserver(keys: Set(SettingsRegistry.entries.map(\.key)), defaults: defaults) {
            changes += 1
        }
        defer { observer.stop() }
        for key in ["systemMonitor.windowPage", "windowState.main", "systemMonitor.trayPage"] {
            defaults.set("cpu", forKey: key)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        }
        XCTAssertEqual(changes, 0)
        defaults.set(false, forKey: "app.showTray")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        XCTAssertEqual(changes, 1)
    }

    func testMainCatalogPreparesRowsOutsideBodyEvaluation() throws {
        let catalog = try sourceFile("powertoys/Views/AllToolsGridView.swift")
        let catalogBody = try XCTUnwrap(catalog.range(of: "var body: some View"))
        let catalogHelpers = try XCTUnwrap(catalog.range(of: "private var tabTools"))
        let body = catalog[catalogBody.lowerBound..<catalogHelpers.lowerBound]
        XCTAssertFalse(body.contains(".filter"))
        XCTAssertFalse(body.contains("MainCatalog.sorted"))
        XCTAssertTrue(catalog.contains("@State private var visibleTools"))
        XCTAssertTrue(catalog.contains("private func refreshCatalog()"))

        let sidebar = try sourceFile("powertoys/Views/ToolSidebarView.swift")
        let sidebarBody = try XCTUnwrap(sidebar.range(of: "var body: some View"))
        let sidebarRefresh = try XCTUnwrap(sidebar.range(of: "private func refreshVisibleTools()"))
        XCTAssertFalse(sidebar[sidebarBody.lowerBound..<sidebarRefresh.lowerBound].contains(".filter"))

        let home = try sourceFile("powertoys/Views/HomeView.swift")
        XCTAssertFalse(home.contains("ForEach(Array(ToolRegistry.allTools"))
        XCTAssertTrue(home.contains("ForEach(shortcutTools.indices"))

        let marketplace = try sourceFile("powertoys/Views/Marketplace/MarketplaceSettingsView.swift")
        XCTAssertTrue(marketplace.contains("@State private var installed: [MarketplaceEntry]"))
        XCTAssertFalse(marketplace.contains("private var installed: [MarketplaceEntry] { manager.entries.filter"))

        let modified = try sourceFile("powertoys/Views/Main/MainModifiedView.swift")
        let modifiedBody = try XCTUnwrap(modified.range(of: "var body: some View"))
        let rowBuilder = try XCTUnwrap(modified.range(of: "static func groupRows"))
        let modifiedRender = modified[modifiedBody.lowerBound..<rowBuilder.lowerBound]
        XCTAssertFalse(modifiedRender.contains(".map"))
        XCTAssertFalse(modifiedRender.contains(".filter"))
        XCTAssertTrue(modified.contains("@State private var groupedDifferences"))
    }

    func testModifiedPairsOnlyAdjacentGroupsWithEqualRowCounts() {
        XCTAssertTrue(MainModifiedView.groupRows([]).isEmpty)
        XCTAssertEqual(MainModifiedView.groupRows([
            ("app", 1), ("rclone", 3), ("ruler", 5), ("awake", 1), ("logs", 2), ("nettoys", 1)
        ]), [["app"], ["rclone"], ["ruler"], ["awake"], ["logs"], ["nettoys"]])
        XCTAssertEqual(MainModifiedView.groupRows([
            ("app", 1), ("ruler", 5), ("awake", 1)
        ]), [["app"], ["ruler"], ["awake"]])
        XCTAssertEqual(MainModifiedView.groupRows([
            ("app", 1), ("rclone", 1), ("ruler", 4), ("awake", 4), ("logs", 2), ("nettoys", 2)
        ]), [["app", "rclone"], ["ruler"], ["awake"], ["logs", "nettoys"]])
    }

    func testSearchMatchesEveryFieldAndRequiresEveryTerm() {
        let tool = CatalogTool(id: "notes", name: "Résumé Notes", description: "Copy useful passages",
                               category: .text, searchKeywords: ["clipboard"])
        for query in ["resume", "Text", "PASSAGES", "clipboard", " resume  clipboard\n"] {
            XCTAssertTrue(MainCatalog.matches(tool, query: query), query)
        }
        XCTAssertTrue(MainCatalog.matches(tool, query: " \n"))
        XCTAssertFalse(MainCatalog.matches(tool, query: "notes storage"))
    }

    func testFavoritesPersistStableIDsAndRecoverFromInvalidStorage() {
        let ids: Set<String> = ["rclone", "color-picker", "marketplace.example"]
        XCTAssertEqual(MainCatalog.favorites(from: MainCatalog.storing(favorites: ids)), ids)
        XCTAssertEqual(MainCatalog.storing(favorites: ids), "[\"color-picker\",\"marketplace.example\",\"rclone\"]")
        XCTAssertEqual(MainCatalog.favorites(from: "[\"logs\",\"logs\"]"), ["logs"])
        XCTAssertTrue(MainCatalog.favorites(from: "not json").isEmpty)
    }

    func testSortPreservesRegistryOrderAndGroupsCategories() {
        let tools: [any Tool] = [
            CatalogTool(id: "notes", name: "Notes", category: .text),
            CatalogTool(id: "logs", name: "Activity", category: .system),
            CatalogTool(id: "files", name: "Files", category: .files)
        ]
        XCTAssertEqual(MainCatalog.sorted(tools, by: .defaultOrder).map(\.id), ["notes", "logs", "files"])
        XCTAssertEqual(MainCatalog.sorted(tools, by: .name).map(\.id), ["logs", "files", "notes"])
        XCTAssertEqual(MainCatalog.sorted(tools, by: .category).map(\.id), ["files", "logs", "notes"])
    }

    func testRoutesCoverCatalogSettingsAndEveryRegisteredTool() {
        let ids = ToolRegistry.builtInTools.map(\.id) + ["marketplace.example"]
        let pages: [(String, MainPageRoute)] = [
            ("all-tools", .catalog(.all)), ("favorites", .catalog(.favorites)),
            ("settings", .settings(.general)), ("settings-marketplace", .settings(.marketplace)),
            ("settings-about", .settings(.about)), ("modified", .modified)
        ]
        for (page, route) in pages { XCTAssertEqual(MainPageRoute.resolve(page, toolIDs: ids), route) }
        for id in ids {
            XCTAssertEqual(MainPageRoute.resolve("tool/" + id, toolIDs: ids), .tool(id))
            XCTAssertEqual(MainPageRoute.resolve(id, toolIDs: ids), .tool(id))
            XCTAssertEqual(MainPageRoute.resolve("manual/" + id, toolIDs: ids), .manual(id))
        }
        XCTAssertNil(MainPageRoute.resolve("tool/removed", toolIDs: ids))
        XCTAssertNil(MainPageRoute.resolve("manual/removed", toolIDs: ids))
        XCTAssertNil(MainPageRoute.resolve("tool/logs/history", toolIDs: ids))
    }

    func testSettingsRoutesRestoreValidTabsAndExplicitDestinationsWin() {
        for tab in MainSettingsTab.allCases {
            XCTAssertEqual(MainPageRoute.resolve("settings", toolIDs: [], savedSettingsTab: tab.rawValue), .settings(tab))
        }
        XCTAssertEqual(MainPageRoute.resolve("settings", toolIDs: [], savedSettingsTab: "removed"), .settings(.general))
        XCTAssertEqual(MainPageRoute.resolve("settings-marketplace", toolIDs: [], savedSettingsTab: "about"), .settings(.marketplace))
        XCTAssertEqual(MainPageRoute.resolve("settings-about", toolIDs: [], savedSettingsTab: "marketplace"), .settings(.about))
    }
}

private func sourceFile(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

private struct CatalogTool: Tool {
    let id: String
    let name: String
    var description = ""
    let category: ToolCategory
    var searchKeywords: [String] = []
    let icon = "doc.text"
    let logoAsset = "LogsLogo"
    let manual: [ToolManualSection] = []
}
