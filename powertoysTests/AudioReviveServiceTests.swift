import XCTest
@testable import powertoys

final class AudioReviveServiceTests: XCTestCase {
    func testStandardErrorCaptureStopsAtItsLimit() {
        let prefix = Data(repeating: 1, count: 12)
        let overflow = Data(repeating: 2, count: 12)

        let result = AudioReviveProcess.capped(prefix, appending: overflow, limit: 16)

        XCTAssertEqual(result.count, 16)
        XCTAssertEqual(result.prefix(12), prefix)
        XCTAssertEqual(result.suffix(4), overflow.prefix(4))
    }
}
