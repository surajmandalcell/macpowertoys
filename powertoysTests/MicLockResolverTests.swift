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
}
