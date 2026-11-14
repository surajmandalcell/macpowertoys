import AppKit
import ApplicationServices
import Foundation
import IOKit
import IOKit.hid
import os

nonisolated enum InputEventOverride: String, Codable, CaseIterable, Identifiable, Sendable {
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

nonisolated struct InputScrollProfile: Codable, Equatable, Sendable {
    var enabled = true
    var reverseVertical = false
    var reverseHorizontal = false
    var horizontalEnabled = true
    var shiftScrollsHorizontally = true
    var speed = 1.0
    var smooth = false

    init(
        enabled: Bool = true,
        reverseVertical: Bool = false,
        reverseHorizontal: Bool = false,
        horizontalEnabled: Bool = true,
        shiftScrollsHorizontally: Bool = true,
        speed: Double = 1.0,
        smooth: Bool = false
    ) {
        self.enabled = enabled
        self.reverseVertical = reverseVertical
        self.reverseHorizontal = reverseHorizontal
        self.horizontalEnabled = horizontalEnabled
        self.shiftScrollsHorizontally = shiftScrollsHorizontally
        self.speed = speed
        self.smooth = smooth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        reverseVertical = try container.decodeIfPresent(Bool.self, forKey: .reverseVertical) ?? false
        reverseHorizontal = try container.decodeIfPresent(Bool.self, forKey: .reverseHorizontal) ?? false
        horizontalEnabled = try container.decodeIfPresent(Bool.self, forKey: .horizontalEnabled) ?? true
        shiftScrollsHorizontally = try container.decodeIfPresent(Bool.self, forKey: .shiftScrollsHorizontally) ?? true
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        smooth = try container.decodeIfPresent(Bool.self, forKey: .smooth) ?? false
    }
}

nonisolated struct InputDevicesSettings: Codable, Equatable, Sendable {
    var scrollControlEnabled = false
    var eventOverride = InputEventOverride.automatic
    var mouse = InputScrollProfile(smooth: true)
    var trackpad = InputScrollProfile()

    static func decoded(from data: Data?) -> InputDevicesSettings {
        guard let data, let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return InputDevicesSettings()
        }
        return decoded
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
}

nonisolated struct InputScrollResult: Equatable, Sendable {
    let vertical: Double
    let horizontal: Double
    let shouldSmooth: Bool
    var shiftConverted = false
}

/// One scroll delta: pixels on both axes plus whole wheel lines on both axes.
nonisolated struct InputScrollStep: Equatable, Sendable {
    var vertical = 0.0
    var horizontal = 0.0
    var lineVertical = 0.0
    var lineHorizontal = 0.0

    var isZero: Bool { vertical == 0 && horizontal == 0 && lineVertical == 0 && lineHorizontal == 0 }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(vertical: lhs.vertical + rhs.vertical, horizontal: lhs.horizontal + rhs.horizontal,
             lineVertical: lhs.lineVertical + rhs.lineVertical, lineHorizontal: lhs.lineHorizontal + rhs.lineHorizontal)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(vertical: lhs.vertical - rhs.vertical, horizontal: lhs.horizontal - rhs.horizontal,
             lineVertical: lhs.lineVertical - rhs.lineVertical, lineHorizontal: lhs.lineHorizontal - rhs.lineHorizontal)
    }

    func share(of steps: Int) -> Self {
        let count = Double(steps)
        return Self(vertical: (vertical / count).rounded(), horizontal: (horizontal / count).rounded(),
                    lineVertical: (lineVertical / count).rounded(), lineHorizontal: (lineHorizontal / count).rounded())
    }
}

/// Splits a smoothed wheel notch: the first step rewrites the real event, the rest are posted later.
/// Whole lines are split too, so line-based readers see the same line total as without smoothing.
nonisolated struct InputScrollSmoother: Equatable, Sendable {
    static let steps = 5
    static let interval = 0.018

    private(set) var pending = InputScrollStep()
    private(set) var stepsLeft = 0

    mutating func begin(_ total: InputScrollStep) -> InputScrollStep {
        let first = total.share(of: Self.steps)
        pending = pending + total - first
        stepsLeft = Self.steps - 1
        return first
    }

    mutating func next() -> InputScrollStep? {
        while stepsLeft > 0 {
            let step = pending.share(of: stepsLeft)
            pending = pending - step
            stepsLeft -= 1
            if !step.isZero { return step }
        }
        return nil
    }
}

