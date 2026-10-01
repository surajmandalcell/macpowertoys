import AppKit
import Observation
import XCTest
@testable import powertoys

@MainActor
final class AppCommandTests: XCTestCase {
    func testSystemFormattingNotificationsInvalidateOnce() {
        let lifetime = AppInitializer.shared
        let revision = lifetime.formattingRevision
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        XCTAssertEqual(lifetime.formattingRevision, revision &+ 1)
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(lifetime.formattingRevision, revision &+ 2)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: nil)
        XCTAssertEqual(lifetime.formattingRevision, revision &+ 2)
    }
}
