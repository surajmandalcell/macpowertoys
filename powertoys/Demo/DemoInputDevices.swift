//
//  DemoInputDevices.swift
//  powertoys
//

#if MPT_DEMO
import Foundation

@MainActor
enum DemoInputDevices {
    static func seed() {
        let mouse = InputDeviceDescriptor(
            id: "demo-mx-master-3s", name: "MX Master 3S", kind: .mouse, transport: "Bluetooth Low Energy",
            isBuiltIn: false, manufacturer: "Logitech", vendorID: 0x046D, productID: 0xB034, versionNumber: 0x0012,
            locationID: 0x1A2B3C, serialNumber: nil, pointerResolutionDPI: 1000, pollingRateHz: 125, buttonCount: 7,
            maxInputReportSize: 20, systemTrackingSpeed: 1.5, batteryPercent: 82
        )
        let trackpad = InputDeviceDescriptor(
            id: "demo-magic-trackpad", name: "Magic Trackpad", kind: .trackpad, transport: "Bluetooth",
            isBuiltIn: false, manufacturer: "Apple", vendorID: 0x004C, productID: 0x0324, versionNumber: 0x0110,
            locationID: 0x4D5E6F, serialNumber: nil, pointerResolutionDPI: nil, pollingRateHz: 90, buttonCount: 1,
            maxInputReportSize: 64, systemTrackingSpeed: 1.0, modelNumber: "A1535", batteryPercent: 64
        )
        InputDevicesManager.shared.demoSeed(devices: [mouse, trackpad], settings: InputDevicesSettings())
    }

    static var scene: DemoScene {
        DemoScene(
            open: { ToolActionRouter.shared.open(toolID: "input-devices", page: "scrolling", activateApp: false) },
            steps: [
                DemoStep(at: 1.2) { InputDevicesManager.shared.update { $0.scrollControlEnabled = true } },
                DemoStep(at: 3.4) { InputDevicesManager.shared.update { $0.mouse.reverseVertical = true } },
            ],
            tail: 2
        )
    }
}
#endif
