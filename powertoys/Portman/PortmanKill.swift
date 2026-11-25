import AppKit
import Darwin

/// The manual kill keys on a Portman server (detail page and row menu): Stop, Force Kill, and Kill Parent.
/// Unlike Clean up they work on any listener the user owns, such as Pumble or Raycast, but never on the
/// processes macOS needs or on MacPowerToys itself. Every key asks first.
nonisolated enum PortmanKill {
    enum Action: Sendable { case stop, forceKill, killParent }

    struct Target: Equatable, Sendable {
        let pid: Int32
        let command: String
        let started: UInt64
        let userID: UInt32
    }

    static let systemCommands: Set<String> = ["launchd", "kernel_task", "windowserver", "loginwindow"]

    /// Why this process may not be signaled, or nil when it may.
    static func blockReason(pid: Int32, command: String, userID: UInt32,
                            ownPID: Int32 = getpid(), currentUser: UInt32 = geteuid()) -> String? {
        if pid <= 0 { return "The process is gone" }
        if pid == 1 { return "launchd (PID 1) runs macOS itself" }
        if pid == ownPID { return "This is MacPowerToys itself" }
        if systemCommands.contains(command.lowercased()) { return "\(command) is part of macOS" }
        if userID != currentUser { return "\(command) runs as another user" }
        return nil
    }

    static func blockReason(_ target: Target) -> String? {
        blockReason(pid: target.pid, command: target.command, userID: target.userID)
    }

    /// A server row without a start time cannot be checked against pid reuse, so it is never signaled.
    static func blockReason(_ port: PortmanLocalPort) -> String? {
        port.started == 0 ? "Portman could not read this process"
            : blockReason(pid: port.pid, command: port.command, userID: port.userID)
    }

    /// The live process behind a pid: its name, start time, and owner. nil when it is gone.
    static func target(pid: Int32) -> Target? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Target(pid: pid, command: name(pid: pid, fallback: info),
                      started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec, userID: info.pbi_uid)
    }

    /// The process that started `pid`, such as the shell or the app that runs a dev server.
    static func parent(of pid: Int32) -> Target? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let parent = Int32(info.pbi_ppid)
        if parent == 1 { return Target(pid: 1, command: "launchd", started: 0, userID: 0) }
        return target(pid: parent)
    }

    private static func name(pid: Int32, fallback info: proc_bsdinfo) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { return String(cString: buffer) }
        return withUnsafeBytes(of: info.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

@MainActor
extension PortmanKill {
    /// Stop: a Clean up eligible dev server takes the process tree path with its forced follow-up; anything else
    /// gets the normal quit (AppKit for apps, SIGTERM otherwise) and is never forced. Force Kill: SIGKILL on every
    /// child, deepest first, then the server. Kill Parent: the normal quit for the parent only.
    static func run(_ action: Action, port: PortmanLocalPort, parent: Target?, service: PortmanService) {
        let failure: MainPanelProcessQuit.Failure?
        switch action {
        case .stop:
            if port.canStop { return service.stopLocal(port) }
            failure = MainPanelProcessQuit.send(force: false, pid: port.pid, started: port.started)
        case .forceKill:
            for child in port.processes.reversed() where child.started > 0
                && blockReason(pid: child.pid, command: URL(fileURLWithPath: child.command).lastPathComponent,
                               userID: child.userID) == nil
                && MainPanelProcessQuit.isSameProcess(pid: child.pid, started: child.started) {
                _ = MainPanelProcessQuit.signal(SIGKILL, pid: child.pid)
            }
            failure = MainPanelProcessQuit.send(force: true, pid: port.pid, started: port.started)
        case .killParent:
            guard let parent, blockReason(parent) == nil else { return }
            failure = MainPanelProcessQuit.send(force: false, pid: parent.pid, started: parent.started)
        }
        service.controlError = failure.map { failure in
            switch failure {
            case .exited: "It has already quit."
            case .notPermitted: "macOS does not let MacPowerToys stop this process."
            case .other(let code): String(cString: strerror(code))
            }
        }
        Task { await service.refreshLocal() }
    }
}
