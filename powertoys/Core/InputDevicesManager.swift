import AppKit
import ApplicationServices
import Foundation
import IOKit
import IOKit.hid

enum InputEventOverride: String, Codable, CaseIterable, Identifiable {
    case automatic
    case mouse
    case trackpad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .mouse: "Mouse-like"
        case .trackpad: "Trackpad-like"
        }
    }
}

struct InputScrollProfile: Codable, Equatable {
    var enabled = true
    var reverseVertical = false
    var reverseHorizontal = false
    var horizontalEnabled = true
    var speed = 1.0
    var smooth = false
}

struct InputDevicesSettings: Codable, Equatable {
    var scrollControlEnabled = false
    var eventOverride = InputEventOverride.automatic
    var mouse = InputScrollProfile(smooth: true)
    var trackpad = InputScrollProfile()
    var iconAsset = "InputDevicesLogoA"
}

struct InputScrollResult: Equatable {
    let vertical: Double
    let horizontal: Double
    let shouldSmooth: Bool
}

enum InputScrollPolicy {
    static func transform(
        vertical: Double,
        horizontal: Double,
        isContinuous: Bool,
        settings: InputDevicesSettings
    ) -> InputScrollResult? {
        let trackpadLike: Bool
        switch settings.eventOverride {
        case .automatic: trackpadLike = isContinuous
        case .mouse: trackpadLike = false
        case .trackpad: trackpadLike = true
        }

        let profile = trackpadLike ? settings.trackpad : settings.mouse
        guard profile.enabled else { return nil }
        return InputScrollResult(
            vertical: vertical * profile.speed * (profile.reverseVertical ? -1 : 1),
            horizontal: profile.horizontalEnabled
                ? horizontal * profile.speed * (profile.reverseHorizontal ? -1 : 1)
                : 0,
            shouldSmooth: profile.smooth && !isContinuous
        )
    }
}

struct InputDeviceDescriptor: Identifiable, Equatable {
    enum Kind: String {
        case mouse = "Mouse"
        case trackpad = "Trackpad"

        var icon: String {
            switch self {
            case .mouse: "computermouse"
            case .trackpad: "rectangle.and.hand.point.up.left"
            }
        }
    }

    let id: String
    let name: String
    let kind: Kind
    let transport: String
    let isBuiltIn: Bool
    let manufacturer: String?
    let vendorID: Int
    let productID: Int
    let versionNumber: Int?
    let locationID: Int
    let serialNumber: String?
    let pointerResolutionDPI: Double?
    let pollingRateHz: Double?
    let buttonCount: Int?
    let maxInputReportSize: Int?
    let systemTrackingSpeed: Double?

    nonisolated static func kind(name: String, usagePage: Int, usage: Int) -> Kind? {
        guard usagePage == kHIDPage_GenericDesktop,
              usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer else { return nil }
        let normalizedName = name.lowercased()
        return normalizedName.contains("trackpad") || normalizedName.contains("touchpad") ? .trackpad : .mouse
    }

    nonisolated static func fixedPointResolution(_ rawValue: Int?) -> Double? {
        guard let rawValue, rawValue > 0 else { return nil }
        return rawValue >= 65_536 ? Double(rawValue) / 65_536 : Double(rawValue)
    }

    nonisolated static func pollingRate(pointerRate: Int?, reportIntervalMicroseconds: Int?) -> Double? {
        if let pointerRate, pointerRate > 0 { return Double(pointerRate) }
        guard let interval = reportIntervalMicroseconds, interval > 0 else { return nil }
        return 1_000_000 / Double(interval)
    }
}

@Observable
@MainActor
final class InputDevicesManager {
    static let shared = InputDevicesManager()

    private static let settingsKey = "inputDevices.settings"
    private static let syntheticEventTag: Int64 = 0x4D_50_54_49_4E_50_55_54

