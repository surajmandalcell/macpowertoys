import ServiceManagement
import Synchronization
import XCTest
@testable import powertoys

@MainActor
final class NetToysNeighborStatusTests: XCTestCase {
    func testRenderingUsesOneBackgroundStatusSnapshotAndRefreshCoalesces() async throws {
        let reads = Mutex(0)
        let manager = NetToysNeighborServiceManager(readStatus: {
            reads.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 0.02)
            return .enabled
        })
        XCTAssertNil(manager.status)
        manager.refresh()
        for _ in 0..<100 where manager.status == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(manager.status, .enabled)
        for _ in 0..<50 { XCTAssertTrue(manager.isEnabled) }
        XCTAssertEqual(reads.withLock { $0 }, 1)
        manager.refresh()
        for _ in 0..<100 where manager.revision < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(manager.revision, 2)
        XCTAssertEqual(reads.withLock { $0 }, 2)
    }
}
