import XCTest
@testable import powertoys

@MainActor
final class MainCatalogTests: XCTestCase {
    func testModifiedPairsShortGroupsWithoutReorderingLongGroups() {
        XCTAssertTrue(MainModifiedView.groupRows([]).isEmpty)
        XCTAssertEqual(MainModifiedView.groupRows([
            ("app", 1), ("rclone", 3), ("ruler", 5), ("awake", 1), ("logs", 2), ("nettoys", 1)
        ]), [["app", "rclone"], ["ruler"], ["awake", "logs"], ["nettoys"]])
        XCTAssertEqual(MainModifiedView.groupRows([
            ("app", 1), ("ruler", 5), ("awake", 1)
        ]), [["app"], ["ruler"], ["awake"]])
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
        }
        XCTAssertNil(MainPageRoute.resolve("tool/removed", toolIDs: ids))
        XCTAssertNil(MainPageRoute.resolve("tool/logs/history", toolIDs: ids))
    }
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
