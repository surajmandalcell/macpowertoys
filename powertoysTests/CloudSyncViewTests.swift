import XCTest
@testable import powertoys

@MainActor
final class CloudSyncViewTests: XCTestCase {
    func testBandwidthInputAcceptsRcloneRatesAndRejectsFreeText() {
        XCTAssertNil(RcloneBandwidthInput.error(for: ""))
        XCTAssertNil(RcloneBandwidthInput.error(for: "off"))
        XCTAssertNil(RcloneBandwidthInput.error(for: "10M"))
        XCTAssertNil(RcloneBandwidthInput.error(for: "1.5GiB"))
        XCTAssertNotNil(RcloneBandwidthInput.error(for: "fast"))
    }

    func testRemoteFolderNameAcceptsOneSafePathComponent() {
        XCTAssertNil(RemoteFolderName.error(for: "Sprint Assets"))
        XCTAssertNil(RemoteFolderName.error(for: "設計"))
        XCTAssertNotNil(RemoteFolderName.error(for: ""))
        XCTAssertNotNil(RemoteFolderName.error(for: ".."))
        XCTAssertNotNil(RemoteFolderName.error(for: "nested/folder"))
        XCTAssertNotNil(RemoteFolderName.error(for: "nested\\folder"))
    }

    func testBackgroundProjectionFormattingMatchesCloudSyncRows() {
        for bytes in [Int64(0), 999, 1_000, 1_500_000, 2_000_000_000] {
            XCTAssertEqual(RcloneProjectionFormat.bytes(bytes), RcloneFormat.bytes(bytes))
        }
        for duration in [TimeInterval(0), 1, 61, 3_661, 90_000] {
            XCTAssertEqual(RcloneProjectionFormat.duration(duration), RcloneFormat.duration(duration))
        }
    }
}
