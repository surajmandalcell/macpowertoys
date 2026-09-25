import AIManagerCore
import AppKit
import SwiftUI
import XCTest
@testable import powertoys

@MainActor
final class SwitchWorkspaceTests: XCTestCase {
    func testAppletRendersSyntheticAccountsAndRecoveryInLightAndDark() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let model = SwitchWorkspaceModel(paths: ManagerPaths.environment(["AI_MANAGER_ROOT": root.path]))
        await model.load()
        try await importAccount(named: "first", into: model, root: root)
        try await importAccount(named: "second", into: model, root: root)
        XCTAssertEqual(model.accounts.count, 2)
        let first = try XCTUnwrap(model.accounts.first { $0.identity.email == "first@example.test" })
        let second = try XCTUnwrap(model.accounts.first { $0.identity.email == "second@example.test" })
        await model.makeDefault(first.id)
        model.selectedAccountID = second.id

        for size in [NSSize(width: 1_024, height: 720), NSSize(width: 880, height: 600)] {
            for scheme in [ColorScheme.light, .dark] {
                for page in SwitchPage.allCases {
                    let host = NSHostingView(rootView: SwitchWindowView(model: model, initialPage: page)
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme))
                    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    host.frame = NSRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(200))
                    host.layoutSubtreeIfNeeded()

                    let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: representation)
                    let image = NSImage(size: size)
                    image.addRepresentation(representation)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Switch — \(page.rawValue) — \(scheme == .dark ? "Dark" : "Light") — \(Int(size.width))"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testAppletLoadsCoreStoreWithoutStandaloneApp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpt-switch-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = SwitchWorkspaceModel(paths: ManagerPaths.environment(["AI_MANAGER_ROOT": root.path]))
        await model.load()

        XCTAssertNotNil(model.snapshot)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.snapshot?.status.sharedRoot,
                       root.appending(path: "default-home", directoryHint: .isDirectory))
        XCTAssertEqual(ToolRegistry.tool(for: "switch")?.logoAsset, "SwitchLogo")
        XCTAssertEqual(UtilityLayout.minimumContentSize(for: "switch"),
                       NSSize(width: 880, height: 600))
    }

    func testAccountImportSwitchAndRemovalUseIsolatedCoreStore() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("mpt-switch-accounts-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let model = SwitchWorkspaceModel(paths: ManagerPaths.environment(["AI_MANAGER_ROOT": root.path]))
        await model.load()

        try await importAccount(named: "first", into: model, root: root)
        try await importAccount(named: "second", into: model, root: root)
        XCTAssertEqual(model.accounts.count, 2)
        let first = try XCTUnwrap(model.accounts.first { $0.identity.email == "first@example.test" })
        let second = try XCTUnwrap(model.accounts.first { $0.identity.email == "second@example.test" })

        await model.makeDefault(second.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.snapshot?.status.firstDefaultAccountID, second.id)
        await model.removeAccount(second.id, replacement: first.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.accounts.map(\.id), [first.id])
        XCTAssertEqual(model.snapshot?.status.firstDefaultAccountID, first.id)
    }

    private func importAccount(named name: String, into model: SwitchWorkspaceModel,
                               root: URL) async throws {
        let files = FileManager.default
        let source = root.appending(path: "source-\(name)")
        try files.createDirectory(at: source, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let claims = try JSONSerialization.data(withJSONObject: [
            "email": "\(name)@example.test", "chatgpt_user_id": "user-\(name)",
            "chatgpt_account_id": "account-\(name)", "workspace_id": "workspace-\(name)"
        ])
        let payload = claims.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let auth = try JSONSerialization.data(withJSONObject: ["tokens": [
            "id_token": "header.\(payload).signature",
            "access_token": "synthetic-access", "refresh_token": "synthetic-refresh",
            "account_id": "account-\(name)"
        ]])
        let authFile = source.appending(path: "auth.json")
        try auth.write(to: authFile, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
        await model.reviewImport(source: source, mode: .full)
        XCTAssertEqual(model.importPlan?.identity.email, "\(name)@example.test")
        await model.commitImport(decisions: [:])
        XCTAssertNil(model.errorMessage)
    }
}
