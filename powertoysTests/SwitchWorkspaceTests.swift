import AIManagerCore
import XCTest
@testable import powertoys

@MainActor
final class SwitchWorkspaceTests: XCTestCase {
    func testWorkspaceLoadsIsolatedCoreStoreWithoutStandaloneApp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpt-switch-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = ManagerPaths.environment(["AI_MANAGER_ROOT": root.path])
        let model = SwitchWorkspaceModel(paths: paths)
        await model.load()

        XCTAssertNotNil(model.snapshot)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(
            model.snapshot?.status.sharedRoot,
            root.appending(path: "default-home", directoryHint: .isDirectory)
        )
        XCTAssertEqual(ToolRegistry.tool(for: "switch")?.logoAsset, "SwitchLogo")
        XCTAssertEqual(
            UtilityLayout.minimumContentSize(for: "switch"),
            NSSize(width: 880, height: 600)
        )
    }
}
