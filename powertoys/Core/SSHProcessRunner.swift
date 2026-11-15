import Darwin
import Foundation

// Taken from NetToysCore (surajmandalcell/nettoys, MIT) when NetToys left MacPowerToys.
// Portman and the process sampler still run bounded child processes and SSH with it.

nonisolated enum SSHKeyAccessError: LocalizedError {
    case timeout
    case outputLimit
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout: "The command timed out."
        case .outputLimit: "Process output exceeded its limit."
        case .processLaunchFailed(let message): "SSH could not start: \(message)"
        }
    }
}

nonisolated struct SSHProcessResult: Sendable {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

nonisolated enum SSHProcessRunner {
    static func baseEnvironment() -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        var environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin",
            "LC_ALL": "C",
        ]
        if let socket = current["SSH_AUTH_SOCK"] { environment["SSH_AUTH_SOCK"] = socket }
        return environment
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = baseEnvironment(),
        standardInput: Data? = nil,
        maximumOutputBytes: Int = 4 * 1_024 * 1_024,
        timeout: TimeInterval
    ) async throws -> SSHProcessResult {
        guard maximumOutputBytes > 0 else { throw SSHKeyAccessError.outputLimit }
        let cancellation = ProcessCancellation()
        // Blocking waits and pipe reads run on dispatch threads, never on the Swift cooperative pool.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try runBlocking(
                            executableURL: executableURL,
                            arguments: arguments,
                            environment: environment,
                            standardInput: standardInput,
                            maximumOutputBytes: maximumOutputBytes,
                            timeout: timeout,
                            cancellation: cancellation
                        )
                    })
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func runBlocking(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Data?,
        maximumOutputBytes: Int,
        timeout: TimeInterval,
        cancellation: ProcessCancellation
    ) throws -> SSHProcessResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let input = standardInput == nil ? nil : Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = error
        process.standardInput = input
        do {
            try process.run()
        } catch {
            throw SSHKeyAccessError.processLaunchFailed(error.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(timeout)
        let readerDeadline = deadline.addingTimeInterval(4)
        let readers = DispatchGroup()
        let outputCapture = PipeCapture()
        let errorCapture = PipeCapture()
        let outputHandle = output.fileHandleForReading
        let errorHandle = error.fileHandleForReading
        DispatchQueue.global(qos: .utility).async(group: readers) {
            outputCapture.read(outputHandle, maximumBytes: maximumOutputBytes, process: process, deadline: readerDeadline)
        }
        DispatchQueue.global(qos: .utility).async(group: readers) {
            errorCapture.read(errorHandle, maximumBytes: maximumOutputBytes, process: process, deadline: readerDeadline)
        }
        if let standardInput, let input {
            let handle = input.fileHandleForWriting
            // A child that exits before reading stdin must not kill this process with SIGPIPE.
            _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? handle.write(contentsOf: standardInput)
            try? handle.close()
        }
        while process.isRunning, !cancellation.isCancelled, Date() < deadline {
            usleep(20_000)
        }
        let wasCancelled = cancellation.isCancelled
        let timedOut = process.isRunning && Date() >= deadline
        if process.isRunning {
            process.terminate()
            let killDeadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < killDeadline {
                usleep(20_000)
            }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        // waitUntilExit() can block forever when Foundation misses the child's exit.
        let reapDeadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < reapDeadline {
            usleep(20_000)
        }
        readers.wait()
        if wasCancelled { throw CancellationError() }
        if timedOut || process.isRunning { throw SSHKeyAccessError.timeout }
        if outputCapture.exceeded || errorCapture.exceeded { throw SSHKeyAccessError.outputLimit }
        return SSHProcessResult(
            status: process.terminationStatus,
            standardOutput: String(decoding: outputCapture.data, as: UTF8.self),
            standardError: String(decoding: errorCapture.data, as: UTF8.self)
        )
    }
}

private final nonisolated class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// Written only by its reader thread; read after the reader's DispatchGroup finishes.
private final nonisolated class PipeCapture: @unchecked Sendable {
    private(set) var data = Data()
    private(set) var exceeded = false

    // Poll with a deadline: a process launched elsewhere can inherit the write end and hold it open.
    func read(_ handle: FileHandle, maximumBytes: Int, process: Process, deadline: Date) {
        let descriptor = handle.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 8_192)
        var quietAfterExit = 0
        while Date() < deadline {
            var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&event, 1, 100) > 0 else {
                if process.isRunning { continue }
                quietAfterExit += 1
                if quietAfterExit >= 3 { break }
                continue
            }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count <= 0 { break }
            let remaining = max(maximumBytes - data.count, 0)
            data.append(contentsOf: buffer.prefix(min(count, remaining)))
            exceeded = exceeded || count > remaining
            if exceeded, process.isRunning { process.terminate() }
        }
    }
}

