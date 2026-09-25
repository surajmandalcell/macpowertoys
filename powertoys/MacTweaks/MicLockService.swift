import AppKit
import CoreAudio
import Foundation

struct MicInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let audioID: AudioDeviceID
    let isWireless: Bool
    let isBuiltIn: Bool
}

struct SavedMicInput: Codable, Equatable {
    let uid: String
    let name: String
}

@Observable
@MainActor
final class MicLockService {
    static let shared = MicLockService()

    private static let enabledKey = "macTweaks.micLock.enabled"
    private static let savedKey = "macTweaks.micLock.savedInputs"
    private let systemID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue.main
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var wakeObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var windowIsOpen = false

    private(set) var devices: [MicInputDevice] = []
    private(set) var currentUID: String?
    private(set) var volume: Float?
    private(set) var muted: Bool?
    private(set) var message: String?
    private(set) var isEnabled: Bool
    private(set) var savedInputs: [SavedMicInput?]

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let saved = (UserDefaults.standard.data(forKey: Self.savedKey))
            .flatMap { try? JSONDecoder().decode([SavedMicInput?].self, from: $0) } ?? []
        savedInputs = Array((saved + Array(repeating: nil, count: 4)).prefix(4))
    }

    func startIfNeeded() {
        guard SettingsManager.shared.isToolEnabled("mac-tweaks"), isEnabled || windowIsOpen else { return }
        if systemListener == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            }
            systemListener = listener
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
                var address = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(systemID, &address, listenerQueue, listener)
            }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            }
        }
        refresh()
    }

    func setWindowOpen(_ open: Bool) {
        windowIsOpen = open
        if open { startIfNeeded() } else if !isEnabled { stop() }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        message = nil
        if enabled { startIfNeeded() } else if !windowIsOpen { stop() }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        if let listener = systemListener {
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(systemID, &address, listenerQueue, listener)
            }
            systemListener = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func setSavedInput(_ uid: String?, at index: Int) {
        guard savedInputs.indices.contains(index) else { return }
        savedInputs[index] = uid.flatMap { selected in
            devices.first(where: { $0.id == selected }).map { SavedMicInput(uid: $0.id, name: $0.name) }
        }
        if let uid {
            for other in savedInputs.indices where other != index && savedInputs[other]?.uid == uid {
                savedInputs[other] = nil
            }
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(savedInputs), forKey: Self.savedKey)
        refresh()
    }

    func refresh() {
        devices = Self.availableInputs()
        let activeID = Self.read(systemID, selector: kAudioHardwarePropertyDefaultInputDevice) as AudioDeviceID?
        currentUID = devices.first(where: { $0.audioID == activeID })?.id
        if isEnabled && SettingsManager.shared.isToolEnabled("mac-tweaks") {
            enforceSelection()
        }
        refreshControls()
    }

    func refreshControls() {
        guard let device = devices.first(where: { $0.id == currentUID }) else {
            volume = nil
            muted = nil
            return
        }
        let elements = [kAudioObjectPropertyElementMain, 1, 2]
        volume = elements.lazy.compactMap {
            Self.read(device.audioID, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: $0) as Float?
        }.first
        muted = elements.lazy.compactMap {
            (Self.read(device.audioID, selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, element: $0) as UInt32?).map { $0 != 0 }
        }.first
    }

    func setVolume(_ value: Float) {
        guard let device = devices.first(where: { $0.id == currentUID }) else { return }
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            if Self.write(device.audioID, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element, value: value) {
                refreshControls()
                return
            }
        }
        message = "This microphone does not allow volume changes."
    }

    func setMuted(_ value: Bool) {
        guard let device = devices.first(where: { $0.id == currentUID }) else { return }
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            if Self.write(device.audioID, selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, element: element, value: UInt32(value ? 1 : 0)) {
                refreshControls()
                return
            }
        }
        message = "This microphone does not allow mute changes."
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    private func enforceSelection() {
        let target = Self.resolvedInput(savedUIDs: savedInputs.compactMap(\.?.uid), devices: devices)
        guard let target else {
            message = "No safe microphone is available. Connect one or turn off Mic Lock."
            return
        }
        guard currentUID != target.id else { message = nil; return }
        if Self.write(systemID, selector: kAudioHardwarePropertyDefaultInputDevice, value: target.audioID) {
            currentUID = target.id
            message = nil
        } else {
            message = "Could not select \(target.name). Refresh devices and try again."
        }
    }

    static func resolvedInput(savedUIDs: [String], devices: [MicInputDevice]) -> MicInputDevice? {
        for uid in savedUIDs {
            if let device = devices.first(where: { $0.id == uid }) { return device }
        }
        return devices.first(where: { $0.isBuiltIn && !$0.isWireless })
            ?? devices.first(where: { !$0.isWireless })
    }

    private static func availableInputs() -> [MicInputDevice] {
        var deviceListAddress = address(kAudioHardwarePropertyDevices)
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, 0, nil, &byteCount) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty else { return [] }
        let listStatus = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, 0, nil, &byteCount, buffer.baseAddress!)
        }
        guard listStatus == noErr else { return [] }
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr,
                  streamSize >= MemoryLayout<AudioBufferList>.size else { return nil }
            let bytes = UnsafeMutableRawPointer.allocate(byteCount: Int(streamSize), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { bytes.deallocate() }
            guard AudioObjectGetPropertyData(id, &streams, 0, nil, &streamSize, bytes) == noErr else { return nil }
            let buffers = UnsafeMutableAudioBufferListPointer(bytes.assumingMemoryBound(to: AudioBufferList.self))
            guard buffers.contains(where: { $0.mNumberChannels > 0 }) else { return nil }
            guard (read(id, selector: kAudioDevicePropertyDeviceIsAlive) as UInt32?) != 0,
                  (read(id, selector: kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioObjectPropertyScopeInput) as UInt32?) != 0,
                  let uid = string(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = string(id, selector: kAudioObjectPropertyName) else { return nil }
            let transport: UInt32 = read(id, selector: kAudioDevicePropertyTransportType) ?? 0
            return MicInputDevice(
                id: uid, name: name, audioID: id,
                isWireless: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func read<T: ExpressibleByIntegerLiteral>(
        _ id: AudioObjectID, selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> T? {
        var address = address(selector, scope: scope, element: element)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return nil }
        return value
    }

    private static func string(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func write<T>(
        _ id: AudioObjectID, selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        value: T
    ) -> Bool {
        var address = address(selector, scope: scope, element: element)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &address),
              AudioObjectIsPropertySettable(id, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var value = value
        return withUnsafeBytes(of: &value) {
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32($0.count), $0.baseAddress!)
        } == noErr
    }
}
