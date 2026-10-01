import XCTest
@testable import powertoys

final class HostUpdateCheckerTests: XCTestCase {
    func testReleaseComparisonUsesNumericVersionsAndRejectsUnsafeMetadata() throws {
        let releaseURL = "https://github.com/surajmandalcell/macpowertoys/releases/tag/v1.8.10"
        func release(_ version: String, url: String = releaseURL, prerelease: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["tag_name": version, "html_url": url,
                                                       "draft": false, "prerelease": prerelease])
        }
        XCTAssertEqual(try HostUpdateChecker.result(for: release("v1.8.10"), installedVersion: "1.8.9"),
                       .available(version: "1.8.10", url: URL(string: releaseURL)!))
        for version in ["1.8.1", "1.8.1.0", "1.7", "0"] {
            XCTAssertEqual(try HostUpdateChecker.result(for: release(version), installedVersion: "1.8.1"), .current)
        }
        for version in ["v1.9-beta", "latest", "", "1..2", "999999999999999999999"] {
            XCTAssertThrowsError(try HostUpdateChecker.result(for: release(version), installedVersion: "1.8.1"))
        }
        for url in ["http://github.com/surajmandalcell/macpowertoys/releases/tag/v2", "https://example.com/release",
                    "https://github.com/other/repo/releases/tag/v2", "https://user@github.com/surajmandalcell/macpowertoys/releases/tag/v2"] {
            XCTAssertThrowsError(try HostUpdateChecker.result(for: release("2", url: url), installedVersion: "1.8.1"))
        }
        XCTAssertThrowsError(try HostUpdateChecker.result(for: release("2", prerelease: true), installedVersion: "1.8.1"))
        XCTAssertThrowsError(try HostUpdateChecker.result(for: release("2"), installedVersion: "Unavailable"))
        XCTAssertThrowsError(try HostUpdateChecker.result(for: Data("{}".utf8), installedVersion: "1.8.1"))
    }
}
