import XCTest
@testable import powertoys

final class MicLockResolverTests: XCTestCase {
    @MainActor
    func testSavedOrderAndSafeFallback() {
        let builtIn = MicInputDevice(id: "internal", name: "Mac microphone", audioID: 1, isWireless: false, isBuiltIn: true)
        let usb = MicInputDevice(id: "usb", name: "USB microphone", audioID: 2, isWireless: false, isBuiltIn: false)
        let headset = MicInputDevice(id: "headset", name: "Headset microphone", audioID: 3, isWireless: true, isBuiltIn: false)

        XCTAssertEqual(MicLockService.resolvedInput(savedUIDs: ["missing", "usb"], devices: [headset, builtIn, usb]), usb)
        XCTAssertEqual(MicLockService.resolvedInput(savedUIDs: ["missing"], devices: [headset, builtIn]), builtIn)
        XCTAssertEqual(MicLockService.resolvedInput(savedUIDs: [], devices: [headset, usb]), usb)
        XCTAssertNil(MicLockService.resolvedInput(savedUIDs: [], devices: [headset]))
    }

    func testReenforceGuardSkipsOnlyARecentWriteOfTheSameTarget() {
        let written = Date(timeIntervalSinceReferenceDate: 1_000)
        let lastWrite = (uid: "usb", date: written)

        XCTAssertTrue(MicLockService.isRecentWrite(of: "usb", lastWrite: lastWrite, now: written.addingTimeInterval(1.9)))
        XCTAssertFalse(MicLockService.isRecentWrite(of: "usb", lastWrite: lastWrite, now: written.addingTimeInterval(2)))
        XCTAssertFalse(MicLockService.isRecentWrite(of: "internal", lastWrite: lastWrite, now: written.addingTimeInterval(0.1)))
        XCTAssertFalse(MicLockService.isRecentWrite(of: "usb", lastWrite: nil, now: written))
    }
}