/// Carries the fraction of a scaled wheel line, so slow speeds still move by whole lines over time.
nonisolated struct InputScrollLineCarry: Equatable, Sendable {
    private(set) var remainder = 0.0

    mutating func take(_ lines: Double) -> Double {
        guard lines != 0 else { return 0 }
        if remainder != 0, (remainder < 0) != (lines < 0) { remainder = 0 }
        let total = remainder + lines
        let whole = total.rounded(.towardZero)
        remainder = total - whole
        return whole
    }
}

nonisolated enum InputScrollPolicy {
    static func profile(for kind: InputDeviceDescriptor.Kind, settings: InputDevicesSettings) -> InputScrollProfile {
        switch settings.eventOverride {
        case .automatic: kind == .mouse ? settings.mouse : settings.trackpad
        case .mouse: settings.mouse
        case .trackpad: settings.trackpad
        }
    }

    static func transform(
        vertical: Double,
        horizontal: Double,
        isContinuous: Bool,
        isPhased: Bool = true,
        shiftHeld: Bool = false,
        settings: InputDevicesSettings
    ) -> InputScrollResult? {
        // Trackpads always send a scroll or momentum phase; phase-less continuous events come from smooth wheels.
        let profile = profile(for: isContinuous && isPhased ? .trackpad : .mouse, settings: settings)
        // Native stepped sliders can save one ULP beyond their endpoints.
        guard vertical != 0 || horizontal != 0,
              settings.scrollControlEnabled, profile.enabled, profile.speed.isFinite,
              ((0.35).nextDown...(3.0).nextUp).contains(profile.speed) else { return nil }
        let convert = shiftHeld && profile.shiftScrollsHorizontally && profile.horizontalEnabled
            && horizontal == 0 && vertical != 0
        let sourceVertical = convert ? 0 : vertical
        let sourceHorizontal = convert ? vertical : horizontal
        return InputScrollResult(
            vertical: sourceVertical * profile.speed * (profile.reverseVertical ? -1 : 1),
            horizontal: profile.horizontalEnabled
                ? sourceHorizontal * profile.speed * (profile.reverseHorizontal ? -1 : 1)
                : 0,
            shouldSmooth: profile.smooth && !isContinuous,
            shiftConverted: convert
        )
    }
}

