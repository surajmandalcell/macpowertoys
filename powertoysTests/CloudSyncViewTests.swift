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

    func testTransferPageCopyMatchesEachFilter() {
        XCTAssertEqual(
            RcloneTransferPresentation.subtitle(
                for: .all,
                activeCount: 2,
                filteredCount: 8,
                aggregateSpeed: 14_200_000
            ),
            "2 active · 14.2 MB/s"
        )
        XCTAssertEqual(
            RcloneTransferPresentation.subtitle(
                for: .completed,
                activeCount: 0,
                filteredCount: 3,
                aggregateSpeed: 0
            ),
            "3 completed"
        )
        XCTAssertEqual(
            RcloneTransferPresentation.subtitle(
                for: .failed,
                activeCount: 0,
                filteredCount: 2,
                aggregateSpeed: 0
            ),
            "2 failed"
        )
        XCTAssertTrue(RcloneTransferPresentation.showsNewTransferAction(for: .active))
        XCTAssertFalse(RcloneTransferPresentation.showsNewTransferAction(for: .completed))
        XCTAssertEqual(
            RcloneTransferPresentation.emptyCaption(for: .failed),
            "Failed and cancelled transfers stay here until you clear them."
        )
    }
}
