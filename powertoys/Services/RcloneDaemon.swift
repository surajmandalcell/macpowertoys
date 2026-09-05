//
//  RcloneDaemon.swift
//  powertoys
//

import Foundation
import Darwin
import Security

@Observable
final class RcloneDaemon {
    enum State: Equatable {
        case stopped
        case starting
        case running(port: Int, version: String)
        case failed(String)
    }

    private(set) var state: State = .stopped
    private var process: Process?
    private var client: RcloneRCClient?

    private nonisolated static let candidatePaths = [
        "/opt/homebrew/bin/rclone",
        "/usr/local/bin/rclone",
        "/usr/bin/rclone",
        "/opt/local/bin/rclone"
    ]

    var isRunning: Bool {
        if case .running = state, process?.isRunning == true { return true }
        return false
    }

    // MARK: Binary resolution

    nonisolated static func resolveBinaryPath(preferred: String) -> String? {
        let fm = FileManager.default
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, fm.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        return resolveViaLoginShell()
    }

    private nonisolated static func resolveViaLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", "command -v rclone"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: Stray daemon registry

    private nonisolated static var registryDirectory: URL {
        AppDataLocation.directory.appendingPathComponent("daemons", isDirectory: true)
    }

    private static func register(daemonPid: pid_t) {
        let fm = FileManager.default
        try? fm.createDirectory(at: registryDirectory, withIntermediateDirectories: true)
        let marker = registryDirectory.appendingPathComponent(String(daemonPid))
        let owner = String(ProcessInfo.processInfo.processIdentifier)
        try? owner.data(using: .utf8)?.write(to: marker)
    }

    private static func unregister(daemonPid: pid_t) {
        try? FileManager.default.removeItem(at: registryDirectory.appendingPathComponent(String(daemonPid)))
    }

    private nonisolated static func reapStrayDaemons() -> [pid_t] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: registryDirectory.path) else { return [] }
        var reaped: [pid_t] = []
        for entry in entries {
            let marker = registryDirectory.appendingPathComponent(entry)
            guard let daemonPid = pid_t(entry), daemonPid > 0 else {
                try? fm.removeItem(at: marker)
                continue
            }
            let ownerPid = (try? String(contentsOf: marker, encoding: .utf8))
                .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if let ownerPid, ownerPid > 0, kill(ownerPid, 0) == 0 {
                continue
            }
            defer { try? fm.removeItem(at: marker) }
            guard kill(daemonPid, 0) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard proc_pidpath(daemonPid, &buffer, UInt32(buffer.count)) > 0,
                  (String(cString: buffer) as NSString).lastPathComponent == "rclone" else { continue }
            kill(daemonPid, SIGTERM)
            reaped.append(daemonPid)
        }
        return reaped
    }

    // MARK: Lifecycle

    func ensureRunning(binaryPath: String) async throws -> RcloneRCClient {
        if isRunning, let client { return client }
        stop()
        return try await startDaemon(binaryPath: binaryPath)
    }

    private func startDaemon(binaryPath: String) async throws -> RcloneRCClient {
        state = .starting

        let startup = await Task.detached(priority: .userInitiated) {
            (Self.resolveBinaryPath(preferred: binaryPath), Self.reapStrayDaemons())
        }.value
        for daemonPid in startup.1 {
            LogManager.shared.info("Reaped stray rclone daemon (pid \(daemonPid))", source: "RcloneDaemon")
        }

        guard let resolved = startup.0 else {
            state = .failed("rclone binary not found. Set its path in settings.")
            throw RcloneRCError.notReachable
        }

        var lastError: Error?
        for _ in 0..<3 {
            guard let port = Self.findFreePort() else { continue }
            guard let credentials = Self.makeCredentials() else {
                state = .failed("Could not secure the local rclone connection.")
                throw RcloneRCError.notReachable
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: resolved)
            proc.arguments = [
                "rcd",
                "--rc-addr", "127.0.0.1:\(port)",
                "--rc-web-gui=false",
                "--rc-job-expire-duration", "168h"
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["RCLONE_RC_USER"] = credentials.username
            environment["RCLONE_RC_PASS"] = credentials.password
            proc.environment = environment
            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = Pipe()
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task { @MainActor in
                    LogManager.shared.debug(trimmed, source: "RcloneDaemon")
                }
            }

            do {
                try proc.run()
            } catch {
                lastError = error
                continue
            }
            Self.register(daemonPid: proc.processIdentifier)

            let candidate = RcloneRCClient(port: port, credentials: credentials)
            if let version = await healthCheck(client: candidate, process: proc) {
                self.process = proc
                self.client = candidate
                state = .running(port: port, version: version)
                LogManager.shared.info("rclone daemon started on port \(port) (\(version))", source: "RcloneDaemon")
                return candidate
            }

            errPipe.fileHandleForReading.readabilityHandler = nil
            proc.terminate()
            Self.unregister(daemonPid: proc.processIdentifier)
            lastError = RcloneRCError.notReachable
        }

        let message = (lastError as? LocalizedError)?.errorDescription ?? "Failed to start rclone daemon."
        state = .failed(message)
        throw RcloneRCError.http(status: 0, message: message)
    }

    nonisolated static func makeCredentials() -> RcloneRCCredentials? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let password = bytes.map { String(format: "%02x", $0) }.joined()
        return RcloneRCCredentials(username: "macpowertoys", password: password)
    }

    private func healthCheck(client: RcloneRCClient, process: Process) async -> String? {
        for _ in 0..<60 {
            guard process.isRunning else { return nil }
            if let version = try? await client.version() {
                return version
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    func stop() {
        if let process {
            if process.isRunning {
                process.terminate()
            }
            Self.unregister(daemonPid: process.processIdentifier)
        }
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        client = nil
        state = .stopped
    }

    // MARK: Free port

    private static func findFreePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return nil }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &len)
            }
        }
        guard nameResult == 0 else { return nil }

        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
