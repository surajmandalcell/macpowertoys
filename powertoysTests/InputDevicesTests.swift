import SwiftUI
import XCTest
@testable import powertoys

@MainActor
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

    func testShiftWheelScrollsSidewaysAndClearsWhenDisabled() throws {
        var settings = InputDevicesSettings()
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: -30, horizontal: 0, isContinuous: false, shiftHeld: true, settings: settings),
            InputScrollResult(vertical: 0, horizontal: -30, shouldSmooth: true, shiftConverted: true)
        )
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: -30, horizontal: 0, isContinuous: false, shiftHeld: false, settings: settings),
            InputScrollResult(vertical: -30, horizontal: 0, shouldSmooth: true)
        )
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: -30, horizontal: 4, isContinuous: false, shiftHeld: true, settings: settings),
            InputScrollResult(vertical: -30, horizontal: 4, shouldSmooth: true),
            "a real sideways delta is never rewritten"
        )
        settings.mouse.reverseHorizontal = true
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: -30, horizontal: 0, isContinuous: false, shiftHeld: true, settings: settings)?.horizontal,
            30
        )
        settings.mouse.shiftScrollsHorizontally = false
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: -30, horizontal: 0, isContinuous: false, shiftHeld: true, settings: settings),
            InputScrollResult(vertical: -30, horizontal: 0, shouldSmooth: true)
        )
        settings.mouse.shiftScrollsHorizontally = true
        settings.mouse.horizontalEnabled = false
        XCTAssertEqual(
            InputScrollPolicy.transform(vertical: -30, horizontal: 0, isContinuous: false, shiftHeld: true, settings: settings),
            InputScrollResult(vertical: -30, horizontal: 0, shouldSmooth: true)
        )

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(InputDevicesSettings().encoded)) as? [String: Any])
        var mouse = try XCTUnwrap(legacy["mouse"] as? [String: Any])
        mouse.removeValue(forKey: "shiftScrollsHorizontally")
        mouse["speed"] = 2.5
        legacy["mouse"] = mouse
        let restored = InputDevicesSettings.decoded(from: try JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(restored.mouse.shiftScrollsHorizontally, "a saved profile without the key keeps shift scrolling on")
        XCTAssertEqual(restored.mouse.speed, 2.5)
    }

    func testDeviceIdentityFormatsFirmwareVendorAndConnection() {
        XCTAssertEqual(InputDeviceDescriptor.firmwareVersion(0x5502), "55.02")
        XCTAssertEqual(InputDeviceDescriptor.firmwareVersion(0x0110), "1.10")
        let receiver = descriptor(name: "USB Receiver", kind: .mouse, manufacturer: nil)
        XCTAssertEqual(receiver.vendorName, "Logitech")
        XCTAssertEqual(receiver.connectionSummary, "USB")
        var magic = descriptor(name: "Magic Mouse", kind: .mouse, manufacturer: "Apple")
        magic.batteryPercent = 84
        XCTAssertEqual(magic.connectionSummary, "USB · 84%")
        let rows = InputDeviceCard(device: receiver, profile: InputScrollProfile(), state: .active).rows.map(\.label)
        XCTAssertEqual(rows, ["Vendor", "Device ID", "Connection", "Scroll speed"])
    }

    func testKeyboardDetailsFormatSavedGlobalSettings() {
        XCTAssertEqual(InputKeyboardDetails(keyRepeat: 2, standardFunctionKeys: true).keyRepeat, "Fast")
        XCTAssertEqual(InputKeyboardDetails(keyRepeat: 4, standardFunctionKeys: false).keyRepeat, "Medium")
        XCTAssertEqual(InputKeyboardDetails(keyRepeat: 7, standardFunctionKeys: nil).keyRepeat, "Slow")
        XCTAssertEqual(InputKeyboardDetails(keyRepeat: nil, standardFunctionKeys: true).keyRepeat, "System default")
        XCTAssertEqual(InputKeyboardDetails(keyRepeat: nil, standardFunctionKeys: true).functionKeys, "Standard F keys")
        XCTAssertEqual(InputKeyboardDetails(keyRepeat: nil, standardFunctionKeys: false).functionKeys, "Media keys")
        XCTAssertEqual(InputKeyboardDetails(keyRepeat: nil, standardFunctionKeys: nil).functionKeys, "System default")
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
            InputControlState.state(settings: settings, permissionGranted: true, interceptionActive: true, kind: .mouse),
            .disabled
        )

        settings.scrollControlEnabled = true
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: false, interceptionActive: false, kind: .mouse),
            .permissionNeeded
        )
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: true, interceptionActive: true, kind: .trackpad),
            .active
        )

        settings.mouse.enabled = false
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: true, interceptionActive: true, kind: .mouse),
            .passthrough
        )
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: true, interceptionActive: true, kind: .trackpad),
            .active
        )
        XCTAssertEqual(
            InputControlState.state(settings: settings, permissionGranted: true, interceptionActive: false, kind: .trackpad),
            .unavailable
        )
    }

    func testForcedProfileMatchesBothTransformationAndDeviceState() {
        var settings = InputDevicesSettings()
        settings.scrollControlEnabled = true
        settings.mouse.enabled = false
        settings.trackpad.speed = 2
        settings.eventOverride = .trackpad

        XCTAssertEqual(InputScrollPolicy.profile(for: .mouse, settings: settings), settings.trackpad)
        XCTAssertEqual(InputScrollPolicy.transform(vertical: 3, horizontal: 2, isContinuous: false, settings: settings),
                       InputScrollResult(vertical: 6, horizontal: 4, shouldSmooth: false))
        XCTAssertEqual(InputControlState.state(settings: settings, permissionGranted: true,
                                              interceptionActive: true, kind: .mouse), .active)

        settings.eventOverride = .mouse
        XCTAssertEqual(InputScrollPolicy.profile(for: .trackpad, settings: settings), settings.mouse)
        XCTAssertNil(InputScrollPolicy.transform(vertical: 3, horizontal: 2, isContinuous: true, settings: settings))
        XCTAssertEqual(InputControlState.state(settings: settings, permissionGranted: true,
                                              interceptionActive: true, kind: .trackpad), .passthrough)
    }

    func testInvalidSavedSpeedPassesThroughWithoutOverflow() throws {
        for speed in [-1.0, 0, 0.34, 3.01, 1e308] {
            var settings = InputDevicesSettings()
            settings.mouse.speed = speed
            let restored = InputDevicesSettings.decoded(from: try XCTUnwrap(settings.encoded))
            XCTAssertNil(InputScrollPolicy.transform(vertical: 30, horizontal: 0, isContinuous: false, settings: restored))
        }
        for speed in [0.35, 1, 3] {
            var settings = InputDevicesSettings()
            settings.mouse.speed = speed
            XCTAssertEqual(InputScrollPolicy.transform(vertical: 30, horizontal: 0, isContinuous: false, settings: settings)?.vertical,
                           30 * speed)
        }
    }

    func testDeviceCardsOmitUnavailableValues() {
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

        XCTAssertTrue(InputDeviceCard(device: richMouse, profile: InputScrollProfile(), state: .active).rows.contains { $0.label == "Polling" })
        XCTAssertFalse(InputDeviceCard(device: sparseTrackpad, profile: InputScrollProfile(), state: .disabled).rows.contains { $0.label == "Battery" })
        XCTAssertFalse(InputDeviceCard(device: sparseTrackpad, profile: InputScrollProfile(), state: .disabled).rows.contains { $0.label == "Firmware" })
        let rows = InputDeviceCard(device: richMouse, profile: InputScrollProfile(), state: .active).rows
        XCTAssertEqual(rows.first { $0.label == "Location" }?.value, "1D100000")
        XCTAssertEqual(rows.first { $0.label == "Input report" }?.value, "32 bytes")

        let noIDs = InputDeviceDescriptor(id: "internal", name: "Internal", kind: .trackpad, transport: "FIFO", isBuiltIn: true,
                                      manufacturer: nil, vendorID: 0, productID: 0, versionNumber: nil, locationID: 0,
                                      serialNumber: nil, pointerResolutionDPI: nil, pollingRateHz: nil, buttonCount: nil,
                                      maxInputReportSize: nil, systemTrackingSpeed: nil)
        XCTAssertFalse(InputDeviceCard(device: noIDs, profile: InputScrollProfile(), state: .disabled).rows.contains { $0.label == "Device ID" })
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

    func testCollapsedProfileKeepsAFullWidthHeaderAndExpandsToAllRows() {
        let collapsed = InputScrollProfileCard(title: "Mouse", icon: "computermouse", deviceCount: 1,
                                               profile: .constant(InputScrollProfile()), isExpanded: .constant(false))
        let expanded = InputScrollProfileCard(title: "Mouse", icon: "computermouse", deviceCount: 1,
                                              profile: .constant(InputScrollProfile()), isExpanded: .constant(true))
        XCTAssertEqual(cardHeight(collapsed), 40, accuracy: 1)
        XCTAssertEqual(cardHeight(expanded) - cardHeight(collapsed), 7 * 44, accuracy: 1)
        let devices = InputDisclosureHeader(title: "Devices", detail: "2 connected",
                                            isExpanded: .constant(false), refreshAction: {})
        XCTAssertEqual(cardHeight(devices), 40, accuracy: 1)
    }

    func testProfileDisclosureHeaderKeepsDirectionAndSpeedWhenCollapsed() {
        var profile = InputScrollProfile(reverseVertical: true, speed: 3)
        var expanded = false
        let card = InputScrollProfileCard(title: "Mouse", icon: "computermouse", deviceCount: 2,
                                         profile: Binding(get: { profile }, set: { profile = $0 }),
                                         isExpanded: Binding(get: { expanded }, set: { expanded = $0 }))
        XCTAssertEqual(card.headerDetail, "Reversed \(3.0.formatted(.number.precision(.fractionLength(2))))×")
        profile.reverseVertical = false
        profile.speed = 0.35
        XCTAssertEqual(card.headerDetail, "System \(0.35.formatted(.number.precision(.fractionLength(2))))×")
        expanded = true
        XCTAssertEqual(card.headerDetail, "2 connected")
    }

    func testProfileRowsFollowTheirGates() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("powertoys/Views/InputDevices/InputDevicesCards.swift"),
                                encoding: .utf8)
        XCTAssertEqual(source.components(separatedBy: ".disabled(!profile.horizontalEnabled)").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy: ".disabled(!profile.enabled)").count - 1, 1)
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
