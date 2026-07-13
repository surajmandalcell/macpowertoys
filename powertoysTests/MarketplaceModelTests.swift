import XCTest
@testable import powertoys

final class MarketplaceModelTests: XCTestCase {
    private static let builtInToolIDs: Set<String> = [
        "cc-history", "rclone", "logs", "ruler", "awake", "color-picker", "text-extractor"
    ]

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("spec/marketplace/\(name)")
        return try Data(contentsOf: url)
    }

    private func decode(_ name: String) throws -> MarketplaceCatalog {
        try MarketplaceCatalog.decode(fixture(name), reservedToolIDs: Self.builtInToolIDs)
    }

    private func assertThrows(_ name: String, _ verify: (MarketplaceCatalogError) -> Void) throws {
        XCTAssertThrowsError(try decode(name)) { error in
            guard let error = error as? MarketplaceCatalogError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            verify(error)
        }
    }

    func testReservedIDsMatchToolRegistry() {
        XCTAssertEqual(Set(ToolRegistry.allTools.map(\.id)), Self.builtInToolIDs)
    }

    func testDecodesValidCatalog() throws {
        let catalog = try decode("valid-catalog.json")
        XCTAssertEqual(catalog.formatVersion, 1)
        XCTAssertEqual(catalog.source.id, "acme-tools")
        XCTAssertEqual(catalog.tools.count, 2)

        let snapper = try XCTUnwrap(catalog.tools.first)
        XCTAssertEqual(snapper.id, "window-snapper")
        XCTAssertEqual(snapper.category, .system)
        XCTAssertEqual(snapper.build, 34)
        XCTAssertEqual(snapper.artifact.teamID, "ABCDE12345")
        XCTAssertEqual(snapper.artifact.architectures, [.arm64, .x86_64])
        XCTAssertEqual(snapper.settingsSync?.keys, ["snapper.gridColumns", "snapper.showOverlay"])
        XCTAssertEqual(snapper.manual.first?.title, "Snapping")

        let clipStack = catalog.tools[1]
        XCTAssertNil(clipStack.settingsSync)
        XCTAssertTrue(clipStack.manual.isEmpty)
    }

    func testRejectsUnsupportedFormatVersion() throws {
        try assertThrows("invalid-format-version.json") {
            XCTAssertEqual($0, .unsupportedFormatVersion(2))
        }
    }

    func testRejectsNonHTTPSArtifactURL() throws {
        try assertThrows("invalid-artifact-url.json") {
            XCTAssertEqual($0, .invalidValue("tools[window-snapper].artifact.url"))
        }
    }

    func testRejectsMalformedSHA256() throws {
        try assertThrows("invalid-sha256.json") {
            XCTAssertEqual($0, .invalidValue("tools[window-snapper].artifact.sha256"))
        }
    }

    func testRejectsDuplicateToolIDs() throws {
        try assertThrows("invalid-duplicate-tool-id.json") {
            XCTAssertEqual($0, .duplicateToolID("window-snapper"))
        }
    }

    func testRejectsMissingArtifactField() throws {
        try assertThrows("invalid-missing-artifact-field.json") {
            guard case .malformedJSON = $0 else {
                return XCTFail("Expected malformedJSON, got \($0)")
            }
        }
    }

    func testRejectsReservedToolID() throws {
        try assertThrows("host-invalid-reserved-tool-id.json") {
            XCTAssertEqual($0, .reservedToolID("rclone"))
        }
    }

    func testAppVersionOrdering() throws {
        let v160 = try XCTUnwrap(AppVersion("1.6.0"))
        let v16 = try XCTUnwrap(AppVersion("1.6"))
        let v159 = try XCTUnwrap(AppVersion("1.5.9"))
        let v2 = try XCTUnwrap(AppVersion("2"))
        XCTAssertEqual(v160, v16)
        XCTAssertLessThan(v159, v160)
        XCTAssertGreaterThan(v2, v160)
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1.6.0-beta"))
        XCTAssertNil(AppVersion("1..0"))
        XCTAssertNil(AppVersion("1.2.3.4.5"))
    }

    func testCompatibilityGate() throws {
        let manifest = try decode("valid-catalog.json").tools[0]
        let compatible = HostEnvironment(
            hostVersion: AppVersion("1.6.0")!,
            hostBuild: 10,
            macOSVersion: AppVersion("26.2")!
        )
        XCTAssertTrue(manifest.isCompatible(with: compatible))

        let oldHostVersion = HostEnvironment(
            hostVersion: AppVersion("1.5.9")!,
            hostBuild: 10,
            macOSVersion: AppVersion("26.2")!
        )
        XCTAssertFalse(manifest.isCompatible(with: oldHostVersion))

        let oldHostBuild = HostEnvironment(
            hostVersion: AppVersion("1.6.0")!,
            hostBuild: 9,
            macOSVersion: AppVersion("26.2")!
        )
        XCTAssertFalse(manifest.isCompatible(with: oldHostBuild))

        let oldMacOS = HostEnvironment(
            hostVersion: AppVersion("1.6.0")!,
            hostBuild: 10,
            macOSVersion: AppVersion("25.0")!
        )
        XCTAssertFalse(manifest.isCompatible(with: oldMacOS))
    }

    func testReceiptRoundtripAndUpdateDetection() throws {
        let catalog = try decode("valid-catalog.json")
        let manifest = catalog.tools[0]
        let sourceURL = URL(string: "https://raw.githubusercontent.com/acme/tools/main/catalog.json")!
        let installedAt = Date(timeIntervalSince1970: 1_780_000_000)

        let receipt = MarketplaceReceipt(
            manifest: manifest,
            sourceID: catalog.source.id,
            sourceURL: sourceURL,
            installedAt: installedAt
        )
        XCTAssertEqual(receipt.toolID, "window-snapper")
        XCTAssertEqual(receipt.bundleID, "com.acme.window-snapper")
        XCTAssertEqual(receipt.sourceID, "acme-tools")
        XCTAssertEqual(receipt.settingsSync, manifest.settingsSync)

        let decoded = try MarketplaceReceipt.decode(receipt.encoded())
        XCTAssertEqual(decoded, receipt)

        XCTAssertFalse(receipt.updateAvailable(in: manifest))
        XCTAssertTrue(receipt.updateAvailable(in: manifestBumping(manifest, build: 35)))
        XCTAssertFalse(receipt.updateAvailable(in: catalog.tools[1]))
    }

    private func manifestBumping(_ manifest: MarketplaceToolManifest, build: Int) -> MarketplaceToolManifest {
        MarketplaceToolManifest(
            id: manifest.id,
            name: manifest.name,
            summary: manifest.summary,
            category: manifest.category,
            manual: manifest.manual,
            iconURL: manifest.iconURL,
            version: manifest.version,
            build: build,
            minHostVersion: manifest.minHostVersion,
            minHostBuild: manifest.minHostBuild,
            minMacOSVersion: manifest.minMacOSVersion,
            artifact: manifest.artifact,
            settingsSync: manifest.settingsSync
        )
    }
}
