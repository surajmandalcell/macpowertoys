import SwiftUI
import XCTest
@testable import powertoys

final class InputDevicesTests: XCTestCase {
    func testScrollProfilesStayIndependent() {
        var settings = InputDevicesSettings()
        settings.mouse.reverseVertical = true
        settings.mouse.reverseHorizontal = true
        settings.mouse.speed = 2
        settings.trackpad.speed = 0.5

        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: 3, horizontal: -2, isContinuous: false, settings: settings),
            InputScrollResult(vertical: -6, horizontal: 4, shouldSmooth: true)
        )
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: 3, horizontal: -2, isContinuous: true, settings: settings),
            InputScrollResult(vertical: 1.5, horizontal: -1, shouldSmooth: false)
        )
    }

    func testMouseHorizontalScrollingPersistsAndBlocksSidewaysMovement() throws {
        var settings = InputDevicesSettings()
        settings.mouse.horizontalEnabled = false

        let restored = InputDevicesSettings.decoded(from: try XCTUnwrap(settings.encoded))

        XCTAssertFalse(restored.mouse.horizontalEnabled)
        XCTAssertTrue(restored.trackpad.horizontalEnabled)
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: 3, horizontal: -2, isContinuous: false, settings: restored),
            InputScrollResult(vertical: 3, horizontal: 0, shouldSmooth: true)
        )
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: 3, horizontal: -2, isContinuous: true, settings: restored),
            InputScrollResult(vertical: 3, horizontal: -2, shouldSmooth: false)
        )
        XCTAssertEqual(InputDevicesSettings.decoded(from: nil), InputDevicesSettings())
    }

    func testHIDTelemetryUsesReportedResolutionAndPollingRate() {
        XCTAssertEqual(
            InputDeviceDescriptor.kind(name: "Apple Internal Keyboard / Trackpad", usagePage: 1, usage: 2),
            .trackpad
        )
        XCTAssertNil(
            InputDeviceDescriptor.kind(name: "Apple Internal Keyboard / Trackpad", usagePage: 1, usage: 6)
        )
        XCTAssertEqual(InputDeviceDescriptor.kind(name: "USB Receiver", usagePage: 1, usage: 2), .mouse)

        XCTAssertEqual(InputDeviceDescriptor.fixedPointResolution(26_214_400), 400)
        XCTAssertEqual(InputDeviceDescriptor.fixedPointResolution(800), 800)
        XCTAssertNil(InputDeviceDescriptor.fixedPointResolution(0))

        XCTAssertEqual(
            InputDeviceDescriptor.pollingRate(pointerRate: 120, reportIntervalMicroseconds: 8_000),
            120
        )
        XCTAssertEqual(
            InputDeviceDescriptor.pollingRate(pointerRate: nil, reportIntervalMicroseconds: 8_000),
            125
        )
        XCTAssertNil(InputDeviceDescriptor.pollingRate(pointerRate: nil, reportIntervalMicroseconds: nil))
    }

    func testControlStateFollowsPermissionAndProfile() {
        var settings = InputDevicesSettings()
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: true, kind: .mouse),
            .disabled
        )

        settings.scrollControlEnabled = true
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: false, kind: .mouse),
            .permissionNeeded
        )
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: true, kind: .trackpad),
            .active
        )

        settings.mouse.enabled = false
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: true, kind: .mouse),
            .passthrough
        )
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: true, kind: .trackpad),
            .active
        )
    }

    @MainActor
    func testMouseAndTrackpadDeviceCardsShareOneHeight() {
        let richMouse = descriptor(
            name: "Logitech MX Master 3S Wireless Mouse",
            kind: .mouse,
            manufacturer: "Logitech",
            versionNumber: 0x0110,
            serialNumber: "A1B2C3D4E5",
            pointerResolutionDPI: 4_000,
            pollingRateHz: 1_000,
            buttonCount: 7,
            maxInputReportSize: 32,
            systemTrackingSpeed: 1.5
        )
        let sparseTrackpad = descriptor(name: "Trackpad", kind: .trackpad)

        XCTAssertEqual(
            cardHeight(InputDeviceCard(device: richMouse, profile: InputScrollProfile(), state: .active)),
            cardHeight(InputDeviceCard(device: sparseTrackpad, profile: InputScrollProfile(), state: .disabled))
        )
    }

    @MainActor
    func testMouseAndTrackpadProfileCardsShareOneHeight() {
        let mouse = InputScrollProfileCard(
            title: "Mouse",
            icon: InputDeviceDescriptor.Kind.mouse.icon,
            deviceCount: 3,
            profile: .constant(InputScrollProfile(smooth: true))
        )
        let trackpad = InputScrollProfileCard(
            title: "Trackpad",
            icon: InputDeviceDescriptor.Kind.trackpad.icon,
            deviceCount: 0,
            profile: .constant(InputScrollProfile(enabled: false, horizontalEnabled: false))
        )

        XCTAssertEqual(cardHeight(mouse), cardHeight(trackpad))
    }

    /// The four gated switches are NSControls. The slider inherits the same
    /// disabled environment but SwiftUI does not back it with an NSControl.
    @MainActor
    func testProfileRowsFollowTheirGates() {
        XCTAssertEqual(
            disabledControlCount(InputScrollProfileCard(
                title: "Mouse",
                icon: InputDeviceDescriptor.Kind.mouse.icon,
                deviceCount: 1,
                profile: .constant(InputScrollProfile())
            )),
            0
        )
        XCTAssertEqual(
            disabledControlCount(InputScrollProfileCard(
                title: "Mouse",
                icon: InputDeviceDescriptor.Kind.mouse.icon,
                deviceCount: 1,
                profile: .constant(InputScrollProfile(horizontalEnabled: false))
            )),
            1
        )
        XCTAssertEqual(
            disabledControlCount(InputScrollProfileCard(
                title: "Mouse",
                icon: InputDeviceDescriptor.Kind.mouse.icon,
                deviceCount: 1,
                profile: .constant(InputScrollProfile(enabled: false))
            )),
            4
        )
    }

    @MainActor
    private func disabledControlCount(_ view: some View, width: CGFloat = 340) -> Int {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: view.frame(width: width))
        window.contentView?.layoutSubtreeIfNeeded()
        return controls(in: window.contentView!).filter { !$0.isEnabled }.count
    }

    private func controls(in view: NSView) -> [NSControl] {
        var found = view.subviews.flatMap { controls(in: $0) }
        if let control = view as? NSControl { found.append(control) }
        return found
    }

    @MainActor
    private func cardHeight(_ view: some View, width: CGFloat = 340) -> CGFloat {
        let hostingView = NSHostingView(rootView: view.frame(width: width))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    private func descriptor(
        name: String,
        kind: InputDeviceDescriptor.Kind,
        manufacturer: String? = nil,
        versionNumber: Int? = nil,
        serialNumber: String? = nil,
        pointerResolutionDPI: Double? = nil,
        pollingRateHz: Double? = nil,
        buttonCount: Int? = nil,
        maxInputReportSize: Int? = nil,
        systemTrackingSpeed: Double? = nil
    ) -> InputDeviceDescriptor {
        InputDeviceDescriptor(
            id: name,
            name: name,
            kind: kind,
            transport: "USB",
            isBuiltIn: kind == .trackpad,
            manufacturer: manufacturer,
            vendorID: 0x046D,
            productID: 0xB034,
            versionNumber: versionNumber,
            locationID: versionNumber == nil ? 0 : 0x1D10_0000,
            serialNumber: serialNumber,
            pointerResolutionDPI: pointerResolutionDPI,
            pollingRateHz: pollingRateHz,
            buttonCount: buttonCount,
            maxInputReportSize: maxInputReportSize,
            systemTrackingSpeed: systemTrackingSpeed
        )
    }
}