    private(set) var settings: InputDevicesSettings
    private(set) var devices: [InputDeviceDescriptor] = []
    private(set) var permissionGranted = AXIsProcessTrusted()
    private(set) var interceptionActive = false
    private(set) var errorMessage: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(InputDevicesSettings.self, from: data) {
            settings = decoded
        } else {
            settings = InputDevicesSettings()
        }
    }

    deinit {
        MainActor.assumeIsolated { stopInterception() }
    }

    func refresh() {
        permissionGranted = AXIsProcessTrusted()
        devices = Self.connectedDevices()
        applyInterceptionState()
    }

    func update(_ change: (inout InputDevicesSettings) -> Void) {
        let wasEnabled = settings.scrollControlEnabled
        let previousIcon = settings.iconAsset
        change(&settings)
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        if wasEnabled != settings.scrollControlEnabled {
            applyInterceptionState()
        }
        if previousIcon != settings.iconAsset {
            AppDelegate.current?.refreshDockIconForKeyWindow()
        }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
        permissionGranted = AXIsProcessTrusted()
        applyInterceptionState()
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func stop() {
        stopInterception()
    }

    private func applyInterceptionState() {
        stopInterception()
        errorMessage = nil
        guard settings.scrollControlEnabled else { return }
        guard permissionGranted else {
            errorMessage = "Accessibility permission is required to adjust scrolling outside MacPowerToys."
            return
        }

        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            errorMessage = "macOS did not allow scroll control. Re-enable Accessibility permission, then try again."
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        interceptionActive = true
    }

    private func stopInterception() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        interceptionActive = false
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<InputDevicesManager>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { manager.applyInterceptionState() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel,
              event.getIntegerValueField(.eventSourceUserData) != syntheticEventTag else {
            return Unmanaged.passUnretained(event)
        }

        return MainActor.assumeIsolated {
            manager.processScroll(event)
        }
    }

    private func processScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let pointVertical = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let pointHorizontal = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let vertical = pointVertical == 0
            ? Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * 10
            : pointVertical
        let horizontal = pointHorizontal == 0
            ? Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * 10
            : pointHorizontal
        guard let result = InputScrollPolicy.transform(
            vertical: vertical,
            horizontal: horizontal,
            isContinuous: continuous,
            settings: settings
        ) else { return Unmanaged.passUnretained(event) }

        if result.shouldSmooth {
            postSmoothed(vertical: result.vertical, horizontal: result.horizontal)
            return nil
        }

        setScrollFields(
            on: event,
            verticalScale: vertical == 0 ? 0 : result.vertical / vertical,
            horizontalScale: horizontal == 0 ? 0 : result.horizontal / horizontal
        )
        return Unmanaged.passUnretained(event)
    }

    private func setScrollFields(on event: CGEvent, verticalScale: Double, horizontalScale: Double) {
        event.setDoubleValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) * verticalScale
        )
        event.setDoubleValueField(
            .scrollWheelEventPointDeltaAxis2,
            value: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) * horizontalScale
        )
        for (field, scale) in [
            (CGEventField.scrollWheelEventDeltaAxis1, verticalScale),
            (.scrollWheelEventDeltaAxis2, horizontalScale),
            (.scrollWheelEventFixedPtDeltaAxis1, verticalScale),
            (.scrollWheelEventFixedPtDeltaAxis2, horizontalScale)
        ] {
            let value = Double(event.getIntegerValueField(field)) * scale
            event.setIntegerValueField(field, value: Int64(value.rounded()))
        }
    }

    private func postSmoothed(vertical: Double, horizontal: Double) {
        let steps = 5
        for index in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.018) {
                let start = Double(index) / Double(steps)
                let end = Double(index + 1) / Double(steps)
                guard self.settings.scrollControlEnabled,
                      let event = CGEvent(
                        scrollWheelEvent2Source: nil,
                        units: .pixel,
                        wheelCount: 2,
                        wheel1: Int32((vertical * end).rounded() - (vertical * start).rounded()),
                        wheel2: Int32((horizontal * end).rounded() - (horizontal * start).rounded()),
                        wheel3: 0
                      ) else { return }
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    nonisolated private static func connectedDevices() -> [InputDeviceDescriptor] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard let values = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

        return values.compactMap { device in
            let name = property(kIOHIDProductKey, on: device) as? String ?? "Pointing Device"
            let usagePage = (property(kIOHIDPrimaryUsagePageKey, on: device) as? NSNumber)?.intValue ?? 0
            let usage = (property(kIOHIDPrimaryUsageKey, on: device) as? NSNumber)?.intValue ?? 0
            guard let kind = InputDeviceDescriptor.kind(name: name, usagePage: usagePage, usage: usage) else { return nil }
            let vendor = (property(kIOHIDVendorIDKey, on: device) as? NSNumber)?.intValue ?? 0
            let product = (property(kIOHIDProductIDKey, on: device) as? NSNumber)?.intValue ?? 0
            let location = (property(kIOHIDLocationIDKey, on: device) as? NSNumber)?.intValue ?? 0
            let version = (property(kIOHIDVersionNumberKey, on: device) as? NSNumber)?.intValue
            let reportInterval = (property(kIOHIDReportIntervalKey, on: device) as? NSNumber)?.intValue
            return InputDeviceDescriptor(
                id: "\(vendor)-\(product)-\(location)-\(name)",
                name: name,
                kind: kind,
                transport: property(kIOHIDTransportKey, on: device) as? String ?? "Unknown connection",
                isBuiltIn: (property(kIOHIDBuiltInKey, on: device) as? NSNumber)?.boolValue ?? false,
                manufacturer: property(kIOHIDManufacturerKey, on: device) as? String,
                vendorID: vendor,
                productID: product,
                versionNumber: version.flatMap { $0 > 0 ? $0 : nil },
                locationID: location,
                serialNumber: property(kIOHIDSerialNumberKey, on: device) as? String,
                pointerResolutionDPI: InputDeviceDescriptor.fixedPointResolution(
                    (property("HIDPointerResolution", on: device) as? NSNumber)?.intValue
                        ?? (registryProperty("HIDPointerResolution", on: device) as? NSNumber)?.intValue
                ),
                pollingRateHz: InputDeviceDescriptor.pollingRate(
                    pointerRate: (property("HIDPointerReportRate", on: device) as? NSNumber)?.intValue
                        ?? (registryProperty("HIDPointerReportRate", on: device) as? NSNumber)?.intValue,
                    reportIntervalMicroseconds: reportInterval
                ),
                buttonCount: (property("HIDPointerButtonCount", on: device) as? NSNumber)?.intValue
                    ?? (registryProperty("HIDPointerButtonCount", on: device) as? NSNumber)?.intValue,
                maxInputReportSize: (property(kIOHIDMaxInputReportSizeKey, on: device) as? NSNumber)?.intValue,
                systemTrackingSpeed: (UserDefaults.standard.object(
                    forKey: kind == .mouse ? "com.apple.mouse.scaling" : "com.apple.trackpad.scaling"
                ) as? NSNumber)?.doubleValue
            )
        }
        .sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
    }

    nonisolated private static func property(_ key: String, on device: IOHIDDevice) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    nonisolated private static func registryProperty(_ key: String, on device: IOHIDDevice) -> Any? {
        IORegistryEntrySearchCFProperty(
            IOHIDDeviceGetService(device),
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )
    }
}