nonisolated struct InputDeviceDescriptor: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
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
    var modelNumber: String? = nil
    var batteryPercent: Int? = nil

    var vendorName: String? {
        if let manufacturer, !manufacturer.isEmpty { return manufacturer }
        return Self.knownVendors[vendorID]
    }

    var firmwareVersion: String? {
        versionNumber.map { Self.firmwareVersion($0) }
    }

    var connectionSummary: String {
        let name: String
        switch transport.lowercased() {
        case "fifo", "spi", "i2c": name = "Internal"
        case let value where value.hasPrefix("bluetooth"): name = "Bluetooth"
        default: name = transport
        }
        guard let batteryPercent else { return name }
        return "\(name) · \(batteryPercent)%"
    }

    nonisolated static func firmwareVersion(_ value: Int) -> String {
        String(format: "%X.%02X", value >> 8, value & 0xFF)
    }

    nonisolated static let knownVendors: [Int: String] = [
        0x046D: "Logitech", 0x05AC: "Apple", 0x004C: "Apple", 0x045E: "Microsoft", 0x1532: "Razer",
        0x1B1C: "Corsair", 0x1038: "SteelSeries", 0x3434: "Keychron", 0x04F2: "Chicony",
        0x0951: "HyperX", 0x03F0: "HP", 0x413C: "Dell", 0x17EF: "Lenovo", 0x0B05: "ASUS",
        0x2516: "Cooler Master", 0x24AE: "Rapoo", 0x093A: "PixArt", 0x0458: "Genius"
    ]

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
    static weak var current: InputDevicesManager?

    private static let settingsKey = "inputDevices.settings"

    private(set) var settings: InputDevicesSettings
    private(set) var devices: [InputDeviceDescriptor] = []
    private(set) var permissionGranted = AXIsProcessTrusted()
    private(set) var interceptionActive = false
    private(set) var errorMessage: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var refreshTask: Task<Void, Never>?
    nonisolated private static let scrollTap = ScrollEventTap()
    private var scrollTap: ScrollEventTap { Self.scrollTap }

    private init() {
        settings = .decoded(from: UserDefaults.standard.data(forKey: Self.settingsKey))
        Self.current = self
    }

    var eventTapOwnerCount: Int { eventTap == nil ? 0 : 1 }

    /// Disables the scroll tap at once from any thread; `stop()` later releases it on the main actor.
    nonisolated static func disableScrollTap() {
        scrollTap.disable()
    }

    func refresh() {
        permissionGranted = AXIsProcessTrusted()
        applyInterceptionState()
        guard refreshTask == nil else { return }
        refreshTask = Task {
            let snapshot = await Task.detached(priority: .utility) { Self.connectedDevices() }.value
            guard !Task.isCancelled else { return }
            if devices != snapshot { devices = snapshot }
            refreshTask = nil
        }
    }

    func update(_ change: (inout InputDevicesSettings) -> Void) {
        change(&settings)
        if let data = settings.encoded {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        applyInterceptionState()
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
        refreshTask?.cancel()
        refreshTask = nil
        stopInterception()
    }

    private func applyInterceptionState() {
        let current = settings
        scrollTap.snapshot.withLockUnchecked { $0.settings = current }
        let anyProfileEnabled = [InputDeviceDescriptor.Kind.mouse, .trackpad].contains {
            InputScrollPolicy.profile(for: $0, settings: current).enabled
        }
        guard current.scrollControlEnabled, anyProfileEnabled,
              SettingsManager.shared.isToolEnabled("input-devices"), permissionGranted else {
            stopInterception()
            errorMessage = nil
            return
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }
        stopInterception()
        errorMessage = nil

        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: ScrollEventTap.callback,
            userInfo: Unmanaged.passUnretained(scrollTap).toOpaque()
        ) else {
            errorMessage = "macOS did not allow scroll control. Re-enable Accessibility permission, then try again."
            return
        }

        let source: CFRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        scrollTap.snapshot.withLockUnchecked { $0.tap = tap }
        EventTapThread.shared.add(source)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        interceptionActive = true
    }

    private func stopInterception() {
        scrollTap.snapshot.withLockUnchecked {
            $0.tap = nil
            $0.generation &+= 1
        }
        if let runLoopSource { EventTapThread.shared.remove(runLoopSource) }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
        interceptionActive = false
    }

    fileprivate func scrollTapWasDisabled(timeout: Bool, trusted: Bool) {
        EventTapThread.logDisabled(source: "Input Devices", timeout: timeout, trusted: trusted)
        guard !trusted else { return }
        permissionGranted = false
        applyInterceptionState()
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
                ) as? NSNumber)?.doubleValue,
                modelNumber: (property("ModelNumber", on: device) as? String).flatMap { $0.isEmpty ? nil : $0 },
                batteryPercent: ((property("BatteryPercent", on: device) as? NSNumber)
                    ?? (ancestorProperty("BatteryPercent", on: device) as? NSNumber))?.intValue
            )
        }
        .sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
    }

    nonisolated private static func property(_ key: String, on device: IOHIDDevice) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    nonisolated private static func ancestorProperty(_ key: String, on device: IOHIDDevice) -> Any? {
        IORegistryEntrySearchCFProperty(
            IOHIDDeviceGetService(device),
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        )
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

/// Runs the scroll tap on `EventTapThread`. The main actor writes `snapshot`; everything else is tap-thread state.
nonisolated final class ScrollEventTap: @unchecked Sendable {
    nonisolated struct Snapshot {
        var settings = InputDevicesSettings()
        var tap: CFMachPort?
        var generation = 0
    }

    static let syntheticEventTag: Int64 = 0x4D_50_54_49_4E_50_55_54
    private static let idleFireDate = Date.distantFuture.timeIntervalSinceReferenceDate
    private static let lateStepLimit = 0.1
    private static let ownPID = Int64(getpid())

    let snapshot = OSAllocatedUnfairLock(uncheckedState: Snapshot())

    private var verticalLines = InputScrollLineCarry()
    private var horizontalLines = InputScrollLineCarry()
    private var smoother = InputScrollSmoother()
    private var smoothingGeneration = 0
    private var stepping = false
    private var nextStepDeadline: CFAbsoluteTime = 0
    private var syntheticFlags: CGEventFlags = []
    private var syntheticLocation = CGPoint.zero
    private lazy var stepTimer: CFRunLoopTimer = makeStepTimer()

    static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        return Unmanaged<ScrollEventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let state = snapshot.withLockUnchecked { $0 }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let trusted = AXIsProcessTrusted()
            if trusted, let tap = state.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            let timeout = type == .tapDisabledByTimeout
            Task { @MainActor in
                InputDevicesManager.current?.scrollTapWasDisabled(timeout: timeout, trusted: trusted)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticEventTag else {
            return Unmanaged.passUnretained(event)
        }
        // An event another process posted was already shaped by that tool; transforming it again would stack.
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        if sourcePID == 0 || sourcePID == Self.ownPID {
            processScroll(event, settings: state.settings, generation: state.generation)
        }
        return Unmanaged.passUnretained(event)
    }

    /// Stops interception at once from any thread, for example at the start of app termination.
    func disable() {
        snapshot.withLockUnchecked { state in
            state.generation &+= 1
            if let tap = state.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        }
    }

    private func processScroll(_ event: CGEvent, settings: InputDevicesSettings, generation: Int) {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let phased = event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        let pointVertical = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let pointHorizontal = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let lineVertical = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let lineHorizontal = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let vertical = pointVertical == 0 ? lineVertical * 10 : pointVertical
        let horizontal = pointHorizontal == 0 ? lineHorizontal * 10 : pointHorizontal
        guard let result = InputScrollPolicy.transform(
            vertical: vertical,
            horizontal: horizontal,
            isContinuous: continuous,
            isPhased: phased,
            shiftHeld: event.flags.contains(.maskShift),
            settings: settings
        ) else { return }

        if result.shiftConverted { event.flags.remove(.maskShift) }
        let horizontalSource = result.shiftConverted ? vertical : horizontal
        let horizontalLineSource = result.shiftConverted ? lineVertical : lineHorizontal
        let verticalScale = vertical == 0 ? 0 : result.vertical / vertical
        let horizontalScale = horizontalSource == 0 ? 0 : result.horizontal / horizontalSource
        let full = InputScrollStep(
            vertical: result.vertical,
            horizontal: result.horizontal,
            lineVertical: verticalLines.take(lineVertical * verticalScale),
            lineHorizontal: horizontalLines.take(horizontalLineSource * horizontalScale)
        )
        let target = result.shouldSmooth ? beginSmoothing(full, from: event, generation: generation) : full
        Self.write(target, to: event, vertical: vertical, horizontal: horizontalSource,
                   shiftConverted: result.shiftConverted)
    }

    /// Scales the real event to `target`; a Shift conversion moves the vertical source onto the horizontal axis.
    static func write(_ target: InputScrollStep, to event: CGEvent, vertical: Double, horizontal: Double,
                      shiftConverted: Bool) {
        let verticalScale = vertical == 0 ? 0 : target.vertical / vertical
        let horizontalScale = horizontal == 0 ? 0 : target.horizontal / horizontal
        let pointVertical = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedVertical = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let pointHorizontal = shiftConverted
            ? pointVertical : event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let fixedHorizontal = shiftConverted
            ? fixedVertical : event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        // Line deltas first: setting them makes CoreGraphics recompute the point and fixed-point deltas.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(target.lineVertical))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(target.lineHorizontal))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointVertical * verticalScale)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointHorizontal * horizontalScale)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixedVertical * verticalScale)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedHorizontal * horizontalScale)
    }

    private func beginSmoothing(_ total: InputScrollStep, from event: CGEvent, generation: Int) -> InputScrollStep {
        if smoothingGeneration != generation {
            smoother = InputScrollSmoother()
            smoothingGeneration = generation
        }
        let first = smoother.begin(total)
        syntheticFlags = event.flags
        syntheticLocation = event.location
        if !stepping {
            stepping = true
            nextStepDeadline = CFAbsoluteTimeGetCurrent() + InputScrollSmoother.interval
            CFRunLoopTimerSetNextFireDate(stepTimer, nextStepDeadline)
        }
        return first
    }

    private func postNextStep() {
        let state = snapshot.withLockUnchecked { $0 }
        let now = CFAbsoluteTimeGetCurrent()
        let late = now - nextStepDeadline > Self.lateStepLimit
        nextStepDeadline = now + InputScrollSmoother.interval
        let live = state.tap != nil && state.generation == smoothingGeneration && state.settings.scrollControlEnabled
        if !live || late { smoother = InputScrollSmoother() }
        guard let step = smoother.next() else {
            stepping = false
            CFRunLoopTimerSetNextFireDate(stepTimer, Self.idleFireDate)
            return
        }
        guard let synthetic = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(step.vertical),
            wheel2: Int32(step.horizontal),
            wheel3: 0
        ) else { return }
        synthetic.flags = syntheticFlags
        synthetic.location = syntheticLocation
        synthetic.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        synthetic.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        synthetic.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(step.lineVertical))
        synthetic.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(step.lineHorizontal))
        synthetic.post(tap: .cgSessionEventTap)
    }

    private func makeStepTimer() -> CFRunLoopTimer {
        let timer: CFRunLoopTimer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, Self.idleFireDate, InputScrollSmoother.interval, 0, 0
        ) { [weak self] timer in
            guard let self else { return CFRunLoopTimerInvalidate(timer) }
            self.postNextStep()
        }
        EventTapThread.shared.add(timer)
        return timer
    }

}
