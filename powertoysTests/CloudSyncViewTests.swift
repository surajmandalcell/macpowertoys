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
}
