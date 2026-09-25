import AVFoundation
import AppKit

@Observable
@MainActor
final class MicInputLevelMonitor {
    private var engine: AVAudioEngine?
    private(set) var level: Float = 0
    private(set) var permission = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var error: String?

    func requestAndStart() async {
        if permission == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            permission = AVCaptureDevice.authorizationStatus(for: .audio)
        }
        if permission == .authorized { start() }
    }

    func refreshPermission() {
        permission = AVCaptureDevice.authorizationStatus(for: .audio)
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
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?.pointee else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let measured = min(1, sqrt(sum / Float(count)) * 5)
            DispatchQueue.main.async { [weak self] in self?.level = measured }
        }
        do {
            try engine.start()
            self.engine = engine
            error = nil
        } catch {
            input.removeTap(onBus: 0)
            self.error = "Could not read input level: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
