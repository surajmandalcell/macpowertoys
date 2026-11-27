import AVFoundation
import AppKit

@Observable
@MainActor
final class MicInputLevelMonitor {
    private var engine: AVAudioEngine?
    private(set) var level: Float = 0
    var permission: AVAuthorizationStatus { PermissionCenter.shared.microphoneStatus }
    private(set) var error: String?

    func requestAndStart() async {
        if permission == .notDetermined { await PermissionCenter.shared.requestMicrophone() }
        if permission == .authorized { start() }
    }

    func refreshPermission() {
        PermissionCenter.shared.refreshMicrophone()
        if permission == .authorized { start() } else { stop() }
    }

    func start() {
        guard permission == .authorized, engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            error = "This microphone has no input channels."
            return
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: Self.levelTap(for: self))
        do {
            try engine.start()
            self.engine = engine
            error = nil
        } catch {
            input.removeTap(onBus: 0)
            self.error = "Could not read input level: \(error.localizedDescription)"
        }
    }

    // A level meter reads as live at 10 Hz; buffers arrive about 47 times per second.
    nonisolated private static let publishIntervalNanoseconds: UInt64 = 100_000_000

    /// Built outside the main actor because AVAudioEngine calls the tap on its realtime thread.
    nonisolated private static func levelTap(for monitor: MicInputLevelMonitor) -> AVAudioNodeTapBlock {
        weak var owner = monitor
        var peak: Float = 0
        var lastPublish = DispatchTime.now().uptimeNanoseconds
        let interval = publishIntervalNanoseconds
        return { buffer, _ in
            guard let samples = buffer.floatChannelData?.pointee else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            peak = max(peak, min(1, sqrt(sum / Float(count)) * 5))
            let now = DispatchTime.now().uptimeNanoseconds
            guard now &- lastPublish >= interval else { return }
            lastPublish = now
            let measured = peak
            peak = 0
            let target = owner
            Task { @MainActor [weak target] in
                guard let target, target.engine != nil else { return }
                target.level = measured
            }
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0
    }
}
