import Darwin
import Foundation

nonisolated struct PortmanLaunch: Sendable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let folder: String

    var replayable: Bool {
        !arguments[0].contains(" ") && !environment.isEmpty
    }

    static func parse(_ bytes: [UInt8], folder: String) -> PortmanLaunch? {
        guard bytes.count >= 4 else { return nil }
        let count = bytes.prefix(4).enumerated().reduce(UInt32(0)) {
            $0 | (UInt32($1.element) << ($1.offset * 8))
        }
        guard count > 0, count <= 1_024 else { return nil }
        var index = 4
        func read() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            guard index < bytes.count else { return nil }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return text
        }
        guard let executable = read(), executable.hasPrefix("/") else { return nil }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        for _ in 0..<count {
            guard let argument = read() else { return nil }
            arguments.append(argument)
        }
        guard !arguments.isEmpty else { return nil }
        var environment: [String: String] = [:]
        while let entry = read(), !entry.isEmpty {
            if let equals = entry.firstIndex(of: "=") {
                environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
            }
        }
        return PortmanLaunch(executable: executable, arguments: arguments,
                             environment: environment, folder: folder)
    }

    static func inspect(pid: Int32, started: UInt64, userID: UInt32, folder: String) -> PortmanLaunch? {
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize,
              info.pbi_uid == userID,
              info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec == started else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(argMax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = bytes.count
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        return parse(Array(bytes.prefix(size)), folder: folder)
    }

    static func capture(_ port: PortmanLocalPort, folder: String) -> PortmanLaunch? {
        guard port.canStop else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let launch = inspect(pid: port.pid, started: port.started,
                                   userID: port.userID, folder: folder),
              FileManager.default.isExecutableFile(atPath: launch.executable),
              launch.replayable else { return nil }
        return launch
    }
}

nonisolated enum PortmanRestart {
    enum Failure: LocalizedError {
        case unavailable
        case busy

        var errorDescription: String? {
            switch self {
            case .unavailable: "The original launch command or folder is unavailable."
            case .busy: "Port is still in use after stopping. The server was not relaunched."
            }
        }
    }

    static func run(_ port: PortmanLocalPort, folder: String) async throws {
        guard let launch = PortmanLaunch.capture(port, folder: folder) else { throw Failure.unavailable }
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacPowerToys/Portman")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("port-\(port.port).log")
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        defer { try? handle.close() }

        try PortmanScanner.stop(port)
        for _ in 0..<20 {
            if !isListening(port.port) { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard !isListening(port.port) else { throw Failure.busy }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = Array(launch.arguments.dropFirst())
        process.environment = launch.environment
        process.currentDirectoryURL = URL(fileURLWithPath: launch.folder)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
    }

    private static func isListening(_ port: UInt16) -> Bool {
        guard let output = try? PortmanScanner.run(
            "/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fn"],
            emptyExitIsSuccess: true
        ) else { return true }
        return output.split(whereSeparator: \.isNewline)
            .contains { $0.first == "n" && $0.hasSuffix(":\(port)") }
    }
}
