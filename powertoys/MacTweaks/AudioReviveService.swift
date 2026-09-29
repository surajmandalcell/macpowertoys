import Darwin
import Foundation
import Observation

struct AudioReviveResult: Sendable {
    let succeeded: Bool
    let message: String
}

@Observable
@MainActor
final class AudioReviveService {
    private(set) var isRunning = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var process: AudioReviveProcess?

    func restart(completion: @escaping @MainActor (AudioReviveResult) -> Void) {
        cancel()
        let process = AudioReviveProcess()
        self.process = process
        isRunning = true
        task = Task { [weak self] in
            let result = await process.run()
            guard let self, !Task.isCancelled, self.process === process else { return }
            self.process = nil
            self.task = nil
            self.isRunning = false
            completion(result)
        }
    }

    func cancel() {
        task?.cancel()
        process?.cancel()
        task = nil
        process = nil
        isRunning = false
    }
}

nonisolated final class AudioReviveProcess: @unchecked Sendable {
    static let stderrLimit = 16 * 1_024
    static let deadline: TimeInterval = 60

    private let lock = NSLock()
    private var activeProcess: Process?
    private var stderr = Data()
    private var cancelled = false
    private var timedOut = false

    func run() async -> AudioReviveResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: self.execute())
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = activeProcess
        lock.unlock()
        terminate(process, timedOut: false)
    }

    static func capped(_ current: Data, appending data: Data, limit: Int = stderrLimit) -> Data {
        guard limit > 0, current.count < limit else { return current.prefixData(limit) }
        return current + data.prefixData(limit - current.count)
    }

    private func execute() -> AudioReviveResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges"
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.appendStderr(data) }
        }

        lock.lock()
        if cancelled {
            lock.unlock()
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return .init(succeeded: false, message: "Audio restart was cancelled.")
        }
        activeProcess = process
        lock.unlock()

        do {
            try process.run()
        } catch {
            finish(process, pipe: errorPipe)
            return .init(succeeded: false, message: "Could not restart audio: \(error.localizedDescription)")
        }

        lock.lock()
        let shouldStop = cancelled
        lock.unlock()
        if shouldStop { terminate(process, timedOut: false) }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.deadline) { [weak self, weak process] in
            self?.terminate(process, timedOut: true)
        }
        process.waitUntilExit()
        finish(process, pipe: errorPipe)

        lock.lock()
        let detail = String(data: stderr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wasCancelled = cancelled
        let didTimeOut = timedOut
        lock.unlock()

        if didTimeOut {
            return .init(succeeded: false, message: "Audio restart stopped after 60 seconds.")
        }
        if wasCancelled {
            return .init(succeeded: false, message: "Audio restart was cancelled.")
        }
        if process.terminationStatus == 0 {
            return .init(succeeded: true, message: "Audio restarted. Devices refreshed.")
        }
        return .init(
            succeeded: false,
            message: detail.isEmpty ? "Audio restart was cancelled." : detail
        )
    }

    private func appendStderr(_ data: Data) {
        lock.lock()
        stderr = Self.capped(stderr, appending: data)
        lock.unlock()
    }

    private func finish(_ process: Process, pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = nil
        if let remainder = try? pipe.fileHandleForReading.readToEnd(), !remainder.isEmpty {
            appendStderr(remainder)
        }
        try? pipe.fileHandleForReading.close()
        lock.lock()
        if activeProcess === process { activeProcess = nil }
        lock.unlock()
    }

    private func terminate(_ process: Process?, timedOut: Bool) {
        guard let process, process.isRunning else { return }
        lock.lock()
        guard activeProcess === process else {
            lock.unlock()
            return
        }
        if timedOut { self.timedOut = true }
        lock.unlock()
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak process] in
            guard let process, process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

nonisolated private extension Data {
    func prefixData(_ count: Int) -> Data {
        Data(prefix(Swift.max(0, count)))
    }
}