/// Hands one password to OpenSSH through SSH_ASKPASS and a private FIFO, never through arguments.
nonisolated final class SSHAskpassChannel: @unchecked Sendable {
    let directoryURL: URL
    let scriptURL: URL
    let fifoURL: URL
    let environment: [String: String]

    init() throws {
        let fileManager = FileManager.default
        directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("macpowertoys-ssh-\(UUID().uuidString)", isDirectory: true)
        scriptURL = directoryURL.appendingPathComponent("askpass.sh")
        fifoURL = directoryURL.appendingPathComponent("password.fifo")
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            let script = "#!/bin/sh\nIFS= read -r p < \"$MPT_ASKPASS_FIFO\" || exit 1\nprintf '%s\\n' \"$p\"\n"
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            guard mkfifo(fifoURL.path, S_IRUSR | S_IWUSR) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
        var environment = SSHProcessRunner.baseEnvironment()
        environment["DISPLAY"] = "macpowertoys"
        environment["SSH_ASKPASS"] = scriptURL.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["MPT_ASKPASS_FIFO"] = fifoURL.path
        self.environment = environment
    }

    func startDelivery(password: String) -> Task<Void, Never> {
        let path = fifoURL.path
        return Task.detached(priority: .userInitiated) {
            var bytes = Array(password.utf8) + [0x0a]
            defer {
                bytes.indices.forEach { bytes[$0] = 0 }
                unlink(path)
            }
            let deadline = Date().addingTimeInterval(45)
            while !Task.isCancelled, Date() < deadline {
                let descriptor = open(path, O_WRONLY | O_NONBLOCK)
                if descriptor >= 0 {
                    defer { close(descriptor) }
                    var written = 0
                    while written < bytes.count, !Task.isCancelled {
                        let count = bytes.withUnsafeBytes { buffer in
                            Darwin.write(
                                descriptor,
                                buffer.baseAddress!.advanced(by: written),
                                bytes.count - written
                            )
                        }
                        if count > 0 { written += count } else { break }
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    func cleanup() {
        unlink(fifoURL.path)
        try? FileManager.default.removeItem(at: directoryURL)
    }

    deinit { cleanup() }
}

nonisolated struct SSHConfigEntry: Equatable, Sendable {
    let aliases: [String]
    let hostName: String
    let port: UInt16
}

/// Reads `Host` entries that name a `HostName` from an OpenSSH config file.
nonisolated enum SSHConfigEditor {
    private struct Directive {
        let key: String
        let valueRange: Range<Int>
    }

    static func entries(in data: Data) -> [SSHConfigEntry] {
        let bytes = [UInt8](data)
        let lines = lineRanges(bytes)
        var result: [SSHConfigEntry] = []
        var index = 0
        while index < lines.count {
            guard let host = directive(in: bytes, range: lines[index]), host.key == "host" else {
                index += 1
                continue
            }
            let aliases = tokens(in: bytes, range: host.valueRange).map { asciiString(bytes[$0]) }
            var hostName: String?
            var port: UInt16?
            index += 1
            while index < lines.count {
                guard let item = directive(in: bytes, range: lines[index]) else {
                    index += 1
                    continue
                }
                if item.key == "host" || item.key == "match" { break }
                if item.key == "hostname", hostName == nil,
                   let token = valueToken(in: bytes, range: item.valueRange) {
                    hostName = asciiString(bytes[token])
                } else if item.key == "port", port == nil,
                          let token = valueToken(in: bytes, range: item.valueRange) {
                    port = UInt16(asciiString(bytes[token]))
                }
                index += 1
            }
            if let hostName, !aliases.isEmpty {
                result.append(SSHConfigEntry(aliases: aliases, hostName: hostName, port: port ?? 22))
            }
        }
        return result
    }

    private static func lineRanges(_ bytes: [UInt8]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0a {
            result.append(start..<index)
            start = index + 1
        }
        if start < bytes.count { result.append(start..<bytes.count) }
        return result
    }

    private static func directive(in bytes: [UInt8], range: Range<Int>) -> Directive? {
        var index = range.lowerBound
        while index < range.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        guard index < range.upperBound, bytes[index] != 0x23 else { return nil }
        let keyStart = index
        while index < range.upperBound, isKeyByte(bytes[index]) { index += 1 }
        guard index > keyStart else { return nil }
        let key = asciiString(bytes[keyStart..<index]).lowercased()
        while index < range.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        if index < range.upperBound, bytes[index] == 0x3d {
            index += 1
            while index < range.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        }
        return Directive(key: key, valueRange: index..<range.upperBound)
    }

    private static func tokens(in bytes: [UInt8], range: Range<Int>) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var index = range.lowerBound
        while index < range.upperBound {
            while index < range.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
            guard index < range.upperBound, bytes[index] != 0x23, bytes[index] != 0x0d else { break }
            let start = index
            while index < range.upperBound,
                  bytes[index] != 0x20, bytes[index] != 0x09,
                  bytes[index] != 0x23, bytes[index] != 0x0d { index += 1 }
            result.append(start..<index)
        }
        return result
    }

    private static func valueToken(in bytes: [UInt8], range: Range<Int>) -> Range<Int>? {
        var start = range.lowerBound
        guard start < range.upperBound, bytes[start] != 0x23, bytes[start] != 0x0d else { return nil }
        if bytes[start] == 0x22 {
            start += 1
            var end = start
            while end < range.upperBound, bytes[end] != 0x22, bytes[end] != 0x0d { end += 1 }
            return start..<end
        }
        var end = start
        while end < range.upperBound,
              bytes[end] != 0x20, bytes[end] != 0x09,
              bytes[end] != 0x23, bytes[end] != 0x0d { end += 1 }
        return start < end ? start..<end : nil
    }

    private static func isKeyByte(_ byte: UInt8) -> Bool {
        (0x41...0x5a).contains(byte) || (0x61...0x7a).contains(byte)
    }

    private static func asciiString(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}
