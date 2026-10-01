import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class MainCatalogRowsTests: XCTestCase {
    func testCatalogHasItsFilteredRowsBeforeAppearance() throws {
        let view = AllToolsGridView(selectedTool: .constant("all-tools"), query: "")
        let state = try XCTUnwrap(Mirror(reflecting: view).children.first { $0.label == "_visibleTools" }?.value
            as? State<[any Tool]>)
        XCTAssertEqual(state.wrappedValue.count, ToolRegistry.allTools.count)
        let noMatches = AllToolsGridView(selectedTool: .constant("all-tools"), query: "no.tool.has.this.name")
        let filtered = try XCTUnwrap(Mirror(reflecting: noMatches).children.first { $0.label == "_visibleTools" }?.value
            as? State<[any Tool]>)
        XCTAssertTrue(filtered.wrappedValue.isEmpty)
    }

    func testFirstFrameRowsAndCountsUseTheCurrentFilterAndPreferences() throws {
        let tools = ToolRegistry.builtInTools
        let first = try XCTUnwrap(tools.first)
        let favorites: Set<String> = [first.id, "removed.tool"]
        func rows(_ filter: MainCatalogFilter, query: String = "")
            -> (visible: [any Tool], total: Int, enabled: Int, favorites: Int) {
            MainCatalog.preparedRows(tools, query: query, filter: filter, sort: .name,
                                     favorites: favorites, disabled: [first.id])
        }
        let all = rows(.all)
        XCTAssertEqual(all.total, tools.count)
        XCTAssertEqual(all.enabled, tools.count - 1)
        XCTAssertEqual(all.favorites, 1)
        XCTAssertEqual(all.visible.map(\.id), MainCatalog.sorted(tools, by: .name).map(\.id))
        XCTAssertFalse(rows(.enabled).visible.contains { $0.id == first.id })
        XCTAssertEqual(rows(.favorites).visible.map(\.id), [first.id])
        XCTAssertEqual(rows(.all, query: " \n").visible.map(\.id), all.visible.map(\.id))
        XCTAssertTrue(rows(.all, query: "no.tool.has.this.name").visible.isEmpty)
    }
}
