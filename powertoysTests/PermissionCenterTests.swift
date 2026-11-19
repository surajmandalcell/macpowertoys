import XCTest
@testable import powertoys

private final class GrantBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Set<PermissionKind> = []
    var granted: Set<PermissionKind> {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@MainActor
final class PermissionCenterTests: XCTestCase {
    func testPollsOnlyWhileAVisibleRowShowsAMissingPermission() async throws {
        let box = GrantBox()
        let center = PermissionCenter(read: { box.granted }, pollInterval: .milliseconds(20))
        await center.refresh()
        XCTAssertFalse(center.isPolling, "no watcher, no timer")

        let row = UUID()
        center.watch(row, kind: .accessibility)
        XCTAssertTrue(center.isPolling, "a missing permission on screen polls")

        center.watch(row, kind: nil)
        XCTAssertFalse(center.isPolling, "a hidden row stops the timer")

        center.watch(row, kind: .accessibility)
        box.granted = [.accessibility]
        for _ in 0..<100 where center.isPolling { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(center.isGranted(.accessibility), "the poll picks up a later grant")
        XCTAssertFalse(center.isPolling, "the timer stops once the permission is granted")
    }
}
