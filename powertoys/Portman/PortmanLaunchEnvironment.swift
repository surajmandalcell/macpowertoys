import Darwin
import Foundation

/// Where a listener's row icon comes from, in the order Portman tries them.
nonisolated enum PortmanIconSource: String, Sendable {
    case app, startedBy, fallback
}

/// The one place for the generic row glyph, so a new pick is a one-line swap.
nonisolated enum PortmanRowIcon {
    static let fallbackSymbol = "terminal"
}

/// The allow-listed launch hints from a process environment. Values of every other key, tokens included,
/// are never copied out of the kernel buffer.
nonisolated struct PortmanLaunchEnvironment: Equatable, Sendable {
    var bundleID: String?
    var termProgram: String?
    var claudeCode = false
    var codex = false
    var cursorAgent = false
    var npmEvent: String?

    var agents: [String] {
        [claudeCode ? "Claude Code" : nil, codex ? "Codex" : nil, cursorAgent ? "Cursor Agent" : nil].compactMap { $0 }
    }

    /// "Orca · Claude Code · npm run dev". `appName` is the app found for `bundleID`.
    func startedBy(appName: String?) -> String? {
        let host = appName ?? termProgram.map {
            ["Apple_Terminal": "Terminal", "vscode": "VS Code"][$0]
                ?? ($0.hasSuffix(".app") ? String($0.dropLast(4)) : $0)
        }
        let label = ([host] + agents.map(Optional.some) + [npmEvent.flatMap { $0 == "npx" ? nil : "npm run \($0)" }])
            .compactMap { $0 }.joined(separator: " · ")
        return label.isEmpty ? nil : label
    }
}

/// argv and the allow-listed environment of one process, from `sysctl(KERN_PROCARGS2)`.
nonisolated enum PortmanProcessArguments {
    private static let valueLimit = 128

    /// Reads a same-user process. Returns nil when the kernel refuses (another user, or the process is gone).
    static func read(pid: Int32) -> (argv: [String], environment: PortmanLaunchEnvironment)? {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(argMax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        defer { buffer.withUnsafeMutableBytes { _ = memset($0.baseAddress, 0, $0.count) } }
        return parse(buffer[..<size])
    }

    /// Layout: Int32 argc, executable path, NUL padding, argc argv strings, then env strings up to an empty one.
    static func parse(_ bytes: ArraySlice<UInt8>) -> (argv: [String], environment: PortmanLaunchEnvironment)? {
        guard bytes.count >= 4 else { return nil }
        let start = bytes.startIndex
        let argc = (0..<4).reduce(0) { $0 | Int(bytes[start + $1]) << (8 * $1) }
        var index = start + 4
        while index < bytes.endIndex, bytes[index] != 0 { index += 1 }
        while index < bytes.endIndex, bytes[index] == 0 { index += 1 }
        func nextString() -> ArraySlice<UInt8>? {
            guard index < bytes.endIndex else { return nil }
            let begin = index
            while index < bytes.endIndex, bytes[index] != 0 { index += 1 }
            defer { index += 1 }
            return bytes[begin..<index]
        }
        var argv: [String] = []
        while argv.count < argc, let item = nextString() { argv.append(String(decoding: item, as: UTF8.self)) }
        var environment = PortmanLaunchEnvironment()
        while let item = nextString(), !item.isEmpty { read(item, into: &environment) }
        return (argv, environment)
    }

    private static func read(_ item: ArraySlice<UInt8>, into environment: inout PortmanLaunchEnvironment) {
        guard let equals = item.firstIndex(of: UInt8(ascii: "=")) else { return }
        let key = String(decoding: item[..<equals], as: UTF8.self)
        func value() -> String? {
            let raw = item[(equals + 1)...]
            return raw.isEmpty || raw.count > valueLimit ? nil : String(decoding: raw, as: UTF8.self)
        }
        switch key {
        case "__CFBundleIdentifier": environment.bundleID = value()
        case "TERM_PROGRAM": environment.termProgram = value()
        case "CLAUDECODE": environment.claudeCode = value() == "1"
        case "npm_lifecycle_event": environment.npmEvent = value()
        case "CURSOR_AGENT": environment.cursorAgent = true
        default: if key.hasPrefix("CODEX_") { environment.codex = true }
        }
    }
}

/// Who runs a listener: the app that started it and the row icon.
nonisolated struct PortmanOrigin: Sendable, Equatable {
    var appBundlePath: String?
    var startedBy: String?
    var startedByAppPath: String?
    var iconPath: String?
    var iconSource = PortmanIconSource.fallback

    /// Icon order: the .app ancestor, the app from the environment, then the glyph.
    static func resolve(ancestor: String?, environment: PortmanLaunchEnvironment?,
                        startedByApp: (path: String, name: String)?) -> PortmanOrigin {
        var origin = PortmanOrigin(appBundlePath: ancestor,
                                   startedBy: environment?.startedBy(appName: startedByApp?.name),
                                   startedByAppPath: startedByApp?.path)
        let candidates: [(String?, PortmanIconSource)] = [(ancestor, .app), (startedByApp?.path, .startedBy)]
        if let found = candidates.first(where: { $0.0 != nil }) {
            origin.iconPath = found.0
            origin.iconSource = found.1
        }
        return origin
    }
}
