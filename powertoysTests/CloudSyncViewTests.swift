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
}
